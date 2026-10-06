# ADR-0011: Roles y permisos en `community`, con un bitmask propagado por evento

- **Estado:** Aceptado
- **Fecha:** 2026-10-05
- **Decisores:** Persona 2 (dueña de Roles y Permisos en el CP2), como implementadora de la decisión
  D2 del plan del sprint, que la deja explícitamente en manos de quien la implementa. Se presenta en
  la weekly; quien quiera cambiarla escribe un ADR que supersede a este, no se reabre la discusión.
- **Servicios afectados:** `community`, `chat-and-real-time`, `web-app`, `mobile`, `backoffice`

> Este ADR **modifica parcialmente** al [ADR-0001](0001-stack-y-lenguajes-por-servicio.md): deja sin
> efecto la fila del servicio `mod` de su tabla de servicios. El resto de esa decisión —los dos
> lenguajes, el reparto por perfil de carga y las bases de datos— sigue vigente sin cambios.

## Contexto

El CP2 tiene que cumplir la corrección 6 del profesor sobre la demo del CP1: **usar los roles**, es
decir no poder ver, escribir ni administrar canales sin el permiso correspondiente. Eso obliga a
responder dos preguntas que hasta ahora estaban abiertas: dónde viven los permisos y cómo llegan al
servicio que tiene que aplicarlos.

**Qué hay hoy.** El [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) previó un servicio `mod` para
"moderación, roles y permisos, baneos". Ese servicio **nunca se creó**, y mientras tanto el modelo de
datos creció en otro lado: `community` ya tiene las tablas `roles` (con `permissions`, `position` e
`is_default`), `member_roles` y `banned_members`, y ya expone crear y listar roles (SCRUM-60, cerrada
en el CP1). El campo `permissions` existe como entero y hoy se escribe siempre en `0`: está
reservado pero sin semántica.

**Quién necesita los permisos.** No solo `community`:

| Servicio | Qué decide | Cuándo |
| --- | --- | --- |
| `community` | Crear, editar y borrar canales y roles; expulsar; banear; listar canales | En cada request HTTP |
| `chat-and-real-time` | Suscribir a un canal, entregar historial, aceptar un mensaje, firmar el token de voz | En cada mensaje y en cada handshake |

**Restricciones que aplican:**

- El [ADR-0004](0004-comunicaciones-sincronicas.md) **rechazó toda llamada sincrónica entre
  servicios**. `chat` no puede preguntarle a `community` por los permisos de un usuario.
- `chat` decide en el camino caliente: valida en cada `MessageSendFrame`. Una consulta remota por
  mensaje es inviable aunque estuviera permitida.
- El [ADR-0003](0003-tecnologia-del-bus-pubsub.md) eligió RabbitMQ, que **no tiene replay**: lo que
  `chat` no reciba no se puede volver a leer, así que la proyección tiene que tolerar duplicados y
  desorden con la regla de `occurredAt` que ya usa (ver [`eventos.md`](../arquitectura/eventos.md)).
- El [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) parte el equipo en dos lenguajes: toda regla
  que haya que escribir en Python y en Go se escribe dos veces y se desincroniza una vez.

## Opciones consideradas

### Opción A — Crear el servicio `mod`, como decía el ADR-0001

- **A favor:** respeta la decisión original; separa moderación del dominio de comunidades; es el
  único camino si moderación crece hasta justificar su propio equipo.
- **En contra:** habría que mover `roles`, `member_roles` y `banned_members` fuera de `community`, y
  con ellos las reglas que ya usan los endpoints de canales e invitaciones. Un rol pertenece a un
  servidor y una asignación pertenece a una membresía: separarlos parte un agregado en dos bases y
  obliga a `community` a proyectar localmente lo que hoy lee con un `JOIN`. Es un servicio nuevo con
  su CI, su deploy y su base, en el sprint que además tiene la voz y el historial.

### Opción B — Roles y permisos en `community`, con un bitmask que se publica por evento

- **A favor:** no mueve ningún dato ni agrega infraestructura; el agregado "servidor" queda entero en
  un solo servicio; `community` calcula una sola vez y los consumidores solo leen bits, sin
  reimplementar reglas en Go; el campo `permissions` ya existe, así que no hay migración de esquema.
- **En contra:** `community` queda como el servicio más grande del sistema y concentra dominio y
  moderación; un bitmask es menos legible en la base que una tabla de permisos por nombre, y agregar
  un permiso obliga a respetar los números ya asignados.

### Opción C — Permisos en `community`, consultados por HTTP desde `chat`

- **A favor:** una sola fuente de verdad y sin proyección que mantener; no hay desfase entre lo que
  decide `community` y lo que ve `chat`.
- **En contra:** lo rechaza el [ADR-0004](0004-comunicaciones-sincronicas.md). Además pone a
  `community` en el camino de cada mensaje: si se cae, la mensajería se cae con él, que es
  exactamente el acoplamiento que el bus existe para evitar.

## Decisión

Elegimos la **Opción B**. **No se crea el servicio `mod`:** roles, permisos y baneos se quedan en
`community`, y la suspensión de cuentas a nivel plataforma queda en `identity`, que es dueño de la
cuenta.

El criterio que desempató no fue el costo de crear un servicio, sino **dónde está el agregado**: un
rol no existe fuera de su servidor, y una asignación de rol no existe fuera de una membresía. Partir
eso en dos bases obligaría a `community` a proyectar para responder lo que hoy resuelve con un
`JOIN`, y a cambio no compra ninguna independencia real: `mod` y `community` se desplegarían siempre
juntos porque cambian juntos.

### El modelo de permisos

Un **bitmask** sobre el campo `permissions` que ya tiene `roles`. Cada permiso es un bit fijo:

| Bit | Valor | Nombre | Qué habilita | Quién lo chequea |
| --: | ----: | --- | --- | --- |
| 0 | 1 | `VIEW_CHANNEL` | Ver el canal, su lista y su historial | `community` y `chat` |
| 1 | 2 | `SEND_MESSAGES` | Escribir en el canal | `chat` |
| 2 | 4 | `CONNECT` | Entrar a un canal de voz | `chat` |
| 3 | 8 | `MANAGE_CHANNELS` | Crear, editar y borrar canales | `community` |
| 4 | 16 | `MANAGE_ROLES` | Crear roles y editar sus permisos | `community` |
| 5 | 32 | `KICK_MEMBERS` | Expulsar miembros | `community` |
| 6 | 64 | `BAN_MEMBERS` | Banear y revocar baneos | `community` |
| 7 | 128 | `MANAGE_SERVER` | Editar la configuración del servidor | `community` |
| 8 | 256 | `ADMINISTRATOR` | Todo, sin chequear bit por bit | `community` y `chat` |

Reglas, que valen para los dos servicios:

1. **El permiso efectivo de un miembro es el OR de los permisos de todos sus roles.**
2. **El owner del servidor tiene todos los permisos**, no dependen de que tenga ningún rol.
3. **`ADMINISTRATOR` implica todos los demás.** Se chequea una sola vez, en el helper, para que
   ningún endpoint tenga que acordarse.
4. **La jerarquía sale de `position`:** nadie puede expulsar, banear ni editarle los roles a un
   miembro cuyo rol más alto esté en una posición igual o superior a la del suyo. El owner es
   inmune y no puede ser objeto de ninguna de esas acciones.
5. **Un miembro sin ningún rol tiene permiso `0`**, salvo que el servidor tenga definido un rol por
   defecto (SCRUM-63), que se le asigna al unirse.
6. **Los números de bit son fijos y no se reusan.** Si un permiso se elimina, su bit queda libre
   para siempre: el valor ya está guardado en la base de todos los servidores.

**`community` es el único que calcula.** `chat` guarda el bitmask ya resuelto en su proyección y
**solo chequea bits**; no reimplementa el OR, ni la herencia de `ADMINISTRATOR`, ni la jerarquía. Es
la misma regla que el [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) deja planteada en sus
consecuencias: lo que se escribe en los dos lenguajes se desincroniza.

### Cómo viaja

`community` publica **`community.member.permissions_changed`** cada vez que cambian los permisos de
un rol, cambia la asignación de roles de un miembro, o entra un miembro nuevo. El evento lleva el
servidor y la **lista de los miembros afectados con su bitmask ya calculado**:

```json
{ "serverId": "0f4e...", "members": [{ "userId": "a1b2...", "permissions": 73 }] }
```

**Un evento por cambio, no uno por miembro.** Editar un rol que tienen 50 personas publica un evento
con 50 entradas; asignarle un rol a alguien publica uno con una sola. Se eligió así por tres
razones:

1. **Escala en cantidad de eventos.** Un cambio de rol en un servidor grande no se convierte en una
   ráfaga de mensajes, cada uno con su envelope completo.
2. **El hecho de negocio es el cambio, no el miembro.** Cincuenta eventos serían cincuenta copias
   del mismo hecho, con `eventId` distintos y nada que los relacione entre sí.
3. **Cubre los tres casos con una sola forma.** Un miembro afectado o cincuenta es la misma
   estructura, con un array de largo distinto.

Se descartó mandar solo `{ serverId, roleId, permissions }`, que sería el mensaje más chico:
obligaría a `chat` a proyectar roles y asignaciones y a rehacer el OR y la jerarquía en Go, que es
exactamente lo que esta decisión evita. El evento lleva los bitmasks resueltos aunque pese más.

El costo aceptado es que el mensaje crece con la cantidad de miembros afectados. Si alguna vez
molestara, el productor parte el cambio en varios eventos con un subconjunto de `members` cada uno,
sin tocar el contrato: el consumidor ya aplica entrada por entrada. El payload completo y las reglas
de idempotencia están en [`eventos.md`](../arquitectura/eventos.md).

El bitmask **no viaja en el JWT**: cambia sin que el token cambie, y un token vive más que una
edición de permisos.

## Consecuencias

**Positivas**

- No se mueve ningún dato, no se crea infraestructura y no hace falta migración de esquema: el campo
  `permissions` ya existe y hoy vale `0` en todos los roles, que es exactamente "ningún permiso".
- `chat` no reimplementa reglas de autorización en Go: lee bits de una proyección que ya mantiene.
- Un solo lugar para auditar quién puede qué, que es lo que la corrección 6 pide poder mostrar.
- Habilita las optativas de permisos del CP3 (eliminar rol, reordenar jerarquía y permisos por canal)
  sin cambiar el modelo, solo agregando bits o alcance.

**Negativas / costo que aceptamos**

- **`community` queda como el servicio más grande**: servidores, canales, invitaciones, membresías,
  roles, permisos y baneos. Si moderación crece en el CP3, volver a partirlo cuesta más que hoy.
- Un bitmask es **menos legible en la base** que una tabla por nombre: `permissions = 73` no se lee
  sin la tabla de arriba al lado.
- **La proyección de `chat` puede quedar desfasada** mientras el evento viaja. Es el costo de no
  consultar sincrónicamente, y se acota con la regla de `occurredAt`: nunca se aplica un evento más
  viejo que el estado guardado.
- Nueve permisos es menos granular que Discord real. Es deliberado: alcanza para las historias del
  TP y cada bit de más es una regla que mantener en dos servicios.

**Qué queda pendiente por esta decisión**

- **El broadcast de `chat` no filtra por canal.** Hoy una conexión se suscribe a *servidores* y el
  hub le manda todos los mensajes del servidor; el cliente filtra por `channelId`. Con
  `VIEW_CHANNEL`, eso significa que un miembro **recibe por el socket mensajes de canales que no
  puede ver**, aunque la interfaz no se los muestre. Está anotado como limitación conocida en
  `arquitectura/protocolo-tiempo-real.md` del repo de `chat`, con dos salidas posibles: filtrar en
  el broadcast o bajar la suscripción a nivel de canal. **Hay que decidirlo en el CP2**, porque sin
  eso `VIEW_CHANNEL` se cumple solo en la interfaz. Puede necesitar un evento nuevo para avisarle a
  las conexiones ya abiertas, como hace hoy `chat.membership.changed`.
- Definir si el cambio de permisos tiene que notificarse a las sesiones abiertas o alcanza con que
  surta efecto en la próxima acción. `SEND_MESSAGES` ya es inmediato, porque `chat` lee la
  proyección en cada mensaje.
- Actualizar `arquitectura/servicios.md` y la tabla del ADR-0001 para que dejen de listar `mod`
  (se hace en este mismo PR).
- Los permisos por canal (sobrescribir un rol en un canal puntual) son una optativa del CP3
  (SCRUM-66) y no entran en este modelo todavía.

## Referencias

- [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) — modificado parcialmente por este ADR
- [ADR-0003](0003-tecnologia-del-bus-pubsub.md) — el bus no tiene replay
- [ADR-0004](0004-comunicaciones-sincronicas.md) — por qué `chat` no puede preguntar por HTTP
- [`arquitectura/eventos.md`](../arquitectura/eventos.md) — payload del evento e idempotencia
- Jira: SCRUM-61 (editar permisos), SCRUM-62 (asignar rol), SCRUM-63 (rol por defecto),
  SCRUM-67 (ver miembros por rol), SCRUM-69 (banear)
