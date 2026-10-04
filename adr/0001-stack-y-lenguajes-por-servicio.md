# ADR-0001: Stack y lenguajes por microservicio

- **Estado:** Modificado parcialmente por [ADR-0011](0011-roles-y-permisos-en-community.md)
- **Fecha:** 2026-09-04
- **Decisores:** equipo completo (reunión de kickoff)
- **Servicios afectados:** todos

> **Qué sigue vigente y qué no.** El [ADR-0011](0011-roles-y-permisos-en-community.md) decidió no
> crear el servicio `mod` y dejar roles, permisos y baneos en `community`.
>
> - **Sigue vigente:** los dos lenguajes de backend, el criterio de reparto por perfil de carga, las
>   bases de datos de cada servicio y el stack de los tres artefactos de front.
> - **Queda sin efecto:** la fila de `mod` en la tabla de abajo. Sus responsabilidades se reparten
>   entre `community` (roles, permisos y baneos) e `identity` (suspensión de cuentas).
>
> La tabla se conserva sin editar: es el registro de lo que se decidió en el kickoff.

## Contexto

La consigna impone restricciones duras sobre el stack:

- Cada servicio con **base de datos independiente**.
- Al menos **dos lenguajes de backend**.
- Al menos **una base SQL** y **una NoSQL**.
- Cuatro artefactos: backend, mobile, web y backoffice.

Además, el equipo son 6 personas con un cuatrimestre de calendario y checkpoints cada 3–4 semanas: cada lenguaje extra es un toolchain, un pipeline de CI y una curva de aprendizaje más.

## Opciones consideradas

### Opción A — Un solo lenguaje de backend

Descartada de entrada: la consigna exige mínimo dos.

### Opción B — Python + Go, repartidos por perfil de carga

- A favor: cumple el mínimo sin excederlo. Python/FastAPI es productivo para CRUD con reglas de negocio; Go rinde mejor en los servicios de conexiones concurrentes y larga duración (tiempo real, voz, ingesta de eventos).
- En contra: dos pipelines de CI, dos estrategias de testing para llegar al 70% de cobertura, y el conocimiento del equipo queda partido.

### Opción C — Tres o más lenguajes

- A favor: más lucimiento técnico.
- En contra: costo de setup y mantenimiento desproporcionado para el tiempo disponible; multiplica el riesgo de la red line "CI roto bloquea la evaluación".

## Decisión

Elegimos la **Opción B**: dos lenguajes de backend, repartidos según el perfil de carga de cada servicio.

| Servicio | Lenguaje | Base de datos | Responsabilidad |
|---|---|---|---|
| `api-gateway` | Go | — | Punto único de entrada (ver [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md)) |
| `identity` | Python + FastAPI | PostgreSQL | Usuarios, autenticación, perfil |
| `community` | Python + FastAPI | PostgreSQL | Servidores, canales, invitaciones, membresías |
| `mod` | Python + FastAPI | PostgreSQL | Moderación, roles y permisos, baneos |
| `monetization` | Python + FastAPI | PostgreSQL | Suscripciones y pagos |
| `chat-and-real-time` | Go | MongoDB | Mensajería y canal de voz |
| `notifications` | Go | sin DB propia | Delegación en Firebase Cloud Messaging |
| `metrics` | Go | PostgreSQL | Consumo de eventos de todos los servicios y agregación |

Front-end: `web-app` y `backoffice` en **React**, `mobile` en **React Native**.

El criterio que desempató el reparto: los servicios con muchas conexiones abiertas simultáneas y throughput de eventos (`chat-and-real-time`, `notifications`, `metrics`, `api-gateway`) van en Go; los servicios de dominio con reglas de negocio y CRUD sobre datos relacionales van en Python.

## Consecuencias

**Positivas**

- Cumple las cuatro restricciones de la consigna (≥2 lenguajes, ≥1 SQL, ≥1 NoSQL, DB por servicio) sin tecnología de más.
- MongoDB queda acotado a `chat-and-real-time`, donde el documento por mensaje es un modelo natural: nadie tiene que aprender NoSQL para trabajar en su épica salvo el equipo de mensajería.

**Negativas / costo que aceptamos**

- Dos pipelines de CI, dos herramientas de cobertura, dos formas de escribir tests.
- No hay reuso de código entre servicios Python y Go: los tipos de los eventos se duplican en ambos lados (ver [`arquitectura/eventos.md`](../arquitectura/eventos.md)).
- `notifications` sin DB propia significa que no puede reintentar ni auditar envíos por su cuenta; si eso hace falta, es un ADR nuevo.

**Qué queda pendiente por esta decisión**

- Definir el catálogo de eventos y cómo se mantiene sincronizado entre los dos lenguajes.
- Definir la estrategia de testing que llega al 70% de cobertura en ambos stacks.

## Referencias

- [`arquitectura/servicios.md`](../arquitectura/servicios.md)
- [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md)
