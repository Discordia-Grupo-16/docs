# ADR-0003: Tecnología de Pub/Sub

- **Estado:** Aceptado
- **Fecha:** 2026-09-09
- **Decisores:** Grupo 16
- **Servicios afectados:** `identity`, `community`, `mod`, `notifications`, `chat-and-real-time`, `metrics`, `monetization`, `api-gateway`

## Contexto

El enunciado exige que la comunicación entre servicios backend sea asíncrona por defecto y que la propagación de mensajes entre instancias del servicio de mensajería se resuelva mediante un mecanismo de pub/sub, de forma que el sistema funcione con varias instancias corriendo en paralelo. Además pide consumidores idempotentes, tolerancia a mensajes duplicados o fuera de orden, y distinguir fallos transitorios (reintentar) de permanentes (compensar o notificar).

El sistema necesita el broker para dos cosas con semántica opuesta:

| | Caso A — Eventos de dominio | Caso B — Fan-out de mensajería |
| --- | --- | --- |
| Ejemplo | `member.banned`, `server.created`, `payment.confirmed` | Un mensaje de canal debe llegar a todos los WebSockets conectados |
| Consumidores | Un servicio: aunque tenga N réplicas, procesa **una** sola | **Todas** las instancias de `chat-and-real-time` |
| Pérdida aceptable | No: debe persistir y reintentarse | Sí: el mensaje ya está en MongoDB y se recupera por historial |
| Latencia | Segundos | Milisegundos |

Una tecnología puede resolver bien uno y mal el otro, así que la decisión tiene que cubrir ambos.

Restricciones que acotan las opciones:

- Dos lenguajes de backend (Python + FastAPI y Go): hace falta cliente maduro en los dos.
- El entorno local completo tiene que levantar con `docker-compose`.
- El despliegue debe usar un plan gratuito o de bajo costo.
- Ningún integrante operó un broker en producción antes, y la ventana del CP1 son 18 días.

## Opciones consideradas

### Opción A — Redis Pub/Sub

- **A favor:** la más simple de todas; latencia mínima; resuelve el Caso B casi sin código; es probable que Redis termine en el stack por otras razones igual.
- **En contra:** es *fire-and-forget*. No hay persistencia, ni `ack`, ni reintentos: un consumidor caído cinco segundos pierde definitivamente lo publicado en esa ventana. Inaceptable para el Caso A, donde la consigna exige consistencia ante fallos parciales y compensación de pagos. Redis Streams sí persiste, pero obliga a implementar a mano consumer groups, reintentos y DLQ.

### Opción B — Apache Kafka

- **A favor:** log persistente con replay desde cualquier offset; orden garantizado por partición; el mayor throughput de las cuatro opciones; es el estándar de la industria para arquitecturas event-driven.
- **En contra:** costo operativo desproporcionado para el proyecto. Hay que gestionar el cluster o pagar un servicio sin free tier razonable, y el modelo de offsets, consumer groups y rebalanceos es una curva de aprendizaje que compite con la épica de Voz, que ya es el riesgo #1 del cuatrimestre. El Caso B es además un antipatrón: crear un consumer group efímero por instancia de WebSocket es caro.

### Opción C — NATS / JetStream

- **A favor:** probablemente el mejor ajuste técnico puro. Un solo binario liviano, latencia muy baja, core NATS resuelve el Caso B de forma nativa y JetStream cubre el Caso A con persistencia.
- **En contra:** nadie del equipo lo usó, la cátedra tiene menos expertise para acompañar y el ecosistema de documentación y respuestas es más chico. En 18 días, cada hora de debugging a ciegas pesa.

### Opción D — RabbitMQ

- **A favor:** cubre los dos casos de uso con una sola pieza de infraestructura, cambiando solo la topología de colas. Trae de fábrica `ack` manual, colas durables, DLQ, TTL para backoff y routing por topic. Clientes maduros en ambos lenguajes (`aio-pika` en Python, `amqp091-go` en Go). Se levanta con una entrada de `docker-compose` y su management UI facilita depurar y mostrar el flujo en la demo. Hay free tier gestionado (CloudAMQP) para la nube. Recomendado por la cátedra, con acompañamiento docente disponible.
- **En contra:** no permite replay de eventos ya consumidos; menor throughput que Kafka; suma una dependencia de infraestructura que hay que operar y monitorear.

## Decisión

Elegimos **RabbitMQ**.

El criterio que desempató no fue el rendimiento sino **cubrir los dos casos de uso con una sola pieza de infraestructura, usando primitivas que ya vienen resueltas**. Redis quedó afuera porque obliga a elegir entre perder eventos o construir a mano la durabilidad; Kafka y NATS quedaron afuera porque su costo de aprendizaje y operación se paga en las mismas semanas en que hay que resolver la voz. El throughput extra de Kafka no lo necesitamos: la escala del TP no lo justifica.

La decisión se implementa con dos topologías distintas sobre el mismo broker:

**Caso A — eventos de dominio.** Topic exchange durable `discordia.events`, routing keys `<dominio>.<entidad>.<acción>` (ej. `mod.member.banned`). Una cola durable por servicio consumidor, compartida por sus réplicas: RabbitMQ reparte round-robin y cada evento lo procesa una sola. `ack` manual tras procesar, reintentos con backoff exponencial vía TTL + DLX, y DLQ después de N intentos.

**Caso B — fan-out de mensajería.** Topic exchange separado `discordia.realtime`, con una cola **exclusiva y auto-delete por instancia** de `chat-and-real-time`, con nombre generado por el broker. Sin durabilidad: si la instancia muere, su cola desaparece y los clientes recuperan lo perdido por el historial.

> La separación es obligatoria, no un detalle de tuning. Si el Caso B usara una cola compartida como el A, el round-robin haría que cada mensaje llegue a una sola instancia y los clientes conectados a las demás no verían nada — exactamente el escenario que la demo del CP1 tiene que probar.

## Consecuencias

**Positivas**

- Una sola dependencia de infraestructura para toda la comunicación asíncrona, en local y en la nube.
- El cliente compartido (INF-06) puede exponer una API única de `publish` / `subscribe` con un modo que selecciona la topología, ocultando la diferencia al resto del equipo.
- La management UI permite mostrarle el flujo de eventos al corrector durante la demo.

**Negativas / costo que aceptamos**

- **Sin replay histórico.** Un evento consumido y ackeado no se puede volver a leer. Si `metrics` necesitara reconstruir su estado, no podría hacerlo desde el bus: tiene que persistir rollups incrementales desde el día uno.
- **El orden no está garantizado end-to-end.** RabbitMQ lo preserva dentro de una cola con un consumidor, pero con prefetch o múltiples réplicas se pierde. Obliga a que todos los consumidores sean idempotentes y toleren desorden, usando `occurred_at` del envelope.
- **El broker es un punto único de falla.** Si RabbitMQ cae, la mensajería deja de propagarse entre instancias. Mitigación: reconexión con backoff en el cliente, y persistir el mensaje en MongoDB *antes* de publicarlo, para que el historial nunca dependa del broker.
- Un servicio más para monitorear, incluyendo la profundidad de las DLQ.

**Qué queda pendiente por esta decisión**

- Definir la política de `prefetch` por consumidor y el máximo de reintentos antes de DLQ. Se cierra al implementar INF-06 y se documenta en su README.
- Confirmar el proveedor gestionado para la nube y su free tier, junto con INF-16.
- Definir cómo se monitorean las DLQ: quién mira, con qué frecuencia y qué se hace con un mensaje muerto.

## Referencias

- Enunciado 2026C2 — Discordia, *Requisitos No Funcionales*: "Mensajería en tiempo real y Voz" e "Integridad y Flujo de Datos".
- ADR-0002 — Corte de microservicios por dominio de negocio.
- INF-02 — Contrato de eventos del bus (envelope, naming, versionado, idempotencia).