# ADR-0019: Suscripción a avisos separada de la de mensajes en `chat`

- **Estado:** Propuesto
- **Fecha:** 2026-11-11
- **Decisores:** Persona 4, con la aprobación de la Persona 2 (dueña de INF-30 y del
  [ADR-0017](0017-eventos-de-ui-por-el-websocket.md)).
- **Servicios afectados:** `chat-and-real-time`. Los clientes (`web-app`, web y mobile) no cambian:
  reciben los mismos avisos, ahora también en los servidores donde no tienen `VIEW_CHANNEL`.

> Este ADR **modifica parcialmente** el [ADR-0017](0017-eventos-de-ui-por-el-websocket.md): cambia a
> quién le llegan los avisos de servidor. El resto del ADR-0017 sigue vigente.

## Contexto

El [ADR-0017](0017-eventos-de-ui-por-el-websocket.md) entrega los avisos de servidor con
`Broadcast(serverId)`, el mismo envío que usan los mensajes del chat. Llega a las conexiones
suscriptas a ese servidor, y una conexión se suscribe solo a los servidores donde el usuario tiene
`VIEW_CHANNEL`. Así tiene que ser para los mensajes: quien no ve los canales no tiene que recibirlos.

Para los avisos, ese filtro deja afuera a miembros que sí tienen que enterarse. El ADR-0017 lo
aceptó como costo: un miembro sin `VIEW_CHANNEL` depende del respaldo de 60 segundos. Eliminar un
rol (SCRUM-64) pide que el rol desaparezca para **todos** los miembros del servidor en hasta
5 segundos, y ese miembro también ve la lista de roles y la de miembros. Lo mismo pasa con el aviso
de cambio de perfil: hoy solo llega a los servidores donde el dueño del perfil tiene `VIEW_CHANNEL`.

## Opciones consideradas

### Opción A — Seguir con el respaldo de 60 segundos

- A favor: no cambia nada.
- En contra: un miembro sin `VIEW_CHANNEL` ve el cambio hasta 60 segundos tarde, lo que no cumple
  el plazo de SCRUM-64. La deuda sigue para cualquier aviso nuevo.

### Opción B — Avisar a cada miembro por usuario, leyendo la proyección

Para cada aviso de servidor, `chat` lee de su proyección los miembros activos y le manda el aviso a
cada uno con `SendToUser`.

- A favor: no toca el hub.
- En contra: una lectura de Mongo por cada evento, en cada instancia, y una solución por evento:
  cada aviso nuevo que tenga que llegarles a todos repite el mismo código.

### Opción C — Dos suscripciones por conexión

Cada conexión tiene una suscripción a los mensajes, que pide `VIEW_CHANNEL`, y otra a los avisos,
que pide solo ser miembro activo.

- A favor: los avisos de servidor les llegan a todos los miembros, sin lecturas por evento. Arregla
  todos los avisos de servidor de una vez, también los que se agreguen después.
- En contra: cambia el hub, la foto al conectar y el relevo de membresías, que es la parte más
  delicada de `chat`.

## Decisión

Elegimos **la Opción C**.

Porque es la única que les entrega los avisos a todos los miembros sin una lectura por evento, y lo
resuelve en un solo lugar para todos los avisos de servidor, no para cada uno.

Cómo queda:

| Suscripción | Quién está | Qué recibe | Cómo se envía |
| --- | --- | --- | --- |
| De mensajes (la de siempre) | Miembros activos con `VIEW_CHANNEL` | Frames con datos: mensajes y participantes de voz | `Broadcast(serverId)` |
| De avisos (nueva) | Todos los miembros activos | Los `invalidate` con alcance de servidor | `BroadcastNotice(serverId)` |

- **Al conectar,** la conexión se suscribe a los mensajes con `ActiveServers`, como hasta ahora, y a
  los avisos con `MemberServers`: las membresías activas del usuario, sin filtrar por permisos. Si
  falla cualquiera de las dos lecturas, la conexión se cierra con `1011`.
- **El relevo `chat.membership.changed`** mantiene las dos. Para quien está conectado en la
  instancia, relee si es miembro activo (decide la suscripción a avisos) y si tiene `VIEW_CHANNEL`
  (decide la de mensajes). Quien pierde `VIEW_CHANNEL` deja de recibir mensajes y sigue recibiendo
  avisos; quien se va del servidor pierde las dos.
- **Los avisos de servidor** de la tabla del ADR-0017 salen por `BroadcastNotice`. `SendToUser` no
  cambia.
- **El aviso de cambio de perfil** elige los servidores del usuario con `MemberServers`, sin mirar
  su `VIEW_CHANNEL`. Así llega también a los servidores donde el dueño del perfil no ve los canales.

## Consecuencias

**Positivas**

- Todos los miembros activos reciben los avisos de servidor en el momento, tengan o no
  `VIEW_CHANNEL`.
- Sin lecturas de Mongo por evento. La única sigue siendo la del aviso de cambio de perfil, que ya
  existía.
- Un aviso nuevo con alcance de servidor les llega a todos sin trabajo extra.

**Negativas / costo que aceptamos**

- Algunas relecturas más de los clientes: las de los miembros sin `VIEW_CHANNEL`, cuando cambia algo
  de su servidor.
- Un cambio en el hub, que maneja la concurrencia de todas las conexiones. Lo cubren tests que
  verifican que un mensaje no le llega a una conexión suscripta solo a los avisos.
- Quien agrega un aviso de servidor tiene que usar `BroadcastNotice` y no `Broadcast`.

**Qué queda pendiente por esta decisión**

- Nada que no estuviera pendiente en el ADR-0017. El aviso no lleva datos, solo nombres de recursos
  y el `serverId`, y quien lo recibe ya puede leer esos recursos por HTTP: no se expone nada nuevo.

## Referencias

- [ADR-0017](0017-eventos-de-ui-por-el-websocket.md): los avisos de UI por el WebSocket.
- [ADR-0011](0011-roles-y-permisos-en-community.md): `VIEW_CHANNEL` y la proyección de permisos.
- SCRUM-64 (Eliminar rol) y SCRUM-35 (Transferir propiedad del servidor).
