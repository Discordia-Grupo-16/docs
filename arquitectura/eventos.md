# Catálogo de eventos del bus

Todo lo que viaja por el bus se declara acá. **Un evento que no está en esta tabla no existe**: si un servicio publica algo que nadie documentó, el consumidor se entera cuando se rompe.

> Estado: envelope, naming, versionado, reglas de idempotencia/orden/reintentos y topología de colas ya definidos (SCRUM-122 a SCRUM-125, INF-02). Catálogo del camino crítico del CP1 completo; los payloads que figuran como *a definir* o como propuesta de un consumidor los cierra el dueño del servicio que publica, en la historia que implementa el evento. Cada épica nueva suma sus eventos a la tabla en el mismo PR que los implementa.

**Por el bus viajan sólo eventos.** Un evento describe algo que ya ocurrió y nadie lo puede rechazar (`chat.message.sent`). **No hay comandos en el bus:** desde el [ADR-0009](../adr/0009-gateway-proxy-sincronico-para-requests-del-cliente.md) el gateway resuelve cada request del cliente como proxy sincrónico al servicio, y el evento lo publica el servicio recién después de confirmar la escritura. Nunca viaja por el broker una orden que todavía puede fallar, así que no hace falta un envelope de comandos ni un mecanismo de respuesta: el de abajo es el único envelope que existe.

## Convención de nombres

```
<servicio>.<agregado>.<evento-en-pasado>
```

Ejemplos: `identity.user.registered`, `community.server.created`, `mod.member.banned`, `chat.message.sent`.

Reglas:

- El verbo va **en pasado**: el evento describe algo que ya ocurrió, no una orden.
- El servicio que publica es el dueño del nombre. Nadie publica en el namespace de otro.
- **El payload lo define el dueño del servicio que publica**, en la historia que implementa el evento, y en ese mismo PR lo deja escrito en la tabla de abajo. Un consumidor puede proponer los campos que necesita, pero la propuesta no es el contrato hasta que el dueño la confirma acá. Un payload que quedó en "a definir" es deuda del dueño de ese servicio, no de quien lo consume.
- Un evento nuevo se agrega; **un evento existente no cambia de forma**. Si el payload tiene que cambiar de manera incompatible, se publica `v2` en paralelo y se deprecia el anterior.

## Envelope común

Todos los eventos comparten la misma estructura externa; lo específico va en `data`.

```json
{
  "eventId": "uuid",
  "eventType": "identity.user.registered",
  "eventVersion": 1,
  "occurredAt": "2026-09-08T14:32:00Z",
  "correlationId": "uuid",
  "causationId": "uuid",
  "producer": "identity",
  "data": { }
}
```

- `eventId`: identifica esta instancia del evento. Es la clave para deduplicar en el consumidor (ver "Idempotencia" más abajo).
- `correlationId` viaja desde el gateway y se propaga a todos los eventos derivados: es lo único que permite seguir un flujo completo entre 8 servicios cuando algo falla.
- `causationId`: el `eventId` del evento que causó directamente este evento. Si el evento nace de una request del cliente no hay evento causante, así que va vacío y el flujo se sigue por `correlationId`. Distinto de `correlationId`, que identifica el flujo completo; `causationId` reconstruye la cadena causal paso a paso dentro de ese flujo.
- `eventVersion` permite convivir dos versiones durante una migración.
- `occurredAt` en UTC ISO-8601 con `Z`, igual que el resto de las fechas del sistema ([convenciones](../procesos/convenciones.md)).

## Idempotencia, orden y reintentos

El bus da entrega **at-least-once**: todo consumidor puede recibir el mismo evento más de una vez y tiene que tolerarlo. Estas reglas son de cumplimiento obligatorio, no una recomendación:

### Idempotencia

- Todo handler de evento es idempotente: procesar el mismo `eventId` dos veces produce el mismo resultado que procesarlo una vez.
- Para escrituras directas (inserts), usar el `eventId` o una clave de negocio como restricción única en la base y tratar el conflicto de duplicado como éxito, no como error.
- Para **proyecciones locales** (un servicio que mantiene una copia derivada del estado de otro, alimentada por eventos), la clave `{eventId}` no alcanza porque además hay que resolver el desorden: cada entidad de la proyección guarda un `lastEventAt`, y un evento entrante se aplica **solo si su `occurredAt` es más nuevo que el `lastEventAt` guardado**. Sin esto, un evento duplicado o reordenado puede pisar un estado más reciente con uno viejo.

### Orden

- El bus **no garantiza orden global** entre eventos de agregados distintos, y con cola compartida (varias instancias compitiendo por la misma cola; la topología se detalla en la próxima sección) tampoco lo garantiza entre eventos del mismo agregado.
- Ningún consumidor asume que los eventos le llegan en el orden en que ocurrieron. El mecanismo para tolerar desorden es el mismo `lastEventAt` de la regla de idempotencia: es la única fuente de verdad sobre "qué es más nuevo", no el orden de llegada.
- Si una historia necesita orden estricto para algo puntual (por ejemplo, los mensajes de un mismo emisor), ese orden se consigue por diseño del lado del productor/consumidor —una sola conexión, una sola goroutine—, no pidiéndoselo al bus.

### Reintentos y dead-letter

- Ack manual **después** de procesar el evento con éxito, nunca al recibirlo. Si el proceso se cae a mitad de camino, el evento no se pierde: vuelve a la cola.
- `prefetch` acotado por consumidor, para no acumular en memoria más de lo que se puede procesar.
- Reintento con backoff exponencial dentro del proceso ante un error transitorio, antes de dar el evento por fallido.
- Agotados los reintentos, el evento va a una dead-letter queue (`x-dead-letter-exchange`) en vez de perderse o bloquear la cola principal. Un evento en la DLQ requiere intervención manual; no hay reproceso automático.
- **Límite conocido de RabbitMQ:** no retiene historial una vez consumido. Si una proyección local se corrompe o se pierde, no se puede reconstruir releyendo el bus — hace falta un endpoint de re-sincronización en el servicio productor (fuera de alcance de CP1) o recrearla desde un seed.

## Topología de colas (RabbitMQ)

Un único exchange **topic**, durable: `discordia.events`. La routing key es el `eventType` completo (`community.member.joined`). Cada consumidor elige su patrón de binding (`community.#`, `chat.message.*`, `#` para fan-out total como hace `metrics`).

Sobre ese exchange hay dos formas de declarar una cola, y **no son intercambiables**:

| Semántica | Cómo se declara | Para qué |
|---|---|---|
| **Cola compartida por servicio** | Durable, nombre fijo (`chat.community-projection`) | Las N instancias del servicio compiten por la cola: cada evento lo procesa **una sola**. Default para todo lo que termina escribiendo en una base |
| **Cola por instancia** | `exclusive` + `auto-delete`, nombre generado por el broker al conectar | Cada instancia recibe **todos** los eventos, no compite con las demás. Único modo que hace funcionar el fan-out multiinstancia |

`chat` necesita las dos, para cosas distintas:

- **Cola compartida** para consumir los eventos de `community` que alimentan su proyección de autorización: el Mongo de `chat` es uno solo, no tiene sentido que tres instancias apliquen el mismo `member.joined` tres veces.
- **Cola por instancia** para `chat.message.sent`: cada instancia tiene un conjunto distinto de clientes WebSocket conectados, así que cada una necesita enterarse de **todos** los mensajes para reenviárselos a los suyos.
- **Cola por instancia** para `identity.user.suspended`: los sockets del usuario suspendido pueden estar en cualquier instancia, así que todas tienen que enterarse para cerrar los suyos.
- **Cola por instancia** para `chat.membership.changed`, el relevo interno de membresías: la instancia que aplica un `member.joined` o `.left` a la proyección no sabe cuál tiene al usuario conectado, así que avisa a todas y cada una actualiza las suscripciones de sus propias conexiones.

**Riesgo a tener presente:** si `chat.message.sent` se declara por error como cola compartida, el mensaje le llega a una sola instancia — es decir, a una fracción de los usuarios conectados. No tira error, solo un cliente que nunca recibe nada, y es muy difícil de diagnosticar sin saber que la topología estaba mal desde el arranque. Por eso queda escrito acá y no solo en la cabeza de quien lo implementa.

Las reglas de ack, prefetch, backoff y dead-letter (sección anterior) aplican igual a las dos semánticas.

## Eventos

| Evento | Publica | Consumen | Payload (`data`) | ADR / historia |
|---|---|---|---|---|
| `identity.user.registered` | `identity` | `metrics` (fan-out) | *A definir por `identity`* | Historia de registro — dueño `identity` |
| `community.server.created` | `community` | `metrics` (fan-out) | *A definir por `community`* | Historia de creación de servidor — dueño `community` |
| `community.channel.created` | `community` | `chat` (proyección de autorización), `metrics` (fan-out) | `{ channelId, serverId, name, type }` ¹ | SCRUM-137 |
| `community.channel.updated` | `community` | `metrics` (fan-out) | `{ channelId, name?, type? }` ¹ | SCRUM-137 |
| `community.channel.deleted` | `community` | `chat` (proyección de autorización), `metrics` (fan-out) | `{ channelId }` ¹ | SCRUM-137 |
| `community.member.joined` | `community` | `chat` (proyección de autorización), `metrics` (fan-out) | `{ serverId, userId }` ¹ | SCRUM-137 |
| `community.member.left` | `community` | `chat` (proyección de autorización), `metrics` (fan-out) | `{ serverId, userId, reason }` ¹ ³ | SCRUM-137, SCRUM-68, SCRUM-69 |
| `community.member.permissions_changed` | `community` | `chat` (proyección de autorización), `metrics` (fan-out) | `{ serverId, members: [{ userId, permissions }] }` ⁴ | SCRUM-61 |
| `chat.message.sent` | `chat` | `chat` (fan-out multiinstancia, cola por instancia), `metrics` (fan-out) | `{ messageId, channelId, serverId, authorId, content, createdAt, clientMessageId }` | SCRUM-41 |
| `chat.membership.changed` | `chat` | `chat` (relevo entre instancias, cola por instancia) | `{ serverId, userId }` ² | SCRUM-146 |
| `identity.user.suspended` | `identity` | `chat` (cierre de sockets, cola por instancia), `metrics` (fan-out) | `{ userId, suspendedBy }` ⁵ | SCRUM-81 |
| `identity.user.reactivated` | `identity` | `metrics` (fan-out) | `{ userId, reactivatedBy }` ⁵ | SCRUM-82 |

¹ Payload de los cinco eventos de `community` propuesto por `chat`, que es quien primero los necesita (proyección local de autorización). Es una propuesta, no el contrato: el dueño de `community` la confirma o la reemplaza en la historia que implementa cada evento y actualiza esta tabla en ese PR. Para el CP1 solo son obligatorios `member.joined` y `channel.created` (la demo depende de ellos); `chat` ya consume también `member.left` y `channel.deleted`, y se catalogan todos ahora para que el nombre y el payload no cambien cuando se implementen. `channel.updated` no lo consume `chat`: el nombre y el tipo de un canal no cambian quién puede escribir en él (la regla del CP1 es que ser miembro del servidor habilita todos sus canales), así que su cola ni siquiera se bindea a ese evento.

² Relevo interno de `chat`, no un hecho de negocio nuevo: lo publica la instancia que aplicó un `community.member.joined` o `.left` a su proyección, con el `eventId` de ese evento como `causationId`, para que la instancia que tiene al usuario conectado lo suscriba o lo desuscriba del servidor. No dice si el usuario entró o salió: quien lo recibe relee la proyección, así que no depende del orden de llegada ni de los duplicados. `metrics` lo recibe por su binding `#`, pero no tiene nada que contar: el hecho de negocio es el evento de `community` que lo causó.

³ `reason` dice **por qué** terminó la membresía: `left` (se fue solo), `kicked` (lo expulsaron) o `banned` (lo banearon). Agregar el campo es compatible hacia atrás y no obliga a tocar Go: `chat` ya corta el acceso con este evento desde SCRUM-137 y SCRUM-146, y puede seguir ignorando el campo. Existe para que `metrics` distinga una baja voluntaria de una sanción, y para que la interfaz pueda explicarle al usuario por qué perdió el acceso. Un consumidor que reciba un `reason` que no conoce lo trata como `left`.

⁴ **Permisos efectivos de los miembros de un servidor**, decididos por el [ADR-0011](../adr/0011-roles-y-permisos-en-community.md). Cada `permissions` es el bitmask **ya calculado** por `community`: el OR de los permisos de todos los roles de ese miembro, con el owner en todos los bits y `ADMINISTRATOR` implicando el resto. `chat` lo guarda tal cual en su proyección `memberships` y **solo chequea bits**; no rehace el OR ni la jerarquía en Go.

```json
{
  "serverId": "0f4e...",
  "members": [
    { "userId": "a1b2...", "permissions": 73 },
    { "userId": "c3d4...", "permissions": 511 }
  ]
}
```

Reglas de publicación:

- **Cuándo se publica:** al editar los permisos de un rol, al asignar o quitar un rol a un miembro, y al entrar un miembro nuevo al servidor (con lo que le dé el rol por defecto, o `0` si no hay).
- **Un evento por cambio, no uno por miembro.** `members` trae **solo los miembros afectados**, no todo el servidor: editar un rol que tienen 50 personas publica un evento con 50 entradas, y asignarle un rol a alguien publica uno con una sola. El hecho de negocio es el cambio, y cincuenta eventos serían cincuenta copias del mismo hecho con `eventId` distintos y nada que los relacione.
- **El cálculo no se delega.** La alternativa de mandar solo `{ serverId, roleId }` obligaría a `chat` a proyectar roles y asignaciones y a rehacer el OR en Go, que es justo lo que el ADR-0011 evita. Por eso el evento lleva los bitmasks resueltos aunque sea más grande.
- **Idempotencia y orden:** se aplica **por entrada de `members`**, con la misma regla que el resto de la proyección — cada miembro se actualiza solo si el `occurredAt` del evento es más nuevo que el `lastEventAt` guardado para esa membresía. Sin eso, dos ediciones seguidas del mismo rol pueden llegar al revés y dejar permisos viejos. Como la regla se evalúa por miembro, reprocesar el evento entero es seguro.
- **Cola compartida**, como los demás eventos de `community`: escribe en el Mongo de `chat`, que es uno solo.
- **Si el servidor es muy grande**, el productor puede partir el cambio en varios eventos con un subconjunto de `members` cada uno. No cambia el contrato: el consumidor ya aplica entrada por entrada.
- El bitmask **no viaja en el JWT**: cambia sin que el token cambie.

⁵ Suspensión de cuentas. `userId` es la cuenta suspendida o reactivada; `suspendedBy` y `reactivatedBy`, el `userId` del staff que hizo la acción (queda para la auditoría). El momento es el `occurredAt` del envelope: no se repite en `data`.

- **Orden dentro de `identity`:** primero marca la cuenta, después revoca todas sus sesiones (borra los refresh tokens y pone cada `jti` de access token en el denylist de Redis, [ADR-0010](../adr/0010-revocacion-de-tokens-con-redis.md)) y recién después publica. Así, cuando `chat` cierra el socket, el cliente ya no puede volver a entrar: el gateway rechaza el token tanto en la API como en el handshake del WebSocket.
- **Qué hace `chat`:** cada instancia cierra los sockets de ese `userId` con el código `4403` (ver el endpoint del WebSocket en [`contratos/chat.yaml`](contratos/chat.yaml)). Solo cierra las conexiones **abiertas antes** del `occurredAt` del evento: si el evento llega tarde, después de una reactivación y un login nuevo, no corta la sesión nueva. Con esa regla el handler no guarda estado y es idempotente: un duplicado no encuentra nada que cerrar.
- **Si una instancia estaba caída** cuando se publicó el evento, se lo pierde (la cola por instancia nace al conectar), pero tampoco tenía sockets: se cayeron con ella, y al reconectar el gateway ya rechaza el token.
- **`reactivated` no lo consume `chat`:** no hay nada que reabrir. El usuario vuelve a loguearse y obtiene un token nuevo. El perfil público lo resuelve `identity` con su propio estado, sin eventos.

## Nota sobre los dos lenguajes

Los tipos del payload se escriben dos veces: structs en Go y modelos Pydantic en Python ([ADR-0001](../adr/0001-stack-y-lenguajes-por-servicio.md)). Esta tabla es la fuente de verdad que los mantiene alineados. Si el equipo prefiere generar los tipos desde un esquema (JSON Schema, Avro, Protobuf), es un ADR nuevo.
