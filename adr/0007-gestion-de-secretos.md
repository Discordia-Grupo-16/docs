# ADR-0007: Gestión de secretos y configuración

- **Estado:** Reemplazado por [ADR-0015](0015-gestion-de-configuracion.md)
- **Fecha:** —
- **Decisores:** _(a completar)_
- **Servicios afectados:** todos

> **Reemplazado por el [ADR-0015](0015-gestion-de-configuracion.md).** Este ADR nunca llegó a una
> decisión: la tomó el ADR-0015, con los secretos en SSM y la configuración en un `.env` en S3 para
> AWS. Las barreras mínimas de abajo siguen vigentes como regla operativa en
> [`git-workflow.md`](../procesos/git-workflow.md#secretos). Se conserva como registro de las
> opciones que se evaluaron.

> **Red line de la consigna: secretos commiteados en el repositorio bloquean la evaluación.** Esto no es una decisión de gusto — es la única decisión de este repo que puede invalidar el trabajo de todo el cuatrimestre en un solo commit.

## Contexto

El sistema va a manejar, como mínimo: credenciales de PostgreSQL y MongoDB, la clave de firma de JWT, credenciales del bus, la service account de Firebase Cloud Messaging, las API keys del canal de voz ([ADR-0005](0005-tecnologia-del-canal-de-voz.md)), credenciales de la pasarela de pagos de `monetization` y los tokens de deploy.

Son 8 repos y 6 personas. La probabilidad de que alguien commitee un `.env` sin querer no es baja.

## Opciones consideradas

### Opción A — `.env` local + GitHub Secrets para CI/CD

- A favor: cero infraestructura; `.env.example` versionado documenta qué variables hacen falta; GitHub Secrets ya está disponible.
- En contra: los secretos de desarrollo circulan a mano entre el equipo (Discord, mensajes privados); rotarlos es manual.

### Opción B — Secret manager del proveedor cloud

- A favor: rotación y auditoría reales; los servicios leen del manager al arrancar.
- En contra: ata la decisión a [ADR-0006](0006-proveedor-cloud-y-cicd.md); no resuelve el desarrollo local, que igual necesita `.env`.

### Opción C — Secretos cifrados en el repo (SOPS, git-crypt, sealed secrets)

- A favor: todo versionado, una sola fuente de verdad.
- En contra: hay que manejar la clave maestra igual; **riesgo alto de que un corrector lea "secretos en el repo" y aplique la red line sin mirar si están cifrados**.

## Decisión

_(a completar)_

## Barreras mínimas, independientemente de la opción elegida

Esto debería implementarse ya, sin esperar a que se cierre el ADR:

- [ ] `.gitignore` con `.env`, `*.pem`, `*.key`, `*credentials*.json` en **los 8 repos**
- [ ] `.env.example` versionado en cada servicio, con nombres de variables y valores dummy
- [ ] Escaneo de secretos en CI (`gitleaks` o el secret scanning nativo de GitHub) — **falla el build si encuentra algo**
- [ ] Regla de equipo: si un secreto llega al historial, se **rota**, no alcanza con borrar el commit
- [ ] Ningún secreto real en Discord, Jira ni en este repo

## Consecuencias

_(a completar)_

## Referencias

- [ADR-0006](0006-proveedor-cloud-y-cicd.md)
