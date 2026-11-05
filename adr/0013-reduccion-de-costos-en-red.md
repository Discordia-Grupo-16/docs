# ADR-0013: Reducción de costos en red

- **Estado:** Aceptado
- **Fecha:** 2026-10-16
- **Decisores:** Equipo de Infraestructura
- **Servicios afectados:** Clúster ECS, todos los microservicios

## Contexto

El clúster ECS con contenedores Fargate necesita salida a internet para descargar las imágenes de Docker desde los repositorios (ECR y Docker Hub) y funcionar correctamente. La arquitectura estándar en la nube dicta que el cómputo debe ir en subredes privadas, utilizando un NAT Gateway en una subred pública para salir a internet de forma segura. El problema es que el NAT Gateway implica un costo fijo mensual mínimo (aprox. $30 USD) que impacta fuertemente en el presupuesto de las etapas iniciales del proyecto.

## Opciones consideradas

### Opción A — Subredes privadas con NAT Gateway

- A favor: Respeta las mejores prácticas de seguridad de AWS (los contenedores no quedan expuestos directamente a internet).
- En contra: Introduce un costo base elevado y constante, además de cargos extra por volumen de datos procesados.

### Opción B — Subredes públicas con IP pública asignada

- A favor: Costo cero de enrutamiento; no requiere recursos intermedios facturables de red.
- En contra: Los contenedores obtienen una dirección IP pública enrutable, delegando toda la responsabilidad perimetral a los Security Groups.

## Decisión

Elegimos **la Opción B (Subredes públicas con IP pública asignada)**.

Porque el presupuesto limitado para la etapa inicial del proyecto hizo inaceptable asumir el costo fijo mensual de un recurso de red, priorizando el ahorro mientras mitigamos el riesgo mediante estrictas reglas de Firewall (Security Groups).

## Consecuencias

**Positivas**

- Eliminación total de los costos base de infraestructura de red (NAT Gateway).

**Negativas / costo que aceptamos**

- Aceptamos el riesgo teórico de que los nodos tengan IPs públicas, confiando ciegamente en que las reglas "deny-all" de entrada de los Security Groups (`databases_sg` e `internal_services_sg`) estén siempre correctamente configuradas.

**Qué queda pendiente por esta decisión**

- Monitorear posibles intentos de acceso directo en los logs de flujo de la VPC.
- Revaluar la migración a subredes privadas cuando el proyecto pase a una fase de producción masiva con un mayor presupuesto.

## Referencias

- Configuración en Terraform: `network.tf`, `security.tf`