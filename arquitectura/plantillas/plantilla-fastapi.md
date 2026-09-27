# Estructura de Microservicios FastAPI — Arquitectura por Dominios

Este documento describe la arquitectura y estructura estándar para los microservicios basados en **FastAPI** del backend de Discordia (`identity`, `community`, `mod`, `monetization`), utilizando una organización modular por **dominios** y tomando `identity` como arquetipo base.

## Principios de Diseño

| Principio | Descripción |
| :--- | :--- |
| **Legibilidad** | Cualquier desarrollador puede encontrar la lógica de un área específica inmediatamente mirando el nombre de la carpeta. |
| **Desacoplamiento** | El código de un módulo no interfiere con otro, permitiendo trabajo en paralelo sin conflictos. |
| **Escalabilidad** | A medida que el proyecto crece, es fácil extraer módulos y convertirlos en microservicios independientes. |

---

## 1. Estructura del Proyecto

```text
├── alembic/                     # Migraciones de base de datos
├── app/                         # Código fuente de la aplicación
│   ├── core/                    # Configuración base, DB, errores y logs transversales
│   ├── domains/                 # Lógica de negocio por dominios
│   │   └── <dominio>/           # Un dominio independiente
│   │       ├── models.py        # Modelos de BD (SQLModel / SQLAlchemy)
│   │       ├── repositories.py  # Capa de acceso a datos y consultas
│   │       ├── router.py        # Endpoints HTTP
│   │       ├── schemas.py       # DTOs de validación y respuesta (Pydantic)
│   │       └── services.py      # Lógica de negocio del dominio
│   ├── integrations/            # Conexiones con servicios/APIs externas
│   └── main.py                  # Punto de entrada y ciclo de vida
├── tests/                       # Pruebas automatizadas
│   ├── conftest.py              # Fixtures compartidas
│   ├── domains/                 # Tests organizados por dominio
│   └── test_errors.py           # Tests de infraestructura transversal
├── .coveragerc                  # Configuración de cobertura (mínimo 70%)
├── .env.example                 # Plantilla de variables de entorno
├── Dockerfile                   # Imagen del contenedor
├── docker-compose.yml           # Orquestación local (App + PostgreSQL)
├── pytest.ini                   # Configuración de pytest
└── requirements.txt             # Dependencias del servicio
```

---

## 2. Responsabilidades por Capa

### `core/`

Esta carpeta actúa como el "corazón técnico" del sistema. Contiene utilidades transversales que son utilizadas por múltiples dominios, pero que no pertenecen a ninguna regla de negocio en particular (Configuración, Conexión a Base de Datos, Manejo de errores global, Seguridad y Logging).

### `domains/` — Lógica de Negocio

Toda la lógica de negocio vive aquí, dividida en módulos (dominios) independientes. Cada dominio encapsula su propio router, lógica, persistencia y esquemas.

### `integrations/` — Servicios Externos

Conexiones y lógica que interactúa con servicios o APIs externas de terceros (o clientes HTTP hacia otros microservicios). Aislar estas integraciones garantiza que la lógica de negocio interna (`services.py`) no dependa ni se contamine con la implementación técnica de servicios de terceros.

### `tests/` — Pruebas Automatizadas

Pruebas organizadas espejando la estructura de dominios (`tests/domains/<dominio>/`), asegurando un mínimo del 70% de cobertura de código según la Definition of Done.

---

## 3. Flujo de Datos (Request Flow)

Para mantener un bajo acoplamiento y alta cohesión, el flujo estándar de una petición dentro de nuestra arquitectura sigue esta secuencia estricta:

1. **Cliente / Interfaz HTTP:** Hace la petición HTTP.
2. **`router.py`**: Actúa como el controlador. Recibe la petición, define las dependencias y delega el trabajo principal.
3. **`schemas.py` (Pydantic)**: Valida automáticamente que el cuerpo de la petición contenga los campos y tipos de datos correctos. Si la estructura es inválida, FastAPI corta el flujo respondiendo un `422 Unprocessable Entity`.
4. **`services.py`**: Es el núcleo de la lógica de negocio. Recibe los datos ya validados por Pydantic. Si requiere recursos del exterior, llama a métodos limpios en `integrations/`. Luego delega la persistencia o consulta a `repositories.py`.
5. **`models.py` (SQLModel / SQLAlchemy)**: Representa las tablas en la base de datos y los datos son persistidos o consultados a través de la sesión de base de datos inyectada.

---

## 4. Pasos para Crear un Nuevo Servicio (desde este esqueleto)

### Paso 1: Clonar la estructura desde Identity

```bash
cp -r identity/ nuevo_servicio/
cd nuevo_servicio/
```

### Paso 2: Personalizar variables y configuración

1. Modificar `.env.example` y crear el `.env`:
   - Cambiar nombres de base de datos (`DATABASE_NAME=nuevo_servicio_db`).
   - Ajustar el puerto si es necesario (`PORT=8081`).
2. En `docker-compose.yml`:
   - Actualizar nombres de contenedores y servicios.
   - Actualizar puertos mapeados.
3. En `app/main.py`:
   - Actualizar `title` y `description` en `FastAPI(...)`.
   - Modificar el logger name en `app/core/logging.py`.
4. En `app/domains/`:
   - Reemplazar los dominios iniciales por los correspondientes al nuevo servicio.

---

## 5. Comandos Frecuentes

| Acción | Comando |
| :--- | :--- |
| **Levantar entorno completo** | `docker compose up --build` |
| **Levantar en segundo plano** | `docker compose up -d` |
| **Detener contenedores** | `docker compose down` |
| **Correr suite de tests** | `docker compose run --rm <servicio> pytest` |
| **Ver reporte de cobertura** | `docker compose run --rm <servicio> coverage report` |
| **Aplicar migraciones** | `docker compose run --rm <servicio> alembic upgrade head` |
| **Crear nueva migración** | `docker compose run --rm <servicio> alembic revision --autogenerate -m "descripcion"` |
| **Verificar formato y linter** | `docker compose run --rm <servicio> ruff check .` |
| **Autofix de linter** | `docker compose run --rm <servicio> ruff check --fix .` |
