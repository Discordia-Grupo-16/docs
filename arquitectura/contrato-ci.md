# Contrato de repositorio para el CI

Un solo pipeline sirve a los 10 repos siempre que todos ubiquen los mismos archivos en
los mismos lugares. Esto es lo que el CI espera encontrar. Si un repo no lo cumple, su
pipeline falla y hay que escribirle uno a medida.

Los workflows viven en el repo **`discordia-ci`**, uno por stack. Cada repo de servicio
tiene un `ci.yml` de ~20 líneas que los llama con `uses:`. Si hay que arreglar el
pipeline, se toca un archivo y se mueve el tag `v1`.

Todo lo de acá está verificado contra `community` (Python), `api-gateway` (Go) y
`web-app` (front).

---

## Servicios Python

`identity` · `community` · `mod` · `monetization`

| Archivo / carpeta | Obligatorio | Nota |
| --- | --- | --- |
| `requirements.txt` | sí | solo deps de runtime |
| `requirements-dev.txt` | sí | `ruff`, `pytest-cov`. Herramientas que no van a la imagen |
| `app/` | sí | código de la aplicación. Es lo que se mide para cobertura |
| `app/models/` | sí | ambos servicios Python existentes ya lo usan. Importa para la decisión de cobertura de más abajo |
| `tests/` | sí | al menos un test desde el primer commit |
| `tests/conftest.py` | sí | la URL de la base de test debería leerse de una **variable de entorno**, no hardcodeada: si no, el CI no puede configurarla |
| `pytest.ini` | sí | config de pytest |
| `.coveragerc` | sí | config de coverage. **No va en `pytest.ini`:** coverage.py no lee ese archivo y la exclusión se ignora en silencio |
| `ruff.toml` | sí | config de lint y formato. Tiene que incluir `exclude = ["migrations/versions"]`: las migraciones las autogenera Alembic con su propio estilo |
| `Dockerfile` | sí | en la raíz, contexto de build `.` |
| `alembic.ini` + `migrations/` | si el servicio tiene esquema | el CI **no** corre migraciones: los tests crean sus tablas |
| `.env.example` | sí | todas las variables que el servicio lee, con valores de ejemplo |

El nombre de la base de test (`community_test_db`, `identity_test_db`…) se pasa como input
`test-db-name` en el caller, y el workflow lo usa tanto en el `POSTGRES_DB` del service
container como en el `DATABASE_URL`. **El valor se saca del `conftest.py` del repo, no se
inventa:** si no coincide, todos los tests fallan con `database does not exist`.

**Dos ORMs en uso:** `community` usa SQLAlchemy y `identity` SQLModel. No está
documentado en ningún ADR y no hay una razón escrita. Vale unificar o justificarlo antes
de que se sumen `mod` y `monetization`.

## Servicios Go

`api-gateway` · `chat-and-real-time` · `notifications` · `metrics`

El pipeline de Go **no ejecuta comandos directos: todo pasa por `make`**, así que el CI y
la máquina de cada uno corren exactamente lo mismo, y las versiones de las herramientas
las fija el repo y no el workflow.

| Archivo / carpeta | Obligatorio | Nota |
| --- | --- | --- |
| `go.mod` | sí | en la raíz |
| `Makefile` | sí | con los targets de abajo |
| `internal/`, `pkg/` | sí | código con lógica |
| `cmd/` | sí | entrypoints |
| `Dockerfile` | sí | en la raíz |
| `.env.example` | sí | idem Python |

**Targets obligatorios del Makefile:**

| Target | Qué hace |
| --- | --- |
| `lint` | `gofmt -l` (falla si hay archivos sin formatear) y `go vet ./...` |
| `build` | compila el binario |
| `cover` | corre los tests **y hace el gate**; acepta `COVER_MIN` desde la línea de comandos |
| `tidy` | `go mod tidy`. El CI corre esto y después `git diff --exit-code go.mod go.sum` |
| `vuln` | `govulncheck` sobre las dependencias |
| `sast` | `gosec` sobre el código propio |

Las versiones de `gosec` y `govulncheck` van **pinneadas en el Makefile**. Un analizador
que se actualiza solo pone en rojo un push que no tiene nada que ver.

**El target `cover` tiene que serializar los binarios de test con `-p 1`.** Con `-coverpkg`
y los paquetes corriendo en paralelo, el profile mergeado sale incompleto y el total
oscila entre corridas sobre el mismo código — se observó 72% y 89% alternándose. Un gate
que titila es peor que no tener gate: pone en rojo un push ajeno y entrena al equipo a
re-correr el CI en vez de leerlo.

**Pendiente:** `api-gateway` mide con `-coverpkg=./...`, que incluye `cmd/`. Hay que
unificar el criterio entre los cuatro repos Go o los números no son comparables.

## Front

`web-app` · `backoffice` · `mobile`

| Requisito | Obligatorio | Nota |
| --- | --- | --- |
| scripts `lint` y `build` en `package.json` | sí | `mobile` puede no tener `build` |
| `package-lock.json` commiteado | sí | el CI usa `npm ci`, que falla sin el lock |
| `tsconfig.json` | sí | |
| script `test` + runner | **falta** | ver abajo |

Si el `build` corre `tsc -b` antes de Vite (como en `web-app`), el typecheck ya está
cubierto y no hace falta un paso aparte. Un repo cuyo build saltee `tsc` necesita un
`tsc --noEmit` propio.

**Ningún repo de front tiene test runner hoy:** no hay vitest, ni jest, ni testing-library,
ni script `test`. El job de tests existe en el workflow pero arranca apagado
(`run-tests: false`). El enunciado pide que el CI bloquee el merge "ante fallas en los
tests", y sin tests eso no se puede cumplir. **Corresponde a INF-12/13/14** sumar el
runner a la base de cada artefacto; cuando esté, se prende con una palabra en el caller.

---

## Lo que trae cada repo desde el primer commit

1. **`.github/workflows/ci.yml`** — el caller que apunta a `discordia-ci`. Va **en el
   mismo PR que la plantilla base del servicio**, no después: así cada repo nace con CI y
   nadie tiene que perseguir a nadie.
2. **Endpoint `/livez` con su test.** Es RNF obligatorio del enunciado igual. Sin al menos
   un test, `pytest` sale con código 5 ("no tests collected") y el repo nace con el CI en
   rojo, que es red line.
3. **`.env` en `.gitignore`.** Junto con `coverage.xml`, `.coverage`, `.ruff_cache/`,
   `coverage.out`.
4. **`.gitattributes`** con `* text=auto eol=lf`. Sin eso, quien trabaje desde WSL sobre
   el disco de Windows ve todos los archivos del repo como modificados por los finales de
   línea. El riesgo real es que alguien lo commitee: un PR de 2000 líneas donde no cambió
   nada, imposible de revisar y que pisa el trabajo de otro.

**El caller no inyecta variables de entorno en repos con tests unitarios.** El input
`extra-env` existe para los que necesitan conexión real a algo, como `community` con su
`DATABASE_URL`. Inyectar variables de más rompe los tests que verifican el comportamiento
*sin* ellas: en `api-gateway`, pasar `JWT_SECRET` hizo fallar el test que comprueba que la
config rechace arrancar sin secret.

## Cobertura

El gate es **70% y bloquea el merge**, como pide el enunciado para los servicios backend.

- No se baja el número: si un servicio no llega, se resuelve con tests.
- En el front no aplica: el enunciado exige el 70% en backend.
- Escribir los tests junto con la feature, no después. El gate corre desde el primer PR.
- **Se mide por servicio**, no como agregado del backend. Con repo por servicio es lo
  único implementable sin agregación externa, y es *más estricto* que el global, que se
  puede compensar con un servicio muy testeado tapando otro sin tests. Queda pendiente
  confirmarlo con el corrector, pero el criterio del grupo es este y el gate ya funciona
  así.
### Los modelos quedan fuera de la medición

La cobertura por líneas sobreestima la calidad de los tests en los servicios Python: los
modelos declarativos dan 100% con solo importarse, sin que ningún test los ejercite. En
`community` son 115 de 263 statements, y con los 13 tests en error el total daba 74% y el
gate pasaba igual, mientras el router con la lógica de negocio estaba al 29%. Pasa con
SQLAlchemy y con SQLModel, así que aplica a los cuatro servicios.

`app/models/` se excluye de la medición. Va en el `.coveragerc` de cada repo:

```ini
[run]
source = app
omit =
    app/models/*
```

**Es la única exclusión.** `migrations/` y `tests/` ya quedan afuera porque el gate corre
con `--cov=app`. Y no se excluye nada más aunque parezca declarativo:

| Archivo | Por qué se mide |
| --- | --- |
| `app/schemas.py` | los `field_validator` son lógica y los tests los ejercitan |
| `app/config.py` | hay validaciones reales, como rechazar arrancar sin `JWT_SECRET` |
| `app/main.py` | ahí viven `/livez` y `/readyz`, que son RNF obligatorios |

Cuanta menos superficie excluida, menos hay que justificar: una exclusión con un motivo
claro es defendible, cinco parecen un atajo.

**Efecto en el número:** en `community` el denominador baja de 263 a ~148 statements y la
cobertura pasa de 87% a ~78%. Sigue arriba del gate, pero con bastante menos margen — y
eso es la señal honesta.

**Se valora complementar** con mutation testing sobre un servicio core (`mutmut` para
Python, opcional en el enunciado), que mide la calidad real de la suite más allá del
porcentaje.

## Lint

**Python:** `ruff check` y `ruff format --check`, los dos bloqueantes.

**Go:** `make lint` (`gofmt -l` + `go vet`). `golangci-lint` no está: ningún repo tiene un
`.golangci.yml` que pase, y correrlo con defaults pone en rojo código existente. Se suma
cuando cada repo tenga su config.

**Front:** `npm run lint` (ESLint). En `web-app` la primera corrida encontró un
`no-constant-condition` en `loginForm.tsx` — una condición que siempre evalúa igual, o sea
un bug real, no un problema de estilo.

**Formatear un repo con ramas abiertas genera conflictos en todas.** El PR de formateo va
aislado, sin nada más adentro, y coordinado con quien tenga ramas en vuelo. En `community`
se hizo en la ventana entre que se cerraron los PRs y se abrieron los siguientes; el SHA
de ese commit va a `.git-blame-ignore-revs`, y cada uno tiene que activarlo en su clon:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

## Required status checks

Con el workflow compartido, los checks tienen **tres niveles**: workflow del caller / job
del caller / job del reusable. Los nombres exactos, como aparecen en el PR:

```
CI / ci / lint
CI / ci / test
CI / ci / build
CI / ci / gitleaks
```

Y en los repos Go, además: `CI / ci / security`.

En el buscador de rulesets de GitHub aparecen sin prefijo (`lint`, `test`, `build`,
`gitleaks`, `security`), y solo figuran en la lista después de la primera corrida del
workflow en ese repo. El orden es: pushear el caller, esperar que corra, y recién ahí
configurar la protección.

**La protección de ramas no se aplica hoy.** GitHub no permite enforcement de branch
protection ni rulesets en repos privados con plan Free de organización: el aviso es
explícito y vale para las dos interfaces. El pipeline corre y el gate falla cuando
corresponde, pero el merge no queda bloqueado técnicamente — y el enunciado pide las dos
cosas. Las reglas están configuradas y se activan solas al pasar los repos a públicos o
al plan Team. **Decisión pendiente del equipo.**

Lo que sí se aplica en privado: Settings → General → Pull Requests, dejando habilitado
solo el método de merge acordado.

## Ramas y merge

Ver [`procesos/git-workflow.md`](../procesos/git-workflow.md), que es la versión canónica
(INF-04). Lo único que el CI necesita saber está arriba, en los nombres de los checks.

## Seguridad

`gitleaks` corre en los 10 repos con `fetch-depth: 0`, o sea escaneando el historial y no
solo el último commit. Cubre la red line de secretos del enunciado. Conviene activarlo
también en repos vacíos: el momento de mayor riesgo es el primer commit.

**No usar `gitleaks/gitleaks-action@v2`:** pide `GITLEAKS_LICENSE` en repos de
organización y falla en ~5 segundos con un error que no lo explica. Va el binario directo:

```yaml
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install gitleaks
        run: |
          wget -qO- https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz | tar xz gitleaks
          sudo mv gitleaks /usr/local/bin/

      - name: Scan git history
        run: gitleaks detect --source . --verbose
```

Sin licencia, sin token, mismo resultado.

**SAST:** en Go ya está, con `govulncheck` (vulnerabilidades conocidas en las
dependencias) y `gosec` (código propio: credenciales hardcodeadas, criptografía débil,
errores sin manejar en llamadas sensibles). Corren en segundos. El equivalente en Python
es `pip-audit` + `bandit` y vale sumarlo a `python-service.yml` en CP2.

**CodeQL** queda diferido a CP2 y solo en los servicios que tocan auth y permisos:
`api-gateway`, `identity`, `community`. El enunciado lo recomienda, no lo exige, y tarda
3-8 minutos por corrida contra el minuto del resto del pipeline — en repos privados con
plan Free eso come los 2000 minutos mensuales de Actions de toda la organización, y si se
agotan se apaga *todo* el CI. Con `govulncheck` y `gosec` ya cubiertos, aporta poco.

## El bus de eventos

El broker es **RabbitMQ** (ADR-0003, `Aceptado`). `community` todavía tiene
`BUS_URL=redis://localhost:6379` en su `.env.example`: hay que alinearlo con
`amqp://` (`api-gateway` ya usa `BUS_DRIVER=rabbitmq`).

`go-service.yml` levanta un `rabbitmq:4-management` en el job de tests con el input
`needs-rabbitmq: true`, igual que `needs-mongo` para Mongo. Se prende en los repos con
tests de integración que se saltan solos sin broker, hoy `chat-and-real-time` (los tests
de `internal/bus`): un test que se saltea en silencio en el CI es un test que no existe.
Los tests que levantan sus propios contenedores con testcontainers (como
`internal/integration` en chat) no necesitan el input, solo Docker, que ya trae
`ubuntu-latest`.