# Contratos OpenAPI

Contratos HTTP entre los tres artefactos cliente, el gateway y los servicios backend del camino crítico del CP1 (INF-01 del [Sprint 1](../../../Sprint-01-Plan-CP1.md)). Fuente de verdad para lo que cada endpoint recibe y devuelve — si el código y este archivo no coinciden, el código está mal o el contrato quedó desactualizado; en cualquier caso, se corrige en el mismo PR que lo detecta.

## Archivos

| Archivo | Servicio | Cubre |
|---|---|---|
| [`api-gateway.yaml`](api-gateway.yaml) | `api-gateway` | Punto único de entrada. Reexpone (con `$ref` cross-file) los endpoints de los tres servicios de abajo bajo `/api/v1/*`. |
| [`identity.yaml`](identity.yaml) | `identity` | Registro (#1), Login (#2), Edición y visualización de perfil propio (#4, #5). |
| [`community.yaml`](community.yaml) | `community` | Crear servidor (#6), Generar invitación (#7), Unirse vía invitación (#8), Abandonar servidor (#9), Crear/Editar/Eliminar canal (#11, #12, #13). |
| [`chat.yaml`](chat.yaml) | `chat-y-real-time` | Enviar mensaje en un canal (#15) — historial y WebSocket. |

Los números de historia son los de la tabla de [Historias obligatorias de la Consigna](../../Consigna). El alcance exacto de cada archivo (qué CA cubre y qué queda fuera de este sprint) está documentado en el `info.description` de cada uno.

## Convenciones usadas en los cuatro archivos

- **IDs:** UUID v4 en todos los servicios (`arquitectura/servicios.md`), no integer.
- **Envelope de respuesta:** `{ "data": ... }` en toda respuesta exitosa con body. Los listados paginados suman `meta` al lado de `data` (ver [Listados paginados](../../procesos/convenciones.md#listados-paginados)).
- **Errores:** `application/problem+json` con el schema `ErrorResponse` (`type`, `title`, `status`, `detail`, `instance`), igual en los cuatro archivos.
- **Identidad entre servicios:** el gateway valida el JWT del cliente (`Authorization: Bearer`) y propaga `X-User-Id` / `X-User-Role` como headers internos a `identity`, `community` y `chat-y-real-time`. Estos servicios no vuelven a validar la firma del JWT en la mayoría de sus endpoints — la excepción es `identity` en los endpoints que manipulan la sesión en sí (`logout`, `refresh`), que sí reciben el JWT completo. Ver `JwtClaims` en `identity.yaml`.
- **Multipart vs. JSON:** los endpoints que suben un archivo (crear servidor con ícono, avatar de perfil) usan `multipart/form-data`; el resto, `application/json`.

## `$ref` entre archivos

`api-gateway.yaml` referencia schemas de `identity.yaml` y `community.yaml` con `$ref` cross-file (ej. `identity.yaml#/components/schemas/RegisterUserRequest`). Esto es válido en OpenAPI 3.0, pero **algunas herramientas no lo resuelven** si se les pega un solo archivo suelto (por ejemplo, Swagger Editor online). Para esos casos, generar un bundle local antes de pegarlo — no se versiona un bundle en este repo, se regenera cuando hace falta:

```bash
npx @redocly/cli bundle api-gateway.yaml -o api-gateway.bundled.yaml
```

## Qué falta (fuera de alcance de este PR)

Historias del resto del catálogo (Roles y Permisos, Moderación, Notificaciones, Métricas, Monetización, y las optativas de Mensajería/Canal de Voz) no tienen contrato todavía. Se agregan a medida que entran al alcance de un checkpoint, en archivos nuevos bajo esta misma carpeta o extendiendo los existentes según a qué servicio pertenezcan (ver [`arquitectura/servicios.md`](../servicios.md)).
