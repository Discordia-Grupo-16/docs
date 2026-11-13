# Índice de decisiones de arquitectura

Esta tabla es la **única página que hace falta leer** para entender el estado del diseño. Incluye los ADR transversales de este repo y los ADR de servicio que valen la pena conocer desde afuera.

Si agregás un ADR, agregá el renglón acá en el mismo PR.

## Transversales

| ID | Título | Estado | Fecha |
|---|---|---|---|
| [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) | Stack y lenguajes por microservicio | Reemplazado parcialmente por [ADR-0011](0011-roles-y-permisos-en-community.md) | 2026-09-04 |
| [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) | API Gateway como punto único de entrada que publica al bus | Reemplazado parcialmente por [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) | 2026-09-04 |
| [ADR-0003](0003-tecnologia-del-bus-pubsub.md) | Tecnología del bus Pub/Sub | Aceptado | 2026-09-24 |
| [ADR-0004](0004-comunicaciones-sincronicas.md) | Comunicaciones sincrónicas permitidas | Rechazado | 2026-09-20 |
| [ADR-0005](0005-tecnologia-del-canal-de-voz.md) | Tecnología del canal de voz | Aceptado | 2026-10-11 |
| [ADR-0006](0006-proveedor-cloud-y-cicd.md) | Proveedor cloud y pipeline de CI/CD | Aceptado | 2026-10-16 |
| [ADR-0007](0007-gestion-de-secretos.md) | Gestión de secretos y configuración | Reemplazado por [ADR-0015](0015-gestion-de-configuracion.md) | — |
| [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) | Proxy WebSocket del gateway hacia `chat` como excepción al ADR-0002 | Aceptado | 2026-10-04 |
| [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) | El gateway resuelve las requests del cliente como proxy sincrónico | Aceptado | 2026-09-19 |
| [ADR-0010](0010-revocacion-de-tokens-con-redis.md) | Revocación de tokens JWT con Redis | Aceptado | 2026-09-24 |
| [ADR-0011](0011-roles-y-permisos-en-community.md) | Roles y permisos en `community`, con un bitmask propagado por evento | Aceptado | 2026-10-05 |
| [ADR-0012](0012-permisos-por-canal.md) | Permisos por canal, como excepción sobre el modelo del ADR-0011 | Propuesto | 2026-10-10 |
| [ADR-0013](0013-reduccion-de-costos-en-red.md) | Reducción de costos en red | Aceptado | 2026-10-16 |
| [ADR-0014](0014-despliegue-de-bases-de-datos.md) | Despliegue de bases de datos stateful en ECS Fargate | Aceptado | 2026-10-16 |
| [ADR-0015](0015-gestion-de-configuracion.md) | Gestión Híbrida de Secretos (SSM) y Configuraciones (S3) | Aceptado | 2026-10-16 |
| [ADR-0017](0017-eventos-de-ui-por-el-websocket.md) | Eventos de UI por el WebSocket de `chat`, en lugar del polling del front | Reemplazado parcialmente por [ADR-0019](0019-suscripcion-a-avisos-separada-de-mensajes.md) | 2026-11-01 |
| [ADR-0018](0018-recupero-segundo-factor-y-ticket-del-websocket.md) | Recupero de contraseña, segundo factor y ticket de un solo uso del WebSocket | Propuesto | 2026-11-07 |
| [ADR-0019](0019-suscripcion-a-avisos-separada-de-mensajes.md) | Suscripción a avisos separada de la de mensajes en `chat` | Aceptado | 2026-11-12 |

## De servicio (referencia)

Viven en el repo de cada servicio, se listan acá solo si afectan a alguien de afuera.

| ID | Título | Servicio | Estado | Link |
|---|---|---|---|---|
| ADR-0001 | Un rol nuevo nace abajo de la jerarquía | `community` | Aceptado | [repo de community](https://github.com/Discordia-Grupo-16/community/blob/develop/docs/adr/0001-posicion-de-los-roles-nuevos.md) |
| ADR-0001 | Brevo como proveedor de email del recupero de contraseña | `identity` | Aceptado | [repo de identity](https://github.com/Discordia-Grupo-16/identity/blob/develop/docs/adr/0001-proveedor-de-email.md) |

## Estados

| Estado | Significa |
|---|---|
| `Propuesto` | Hay un PR abierto o la discusión está en curso. **No implementar todavía.** |
| `Aceptado` | Decidido. Es la referencia vigente. |
| `Rechazado` | Se evaluó y se descartó. Se conserva para no volver a discutirlo. |
| `Reemplazado por ADR-00XX` | Ya no vale. El ADR que lo reemplaza explica por qué. |
| `Reemplazado parcialmente por ADR-00XX` | Una parte de la decisión sigue vigente y otra quedó sin efecto. El ADR nuevo dice exactamente cuál es cuál. |
