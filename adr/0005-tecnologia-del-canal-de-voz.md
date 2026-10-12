# ADR-0005: Tecnología del canal de voz

- **Estado:** Aceptado
- **Fecha:** 2026-10-11
- **Decisores:** Milton (dueño de la épica del canal de voz)
- **Servicios afectados:** `chat-and-real-time`, `web-app`, `mobile`

## Contexto

El canal de voz vive dentro de `chat-and-real-time` (Go, MongoDB). Es la funcionalidad con más riesgo técnico del TP: WebRTC tiene señalización, NAT traversal (STUN/TURN), codecs y permisos de dispositivo, y hay que hacerlo funcionar en **web y en React Native** a la vez.

El equipo no tiene experiencia previa declarada en tiempo real, y esta épica compite en calendario con el resto del sprint.

## Opciones consideradas

### Opción A — Servicio gestionado (LiveKit Cloud, Agora, Daily, Twilio)

- A favor: SDK para web y React Native, TURN incluido, sale funcionando en días; el riesgo técnico se terceriza y el equipo se concentra en el producto.
- En contra: dependencia de un tercero y de su free tier; hace falta cuenta y credenciales (ver [ADR-0007](0007-gestion-de-secretos.md)); menos "mérito arquitectónico" si la cátedra valora la implementación propia.

### Opción B — SFU propio self-hosted (LiveKit OSS, mediasoup, Janus)

- A favor: control total, corre en la nube propia, demuestra manejo de la tecnología; LiveKit OSS mantiene los mismos SDK de cliente que la opción A.
- En contra: hay que operarlo (contenedor, puertos UDP, TURN propio); los puertos UDP son un problema real en varios PaaS baratos; sube el costo de la infra y del deploy.

### Opción C — WebRTC P2P en malla, sin servidor de medios

- A favor: nada que operar más allá de la señalización, que ya la puede hacer `chat-and-real-time`.
- En contra: no escala más allá de 3–4 participantes (cada cliente sube N-1 streams); problemas de NAT sin TURN; en la práctica no sirve para un canal de voz tipo Discord.

## Decisión

Elegimos **Opción A — LiveKit Cloud**.

Porque la cátedra deja la tecnología a elección del grupo y evalúa que el canal de voz funcione, no que esté implementado a bajo nivel. Con eso resuelto, un servicio gestionado libera semanas en la épica con más riesgo técnico del TP. Entre los gestionados elegimos LiveKit porque tiene SDK de cliente para web y React Native, incluye TURN, no nos obliga a abrir puertos UDP en nuestra nube ([ADR-0006](0006-proveedor-cloud-y-cicd.md)) y su plan Build es gratuito.

LiveKit Cloud además deja una salida barata: LiveKit OSS (Opción B) usa los mismos SDK de cliente y la misma API de salas, así que pasar a un SFU propio es un cambio de configuración de `chat-and-real-time`. En el entorno local usamos LiveKit OSS en modo dev, un contenedor que levanta el compose, para que nadie necesite cuenta ni claves de Cloud y las pruebas no gasten el free tier. Como la API es la misma, la app no cambia entre local y nube.

La Opción C se descarta: no escala más allá de 3 o 4 participantes por canal.

## Consecuencias

**Positivas**

- El audio va directo del cliente a LiveKit y no pasa por nuestros servicios. `chat-and-real-time` solo autoriza la unión y firma el token de acceso a la sala.
- La revocación de tokens de LiveKit permite cortar la llamada de quien pierde el acceso al canal.
- Los clientes web y mobile usan el mismo SDK.

**Negativas / costo que aceptamos**

- Dependencia de un tercero y de su free tier (5000 minutos por mes, 100 conexiones simultáneas).
- Hace falta una cuenta y credenciales, gestionadas según [ADR-0007](0007-gestion-de-secretos.md).
- Mobile necesita un development build: el SDK de LiveKit no corre en Expo Go.
- `chat-and-real-time` sube a Go 1.26.9, la versión que pide el SDK de servidor.

**Qué queda pendiente por esta decisión**

- Decidir [ADR-0007](0007-gestion-de-secretos.md) para guardar las claves de LiveKit en la nube.
- Documentar el paso a LiveKit OSS si se agota el free tier o lo pide la cátedra.

## Referencias

- [ADR-0006](0006-proveedor-cloud-y-cicd.md) — dónde correría el SFU si se pasa a LiveKit OSS
- [ADR-0007](0007-gestion-de-secretos.md) — credenciales de LiveKit Cloud
- SCRUM-51 — Unirse a un canal de voz
