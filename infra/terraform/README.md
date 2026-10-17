# Infraestructura como Código (IaC) - Proyecto Discordia

Este directorio contiene la configuración de Terraform para desplegar la infraestructura completa del proyecto **Discordia** en Amazon Web Services (AWS).

## Arquitectura General

La infraestructura despliega:
* **Red:** VPC pública sin NAT Gateway para reducción de costos (ver `ADR-0013`).
* **Cómputo:** Clúster de ECS utilizando AWS Fargate (Serverless).
* **Almacenamiento y Colas:** PostgreSQL, MongoDB, Redis y RabbitMQ containerizados en ECS (ver `ADR-0014`).
* **Seguridad y Configuración:** Gestión híbrida usando SSM Parameter Store para secretos y S3 para variables de entorno (ver `ADR-0015`).
* **CI/CD:** Proveedor OIDC para despliegues automatizados sin credenciales estáticas vía GitHub Actions.

---

## 📋 Requisitos Previos

1. Instalar [Terraform](https://developer.hashicorp.com/terraform/downloads) (v1.5 o superior).
2. Instalar [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
3. Configurar tus credenciales de AWS ejecutando:
   ```bash
   aws configure
   ```
   *(Necesitarás tu Access Key, Secret Key y configurar la región por defecto, ej: `us-east-1`)*.

---

## 🚀 Pasos para el Despliegue

### 1. Inicializar Terraform
Prepara el directorio de trabajo descargando los proveedores necesarios (como el de AWS).
```bash
terraform init
```

### 2. Validar y Planificar
Verifica que la sintaxis sea correcta y visualiza qué recursos se van a crear, modificar o destruir.
```bash
terraform validate
terraform plan
```

### 3. Aplicar la Infraestructura
Ejecuta el despliegue en tu cuenta de AWS. Terraform te pedirá confirmación escribiendo `yes`.
```bash
terraform apply
```

> **⚠️ IMPORTANTE - Comportamiento Esperado en la Primera Ejecución:**
> Durante el primer `terraform apply`, los servicios de ECS (`gateway`, `identity`, `chat`, `community`) se crearán pero **sus tareas fallarán al intentar arrancar**. Esto es normal y esperado porque aún no existen las imágenes de Docker en ECR ni los archivos `.env` en S3. Procede inmediatamente al paso 4.

---

## ⚙️ Tareas Post-Despliegue (Requerido)

Una vez que Terraform termine de crear los recursos base (Buckets y repositorios ECR), debes proveerle a los contenedores lo que necesitan para funcionar.

### A. Cargar archivos `.env` a S3
AWS Fargate irá a buscar las variables de entorno operativas al bucket `discordia-env-configs-<TU_ACCOUNT_ID>`. Debes subir los siguientes archivos en la raíz del bucket:

* `api-gateway.env`
* `identity.env`
* `chat.env`
* `community.env`

Puedes subirlos desde la consola web de AWS S3 o usando la CLI:
```bash
# Reemplaza <TU_ACCOUNT_ID> por tu ID de cuenta de AWS de 12 dígitos
aws s3 cp ./api-gateway.env s3://discordia-env-configs-<TU_ACCOUNT_ID>/api-gateway.env
# Repetir para los demás...
```

### B. Subir las imágenes iniciales a ECR
Para que las tareas arranquen, los repositorios de Elastic Container Registry (ECR) deben tener la imagen con el tag `:latest`. Tienes dos opciones:
1. **Manual:** Hacer `docker push` de tus imágenes locales a las URLs de los repositorios ECR generados.
2. **Automático:** Disparar tus pipelines de GitHub Actions. Como Terraform ya configuró el proveedor OIDC (`oidc.tf`), GitHub Actions tiene permisos para subir las imágenes y forzar un nuevo despliegue de ECS automáticamente.

---

## 🧹 Destrucción de la Infraestructura

Si necesitas apagar todos los recursos para dejar de incurrir en costos (por ejemplo, al finalizar el entorno de desarrollo/pruebas), ejecuta:

```bash
terraform destroy
```
*Nota: Asegúrate de vaciar manualmente el bucket de S3 y los repositorios ECR de imágenes antes de ejecutar este comando, o Terraform podría arrojar un error impidiendo borrar un recurso que no esté vacío.*

---

## 📚 Enlaces Útiles
* DNS del Balanceador de Carga (API Pública): Disponible en la salida de consola al finalizar el `apply` (`alb_dns_name`).
* [Documentación de Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)