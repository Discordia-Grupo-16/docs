# ADR-0012: Permisos por canal, como excepción sobre el modelo del ADR-0011

- **Estado:** Propuesto
- **Fecha:** 2026-10-10
- **Decisores:** Persona 2 (dueña de Roles y Permisos en el CP2) propone — pendiente de aval del
  equipo en la weekly, porque cambia el payload de un evento y el hub de `chat`
- **Servicios afectados:** `community`, `chat-and-real-time`, `web-app`, `mobile`

> Este ADR **modifica parcialmente** al [ADR-0011](0011-roles-y-permisos-en-community.md): deja sin
> efecto su última consecuencia, la que dice que los permisos por canal "no entran en este modelo
> todavía". Todo el resto del ADR-0011 sigue vigente sin cambios — los bits, el OR de los roles, el
> owner con todos, `ADMINISTRATOR`, la jerarquía por `position`, y que `community` es el único que
> calcula.

## Contexto

El [ADR-0011](0011-roles-y-permisos-en-community.md) definió los permisos **por servidor**: un rol
otorga un bitmask que vale igual en todos los canales. Es lo que pide la historia obligatoria #22
(SCRUM-61, "Editar permisos de un rol"), y la consigna separa las excepciones por canal en una
historia distinta, la #57 (SCRUM-66), que es **optativa** y que el plan del CP2 difirió al CP3.

El problema apareció al revisar la **demo que el propio plan del sprint define** para dar el CP2 por
terminado (sección 8):

> *"un miembro con el rol por defecto no puede escribir en `#anuncios` ni ve `#staff`"*

Eso nombra canales concretos: implica que en los demás canales **sí** puede escribir y **sí** los
ve. Con permisos por servidor lo único demostrable es el caso extremo —un miembro que no ve ningún
canal, o que no escribe en ninguno—, que cumple el criterio escrito de SCRUM-61 pero no es lo que la
demo promete ni lo que la corrección 6 del profesor ("no poder ver, escribir ni administrar
canales") hace pensar.

Hay entonces una contradicción dentro del plan: el Anexo A define el modelo por servidor, el Anexo C
manda los permisos por canal al CP3, y la sección 8 describe una demo que los necesita. Este ADR
resuelve esa contradicción trayendo SCRUM-66 al CP2.

Restricciones que siguen aplicando:

- El [ADR-0004](0004-comunicaciones-sincronicas.md) rechaza toda llamada sincrónica entre servicios:
  `chat` no puede preguntarle los permisos a `community`.
- El ADR-0011 fija que **`community` es el único que calcula**. Cualquier forma que obligue a `chat`
  a resolver reglas de permisos en Go contradice esa decisión.
- `chat` decide en el camino caliente: valida en cada mensaje enviado y reparte cada mensaje a todas
  las conexiones del servidor. Lo que se agregue no puede costar una lectura de Mongo por mensaje.

## Opciones consideradas

### Opción A — Un bitmask absoluto por canal y rol

Cada par (canal, rol) guarda el permiso completo que vale en ese canal, y reemplaza al del servidor.

- **A favor:** es el modelo más simple de leer y de calcular; un solo campo por fila.
- **En contra:** **no compone**. Si un miembro tiene dos roles con bitmask absoluto en el mismo
  canal, no hay forma no arbitraria de combinarlos: cualquiera de los dos "gana" entero. Y obliga a
  repetir en cada canal los permisos que no cambian, así que editar un rol a nivel servidor deja de
  surtir efecto donde haya una excepción.

### Opción B — Excepciones `allow` / `deny` por canal y rol

Cada par (canal, rol) guarda dos bitmask: lo que ese canal **concede** y lo que **quita**. El
permiso efectivo en un canal es el del servidor, menos lo denegado, más lo concedido.

- **A favor:** compone bien con varios roles (los `deny` se suman entre sí y los `allow` también);
  deja distinguir "este canal no opina sobre `SEND_MESSAGES`" de "este canal lo prohíbe", que con un
  solo campo es imposible; editar el rol a nivel servidor sigue surtiendo efecto en todo lo que el
  canal no sobrescribe. Es el modelo de Discord, así que el comportamiento no sorprende a nadie.
- **En contra:** dos columnas en vez de una y un orden de aplicación que hay que respetar en todos
  lados; un permiso efectivo ya no se lee de un solo campo.

### Opción C — Una ACL por canal y usuario

Una tabla de (canal, usuario) con el permiso resultante, sin pasar por roles.

- **A favor:** la más expresiva; permite excepciones para una persona puntual.
- **En contra:** crece con miembros × canales en vez de con roles × canales, y hay que recalcularla
  entera cada vez que alguien cambia de rol o entra al servidor. Para el tamaño del TP es trabajo y
  volumen de datos sin un caso de uso que lo pida: ninguna historia necesita una excepción por
  persona.

## Decisión

Elegimos la **Opción B**.

El criterio que desempató fue **la composición**: un miembro con varios roles es el caso normal, no
el borde, y es justo donde la Opción A no tiene una respuesta defendible. La Opción C resuelve un
problema que ninguna historia plantea.

### El modelo

Una tabla nueva en `community`:

| `channel_overwrites` | |
|---|---|
| `channel_id` | el canal al que se le pone la excepción |
| `role_id` | el rol sobre el que aplica |
| `allow` | bits que este canal concede, aunque el rol no los tenga en el servidor |
| `deny` | bits que este canal quita, aunque el rol los tenga en el servidor |

Con `UNIQUE (channel_id, role_id)`: una excepción por rol y canal.

El permiso efectivo de un miembro **en un canal**:

1. Si es el owner del servidor → todos los bits.
2. `base` = el permiso efectivo en el servidor, tal como lo define el ADR-0011 (el OR de sus roles).
3. Si `base` incluye `ADMINISTRATOR` → todos los bits. **Un administrador ignora las excepciones**,
   igual que en Discord: si no, una excepción en un canal podría dejar al servidor sin nadie capaz
   de administrarlo ahí.
4. `deny` = el OR de los `deny` de las excepciones de **sus** roles en ese canal.
5. `allow` = el OR de los `allow` de esas mismas excepciones.
6. Efectivo = `(base & ~deny) | allow`.

**Primero se quita y después se concede**: un `allow` explícito gana sobre un `deny` de otro rol. Es
la regla de Discord y la que hace que dar un permiso puntual a un rol alto no quede anulado por la
restricción general.

### Cómo viaja

El evento **`community.member.permissions-changed` no cambia de nombre ni de forma general**: suma
un campo opcional con los canales donde el resultado difiere del permiso de servidor.

```json
{
  "serverId": "0f4e…",
  "members": [
    { "userId": "a1b2…", "permissions": 3, "channelOverrides": { "<id de #staff>": 2 } }
  ]
}
```

Tres propiedades que importan:

- **`channelOverrides` lleva el resultado ya calculado, no las excepciones crudas.** Mandar
  `allow`/`deny` obligaría a `chat` a rehacer el cálculo y conocer los roles del miembro, que es
  justo lo que el ADR-0011 evita.
- **Solo aparecen los canales que difieren** del permiso de servidor. En un servidor sin excepciones
  el campo va vacío y el evento es idéntico al de hoy.
- **Es compatible hacia atrás.** Un consumidor que no conozca el campo sigue funcionando con
  permisos por servidor: resuelve `permisos(canal) = channelOverrides[canal] ?? permissions`, y sin
  el campo es siempre la segunda rama.

Se publica, además de en los casos que ya define el ADR-0011, cuando se crea, edita o borra una
excepción de canal.

## Consecuencias

**Positivas**

- La demo de la sección 8 del plan del sprint pasa a ser demostrable tal como está escrita, sin
  reescribirla ni pedirle al corrector que acepte una versión más pobre.
- Cierra la corrección 6 del profesor en su lectura más exigente: un canal que un miembro no ve.
- El modelo no cambia para quien no usa excepciones: un servidor sin `channel_overwrites` se
  comporta exactamente como con el ADR-0011 solo.
- Deja el terreno listo para SCRUM-65 (reordenar jerarquía) y las demás optativas de permisos del
  CP3, sin volver a tocar el contrato.

**Negativas / costo que aceptamos**

- **El hub de `chat` tiene que filtrar el broadcast por canal.** Hoy una conexión se suscribe a
  servidores y recibe todos sus mensajes, y es el cliente el que filtra por `channelId`
  (`arquitectura/protocolo-tiempo-real.md` lo anota como limitación conocida). Con permisos por
  canal eso deja de alcanzar: el mensaje de un canal que el usuario no puede ver **no puede salir
  del servidor**. Es el cambio más caro de esta decisión y toca el núcleo del tiempo real.
- Para no pagar una lectura de Mongo por mensaje, cada conexión guarda en memoria su permiso por
  canal al suscribirse, y el relevo `chat.membership.changed` lo refresca. Eso agrega estado al hub,
  que hasta ahora solo sabía de servidores.
- Un permiso efectivo deja de leerse de un solo campo: hay que mirar la excepción del canal antes
  que el permiso del servidor, en `community`, en `chat` y en las dos interfaces.
- El evento crece con la cantidad de canales con excepción. Acotado: solo viajan los que difieren.

**Qué queda pendiente por esta decisión**

- Sigue habiendo una ventana chica entre que los permisos cambian y que el relevo llega a la
  instancia que tiene al usuario conectado. Es la misma que ya se acepta cuando alguien deja un
  servidor, y está documentada desde el CP1.
- Las excepciones por **usuario** (no por rol) quedan fuera, como en la Opción C. Ninguna historia
  las pide.
- Este ADR no cambia el estado de SCRUM-66 en el backlog: traerla al CP2 es una decisión de alcance
  que se toma en la weekly, no acá.

## Referencias

- [ADR-0011](0011-roles-y-permisos-en-community.md) — modificado parcialmente por este ADR
- [ADR-0004](0004-comunicaciones-sincronicas.md) — por qué `chat` no puede consultar por HTTP
- [`arquitectura/eventos.md`](../arquitectura/eventos.md) — payload del evento e idempotencia
- `arquitectura/protocolo-tiempo-real.md` del repo de `chat` — la limitación del broadcast por canal
- Jira: SCRUM-66 (sobrescribir permisos en un canal), SCRUM-61 (editar permisos de un rol)
