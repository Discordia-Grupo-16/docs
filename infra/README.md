# Entorno de demo end-to-end

Este `docker-compose.yaml` levanta **todos los servicios a la vez**, para ensayar la demo del checkpoint o para probar un flujo que cruza varios servicios sin desplegar nada. No es el entorno de desarrollo local de un servicio individual — para eso, cada repo tiene su propio compose (ver [`INF-05`](../Sprint-01-Plan-CP1.md) en el plan del sprint).

> **Estado: propuesta.** Los nombres de carpeta, de servicio y la política de puertos todavía no están validados con el resto del equipo. Revisar la sección [Pendientes](#pendientes-antes-de-darlo-por-cerrado) antes de asumir que esto es la versión final.

## Qué hace

- [`docker-compose.yaml`](./docker-compose.yaml) usa `include:` para levantar el compose de cada repo de servicio sin duplicar su definición acá. La fuente de verdad de cómo se arma cada servicio sigue siendo su propio repo.
- [`docker-compose.override.yaml`](./docker-compose.override.yaml) hace dos cosas:
  1. Le indica a `api-gateway` las URLs internas de cada servicio (`UPSTREAM_IDENTITY_URL`, `UPSTREAM_CHAT_URL`, `UPSTREAM_COMMUNITY_URL`), porque dentro de la red de Docker cada servicio se resuelve por nombre, no por `localhost`.
  2. Une todos los servicios a una red compartida (`red-local`) para que puedan verse entre sí, y le saca los puertos publicados al host a los servicios de dominio y a las bases de datos.

## Layout de carpetas esperado

`include:` usa paths relativos, así que este archivo asume que los repos están clonados como **carpetas hermanas** de esta, dentro de un mismo workspace:

```
discordia/
├── docs/                      (o discordia-docs/)
│   └── infra/
│       ├── docker-compose.yaml
│       ├── docker-compose.override.yaml
│       └── README.md          <- este archivo
├── api-gateway/
├── identity/
├── community/
└── chat-and-real-time/
```

> Los nombres de carpeta son los que surgen de un `git clone` directo de cada repo (`identity`, `community`, `chat-and-real-time`, `api-gateway`), siguiendo [`procesos/git-workflow.md`](../procesos/git-workflow.md#repos). Si el nombre de un repo cambia, actualizar el `include:` en el mismo PR que lo renombra.

Si tu clone usa otros nombres de carpeta, o los repos no están todos al mismo nivel, editá los paths del `include:` en tu copia local — no lo subas modificado salvo que sea para reflejar un renombre real del repo.

## Cómo levantarlo

Requiere **Docker Compose v2.20+** (por el soporte de `include:`). Verificá con:

```bash
docker compose version
```

Desde esta carpeta:

```bash
docker compose up --build
```

Docker Compose combina automáticamente `docker-compose.yaml` con `docker-compose.override.yaml` porque respeta ese nombre por convención. No hace falta pasar `-f` a mano.

Para bajar todo y limpiar:

```bash
docker compose down -v
```

## Acceso desde el host

Con el override actual, **la única puerta de entrada expuesta al host es `api-gateway`**. Los servicios de dominio (`identity-service`, `chat-service`, `community-service`) y sus bases de datos (`identity-db`, `community-db`, `chat-mongo`) tienen `ports: !reset []`: solo son alcanzables entre contenedores dentro de `red-local`, no desde tu máquina.

Esto refleja la arquitectura real ([ADR-0002](../adr/0002-api-gateway-y-publicacion-al-bus.md): los tres clientes hablan solo con el gateway), pero tiene un costo práctico durante el ensayo de la demo:

- No podés pegarle a `identity-service` directo con Postman/curl para descartar si un bug es del gateway o del servicio.
- No podés abrir un cliente de base de datos local contra `identity-db`, `community-db` o `chat-mongo` para mirar el estado de los datos a mitad de la demo.

**Para debuggear con los puertos abiertos**, usá [`docker-compose.demo.yaml`](./docker-compose.demo.yaml) en vez del override por defecto — ver la sección [Variante para pruebas y debugging](#variante-para-pruebas-y-debugging) más abajo. No modifiques `docker-compose.override.yaml` para esto: ese archivo es el que representa la arquitectura real (todo pasa por el gateway) y se aplica siempre por default con `docker compose up`.

## Variante para pruebas y debugging

[`docker-compose.demo.yaml`](./docker-compose.demo.yaml) es un tercer archivo, pensado para correrse **encima** de los otros dos cuando necesitás pegarle a un servicio o a una base de datos directamente — para debuggear un flujo, revisar datos a mitad de un ensayo, o correr una prueba puntual contra `community-service` sin pasar por el gateway.

No reemplaza al override por defecto: lo extiende. Se levanta con los tres archivos encadenados:

```bash
docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.demo.yaml up --build
```

Con esto, además de `api-gateway` (puerto `8080`), quedan expuestos al host (coincidiendo con los contratos de `arquitectura/contratos/`):

| Servicio | Puerto en host | Para qué |
|---|---|---|
| `identity-service` | `8001` | Pegarle directo con curl/Postman |
| `community-service` | `8002` | Pegarle directo con curl/Postman |
| `chat-service` | `8003` | Pegarle directo con curl/Postman |
| `identity-db` | `5433` | Cliente de Postgres (psql, DBeaver, etc.) |
| `community-db` | `5434` | Cliente de Postgres |
| `chat-mongo` | `27018` | Cliente de Mongo (Compass, mongosh) |
| `identity-redis` | `6380` | Cliente de Redis (redis-cli, etc.) |

Los puertos externos de DB son intencionalmente distintos a los estándar (`5432`, `27017`, `6379`, etc.) para no chocar con una instancia de Postgres/Mongo/Redis que ya tengas corriendo en tu máquina para otra cosa.

Esta variante **no se usa para la demo frente al corrector** — ahí corre solo `docker-compose.yaml` + `docker-compose.override.yaml`, con únicamente el gateway expuesto (`8080`), que es lo que refleja la arquitectura real. `docker-compose.demo.yaml` es una herramienta de trabajo del equipo, pese al nombre; si genera confusión lo renombramos a `docker-compose.debug.yaml` en un próximo PR.

## Servicios incluidos hoy

| Servicio (nombre en este compose) | Nombre canónico ([`servicios.md`](../arquitectura/servicios.md)) | Puerto publicado al host |
|---|---|---|
| `api-gateway` | `api-gateway` | Sí (`8080`) |
| `identity-service` | `identity` | No |
| `chat-service` | `chat-and-real-time` | No |
| `community-service` | `community` | No |
| `identity-db` | — | No |
| `identity-redis` | — | No |
| `community-db` | — | No |
| `chat-mongo` | — | No |

> Los nombres de la primera columna son los definitivos para el nombre de host dentro de Docker: cada servicio se llama `<dominio>-service` en su propio compose (`identity-service`, `chat-service`, `community-service`), independientemente del nombre canónico de `servicios.md`. Es una decisión tomada, no una inconsistencia a resolver — el gateway y este override dependen de que se mantenga ese sufijo `-service` en todo servicio nuevo que se agregue.

## Qué falta agregar

Este compose cubre el camino crítico del CP1 (identity, community, chat, gateway). Todavía no incluye:

- `mod` (Roles y Permisos, Moderación)
- `notifications`
- `metrics`
- `monetization`
- Los tres artefactos front (`web-app`, `backoffice`, `mobile`) — hoy se corren aparte, fuera de este compose
- El broker de Pub/Sub ([ADR-0003](../adr/0003-tecnologia-del-bus-pubsub.md)) — falta confirmar si se declara acá o en el compose de cada servicio que lo consume

A medida que un servicio nuevo entra en alcance de un checkpoint, agregar su línea en `include:` y, si el gateway le apunta directo, su override correspondiente en el mismo PR.

## Decisiones ya tomadas (no reabrir sin avisar al equipo)

- **Nombres de carpeta = nombre de `git clone`.** `identity`, `community`, `chat-and-real-time`, `api-gateway` quedan tal cual surgen de clonar cada repo (siguiendo [`procesos/git-workflow.md`](../procesos/git-workflow.md#repos)). Si el repo se renombra, el `include:` se actualiza en el mismo PR.
- **Nombres de servicio con sufijo `-service`.** `identity-service`, `community-service`, `chat-service` son los nombres de host definitivos dentro de Docker, aunque no coincidan textualmente con `arquitectura/servicios.md`. Todo servicio nuevo que se agregue a este compose mantiene el mismo sufijo.
- **Puertos alineados con los contratos OpenAPI de `dev`.** Gateway en `8080` (el mismo puerto interno del contenedor), `identity-service` en `8001`, `community-service` en `8002`, `chat-service` en `8003`.
- **RabbitMQ vive en el compose de `api-gateway`**, no en éste. Lo agregó el equipo de gateway y se levanta automáticamente al incluir `./api-gateway/compose.yaml`. Si RabbitMQ necesita configuración adicional para algún consumidor nuevo, esa configuración va en el override de quien lo consuma, no acá.

## Pendientes antes de darlo por cerrado

1. **Documentar la conexión a RabbitMQ para el resto de los servicios.** Ya sabemos dónde vive el broker, pero falta confirmar acá (o en `arquitectura/eventos.md`) qué variables de entorno espera cada servicio para conectarse (host, puerto, credenciales), para que quien agregue `mod`, `notifications` o `metrics` a este compose sepa cómo apuntarlo sin tener que leer el compose de `api-gateway` primero.
2. **Confirmar si `docker-compose.demo.yaml` necesita también exponer el puerto de RabbitMQ** (para inspeccionar colas con la management UI durante el debugging) — depende de cómo lo haya expuesto el compañero que lo subió en `api-gateway`.

## Referencias

- [`arquitectura/servicios.md`](../arquitectura/servicios.md) — nombres canónicos y responsabilidades de cada servicio
- [`arquitectura/contexto.md`](../arquitectura/contexto.md) — por qué los clientes solo hablan con el gateway
- [ADR-0002](../adr/0002-api-gateway-y-publicacion-al-bus.md) — gateway como punto único de entrada
- [ADR-0003](../adr/0003-tecnologia-del-bus-pubsub.md) — tecnología de Pub/Sub (RabbitMQ)
- [`procesos/convenciones.md`](../procesos/convenciones.md) — naming de repos y servicios