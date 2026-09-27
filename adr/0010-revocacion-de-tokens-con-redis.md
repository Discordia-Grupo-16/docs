# ADR-0010: Revocación de tokens JWT con Redis

- **Estado:** Propuesto
- **Fecha:** 2026-09-23
- **Decisores:**
- **Servicios afectados:** `identity`, `api-gateway`

## Contexto

El CA5 de la historia de login exige que al cerrar sesión el sistema **invalide la sesión actual** y **rechace reutilizar ese token para acciones autenticadas posteriores**:

> Dado que un usuario tiene una sesión activa, cuando elige cerrar sesión, entonces el sistema invalida la sesión actual, lo dirige a la pantalla de login y rechaza reutilizar ese token para acciones autenticadas posteriores.

Hoy el flujo de logout (`DELETE /api/v1/sessions`) elimina el refresh token del lado del servidor, pero el access token sigue siendo válido hasta que expira. Como el access token es un JWT firmado y stateless, el gateway lo acepta mientras la firma y el `exp` sean correctos: no hay forma de rechazarlo antes de su vencimiento natural.

El problema es que un JWT ya emitido no se puede "borrar": la única manera de invalidarlo antes de su expiración es mantener un registro de tokens revocados y consultarlo en cada request autenticada. Ese registro tiene que ser:

- **Rápido**: se consulta en cada request, así que agregar latencia perceptible al proxy es inaceptable.
- **Volátil**: un token revocado solo necesita existir hasta su expiración natural — después el JWT se rechaza solo por `exp`.
- **Compartido**: `identity` es quien sabe que hubo un logout; `api-gateway` es quien decide si deja pasar la request.

El [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) establece que el gateway valida el JWT y propaga identidad. Hoy esa validación es puramente criptográfica (firma + expiración). Este ADR agrega una segunda verificación: que el token no haya sido revocado.

## Opciones consideradas

### Opción A — Blacklist en la base de datos de `identity`

El gateway consulta a `identity` (vía HTTP) en cada request autenticada para saber si el `jti` fue revocado.

- A favor: no agrega infraestructura nueva; reutiliza PostgreSQL que ya existe.
- En contra: agrega una llamada sincrónica servicio→servicio en **cada request**, contradiciendo el espíritu del [ADR-0004](0004-comunicaciones-sincronicas.md) y del [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md), que mantiene la comunicación entre servicios backend 100% asincrónica. Además, duplica la latencia del proxy: el gateway haría dos llamadas HTTP (una a `identity` y una al servicio destino) por cada request. Si `identity` se cae, ninguna request autenticada pasa.

### Opción B — Blacklist en Redis, compartido entre `identity` y `api-gateway`

`identity` escribe el `jti` del token revocado en Redis con un TTL igual al tiempo restante hasta la expiración del JWT. El gateway consulta Redis antes de reenviar la request; si el `jti` está presente, responde `401`.

- A favor: Redis es un store en memoria diseñado para lookups de clave por valor con latencia sub-milisegundo. El TTL nativo evita limpiar registros expirados. No introduce una llamada sincrónica entre servicios: ambos hablan con un store de datos compartido, no entre sí. Es el patrón estándar de la industria para revocación de JWT (token blacklist / denylist).
- En contra: agrega un componente de infraestructura nuevo (Redis) que hay que desplegar, monitorear y mantener. Si Redis se cae, el gateway tiene que decidir qué hacer (fail open o fail closed).

### Opción C — Access tokens de vida muy corta + solo revocar el refresh token

Reducir el `exp` del access token a unos pocos segundos (e.g. 30 s) para que al revocar el refresh token la ventana de reutilización sea mínima.

- A favor: no agrega infraestructura; el logout actual (borrar el refresh token) ya bastaría en la práctica.
- En contra: no cumple el CA5 al pie de la letra — el token sigue siendo válido por esa ventana. Además, obliga al front a refrescar el token constantemente, multiplicando las requests a `identity` y haciendo que cualquier interrupción del refresh cierre la sesión del usuario.

## Decisión

Elegimos la **Opción B**: blacklist de `jti` en Redis con TTL.

El criterio que desempató: es la única opción que cumple el CA5 literalmente (el token queda invalidado de forma inmediata) sin violar la regla de que los servicios backend no se llaman entre sí sincrónicamente. Redis no es un servicio de negocio sino un store de infraestructura compartido — en la misma categoría que la clave secreta del JWT, que ya se comparte entre `identity` y `api-gateway` por configuración.

### Flujo de logout

```
cliente ──DELETE /api/v1/sessions──► api-gateway ──proxy──► identity
                                                              │
                                                              ├─ elimina el refresh token de la DB
                                                              ├─ extrae el jti y el exp del access token
                                                              ├─ SETEX jti <ttl_restante> en Redis
                                                              └─ responde 204
```

### Flujo de verificación en cada request autenticada

```
cliente ──request──► api-gateway
                        │
                        ├─ verifica firma y exp del JWT (como hoy)
                        ├─ GET jti en Redis
                        │    ├─ existe → 401 (token revocado)
                        │    └─ no existe → continúa
                        └─ proxy al servicio destino
```

### Despliegue de Redis

El contenedor de Redis se agrega al `docker-compose.yml` de `identity`, junto a la base PostgreSQL. La razón: todo lo relacionado con la gestión de sesiones (emisión de tokens, refresh, revocación) es responsabilidad del dominio de `identity`, y Redis es la infraestructura que soporta esa responsabilidad. El gateway es un **consumidor de lectura** de ese Redis, igual que es un consumidor de la clave secreta del JWT.

### Política ante caída de Redis

Si el gateway no puede conectarse a Redis, deja pasar la request (**fail open**). La justificación: el access token ya fue verificado criptográficamente y no está expirado; la revocación es una mejora de seguridad, no el mecanismo primario de autenticación. Una caída de Redis no debe convertirse en una denegación de servicio para todos los usuarios. Se loguea un warning en cada fallo de conexión para que se detecte rápido.

## Consecuencias

**Positivas**

- Se cumple el CA5: el token queda inutilizable de forma inmediata tras el logout.
- La verificación agrega latencia despreciable (< 1 ms por lookup en Redis).
- No se introduce comunicación sincrónica entre servicios de negocio: Redis es infraestructura compartida, no un servicio que procesa lógica.
- Los tokens expirados se limpian solos gracias al TTL nativo de Redis; no hace falta un job de limpieza.
- El patrón es extensible: si en el futuro se necesita revocar tokens por otras razones (cambio de contraseña, baneo), el mecanismo ya existe.

**Negativas / costo que aceptamos**

- Un componente de infraestructura más que desplegar y monitorear en producción.
- Si Redis se cae, hay una ventana donde tokens revocados podrían ser aceptados (fail open). Es un tradeoff aceptable frente a bloquear a todos los usuarios.
- El gateway adquiere una dependencia de red nueva (conexión a Redis), aunque con política de degradación graceful.

### Variables de entorno de conexión a Redis

Ambos servicios (`identity` y `api-gateway`) usan las mismas variables. Los valores por defecto apuntan al contenedor de Redis del compose de `identity`.

| Variable | Default | Descripción |
|---|---|---|
| `REDIS_HOST` | `localhost` | Host del servidor Redis |
| `REDIS_PORT` | `6379` | Puerto del servidor Redis |
| `REDIS_PASSWORD` | _(vacío)_ | Contraseña. En desarrollo se deja vacía; en producción se configura |
| `REDIS_DB` | `0` | Número de base de datos lógica de Redis |

## Referencias

- [ADR-0009](0009-gateway-proxy-sincronico-para-requests-del-cliente.md) — el gateway como proxy sincrónico y validador del JWT
- [ADR-0001](0001-stack-y-lenguajes-por-servicio.md) — stack por servicio
- Enunciado 2026C2 — Discordia, historia *Login con email y contraseña*, CA5
