# Convenciones

**Estado: acordado.** Aplica a todos los repos de la organización. Cambiar cualquiera de estas convenciones va por PR, y si toca un contrato entre servicios va además con ADR (ver [CONTRIBUTING](../CONTRIBUTING.md)).

## Repos

Ver [`git-workflow.md`](git-workflow.md#repos).

## Servicios

Minúscula, guion medio, en inglés y en singular salvo que el plural sea el dominio: `identity`, `community`, `monetization`, `chat-and-real-time`, `notifications`, `metrics`.

## HTTP

- Todo cuelga de `/api/v1/` en el gateway.
- Recursos en **plural**: `/api/v1/servers`, `/api/v1/servers/{serverId}/channels`.
- Sin verbos en la URL: la acción la da el método HTTP.
- `camelCase` en los JSON (el front es JavaScript en los tres artefactos).
- Respuestas exitosas con body: envelope `{ "data": ... }`.
- **Errores: `application/problem+json`** (RFC 7807) con el schema `ErrorResponse`, igual en los cuatro contratos. Los cinco campos son obligatorios:

```json
{
  "type": "about:blank",
  "title": "Servidor no encontrado",
  "status": 404,
  "detail": "No existe un servidor con id 7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "instance": "/api/v1/servers/7c9e6679-7425-40de-944b-e07fc1f90ae7"
}
```

- El `correlationId` **no va en el body**: viaja en el header `X-Correlation-Id`, que el gateway genera en cada request y devuelve en la respuesta ([ADR-0009](../adr/0009-gateway-proxy-sincronico-para-requests-del-cliente.md)). Es el dato que hay que adjuntar en un reporte de bug para poder seguir el flujo entre servicios.
- `title` y `detail` en **español**, a diferencia del resto de la superficie de API: son los dos únicos campos que el front puede llegar a mostrarle al usuario tal cual, así que van en el idioma del producto. Los nombres de campo, los paths y los valores de `type` siguen en inglés.
- Hoy `type` está fijado en `about:blank` en los cuatro contratos, así que **no hay un código de error machine-readable**: el front distingue por `status` y por el endpoint. Si alguna pantalla necesita más granularidad, RFC 7807 lo permite con un `type` propio, pero eso es un cambio de contrato y va con ADR.

## Tópicos y eventos

Ver [`arquitectura/eventos.md`](../arquitectura/eventos.md).

## Bases de datos

- PostgreSQL: tablas en plural y `snake_case` (`server_members`); migraciones con Alembic en los servicios Python.
- MongoDB: colecciones en plural y `camelCase` en los documentos.
- **Ningún servicio se conecta a la base de otro.** Nunca.

## Identificadores

UUID v4 para todas las entidades de dominio. No exponer ids autoincrementales en la API.

## Fechas

UTC en ISO-8601 con `Z` (`2026-09-08T14:32:00Z`), tanto en la API como en los eventos. La conversión a hora local es responsabilidad del front.

## Idioma

- Código, nombres de variables, eventos, endpoints y commits de los repos de código: **inglés**.
- Excepción: `title` y `detail` de los errores HTTP van en **español** (ver [HTTP](#http)), porque son texto que el usuario puede terminar viendo.
- Ramas: **inglés**, siguiendo el idioma del repo (ver [`git-workflow.md`](git-workflow.md#commits)).
- Documentación, ADR, informes y commits de `docs`: **español**.
## Ramas, commits y PRs

Ver [`git-workflow.md`](git-workflow.md).