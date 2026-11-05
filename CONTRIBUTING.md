# Cómo contribuir a la documentación

## Flujo

Igual que el código: **nadie escribe directo en `develop` ni en `main`.**

1. Rama desde `develop`: `docs/<tema-corto>` o `adr/<numero>-<slug>`.
2. Commit y PR contra `develop`.
3. **Un reviewer aprueba** (no el autor). Para ADR transversales conviene que sea alguien de otra épica.
4. Merge commit a `develop`. `develop` → `main` en cada checkpoint, con tag `x.y.z`.

## ¿Esto necesita un ADR?

Sí, si la respuesta a alguna de estas es "sí":

- ¿Cambia un contrato entre dos servicios (evento, endpoint, esquema)?
- ¿Elige una tecnología que después es cara de cambiar (bus, DB, cloud, framework)?
- ¿Contradice o justifica una restricción de la consigna (comunicación sincrónica, lenguajes, tipo de DB)?
- ¿Alguien del equipo va a preguntar "¿y por qué hicimos esto?" dentro de un mes?

No, si es una elección interna de un servicio que se puede revertir sin avisarle a nadie (una librería, la estructura de carpetas, cómo se ordenan los tests).

## ¿ADR global o del servicio?

> **Si la decisión la puede revertir un solo equipo sin romper a nadie, va en el repo del servicio. Si toca un contrato entre servicios o una restricción de la consigna, va acá.**

| Va en `docs/adr/` | Va en `<servicio>/adr/` |
|---|---|
| Tecnología del bus, formato de eventos | Librería de validación, ORM |
| Comunicaciones sincrónicas entre servicios | Estructura de carpetas del proyecto |
| Elección de lenguaje y motor de DB por servicio | Estrategia de mocks en los tests |
| Proveedor cloud, CI/CD, secretos | Naming interno de módulos |
| Autenticación y propagación de identidad | Formato de logs internos |

## Numeración

- Transversales: `ADR-0001`, `ADR-0002`, … secuencial y **nunca se reusa un número**.
- De servicio: `ADR-IDENTITY-0001`, `ADR-METRICS-0001`, … prefijo = nombre del servicio en mayúsculas.

El número se reserva al abrir el PR. Si dos PR toman el mismo número, el que mergea segundo renumera.

## Ciclo de vida de un ADR

```
Propuesto ──► Aceptado ──► Reemplazado por ADR-00XX
    │
    └──► Rechazado
```

- Se abre el PR con estado `Propuesto`.
- Al mergear pasa a `Aceptado` con la fecha del merge.
- **Un ADR aceptado no se edita.** Si la decisión cambia, se escribe uno nuevo y al viejo se le pone `Reemplazado por ADR-00XX`. El historial de por qué cambiamos de idea es tan valioso como la decisión actual.
- Correcciones de typos o links sí se editan, obvio.

## Qué NO va en este repo

- Backlog, historias, estimaciones → Jira
- Actas de reunión y coordinación → Discord
- Notas personales
- Cualquier secreto, credencial, `.env` real o string de conexión → **red line de la consigna**
