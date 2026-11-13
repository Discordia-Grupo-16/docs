# ADR-0018: Recupero de contraseña, segundo factor y ticket de un solo uso del WebSocket

- **Estado:** Aceptado
- **Fecha:** 2026-11-07
- **Decisores:** Felipe Abad Mustillo (Persona 6, dueño de SCRUM-20, SCRUM-23 y SCRUM-150). Baja a detalle las decisiones D10, D11 y D13 del Anexo A del plan del sprint 3; el taller de contratos del 29/10 aprobó los cambios que se listan en "Qué cambia respecto del plan".
- **Servicios afectados:** `identity` (recupero y 2FA), `api-gateway` (rutas, límites por IP y ticket), `web-app` (web y mobile), `chat-and-real-time` solo como destino del WebSocket.

> Este ADR es **transversal** porque trata de autenticación y cruza servicios (regla de ruteo de
> `CONTRIBUTING.md`). El número 0018 se reserva al abrir el PR: 0016 y 0017 ya son de Tomás y de
> Luis. Al cerrarse la transición del ticket, el [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md)
> sumó la sección "Actualización: ticket de un solo uso" con el ticket en lugar del `access_token`;
> **este ADR no lo reemplaza**, lo completa en el punto de cómo se autentica el handshake.

## Contexto

El sprint 3 pide tres piezas de autenticación que comparten un mismo problema: **un secreto de corta
vida que viaja por un canal donde puede quedar registrado**.

1. **Recupero de contraseña (SCRUM-20).** La persona que olvidó la contraseña no tiene sesión. Hay
   que mandarle un link por email que le permita elegir una nueva. Ese link es, por unos minutos,
   equivalente a la contraseña.
2. **Segundo factor optativo (SCRUM-23).** La consigna lo pide como funcionalidad opcional. Cambia el
   login de un paso a dos pasos para las cuentas que lo activen.
3. **WebSocket sin token en la URL (SCRUM-150).** Hoy el cliente abre `wss://…/api/v1/ws?access_token=…`
   porque un navegador no puede mandar un header `Authorization` en un handshake de WebSocket. Una URL
   con el JWT queda en los access logs del gateway, del balanceador y de cualquier proxy, y se pega en
   herramientas de soporte. El [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) lo dejó
   como deuda.

Restricciones que mandaron:

- **La consigna** pide límite de intentos **por IP y por cuenta** en el login y en el recupero, y
  prohíbe secretos en el repo (red line). El gateway ya limita por IP, pero con un limitador en memoria
  por instancia, y hasta ahora no había límite por cuenta.
- **Un recupero no puede revelar qué cuentas existen.** Ni por la respuesta, ni por el tiempo, ni por
  un `429` que solo salga para cuentas registradas.
- **`identity` ya hashea con Argon2** (`pwdlib`) y el gateway ya tiene Redis para la denylist de tokens
  ([ADR-0010](0010-revocacion-de-tokens-con-redis.md)). Lo que se agregue tiene que apoyarse en eso.
- **Los secretos nuevos van a SSM** ([ADR-0015](0015-gestion-de-configuracion.md)): la clave del
  proveedor de email y la clave que cifra los secretos TOTP.
- **Tiempo.** El backend de las tres piezas tenía que estar en `v0.3.0-rc.1` el 05/11.

## Opciones consideradas

Se decidieron siete cosas; cada una con las alternativas que se descartaron.

### 1. Cómo viaja el token del recupero

#### Opción A — El token en el fragmento del link (`/reset-password#token=…`)

- A favor: el fragmento no se manda al servidor, así que el token no queda en ningún access log ni en
  el `Referer`. La página lo lee y lo borra de la barra con `history.replaceState`.
- En contra: la pantalla tiene que ser una ruta del front que haga una llamada de verificación; no
  alcanza con un link que el servidor resuelva solo.

#### Opción B — El token en el query string (`/reset-password?token=…`)

- A favor: es lo más común y lo más simple de implementar.
- En contra: el token queda en los logs del servidor de estáticos, del CDN y en el `Referer` de
  cualquier recurso externo que cargue la página. Es exactamente el problema que el ticket del
  WebSocket resuelve en otro lugar.

### 2. Qué se guarda y cuánto vale el token del recupero

#### Opción A — 256 bits aleatorios, solo su SHA-256 en la base, una hora, un uso

- A favor: con 256 bits de entropía no hace falta un hash lento (Argon2 sería costo sin ganancia), y el
  SHA-256 permite buscar el token por igualdad. Si se filtra la base, los hashes no sirven para armar un
  link. Pedir uno nuevo invalida los anteriores.
- En contra: no hay forma de reenviar el mismo link; hay que generar otro.

#### Opción B — Token firmado (JWT) sin estado en la base

- A favor: no necesita tabla.
- En contra: no se puede invalidar tras un uso ni al pedir uno nuevo sin guardar algo, así que termina
  necesitando la tabla de todos modos.

### 3. Límite de intentos por cuenta

#### Opción A — Contadores en Redis, por SHA-256 del email, con respuesta indistinguible

- A favor: sirve con varias instancias de `identity`. Cuenta el email **escrito**, exista o no, así que
  el `429` del login y el `202` mudo del recupero no revelan nada. Falla abierto: si Redis cae, nadie
  queda afuera de su cuenta (el gateway sigue limitando por IP).
- En contra: depende de Redis para esta protección; con Redis caído la defensa por cuenta se pierde.

#### Opción B — Contador en la tabla `users` (intentos fallidos y bloqueo)

- A favor: sin infraestructura extra.
- En contra: bloquear la cuenta tras N intentos le permite a cualquiera dejar afuera a una persona
  conocida, y un contador por columna solo existe para cuentas registradas, lo que revela cuáles son.

### 4. Segundo factor: qué tipo

#### Opción A — TOTP (RFC 6238) con una app autenticadora, más códigos de recuperación

- A favor: sin costo, sin depender de un tercero en cada login, y funciona sin red en el teléfono. Es
  lo que el usuario espera de un 2FA optativo.
- En contra: perder el teléfono deja la cuenta sin acceso si no se guardaron los códigos de
  recuperación; por eso se generan al activar.

#### Opción B — SMS

- A favor: no requiere instalar nada.
- En contra: un proveedor de SMS con costo, números de teléfono (dato personal que hoy no guardamos) y
  un canal débil frente al intercambio de SIM. Descartada.

#### Opción C — Código por email

- A favor: reutiliza el proveedor del recupero.
- En contra: quien controla la casilla ya puede recuperar la contraseña, así que no es un segundo factor
  independiente; y suma un envío por login contra un proveedor con cupo diario. Descartada.

### 5. Cómo se cifran y se hashean los secretos del 2FA

#### Opción A — El secreto TOTP cifrado con Fernet; los códigos de recuperación con Argon2

- A favor: el secreto tiene que poder **leerse** para validar un código, así que se cifra (no se hashea)
  con una clave en SSM. Los códigos de recuperación solo se **comparan**, así que se hashean con el
  mismo Argon2 que las contraseñas, sin dependencia nueva.
- En contra: la clave de cifrado (`MFA_ENCRYPTION_KEY`) no se puede cambiar mientras haya cuentas con
  2FA, o los secretos dejan de poder leerse. Rotarla exigiría una migración.

#### Opción B — Los códigos de recuperación con bcrypt (lo que decía D11)

- A favor: es el algoritmo que nombra el plan.
- En contra: sumaría una dependencia para algo que Argon2 ya hace, y la consigna acepta "BCrypt o
  equivalente". El taller del 29/10 aprobó Argon2.

### 6. El QR y el login en dos pasos

#### Opción A — El QR lo dibuja el cliente; el login es `POST /sessions` + `POST /sessions/mfa`

- A favor: `identity` no suma Pillow ni una librería de imágenes, y el secreto nunca viaja en una imagen
  generada por el servidor. En mobile, además, se puede abrir el `otpauth://` en la app autenticadora
  del mismo teléfono, que no puede escanear su propia pantalla. Los endpoints reales de `identity` son
  `/sessions` y `/sessions/refresh`; D11 hablaba de `/auth/login`, que no existe.
- En contra: los dos clientes (web y mobile) tienen que dibujar el QR (`qrcode.react` en web, `react-native-qrcode-svg`
  en mobile).

#### Opción B — El servidor devuelve el QR como imagen

- A favor: el cliente no necesita una librería.
- En contra: una dependencia de imágenes en `identity` y el secreto en una imagen que se puede cachear.
  Descartada.

### 7. Cómo autentica el handshake del WebSocket

#### Opción A — Un ticket de un solo uso de 30 segundos, emitido por el gateway

El cliente pide `POST /api/v1/ws-ticket` con su JWT; el gateway guarda `wsticket:<sha256>` en Redis con
30 s de vida y lo devuelve. El cliente abre el socket con `?ticket=…`. El gateway lo canjea con `GETDEL`,
vuelve a chequear que el `jti` no esté revocado y pasa la identidad a `chat`.

- A favor: lo que queda en la URL vale 30 segundos y sirve una vez, así que un log no deja nada
  reutilizable. `GETDEL` en Redis hace el canje atómico aunque haya dos instancias del gateway. No hace
  falta tocar `chat`.
- En contra: cada intento de conexión pide un ticket nuevo (una request más por reconexión) y el gateway
  deja de ser puramente un verificador de JWT: ahora emite algo.

#### Opción B — Seguir con `?access_token=`

- A favor: no cambia nada.
- En contra: el JWT completo, válido por minutos, en la URL. Es la deuda que se quiere cerrar.

#### Opción C — Mandar el JWT en un primer frame, ya con el socket abierto

- A favor: la URL queda limpia.
- En contra: el gateway tendría que aceptar el upgrade sin identidad y mantener un estado intermedio,
  contra la regla del [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md) de validar antes de
  aceptar el upgrade. Además deja sockets abiertos de personas no autenticadas.

## Decisión

Elegimos la **Opción A de cada punto**.

El criterio que desempató fue el mismo en las tres piezas: **que lo que viaja por un canal registrable
valga poco y se gaste rápido**. El token del recupero va en el fragmento y se guarda hasheado; el
`mfaToken` vive 5 minutos y se usa una vez; el ticket del WebSocket vive 30 segundos y se canjea una vez.
Y que lo que protege contra el abuso no revele nada: los límites por cuenta cuentan lo que se escribió,
exista o no la cuenta.

### Recupero de contraseña (SCRUM-20)

- `POST /password-resets { email }` responde **siempre `202`** con el mismo mensaje. El email se manda en
  segundo plano para que el tiempo de respuesta tampoco revele si la cuenta existe.
- `POST /password-resets/check { token }` (`204` o `400`) y `POST /password-resets/confirm { token,
  newPassword }` (`204` o el mismo `400`).
- El token es `secrets.token_urlsafe(32)`; en la base queda su SHA-256; vence en 1 hora; sirve una vez.
- Al confirmar, en **una sola transacción**: se guarda el hash nuevo, se marca el token como usado y se
  revocan todas las sesiones, con sus `jti` en la denylist de Redis. **El recupero no saltea el 2FA**: el
  login siguiente lo sigue pidiendo.
- Límites: por IP en el gateway (5 cada 15 minutos para pedir; 10 por minuto para `check` y `confirm`),
  y por cuenta en `identity` (3 emails por hora por email hasheado, con el mismo `202` pasado el límite).
  El **mismo mecanismo cubre el login**: 10 fallos cada 15 minutos por email hasheado dan `429`; un login
  correcto limpia el contador.
- El proveedor de email es Brevo, detrás de una interfaz `EmailSender` (decisión de servicio:
  `ADR-0001` de `identity`). En producción `identity` no arranca con el sender de consola.

### Segundo factor (SCRUM-23)

- **Activar:** `POST /users/me/mfa/setup` genera el secreto y lo guarda cifrado, todavía inactivo (`409`
  si el 2FA ya está activo). `POST /users/me/mfa/enable { code }` verifica el primer código, activa el 2FA
  y devuelve 10 códigos `xxxx-xxxx` sin caracteres ambiguos, que se muestran una sola vez.
- **Login en dos pasos:** con 2FA, `POST /sessions` responde `{ mfaRequired: true, mfaToken }` en lugar de
  la sesión, y `POST /sessions/mfa { mfaToken, code | recoveryCode }` la emite. Con un código de
  recuperación suma `recoveryCodesRemaining`.
- **`mfaToken`:** 32 bytes; en Redis queda `mfa:<sha256>` → `userId` con TTL de 5 minutos; se borra al
  usarlo; admite 5 intentos y al quinto error se borra. Se vuelve a chequear la suspensión en este paso.
- **Anti-replay:** `mfa:last-step:<userId>` guarda el último paso de 30 s aceptado; no se acepta un código
  de ese paso ni de uno anterior. `valid_window=1` tolera un reloj corrido.
- **Mensajes de error:** el segundo paso responde `401` con dos `detail` distintos: «El código no es
  válido.» (el token sigue vivo, se puede reintentar) y «La verificación venció. Volvé a iniciar sesión.»
  (el token venció, se usó, se agotó o el 2FA se desactivó entre los dos pasos; el cliente vuelve al
  login). El quinto código incorrecto responde el primero y borra el token; el intento siguiente recibe el
  segundo.
- **Regenerar** los códigos (`POST /users/me/mfa/recovery-codes { code }`) pide un código TOTP vigente e
  invalida la lista anterior. **Desactivar** (`POST /users/me/mfa/disable { password }`) borra el secreto
  y los códigos; las contraseñas incorrectas se cuentan por cuenta (5 cada 15 minutos).
- **Redis caído:** el segundo paso **falla cerrado**: nadie pasa el segundo factor sin poder verificar el
  token. Es lo contrario del limitador por cuenta, que falla abierto, y es deliberado: lo que un fallo de
  Redis no puede hacer es saltear un factor de autenticación.

### Ticket del WebSocket (SCRUM-150)

- `POST /api/v1/ws-ticket` lo atiende el gateway, sin upstream; requiere un JWT válido y no revocado y
  responde `{ data: { ticket, expiresIn: 30 } }`. Límite de 30 por minuto, para no frenar las
  reconexiones.
- La ruta del WebSocket pasa a un modo de auth nuevo, `ticket`, en `routes.yaml`.
- **Transición sin cortar clientes:** 1) el gateway acepta el ticket y, mientras
  `WS_ALLOW_QUERY_TOKEN=true`, también `?access_token=`; 2) cambian los clientes (`getToken` pasa a
  `getTicket` en `packages/api`); 3) un último PR pone `WS_ALLOW_QUERY_TOKEN=false` y saca el
  `access_token` del WebSocket. Recién entonces el ADR-0008 se acepta.

## Qué cambia respecto del plan

El taller del 29/10 aprobó estos cambios sobre D10, D11 y D13:

| Plan | Se hizo | Por qué |
|---|---|---|
| Login 2FA en `POST /auth/login` | `POST /sessions` + `POST /sessions/mfa` | `/auth/login` no existe en `identity`; el login real es `/sessions` |
| Códigos de recuperación con bcrypt | Argon2 | Ya es dependencia; la consigna acepta "BCrypt o equivalente" |
| — | Límite por cuenta en el login, dentro de SCRUM-20 | Cubre "por IP y por cuenta" con el mecanismo que ya hacía falta |
| Rutas `/auth/login` y `/auth/refresh` en el gateway | Se borraron, y también el resto de `/auth/*` sin uso | Apuntaban a rutas que `identity` no tiene |

## Consecuencias

**Positivas**

- Ningún token reutilizable queda en una URL: el del recupero va en el fragmento y el del WebSocket vale
  30 segundos y un uso. El criterio de cierre del sprint («ninguna URL lleva un token») es verificable.
- El login tiene por fin límite por cuenta, y el recupero no revela qué cuentas existen.
- Una cuenta con 2FA no se puede abrir con solo la contraseña, ni con un recupero de contraseña, y un
  código TOTP aceptado no se puede reusar.
- `identity` y el gateway no suman dependencias nuevas de imágenes ni de hashing; `pyotp` y
  `cryptography` son las únicas librerías nuevas de `identity`.

**Negativas / costo que aceptamos**

- El gateway pasa a **emitir** algo (el ticket), no solo a verificar. Es más estado en el componente que
  ya es el punto único de entrada.
- Una reconexión del WebSocket cuesta una request más (el ticket).
- `MFA_ENCRYPTION_KEY` no se puede cambiar con cuentas con 2FA activas sin una migración de los secretos.
- Si Redis cae, nadie con 2FA puede iniciar sesión (falla cerrado) y se pierde el límite por cuenta
  (falla abierto). Se aceptan las dos consecuencias porque cada una falla hacia el lado seguro para lo que
  protege.
- La verificación de anti-replay lee el último paso y después lo escribe, sin transacción: dos pedidos
  simultáneos con el mismo código nuevo podrían pasar los dos. Para eso tendrían que tener ya el
  `mfaToken`, que se consume de forma atómica, así que el riesgo no se explota sin el primer factor.
- Con un email real y sin dominio propio, el remitente del recupero puede caer en spam (consecuencia del
  `ADR-0001` de `identity`).

**Qué queda pendiente por esta decisión**

- El login con Google (SCRUM-21, ideal) usa el mismo `mfaRequired` pero no se decide acá: si entra, va en
  su propio ADR o en una enmienda de este.
- Que las cuentas sin contraseña (las de Google) puedan desactivar el 2FA: hoy `disable` pide la
  contraseña.
- Rotación de `MFA_ENCRYPTION_KEY`, si alguna vez hiciera falta.

## Referencias

- [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md), [ADR-0007](0007-gestion-de-secretos.md),
  [ADR-0008](0008-proxy-websocket-como-excepcion-al-adr-0002.md),
  [ADR-0010](0010-revocacion-de-tokens-con-redis.md), [ADR-0015](0015-gestion-de-configuracion.md)
- Contrato de `identity`: `arquitectura/contratos/identity.yaml` (`/password-resets`, `/sessions/mfa`,
  `/users/me/mfa/*`) y de `api-gateway` (`/ws-ticket`).
- `ADR-0001` de `identity` (Brevo como proveedor de email), en el repo de `identity`.
- RFC 6238 (TOTP).
- Jira: SCRUM-20 (recupero), SCRUM-23 (2FA), SCRUM-150 (ticket del WebSocket)
