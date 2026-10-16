# ADR-0014: Despliegue de bases de datos stateful en ECS Fargate

- **Estado:** Aceptado
- **Fecha:** 2026-10-16
- **Decisores:** Equipo de Infraestructura / Backend
- **Servicios afectados:** PostgreSQL, MongoDB, Redis, RabbitMQ

## Contexto

La arquitectura de microservicios de la aplicación requiere de múltiples motores de almacenamiento y mensajería operando en simultáneo (PostgreSQL, MongoDB, Redis y RabbitMQ). Se necesita proveer estos servicios a la capa de cómputo dentro de la misma nube (AWS) teniendo en cuenta que el presupuesto es sumamente acotado y el proyecto se encuentra en una etapa donde la tolerancia a pérdida de datos transaccionales es aceptable.

## Opciones consideradas

### Opción A — Utilizar servicios administrados de AWS (RDS, DocumentDB, ElastiCache, Amazon MQ)

- A favor: Alta disponibilidad nativa, backups automatizados, mantenimiento delegado y persistencia garantizada.
- En contra: Costos operativos prohibitivos al tener que provisionar múltiples instancias dedicadas para cada motor distinto.

### Opción B — Containerizar las bases de datos en ECS Fargate

- A favor: Todo el stack se unifica bajo el mismo presupuesto de cómputo por uso de CPU/RAM, reduciendo los costos al mínimo.
- En contra: El almacenamiento de Fargate es efímero; si el contenedor se reinicia o se cae, se pierden todos los datos almacenados.

## Decisión

Elegimos **la Opción B (Containerizar las bases de datos en ECS Fargate)**.

Porque la viabilidad económica en esta fase de desarrollo prevaleció por completo sobre la necesidad de poseer persistencia de datos a largo plazo y alta disponibilidad.

## Consecuencias

**Positivas**

- Unificación del pipeline de despliegue (se gestionan igual que los microservicios).
- Ahorro drástico en la factura de AWS frente al uso de servicios administrados.

**Negativas / costo que aceptamos**

- Aceptamos que cualquier reinicio de las tareas de las bases de datos resultará en la pérdida total del estado actual (base de datos en blanco).

**Qué queda pendiente por esta decisión**

- Automatizar scripts de "seeding" (llenado de datos) para recrear estados útiles al levantarse los servicios vacíos.
- Planificar la integración de Amazon EFS a las tareas para ganar persistencia, o la migración a servicios administrados cuando el producto lo requiera comercialmente.

## Referencias

- Configuración en Terraform: `database.tf`
- [ADR-0013](0013-reduccion-de-costos-en-red.md)