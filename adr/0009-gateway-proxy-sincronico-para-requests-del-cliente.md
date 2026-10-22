# ADR-0009: El gateway resuelve las requests del cliente como proxy sincrónico

- **Estado:** Aceptado
- **Fecha:** 2026-09-19
- **Decisores:** equipo completo (reunión de seguimiento)
- **Servicios afectados:** `api-gateway`, `identity`, `community`, `chat-and-real-time`, `mod`, `monetization`, `notifications`, `metrics`, los tres artefactos cliente

> Este ADR **reemplaza parcialmente** al [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md): mantiene el gateway como punto único de entrada y deja sin efecto la parte de su decisión que dice que el gateway publica al bus y no llama a los servicios. El número tentativo `0008` que el ADR-0002 mencionaba ya lo tomó el [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) por orden de llegada, así que esta decisión toma el siguiente número libre.

## Contexto

El [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) dejó un problema abierto que bloquea el arranque de las historias del CP1:

> un `POST /servers` desde el front necesita una respuesta, y publicar al bus no la devuelve.

El ADR-0002 enumeró tres candidatos (correlation ID + espera, `202` + polling, `202` + WebSocket/SSE) y no eligió ninguno. Mientras tanto el problema se agrandó, porque no es sólo `POST /servers`:

- **Casi toda la API es request/response.** Los contratos OpenAPI ya escritos para el camino crítico ([`arquitectura/contratos/`](../arquitectura/contratos/README.md), INF-01) tienen 20 operaciones; 19 son HTTP request/response y las 19 devuelven un status y un body que el cliente necesita: `201` con el servidor recién creado, `200` con los tokens del login, `403` cuando el usuario no tiene permiso, `404` cuando el canal no existe, `422` cuando el nombre está vacío.
- **Los errores de dominio no los puede decidir el gateway.** "Este email ya está registrado", "no sos miembro de este servidor", "el canal no existe" salen de la base del servicio. Un `202` obligaría a construir un camino de vuelta asincrónico cuyo único trabajo sería transportar rechazos — exactamente lo que el [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) ya descartó para el caso de mensajería.

Restricciones que aplican:

- La consigna exige **API Gateway como punto único de entrada** y **comunicación asíncrona por defecto entre servicios**, con toda comunicación sincrónica **justificada en un ADR**. Este es ese ADR para el tráfico cliente↔plataforma; el tráfico servicio↔servicio lo gobierna el [ADR-0004](0004-comunicaciones-sincronicas.md), que rechazó toda llamada sincrónica interna.
- La decisión define la forma de **todos** los endpoints, así que bloquea al front y a los tres servicios del camino crítico.
- El [ADR-0003](0003-tecnologia-del-bus-pubsub.md) eligió RabbitMQ, que **no tiene replay**: un mensaje publicado y consumido no se puede volver a leer, y un mensaje que nunca se publicó no se puede recuperar. Eso pesa sobre quién publica y cuándo.

## Opciones consideradas

### Opción A — Correlation ID + espera en el gateway

El gateway publica un comando al bus con un `correlationId`, se suscribe a un tópico de respuesta y bloquea hasta recibirla o hasta el timeout.

- A favor: el front ve request/response normal; formalmente "el gateway publica al bus", así que el ADR-0002 queda intacto en la letra.
- En contra: es una llamada sincrónica disfrazada — el gateway queda igual de acoplado a la disponibilidad del servicio, pero con dos saltos de broker en el medio, un tópico de respuesta por request, correlación manual y timeouts propios. Paga todo el costo de lo sincrónico y encima el de lo asincrónico. Si el servicio responde después del timeout, el comando ya se ejecutó y el cliente vio un error: divergencia silenciosa.

### Opción B — `202 Accepted` + polling

El gateway responde `202` con un id de operación y el front consulta el estado hasta que termina.

- A favor: es el modelo honestamente asincrónico; el gateway nunca espera a nadie.
- En contra: hace falta un store de operaciones (qué pasó con cada id, quién lo puede consultar, cuánto vive), que hoy no existe y nadie es dueño. Cambia el diseño de las pantallas de los tres artefactos: cada formulario pasa a tener estado "pendiente". Y para un `422` de validación el usuario espera dos vueltas de polling para enterarse de que escribió mal el nombre.

### Opción C — `202 Accepted` + notificación por WebSocket/SSE

Igual que B, pero el resultado llega empujado por el canal de tiempo real.

- A favor: mejor UX que el polling; reusa el socket que la mensajería necesita igual.
- En contra: convierte al socket de `chat` en el bus de notificaciones de toda la plataforma — justo lo que el [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) marcó como lo que **no** hay que hacer sin una decisión explícita. Acopla `identity`, `community` y `monetization` a que el usuario tenga un socket vivo: si el socket se cayó, el resultado de su `POST` no llega a ningún lado. Sigue necesitando el store de operaciones de la Opción B como respaldo.

### Opción D — El gateway resuelve la request como proxy sincrónico al servicio

El gateway recibe la request del cliente, la reenvía al servicio dueño del recurso, espera la respuesta y se la devuelve al cliente tal cual.

- A favor: el cliente obtiene el resultado y el error de dominio en la misma request, sin infraestructura nueva. Es el contrato que ya está escrito en `api-gateway.yaml`. Es el patrón que usan los productos reales del dominio (edge gateway sincrónico + interior event-driven). Es el mismo rol que el [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) ya le dio al gateway para el WebSocket, ahora para HTTP.
- En contra: la disponibilidad de escritura del cliente pasa a ser la del servicio — si `community` está caído, `POST /servers` falla en vez de encolarse. Y es una llamada sincrónica explícita, que hay que justificar ante la consigna (este ADR).

## Decisión

Elegimos la **Opción D**.

El criterio que desempató: **las opciones A, B y C construyen infraestructura nueva cuyo único propósito es devolverle al cliente un dato que el servicio ya tenía en la mano**. Ninguna de las tres evita el acoplamiento real —el usuario igual espera a que `community` conteste— y las tres lo pagan con un componente nuevo que hay que diseñar, implementar, testear y depurar en 18 días compartidos con la épica de Voz. El encolado que la Opción B y la C prometen sólo sirve si el resultado se puede diferir; como el `422` y el `403` no se pueden diferir, el encolado no compra nada y cuesta todo.

La decisión se compone de cuatro partes.

### 1. Toda request HTTP del cliente se resuelve como proxy sincrónico

```
cliente ──HTTP──► api-gateway ──HTTP──► * 
* servicio dueño del recurso
  │
  ├─ falla ──► respuesta de error ──► gateway ──► cliente
  │
  └─ éxito ──► commit + publica evento al bus
              └──► consumidores asincrónicos
              └──► respuesta ──► gateway ──► cliente
```

- El gateway **no publica al bus** y **no tiene lógica de negocio**: valida el JWT, aplica rate limiting, propaga identidad y correlación por headers, reenvía y devuelve. Deja de ser productor del bus.
- El gateway sigue siendo el **único punto de entrada**: los tres artefactos cliente no conocen ni alcanzan a ningún servicio directamente. Esa parte del ADR-0002 no cambia.
- La comunicación **entre servicios backend** sigue siendo **100% asincrónica por el bus**. Este ADR no habilita ni una sola llamada servicio→servicio; eso lo gobierna el [ADR-0004](0004-comunicaciones-sincronicas.md), que las rechazó todas.

### 2. El evento al bus lo publica el servicio, no el gateway

Cuando una escritura tiene que enterar a otros servicios, el evento lo publica **el servicio dueño del recurso, dentro del mismo caso de uso, después de confirmar la escritura en su base**. El gateway no participa.

La alternativa que se evaluó —que el gateway publique el evento al recibir una respuesta exitosa— se descartó por cuatro razones:

- **Rompe la propiedad de los eventos.** [`arquitectura/eventos.md`](../arquitectura/eventos.md) establece que el servicio que publica es el dueño del nombre y que nadie publica en el namespace de otro. Con el gateway publicando, `community.server.created` lo emitiría `api-gateway`, y el campo `producer` del envelope diría algo distinto de lo que dice el `eventType`.
- **Pierde eventos sin dejar rastro.** Si el servicio commitea y el gateway se cae, o la respuesta se pierde en un timeout, la escritura ocurrió y el evento no existe. Como RabbitMQ no tiene replay ([ADR-0003](0003-tecnologia-del-bus-pubsub.md)), esa divergencia es permanente y nadie se entera: `chat` nunca ve el `member.joined` y `metrics` nunca cuenta el servidor. Con el servicio publicando, el productor es el mismo que hizo el commit y puede reintentar sabiendo qué escribió.
- **El payload del evento no es el body de la respuesta.** El body es una representación pensada para el front; el evento es un contrato entre servicios. Derivar uno del otro los ata: cada cambio cosmético de la API cambiaría en silencio el contrato del bus.
- **Habría dos caminos de publicación para el mismo evento.** Un `member.left` disparado por un baneo de `mod` o por un job interno no pasa por el gateway. Con el gateway como productor harían falta las dos rutas para el mismo evento, con el doble de superficie de bugs.

Regla operativa mínima para el CP1: **publicar después del commit**, con reintento en proceso y log del fallo. El *outbox* transaccional queda pendiente (ver más abajo).

### 3. Qué es sincrónico y qué va al bus, request por request

La consigna pide justificar cada comunicación sincrónica. Las 19 operaciones HTTP del camino crítico (la veinteava es el upgrade a WebSocket, que gobierna el ADR-0008) caen en tres justificaciones, y ninguna admite una respuesta diferida:

| Familia | Por qué no puede ser asincrónica |
|---|---|
| **Lecturas (`GET`)** | No hay nada que diferir: el cliente pide un dato para pintarlo en pantalla. No generan evento porque no cambian nada. |
| **Escrituras cuyo resultado el cliente usa para continuar** | El `serverId` de `POST /servers` es el que la UI usa para navegar al servidor recién creado; sin el token de `POST /sessions` no hay ninguna request siguiente; el código de `POST /invites` es lo que el usuario copia y pega. |
| **Escrituras con validación de dominio** | `403`, `404`, `409` y `422` se deciden contra la base del servicio. El gateway no tiene esa base ni esa lógica, y el cliente necesita el error para mostrarlo en el formulario. |

| Request del cliente | Sincrónico | Evento al bus | Consumidores |
|---|---|---|---|
| `POST /api/v1/users` | sí — `201` con el usuario, `409` si el email existe | `identity.user.registered` | `metrics` |
| `POST /api/v1/sessions` | sí — `200` con los tokens | — | |
| `DELETE /api/v1/sessions` | sí — `204` | — | |
| `POST /api/v1/sessions/refresh` | sí — `200` con el token nuevo | — | |
| `GET /api/v1/users/me` | sí — lectura | — | |
| `PATCH /api/v1/users/me` | sí — `200` con el perfil actualizado, `422` | — ¹ | |
| `PUT /api/v1/users/me/avatar` | sí — `200` con la URL del avatar | — ¹ | |
| `POST /api/v1/servers` | sí — `201` con el servidor creado | `community.server.created` | `metrics` |
| `GET /api/v1/servers/{serverId}` | sí — lectura, `403` si no es miembro | — | |
| `DELETE /api/v1/servers/{serverId}/members/me` | sí — `204` | `community.member.left` | `chat`, `metrics` |
| `PUT /api/v1/servers/{serverId}/bans/{userId}` | sí — `204`, idempotente | `community.member.left` | `chat`, `metrics` |
| `POST /api/v1/servers/{serverId}/invites` | sí — `201` con el código | — ¹ | |
| `DELETE /api/v1/servers/{serverId}/invites/{inviteId}` | sí — `204` | — ¹ | |
| `GET /api/v1/invites/{code}` | sí — lectura previa a unirse | — | |
| `POST /api/v1/invites/{code}` | sí — `200`/`201`, `410` si expiró | `community.member.joined` | `chat`, `metrics` |
| `POST /api/v1/servers/{serverId}/channels` | sí — `201` con el canal | `community.channel.created` | `chat`, `metrics` |
| `GET /api/v1/servers/{serverId}/channels` | sí — lectura | — | |
| `PATCH /api/v1/servers/{serverId}/channels/{channelId}` | sí — `200` con el canal | `community.channel.updated` | `chat`, `metrics` |
| `DELETE /api/v1/servers/{serverId}/channels/{channelId}` | sí — `204` | `community.channel.deleted` | `chat`, `metrics` |
| `GET /api/v1/channels/{channelId}/messages` | sí — lectura del historial | — | |
| `GET /api/v1/channels/{channelId}/ws` | no aplica — transporte de larga duración, [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) | `chat.message.sent` | `chat` (fan-out), `metrics` |

¹ No hay evento catalogado hoy en [`arquitectura/eventos.md`](../arquitectura/eventos.md). Si una historia futura necesita enterarse, se agrega a esa tabla en el mismo PR que lo implementa; no se publica nada que no esté catalogado.

**Regla para los endpoints que todavía no existen.** El default es proxy sincrónico. Un endpoint puede responder `202` y resolverse por evento **sólo si** se cumplen las dos condiciones a la vez: (a) el cliente puede seguir usando la aplicación sin el resultado, y (b) todo lo que puede salir mal se puede detectar en el borde (formato, auth, rate limit), sin consultar la base del servicio. El caso típico es un disparo de notificación o una carga diferida. Cada excepción se anota en la tabla de arriba en el PR que la introduce.

### 4. Contrato operativo del proxy

- **Ruteo:** por prefijo de path, igual que ya documenta `api-gateway.yaml`. El gateway conoce la dirección interna de cada servicio por configuración; los clientes no.
- **Identidad:** el gateway valida el JWT y propaga `X-User-Id` y `X-User-Role`. Los servicios confían en esos headers dentro de la red interna, con la excepción de `identity` en `logout` y `refresh` (ya documentado en los contratos).
- **Correlación:** el gateway genera un `X-Correlation-Id` (UUID v4) por request, lo propaga al servicio y lo devuelve al cliente. El servicio lo copia en el campo `correlationId` del envelope de **todo** evento que derive de esa request, como exige [`arquitectura/eventos.md`](../arquitectura/eventos.md).
- **Errores:** el gateway devuelve **tal cual** el status y el body de cualquier respuesta HTTP del servicio, incluidos `4xx` y `5xx` de dominio. No los reescribe ni los envuelve. Sólo genera respuestas propias para `401`/`403` de autenticación, `429` de rate limit, `502` (conexión rechazada o respuesta inválida), `503` (circuit breaker abierto) y `504` (timeout).
- **Timeouts:** 5 s end-to-end por request; 30 s para los endpoints `multipart/form-data` (ícono de servidor, avatar). Valores por defecto, ajustables en la configuración del gateway.
- **Reintentos:** sólo sobre errores de conexión y sólo en métodos idempotentes (`GET`, `DELETE`), un reintento como máximo. **`POST`, `PATCH` y `PUT` no se reintentan nunca automáticamente**: no hay forma de saber si el servicio llegó a commitear, y un reintento ciego duplica servidores, canales e invitaciones. Ante un timeout en una escritura, el gateway devuelve `504` y el cliente decide.
- **Circuit breaker por servicio:** tras N fallos consecutivos el gateway corta y devuelve `503` sin intentar la conexión, para no acumular requests contra un servicio caído.

### Relación con los ADR anteriores

| ADR | Qué pasa |
|---|---|
| [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) | **Reemplazado parcialmente.** Sigue vigente: gateway como punto único de entrada, concentrador de auth, rate limiting y ruteo, y servicios sin puertos al exterior. Queda sin efecto: "el gateway publica al bus Pub/Sub… El gateway no llama directo a los servicios". |
| [ADR-0003](0003-tecnologia-del-bus-pubsub.md) | Sin cambios. El bus sigue siendo RabbitMQ con las dos topologías. Cambia quién publica (el servicio, nunca el gateway) y qué viaja: **sólo eventos**. |
| [ADR-0004](0004-comunicaciones-sincronicas.md) | **Rechazado** a partir de esta decisión. Gobernaba las llamadas sincrónicas **entre servicios backend**, que este ADR no habilita ni amplía: al resolverse la respuesta al cliente en el gateway, ningún servicio necesita llamar a otro y las tres comunicaciones que enumeraba se descartaron. |
| [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) | Coherente y reforzado. Deja de ser "una excepción al ADR-0002" para ser el caso de transporte de larga duración de la misma regla general: el gateway termina y reenvía el transporte del cliente hacia el servicio dueño. La restricción de su "Alcance de la excepción" que decía que no habilita proxy HTTP de otros endpoints queda subsumida por este ADR. |

**Desaparece la noción de comando en el bus.** El ADR-0002 la había introducido y [`arquitectura/eventos.md`](../arquitectura/eventos.md) dejó pendiente definir su envelope y su mecanismo de respuesta. Con esta decisión, por el bus viajan **sólo eventos**: hechos ya ocurridos, que nadie puede rechazar. No hace falta envelope de comandos, ni tópico de respuestas, ni correlación de comandos con resultados.

## Consecuencias

**Positivas**

- Se cierra el problema abierto que el ADR-0002 marcaba como bloqueante para arrancar las historias del CP1.
- **Los contratos OpenAPI ya escritos quedan válidos sin un solo cambio**: `api-gateway.yaml` ya está redactado como proxy (`[proxy → identity]`, `[proxy → community]`) con los status de los servicios de origen. El código y el ADR pasan a decir lo mismo.
- El front implementa request/response común en los tres artefactos: sin polling, sin store de operaciones, sin pantallas en estado "pendiente", sin correlación manual.
- Los errores de dominio llegan al cliente con su status y su body reales, que es lo que los criterios de aceptación de las historias piden mostrar.
- Un solo mecanismo para todos los endpoints: no hay que decidir caso por caso en cada historia.
- El gateway se simplifica: no necesita cliente de RabbitMQ, ni suscripciones, ni manejo de timeouts de bus. Menos código en el componente que es punto único de falla.
- La comunicación entre servicios backend sigue siendo 100% asincrónica y el bus queda con una sola semántica (eventos), más fácil de explicar y de demostrar.

**Negativas / costo que aceptamos**

- **La disponibilidad de escritura del cliente es la del servicio.** Si `community` está caído, `POST /servers` devuelve `503`/`504` en vez de encolarse. Lo aceptamos porque el encolado nunca iba a poder devolver el `422`, y porque el gateway ya era punto único de falla igual.
- **Hay una ventana de inconsistencia entre el commit y la publicación del evento.** Si el servicio commitea y el `publish` falla, la escritura ocurrió y los consumidores no se enteran, sin replay posible en RabbitMQ. Mitigación de CP1: reintento en proceso y log; la solución real es un outbox transaccional, que queda pendiente.
- **El cliente ve dos clases de error.** Los de dominio vienen del servicio; `502`, `503` y `504` los genera el gateway. El front tiene que distinguirlos para no mostrar "email inválido" cuando lo que pasó es que el servicio no contestó.
- **El gateway conoce la topología interna.** Mover un recurso de un servicio a otro ahora es un cambio de configuración del gateway. Sigue siendo mucho mejor que tocar los tres clientes, que era el punto del ADR-0002.
- **Un salto de red más por request** frente a que el cliente llamara al servicio, que igual la consigna no permite.
- **Hay que sostener el argumento ante la cátedra.** "Asíncrono por defecto" aplica a la comunicación entre servicios backend, que acá sigue siendo asincrónica sin excepciones. Lo que se vuelve sincrónico es el tráfico cliente↔plataforma, que es request/response por naturaleza del protocolo HTTP. Este ADR es la justificación explícita que la consigna exige, y la tabla de la sección 3 la hace endpoint por endpoint.

**Qué queda pendiente por esta decisión**

- **Outbox transaccional** en los servicios Python, para cerrar la ventana commit↔publish. Se evalúa después del CP1; hasta entonces, publicar tras el commit con reintento y log.
- **`Idempotency-Key` en los `POST`**, para que el cliente pueda reintentar una escritura que terminó en `504` sin duplicarla. Hoy el cliente reintenta a ciegas.
- **Valores concretos** de timeout, umbral del circuit breaker y límites de rate limiting: se cierran al implementar el gateway (INF-10) y se documentan en su README.

## Referencias

- [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) — reemplazado parcialmente por este
- [ADR-0003](0003-tecnologia-del-bus-pubsub.md), [ADR-0004](0004-comunicaciones-sincronicas.md), [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md)
- [`arquitectura/contratos/`](../arquitectura/contratos/README.md) — las 20 operaciones del camino crítico (INF-01)
- [`arquitectura/eventos.md`](../arquitectura/eventos.md) — envelope, propiedad de los eventos, idempotencia y topología
- Enunciado 2026C2 — Discordia, *Requisitos No Funcionales*: "Componentes" (API Gateway como punto único de entrada) e "Integridad y Flujo de Datos" (asincronía por defecto, sincronía justificada por ADR)
