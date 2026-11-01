# ADR-0017: Eventos de UI por el WebSocket de `chat`, en lugar del polling del front

- **Estado:** Aceptado
- **Fecha:** 2026-11-01
- **Decisores:** Persona 2 (dueña de INF-30 en el CP3), como implementadora de la decisión D17 del
  Anexo A del plan del sprint. La gestiona y la acepta quien la escribe, que es lo que el plan
  previó para las decisiones de diseño; cambiarla es escribir un ADR que la reemplace, no reabrir
  la discusión.
- **Servicios afectados:** `chat-and-real-time`, `web-app` (web y mobile). `community` e `identity`
  solo como productores de eventos, algunos que ya publican y otros que van a publicar.

> Este ADR **no modifica** ningún ADR anterior. Se apoya en el socket y el hub de `chat` que el
> [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) ya puso detrás del gateway, y
> respeta que el gateway no consume el bus ([ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md)).

## Contexto

Hoy el front se entera de los cambios de otros servicios **preguntando**. Hay un polling de 5
segundos en seis lugares por plataforma: la lista de servidores, el servidor con sus canales y
permisos (dos veces en la web, en `ChannelRoute` y en `useServer`), los miembros, los baneos y el
perfil. Una pestaña dentro de un canal hace entre 60 y 72 requests por minuto, que es el 20-24%
del rate limit por usuario del gateway (300 por minuto).

El costo de requests no es el único problema. Conviven **dos sistemas que no se hablan**: `chat`
ya reacciona al instante a los cambios que le importan (rechaza el envío con `FORBIDDEN`, corta la
voz de quien pierde `CONNECT`, cierra los sockets con `4403`), pero la pantalla se entera recién en
el polling siguiente. Para que una respuesta vieja no pise un cambio hecho en el propio cliente
existen `localChangeRef` y los merges parciales, que son código que solo está para tapar esa
diferencia.

El sprint además suma frames nuevos en el mismo socket: participantes de voz, estado de lectura y
mensajes editados. Si cada historia inventa cómo avisar, quedan tres mecanismos.

Restricciones que aplican:

- El [ADR-0004](0004-comunicaciones-sincronicas.md) rechaza toda llamada sincrónica entre
  servicios: `chat` no puede pedirle a `community` el dato que cambió.
- El gateway no tiene lógica de negocio ni consume el bus (ADR-0009). Lo que lo haría saber a
  quién le importa cada evento es dominio.
- Por el bus no viajan datos personales ([`eventos.md`](../arquitectura/eventos.md), nota 6). Las
  proyecciones de `chat` guardan lo que `chat` necesita para decidir, no una copia de `community`
  ni de `identity`.
- El [ADR-0003](0003-tecnologia-del-bus-pubsub.md) eligió RabbitMQ, que no tiene replay: lo que una
  instancia no recibe no se puede volver a leer. Y `chat` corre con varias instancias, cada una con
  sus propias conexiones.

## Opciones consideradas

### Opción A — Seguir con polling, más espaciado

Subir el intervalo a 15 o 30 segundos.

- A favor: no hay que escribir nada.
- En contra: cambia carga por latencia. Un permiso que se quita se ve 30 segundos tarde, y esa
  demora se nota justo en lo que la demo muestra. Los dos sistemas siguen sin hablarse, y los
  frames nuevos del sprint necesitan su propio mecanismo igual.

### Opción B — SSE desde el gateway

Una conexión de eventos del servidor que abre el gateway.

- A favor: es HTTP común, y lo que hace falta es unidireccional.
- En contra: obliga al gateway a consumir el bus y a decidir a quién le importa cada evento, que es
  lo que el ADR-0009 le sacó. Es una segunda conexión persistente por cliente al lado del
  WebSocket que ya hay, y el soporte de SSE en React Native es flojo, así que mobile terminaría
  con otra solución.

### Opción C — Un servicio `notifications` con su propio socket

- A favor: separa las responsabilidades, y es la base natural de un centro de notificaciones o de
  las notificaciones push.
- En contra: un servicio nuevo con su deploy, su ticket de WebSocket y su hub multiinstancia, para
  resolver lo que `chat` ya resuelve. Ninguna historia del CP3 lo pide. Queda como evolución si
  alguna vez se eligen las notificaciones push.

### Opción D — Frames que llevan el dato nuevo

El aviso trae el canal creado, el rol cambiado o el perfil editado, y el cliente no vuelve a pedir
nada.

- A favor: sin requests extra.
- En contra: `chat` tendría que proyectar datos de `community` e `identity` (nombres de canales,
  roles, perfiles) para poder armar el frame, lo que contradice la regla de que por el bus no viajan
  datos personales y vuelve a `chat` una segunda fuente de verdad. Además, un aviso duplicado o
  fuera de orden pisaría un estado más nuevo del cliente.

### Opción E — Avisos de invalidación por el socket de `chat`

El frame dice **qué recurso quedó viejo**, sin el dato. El cliente lo vuelve a pedir por HTTP con la
misma función que ya usa. Cuando el dato es de `chat` (mensajes, lectura, voz) el frame sí lo
lleva, porque `chat` es su fuente.

- A favor: reusa el socket, el hub, el índice por usuario y el fan-out multiinstancia que ya
  existen. `community` e `identity` siguen siendo la única fuente de lo suyo. Un aviso duplicado o
  fuera de orden solo provoca una relectura, así que no hay estado que corromper.
- En contra: cada aviso cuesta un request. El cliente gana estado (agrupar avisos, reintentar,
  respaldo). Y como el bus no tiene replay, un aviso perdido deja la pantalla vieja hasta el
  próximo cambio o hasta el respaldo.

## Decisión

Elegimos la **Opción E**.

El criterio que desempató fue que **ningún dato cambia de dueño**. La D saca el polling pero obliga
a `chat` a conocer el dominio de los demás; la B lo obliga al gateway. Con la E el único servicio
que aprende algo nuevo es el que ya tiene los sockets, y lo que aprende es *qué* quedó viejo, no
*cómo es* ahora.

### La regla del payload

- Si el dato es de **otro servicio** (`community`, `identity`), el frame solo invalida.
- Si el dato es de **`chat`** (mensajes, estado de lectura, participantes de voz), el frame lleva
  el dato. Esos frames los define cada historia y se montan sobre este mecanismo.

### El frame

```json
{ "type": "invalidate", "serverId": "0f4e…", "resources": ["members", "bans"] }
```

| Campo | Obligatorio | Significado |
| --- | :-: | --- |
| `type` | sí | Siempre `invalidate` |
| `resources` | sí | Qué quedó viejo: `servers`, `server`, `channels`, `permissions`, `members`, `bans`, `profile`, `ownershipTransfers` |
| `serverId` | no | A qué servidor se refieren los recursos. Va con `server`, `channels`, `permissions`, `members` y `bans`; no con `servers` ni `profile` |
| `userId` | no | De quién cambió el perfil. Solo va con `profile` y con `members` cuando el motivo es un cambio de perfil |

- **`resources` es un conjunto abierto.** El cliente ignora los valores que no conoce, igual que ya
  ignora los `type` de frame que no conoce. Así un cliente viejo sobrevive a un recurso nuevo.
- **`userId` existe por el caché de perfiles.** Los nombres y avatares de la lista de miembros
  salen de `publicProfileCache`. Sin saber de quién cambió el perfil, el cliente releería la lista
  y seguiría mostrando el avatar viejo.
- **No hay un campo `scope`.** La D17 del plan lo previó, pero a quién se manda el aviso (a los
  suscriptos a un servidor o a un usuario) lo decide `chat`, y el cliente no tiene qué hacer con esa
  información: lo que necesita ya lo dice `serverId`. Un campo que nadie lee se desactualiza.
- **Nombres.** Los eventos del bus usan guión medio entre palabras (`eventos.md`, "Convención de
  nombres"), y los tipos de frame siguen la misma regla (`read-state.updated`, no
  `read_state.updated`), para que haya una sola.

### A quién llega

`chat` tiene dos formas de entregar un frame, y este ADR agrega la segunda:

- **A un servidor:** `Broadcast(serverId)`, que ya existe. Llega a las conexiones suscriptas a ese
  servidor, que son las de los miembros con `VIEW_CHANNEL` (ADR-0011).
- **A un usuario:** `SendToUser(userId)`, nuevo, sobre el índice por usuario que el hub ya usa para
  el cierre `4403`. Llega a todas las pestañas de esa persona en la instancia, sin depender de a qué
  servidores está suscripta.

Hace falta la segunda porque hay avisos que no pueden depender de la suscripción. Cuando expulsan
a alguien, el relevo `chat.membership.changed` lo desuscribe del servidor de forma asincrónica, así
que un `Broadcast` puede llegarle o no. Y quien pierde `VIEW_CHANNEL` queda desuscripto pero igual
tiene que enterarse para que su pantalla cambie.

### Qué hace `chat`

Un consumidor nuevo, **en una cola por instancia** y en una cola propia, traduce los eventos de
origen a avisos. Cada instancia tiene sus propias conexiones, así que todas tienen que ver cada
evento, y con una cola compartida lo recibiría una sola y los demás clientes nunca se enterarían.
Va aparte de la cola de mensajes por la misma razón que ya aplican `identity.user.suspended` y
`chat.membership.changed`: una lectura lenta no demora los broadcasts.

No escribe en Mongo. Lo único que lee es la proyección, para saber los servidores de un usuario
cuando cambia su perfil.

| Evento de origen | ¿Existe? | A quién | Aviso |
| --- | :-: | --- | --- |
| `community.channel.created`, `updated` y `deleted` | Sí | Servidor | `channels` |
| `community.member.joined` | Sí | Servidor; el usuario | `members`; `servers` |
| `community.member.left` | Sí | Servidor; el usuario | `members`, y también `bans` si `reason` es `banned`; `servers` |
| `community.member.permissions-changed` | Sí | Cada usuario de `members` | `permissions` y `channels` de ese servidor |
| `community.server.created` | Sí | El owner, por sus otras sesiones | `servers` |
| `identity.user.profile-updated` | No (`identity`) | El usuario; sus servidores | `profile`; `members` con `userId` |
| `community.server.layout-updated` | No (`community`) | Servidor | `channels` |
| `community.server.updated` | No (`community`) | Servidor | `server` |
| `community.server.deleted` | No (`community`) | Servidor | `servers` |
| `community.server.ownership-transferred` | No (`community`) | Servidor | `server` |
| `community.server.ownership-transfer-changed` | No (`community`) | El destinatario | `ownershipTransfers` |

Los eventos que todavía no existen los agrega su dueño al catálogo cuando los implementa, y sumar
la fila al consumidor es una línea y un test. Los nombres de la tabla son los que corresponden a la
convención; si su dueño necesita cambiarlos al catalogarlos, lo hace en su PR.

`permissions-changed` suma `channels` porque `GET /servers/{id}` devuelve los canales y los
permisos juntos, y con el ADR-0011 el permiso decide qué canales ve cada uno.

### Qué hace el cliente

- **Despacho.** El cliente de tiempo real de `@discordia/api` entrega el frame `invalidate` como un
  evento más, y `@discordia/core` lo expone por el contexto de tiempo real para que ningún hook
  toque el socket directamente.
- **Un hook, `useServerEvents`,** que reemplaza el polling. Recibe qué recursos le importan y la
  misma función de recarga que hoy se llama desde el intervalo.
- **Agrupa y dispersa.** Los avisos que llegan juntos se agrupan unos 300 ms en una sola recarga,
  y la recarga sale con un retraso aleatorio de hasta 1 segundo. Sin esto, un cambio en un servidor
  grande hace que todos sus miembros pidan lo mismo en el mismo instante.
- **Relee todo cuando pudo perderse algo.** Al reconectar el socket y al volver a la pestaña o a la
  app, pide de nuevo lo que tiene montado, porque durante el corte el bus no guardó nada para él.
- **El polling queda como respaldo cada 60 segundos.** Cubre los eventos que todavía no existen y
  el aviso que se perdió. Si el tiempo real está deshabilitado (no hay URL de WebSocket), vuelve a
  los 5 segundos de hoy.

### Qué les pide a los productores

Cada evento se publica **después del commit**. Si no, el cliente se entera antes de que el dato
exista, relee, y se queda con el estado viejo hasta el siguiente aviso.

## Consecuencias

**Positivas**

- Los cambios de servidores, canales, permisos y miembros se ven al instante en los otros clientes,
  que es lo que muestra la demo del CP3.
- En reposo, cada fuente pasa de 12 requests por minuto a 1, así que una pestaña dentro de un canal
  deja de gastar el 20-24% del rate limit. La prueba de carga del CP3 (INF-23, escenario de
  navegación) lo mide contra el polling de hoy y el resultado se agrega a este ADR.
- Hay **un solo mecanismo** para todos los frames del sprint (voz, lectura, edición, avisos), en
  lugar de uno por historia.
- Quedan sin razón de ser `localChangeRef` y los merges parciales, que existen por el desfase del
  polling. Se pueden borrar después, en un cambio aparte.
- Es compatible con los permisos por canal del [ADR-0012](0012-permisos-por-canal.md): el aviso no
  lleva ningún dato, así que no filtra nada aunque el broadcast todavía no filtre por canal.

**Negativas / costo que aceptamos**

- **Cada aviso cuesta un request.** Es el precio de que la fuente de verdad no cambie. Se acota con
  el agrupado y el retraso aleatorio, no se elimina.
- **Un aviso perdido se corrige tarde.** Sin replay, una instancia que estaba caída o un socket
  cortado no recibe lo que pasó mientras tanto. Lo cubre la relectura al reconectar y, en el peor
  caso, el respaldo de 60 segundos.
- **Quien no está suscripto a un servidor no recibe sus avisos de servidor.** Un miembro sin
  `VIEW_CHANNEL` depende del respaldo. Es aceptable porque no ve canales, y los avisos que sí lo
  afectan (`permissions`, `servers`) le llegan por `SendToUser`.
- El cliente gana estado y lógica que antes no tenía: agrupar, dispersar y relear.
- `profile-updated` obliga a una lectura de Mongo por instancia para saber los servidores del
  usuario. Es un evento raro, pero es la única vez que el consumidor toca la base.

**Qué queda pendiente por esta decisión**

- **La lista de roles y el desbaneo no tienen evento** y siguen con el respaldo de 60 segundos
  hasta que lo tengan.
- Los eventos que marca la tabla como inexistentes los publican sus dueños: `layout-updated` y
  `server.updated` (`community`, organización del servidor), `server.deleted` (`community`,
  backoffice), los de la transferencia de propiedad (`community`) y `profile-updated` (`identity`,
  que ya figura en el catálogo pero todavía no se publica).
- `ActiveServers` filtra por `VIEW_CHANNEL` del usuario que cambió su perfil. Si se quiere que lo
  vean también los servidores donde no tiene ese permiso, hace falta una consulta sin ese filtro.
- Si en el futuro se elige el push o un centro de notificaciones, hay que revisar la Opción C.

## Referencias

- [ADR-0003](0003-tecnologia-del-bus-pubsub.md) — el bus no tiene replay
- [ADR-0004](0004-comunicaciones-sincronicas.md) — por qué `chat` no puede preguntar por HTTP
- [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) — el WebSocket de `chat` detrás del gateway
- [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) — el gateway no consume el bus
- [ADR-0011](0011-roles-y-permisos-en-community.md) y [ADR-0012](0012-permisos-por-canal.md) — quién está suscripto a qué
- [`arquitectura/eventos.md`](../arquitectura/eventos.md) — catálogo de eventos y convención de nombres
- Plan del Sprint 3: Anexo A, decisión D17, y hallazgo 11 del relevamiento
- Jira: SCRUM-167 (INF-30)
