# ADR-0015: Gestión Híbrida de Secretos (SSM) y Configuraciones (S3)

- **Estado:** Aceptado
- **Fecha:** 2026-10-16
- **Decisores:** Equipo de Infraestructura / Seguridad
- **Servicios afectados:** Todos los microservicios en ECS y API Gateway

## Contexto

Las aplicaciones backend requieren credenciales confidenciales (contraseñas de BD, secretos JWT) y variables operativas generales (nombres de entorno, configuraciones de framework). Poner estos valores estáticos en el repositorio de código de Terraform o en las definiciones de las tareas expone la seguridad y obliga a volver a aplicar la infraestructura completa (`terraform apply`) cada vez que un desarrollador requiere cambiar un simple flag operativo.

## Opciones consideradas

### Opción A — Inyectar todo en texto plano desde Terraform

- A favor: Simplicidad absoluta de despliegue sin depender de servicios externos de configuración.
- En contra: Alto riesgo de seguridad y acoplamiento severo entre el ciclo de vida del código de infraestructura y los cambios menores en la aplicación.

### Opción B — Almacenar todo en AWS Systems Manager (SSM Parameter Store)

- A favor: Gestión nativa centralizada y segura.
- En contra: Dificulta la gestión de decenas de variables no sensibles, engrosando y haciendo ilegible la Task Definition en Terraform.

### Opción C — Enfoque híbrido: Secretos en SSM y archivo .env en S3

- A favor: Máxima seguridad cifrada para las credenciales en Parameter Store y agilidad operativa utilizando un archivo plano cargado en un bucket privado para variables inofensivas.
- En contra: Requiere configurar múltiples permisos y políticas de IAM granulares en los roles de ejecución de ECS.

## Decisión

Elegimos **la Opción C (Enfoque híbrido: Secretos en SSM y archivo .env en S3)**.

Porque resolvió la necesidad de permitir modificar configuraciones operativas rápidamente alterando un simple archivo, sin comprometer nunca la seguridad de las contraseñas criptográficas ni requerir redespliegues forzados de infraestructura.

## Consecuencias

**Positivas**

- Cumplimiento de mejores prácticas de seguridad (Zero-Trust para los secretos).
- Agilidad en el día a día para cambios de variables operativas.

**Negativas / costo que aceptamos**

- Aceptamos la sobrecarga administrativa inicial en Terraform al tener que gestionar roles de IAM más complejos (`ecs_ssm_policy` y `ecs_s3_policy`).

**Qué queda pendiente por esta decisión**

- Incluir el proceso de carga y actualización del archivo `.env` hacia S3 en las guías del desarrollador o automatizarlo vía CI/CD.

## Referencias

- Configuración en Terraform: `secrets.tf`, `s3.tf`, `ecs.tf`