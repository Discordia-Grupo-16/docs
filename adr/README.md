# Índice de decisiones de arquitectura

Esta tabla es la **única página que hace falta leer** para entender el estado del diseño. Incluye los ADR transversales de este repo y los ADR de servicio que valen la pena conocer desde afuera.

Si agregás un ADR, agregá el renglón acá en el mismo PR.

## Transversales

| ID | Título | Estado | Fecha |
|---|---|---|---|
| [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) | Stack y lenguajes por microservicio | Aceptado | 2026-09-04 |
| [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) | API Gateway como punto único de entrada que publica al bus | Reemplazado parcialmente por [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) | 2026-09-04 |
| [ADR-0003](0003-tecnologia-del-bus-pubsub.md) | Tecnología del bus Pub/Sub | Aceptado | 2026-09-24 |
| [ADR-0004](0004-comunicaciones-sincronicas.md) | Comunicaciones sincrónicas permitidas | Rechazado | 2026-09-20 |
| [ADR-0005](0005-tecnologia-del-canal-de-voz.md) | Tecnología del canal de voz | Propuesto | — |
| [ADR-0006](0006-proveedor-cloud-y-cicd.md) | Proveedor cloud y pipeline de CI/CD | Propuesto | — |
| [ADR-0007](0007-gestion-de-secretos.md) | Gestión de secretos y configuración | Propuesto | — |
| [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) | Proxy WebSocket del gateway hacia `chat` como excepción al ADR-0002 | Propuesto | — |
| [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) | El gateway resuelve las requests del cliente como proxy sincrónico | Aceptado | 2026-09-19 |
| [ADR-0010](0010-revocacion-de-tokens-con-redis.md) | Revocación de tokens JWT con Redis | Propuesto | — |

## De servicio (referencia)

Viven en el repo de cada servicio, se listan acá solo si afectan a alguien de afuera.

| ID | Título | Servicio | Estado | Link |
|---|---|---|---|---|
| — | _(todavía ninguno)_ | | | |

## Estados

| Estado | Significa |
|---|---|
| `Propuesto` | Hay un PR abierto o la discusión está en curso. **No implementar todavía.** |
| `Aceptado` | Decidido. Es la referencia vigente. |
| `Rechazado` | Se evaluó y se descartó. Se conserva para no volver a discutirlo. |
| `Reemplazado por ADR-00XX` | Ya no vale. El ADR que lo reemplaza explica por qué. |
| `Reemplazado parcialmente por ADR-00XX` | Una parte de la decisión sigue vigente y otra quedó sin efecto. El ADR nuevo dice exactamente cuál es cuál. |
