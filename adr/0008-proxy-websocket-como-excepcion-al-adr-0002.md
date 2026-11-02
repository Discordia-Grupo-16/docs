# ADR-0008: Proxy WebSocket del gateway hacia `chat` como excepción al ADR-0002

- **Estado:** Aceptado
- **Fecha:** 2026-09-16
- **Decisores:** Felipe Abad Mustillo (propone, dueño de `chat` en el sprint 1)
- **Servicios afectados:** `api-gateway`, `chat-and-real-time`

> Este número (`0008`) lo toma este ADR al abrir el PR, por orden de
> llegada — no está reservado para el ADR del mecanismo de respuesta del
> gateway que menciona el [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md)
> como "candidato a ADR-0008" (esa numeración era tentativa, no una reserva
> firme; ver regla de numeración en `CONTRIBUTING.md`). Ese ADR pendiente
> toma el siguiente número libre cuando se escriba.

## Contexto

[ADR-0002](0002-api-gateway-y-publicacion-al-bus.md) establece que el
gateway **no llama directo a los servicios**: publica al bus y los
servicios consumen de ahí. Es la regla por defecto para la comunicación
**entre servicios backend**.

La historia SCRUM-41 (enviar un mensaje en un canal, CP1) necesita que un
cliente reciba mensajes **en tiempo real**, incluidos los que llegan por
canales a los que está suscripto mientras tiene la app abierta. Eso exige
un transporte de larga duración entre el cliente y la plataforma —
WebSocket es la elección obvia y no está en discusión en este ADR (no hay
alternativa razonable a un socket para push en tiempo real desde el
servidor).

La pregunta que sí hace falta resolver: **¿cómo llega ese WebSocket desde
el cliente hasta la instancia de `chat` que lo atiende, sin romper "API
Gateway como punto único de entrada"?**

Restricciones que aplican:

- La consigna exige gateway único: los tres artefactos cliente no pueden
  hablar directo con `chat`.
- El handshake de WebSocket es un `GET` HTTP con `Upgrade: websocket` — el
  JWT viaja ahí y hay que validarlo antes de aceptar el upgrade, igual que
  cualquier otro endpoint.
- Una vez enviado un `message.send`, tres de los cuatro criterios de
  aceptación de SCRUM-41 (CA2 vacío, CA3 autorización, CA4 largo) son
  casos de **error que hay que contestar**, y hace falta que la respuesta
  llegue por el mismo socket que originó el pedido.
- El orden de los mensajes de un mismo emisor debe preservarse.

## Opciones consideradas

### Opción A — El gateway hace de proxy transparente del WebSocket hacia una instancia de `chat`

El cliente abre `wss://gateway/api/v1/ws` con el JWT. El gateway valida el
JWT en el handshake (401 si es inválido, sin abrir el socket), y con el
token válido abre su **propio** WebSocket contra una instancia de `chat`,
pasándole la identidad ya validada en headers (`X-User-Id`,
`X-Correlation-Id`). A partir de ahí copia frames en las dos direcciones
sin interpretarlos.

- A favor:
  - Una sola vuelta de bus en el camino feliz (persistir + publicar +
    fan-out), en vez de dos.
  - La instancia que valida es la que tiene el socket del emisor → CA2,
    CA3 y CA4 se contestan **inmediatamente por el mismo socket**, sin
    construir un camino de ruteo de rechazos asincrónico que solo existiría
    para contestar errores.
  - El orden por emisor sale gratis: los frames de un cliente llegan por
    una sola conexión TCP y los procesa una sola goroutine, en orden.
  - El gateway sigue siendo el único punto de entrada visible para el
    cliente y sigue haciendo autenticación y rate limiting.
- En contra:
  - El gateway mantiene un WebSocket abierto hacia `chat` por cada cliente
    conectado — más estado y más conexiones simultáneas que un proxy HTTP
    sin estado.
  - A primera lectura, "el gateway habla directo con un servicio" suena a
    lo que el ADR-0002 prohíbe. Hace falta trazar la línea explícitamente
    (ver Decisión).

### Opción B — POST + comando al bus + ack asincrónico

El cliente manda `POST /messages` al gateway, que publica un comando al
bus. `chat` lo consume, procesa y publica la respuesta (éxito o error) a
un tópico de respuesta; el cliente se entera por un WebSocket aparte que
sólo transporta notificaciones, no el pedido original.

- A favor: mantiene el patrón "gateway publica, nunca llama directo" sin
  excepciones — el WebSocket solo estaría corriendo el patrón de
  ADR-0002 hacia el cliente en la dirección servidor→cliente.
- En contra:
  - Sigue necesitando igual un WebSocket vivo entre el cliente y algo del
    lado del servidor para el push de notificaciones — el problema del
    transporte de larga duración no desaparece, solo se le saca la mitad
    del tráfico (el `send`).
  - Dos vueltas de bus en el camino feliz en vez de una.
  - CA2, CA3 y CA4 pasan a ser asincrónicos: hay que construir un tópico de
    respuesta, correlacionar el comando con su resultado y rutear el error
    de vuelta al cliente correcto — maquinaria que existe únicamente para
    contestar rechazos que, en la Opción A, el mismo socket contesta gratis.
  - El orden por emisor deja de salir gratis: dos `POST` con 20 ms de
    diferencia pueden ser tomados por instancias distintas de `chat` y
    procesarse en orden invertido. Arreglarlo exige particionar el consumo
    por `channelId`, complejidad que la Opción A no necesita.

### Opción C — Patrón Discord/Slack: REST sincrónico para enviar, WebSocket solo para recibir

El cliente manda el mensaje por `POST` sincrónico directo (o vía gateway
como proxy HTTP) a `chat`, que responde en la misma request; por separado,
un WebSocket aparte empuja los mensajes entrantes.

- A favor: es el patrón que usan productos reales del mismo dominio; el
  `POST` da una respuesta inmediata y simple de manejar en el cliente.
- En contra: es exactamente la Opción A de ADR-0002 (proxy HTTP sincrónico
  a un servicio) aplicada al envío, que ADR-0002 ya descartó porque vuelve
  sincrónica la comunicación cliente→servicio en el camino por defecto.
  Además **igual** necesita el WebSocket de la Opción A para el lado de
  recepción, así que paga el costo de mantener sockets vivos igual que la
  Opción A y encima reintroduce el problema de sincronía que el ADR-0002
  ya resolvió para el resto de la API.

## Decisión

Elegimos la **Opción A**.

El argumento decisivo: las tres opciones necesitan igual un WebSocket vivo
contra `chat`. Ese socket o pasa por el gateway —y entonces el gateway ya
está proxeando un transporte hacia un servicio, que es la Opción A— o no
pasa, y ahí se rompe "API Gateway como punto único de entrada", que es una
restricción explícita de la consigna y no una decisión de este equipo. La
Opción C paga el mismo costo de sockets que la A y además reintroduce
sincronía que el ADR-0002 ya había resuelto; la Opción B paga el costo de
sockets sin evitarlo y encima paga con errores asincrónicos y pérdida de
orden.

### La excepción al ADR-0002, y por qué no lo debilita

> El ADR-0002 y la consigna regulan la comunicación **entre servicios
> backend**. Un WebSocket de un cliente hacia el sistema es transporte
> cliente↔plataforma, no comunicación entre servicios. El gateway no llama
> sincrónicamente a `chat`: termina y reenvía un transporte de larga
> duración, igual que ya termina y reenvía HTTP. La comunicación **entre
> servicios** en esta historia (`chat` → las otras instancias de `chat`,
> `community` → `chat`) sigue siendo 100% asincrónica por el bus, sin
> excepciones.

En otras palabras: lo que cambia es el transporte cliente→gateway→`chat`
(de request/response a un socket de larga duración), no el modelo de
comunicación entre microservicios, que el ADR-0002 sigue gobernando sin
cambios.

### Alcance de la excepción

- Aplica **solo** al handshake y al reenvío de frames de
  `GET /api/v1/ws`. No habilita al gateway a hacer proxy HTTP sincrónico de
  ningún otro endpoint de `chat` ni de ningún otro servicio.
- El gateway sigue sin interpretar el contenido de los frames: valida el
  JWT en el handshake y hace rate limiting, nada más. La lógica de negocio
  (validación de canal, autorización, persistencia, fan-out) vive
  enteramente en `chat`.
- Un `MessageAckFrame`, `MessageCreatedFrame` o `ErrorFrame` que `chat`
  manda por este socket **no** es un comando ni una respuesta a un comando
  del gateway en el sentido del problema abierto de ADR-0002 (mecanismo de
  respuesta para `POST /servers` y similares) — ese problema sigue abierto
  y se resuelve en un ADR aparte, con dueño en el slot de Persona 3.

## Consecuencias

**Positivas**

- SCRUM-41 tiene un camino de mensaje con una sola vuelta de bus, orden
  garantizado por emisor y errores síncronos, sin construir infraestructura
  de notificaciones genérica solo para contestar tres criterios de error.
- El gateway conserva el rol de único punto de entrada, autenticación y
  rate limiting para el tráfico de tiempo real, igual que para HTTP.
- La comunicación entre microservicios backend sigue siendo 100%
  asincrónica; esta excepción no abre la puerta a llamadas sincrónicas
  service-to-service (eso lo sigue gobernando
  [ADR-0004](0004-comunicaciones-sincronicas.md), sin relación con esta
  decisión).

**Negativas / costo que aceptamos**

- El gateway mantiene un WebSocket abierto por cada cliente conectado
  hacia una instancia de `chat` — más estado en el componente que ya es el
  punto único de falla del sistema (riesgo ya aceptado en ADR-0002).
- Como el fan-out va por el bus y no por sticky sessions, cualquier
  instancia de `chat` puede atender cualquier socket; hay que verificar
  temprano que el proveedor cloud elegido (ADR-0006) sostiene WebSockets
  con múltiples instancias sin afinidad de sesión (ver contingencia en el
  plan de sprint de `chat`).
- Esta excepción es específica del transporte de tiempo real de mensajería;
  si otra historia futura quisiera el mismo patrón para otro dominio, hay
  que evaluarla de nuevo, no asumir que esta decisión la cubre.

**Qué queda pendiente por esta decisión**

- El ADR del mecanismo de respuesta del gateway para comandos HTTP
  ordinarios (`POST /servers` y similares) sigue sin escribirse — no lo
  resuelve este ADR, y **no debe** heredar este socket de chat como su
  mecanismo general de notificación sin una decisión explícita (ver alerta
  de alcance en el plan de sprint de `chat`, sección 7).
- Verificación temprana de soporte de WebSocket multiinstancia en el
  proveedor cloud elegido (contingencia, no bloquea esta decisión).

## Referencias

- [ADR-0002](0002-api-gateway-y-publicacion-al-bus.md)
- [ADR-0004](0004-comunicaciones-sincronicas.md) (sin relación directa —
  gobierna llamadas sincrónicas *entre servicios backend*, no transporte
  cliente↔plataforma)
- `chat-and-real-time/openapi.yaml` y
  `chat-and-real-time/arquitectura/protocolo-tiempo-real.md` (SCRUM-131,
  contrato y semántica de los frames)
- Jira: SCRUM-41 (Enviar mensaje en un canal), SCRUM-132 (esta decisión)
