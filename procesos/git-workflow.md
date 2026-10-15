# Flujo de trabajo con Git

**Estado: acordado.** Aplica a todos los repos de la organización.

Es la versión canónica para nombres de repo, ramas, commits, PRs y manejo de secretos.
Si otro documento dice algo distinto sobre estos temas, manda este.

---

## Repos

**Un repo por servicio**, más el de documentación y el de CI. El front (web y mobile) vive
junto en `web-app`, un monorepo con `apps/web`, `apps/mobile` y los paquetes compartidos
(`@discordia/services`, `@discordia/realtime`).

Nombres en minúscula, guion medio, **sin prefijo** `discordia-`: la organización ya se
llama `Discordia-Grupo-16` y repetirlo en cada repo es redundante.

| Repo | Qué es |
| --- | --- |
| `api-gateway` | Gateway: autenticación, rate limit y proxy hacia los servicios |
| `identity` | Cuentas, sesiones y perfiles |
| `community` | Servidores, canales, roles e invitaciones |
| `chat-and-real-time` | Mensajes y tiempo real (WebSocket) |
| `pubsub` | Cliente compartido del bus de eventos |
| `web-app` | Web y mobile, con los paquetes compartidos |
| `docs` | Documentación, ADRs y entregas |
| `discordia-ci` | Infraestructura de CI: workflows reutilizables, que los demás repos usan como `@v1` |

Los servicios `mod`, `monetization`, `notifications`, `metrics` y `backoffice` no tienen
repo: el alcance acordado no los incluye (los roles y baneos viven en `community`).

## Ramas

| Rama | Para qué |
| --- | --- |
| `main` | Lo que está desplegado / lo que se entrega en cada checkpoint |
| `develop` | Integración. De acá salen y acá vuelven todas las features |
| `<tipo>/SCRUM-XXX-<slug>` | Una rama por historia o task de Jira |

- **Sin commits directos a `develop` ni a `main`.** Hoy se cumple por proceso, no por
  configuración (ver [Branch protection](#branch-protection)).
- `develop` → `main` solo en los checkpoints, con un tag `x.y.z` (sin `v`, anotado): `0.1.0`
  para el CP1 y `0.2.0` para el CP2. Un fix posterior sube la última cifra. `discordia-ci`
  conserva `v1`, que es lo que referencian los workflows de los otros repos.
- Las ramas de trabajo salen siempre de `develop` y se borran después del merge.

Tipos: `feat/` funcionalidad nueva · `fix/` corrección · `chore/` infraestructura, build,
dependencias · `docs/` documentación · `refactor/` cambio interno sin cambio de
comportamiento.

```
chore/SCRUM-101-pipeline-ci
feat/SCRUM-30-generar-invitacion
fix/SCRUM-112-permissions-nullable
```

El número de Jira en el nombre hace que GitHub lo ponga solo en el título del PR y que la
integración Jira↔GitHub linkee sin intervención manual.

> **Corrige a ADR-0006**, que dice que el deploy sale de `master`. La rama de producción
> se llama `main`. Hay que actualizar ese ADR.

## Commits

Prefijo de tipo, dos puntos, y mensaje en minúscula.

**Idioma según el repo:** inglés en los repos de código, español en el repo docs. Es lo que se
está usando de hecho en cada uno.

Repos de código:

```
feat: crear rol en un servidor
fix: permissions entraba nullable sin default
chore: agregar requirements-dev con ruff y pytest-cov
docs: actualizar README con setup de dev
```

No se exige referencia a Jira en cada commit individual: va en el título del PR.

**No se aceptan mensajes genéricos.** Nada de `fix`, `wip`, `changes`, `update`, `asd`.
La consigna lo marca explícitamente.

Como los merges son merge commit y no squash, cada commit sobrevive en el historial de
`develop`: el mensaje individual es lo que se ve al hacer `git log`, no solo el título del
PR.

## Pull requests

- **Una historia = un PR.** Si el PR toca tres historias, está mal armado. Un reformateo
  masivo va en su propio PR, sin nada más adentro.
- **Título:** `[SCRUM-XXX] Descripción del cambio`
- Un **autor** (assignee) y un **reviewer** que aprueba. El reviewer no puede ser el autor.
- **1 approval** para mergear.
- **Merge commit** hacia `develop`. Es el único método habilitado.
- **Los checks del CI tienen que pasar.** El merge queda bloqueado si no.
- Avisar por el canal del grupo cuando se pide un review: las notificaciones de GitHub se
  pierden entre el resto.

La descripción sigue la plantilla (`.github/pull_request_template.md`): qué hace, qué
historia cubre, cómo se prueba, y **deuda conocida** si el PR deja algo a medias a
propósito. Ese último punto no es opcional: un `continue-on-error` o un `TODO` sin
explicación y sin ticket es peor que el problema que evita.

## Antes de pedir review

- [ ] CI en verde (la consigna marca CI roto como red line)
- [ ] Sin `.env`, credenciales ni claves en el diff
- [ ] Tests de lo nuevo, con la cobertura del repo por encima del 70%
- [ ] Si cambia un contrato entre servicios, el evento está en
      [`arquitectura/eventos.md`](../arquitectura/eventos.md)
- [ ] Si toca el esquema, la migración encadena con la última que entró a `develop`
- [ ] Si es una decisión de diseño, hay un ADR (ver [CONTRIBUTING](../CONTRIBUTING.md))

## Branch protection

**Lo que se quiere**, sobre `develop` y `main`:

- Pull request obligatorio con **1 approval**
- Solo **Merge commit**
- Checks obligatorios: `lint`, `test`, `build`, `gitleaks`
- Rama al día antes de mergear
- Sin force push

**Lo que hay de verdad:** nada de eso está configurado. La organización está en el plan
Free de GitHub, y en los repos privados la API responde 403 tanto a branch protection como
a rulesets (`docs` y `pubsub`, que son públicos, tampoco la tienen). Hasta que el equipo
decida (hacer públicos los repos, o aceptar la limitación), la regla se cumple por proceso:

- Nadie pushea a `develop` ni a `main`: todo entra por PR.
- Nadie mergea con el CI en rojo ni sin approval.
- Quien revisa mira el CI de `develop` todas las noches.

En el PR los checks se muestran como `CI / lint`, `CI / test`, `CI / build` y
`CI / gitleaks`.

## Migraciones de base de datos

En los servicios con Alembic, **dos PRs en paralelo no pueden generar migraciones sobre la
misma revisión padre**: quedan dos heads y Alembic falla al aplicarlas.

Quien mergea segundo rebasea y reencadena su `down_revision` apuntando a la migración que
ya entró. Conviene avisar en el canal cuando se genera una migración.

## Reformateos masivos

Cuando un PR reformatea archivos enteros, el SHA del commit de formateo va a
`.git-blame-ignore-revs` en la raíz del repo, así `git blame` no atribuye todo el archivo a
ese commit.

Cada uno tiene que activarlo en su clon una vez — no se hereda del repo:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

## Secretos

El detalle está en ADR-0007. Lo operativo:

- `.env` en `.gitignore`, junto con `*.pem`, `*.key`, `*credentials*.json`,
  `coverage.xml`, `.coverage`, `.ruff_cache/`.
- `.env.example` versionado en cada servicio, con los nombres de las variables y valores
  dummy.
- `gitleaks` corre en el CI de todos los repos escaneando el **historial completo**, no
  solo el último commit.
- **Ningún secreto real en Discord, en Jira ni en los repos de documentación.**
- **Si un secreto llega al historial, se rota.** Borrar el commit no alcanza: hay que
  asumir que quedó expuesto y cambiar la credencial, porque el commit ya se clonó en las
  máquinas de los demás.

Secretos commiteados son red line de la consigna: bloquean la evaluación del proyecto.

## Referencias

- [`convenciones.md`](convenciones.md) — naming de servicios, HTTP, bases de datos, fechas
- [`definition-of-done.md`](definition-of-done.md)
- [Contrato de repositorio para el CI](../ci/contrato-ci.md) — el layout que cada repo debe
  cumplir para que el pipeline compartido funcione
- ADR-0006 — proveedor cloud y CI/CD (pendiente: dice `master`, va `main`)
- ADR-0007 — gestión de secretos