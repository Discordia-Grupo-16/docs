# Contexto y arquitectura de alto nivel

> Diagrama fuente: [`arquitectura-discordia.mmd`](arquitectura-discordia.mmd). Si cambia la arquitectura, se edita ahí — no se versiona una imagen exportada.

## Qué es Discordia

Plataforma de comunidades con servidores, canales de texto y de voz, mensajería en tiempo real, roles y permisos, moderación, notificaciones y monetización. Cuatro artefactos: backend de microservicios, web, backoffice y mobile.

## Forma general

- Los tres clientes hablan **solo** con `api-gateway`.
- El gateway resuelve cada request del cliente como **proxy sincrónico** al servicio dueño del recurso y le devuelve la respuesta tal cual ([ADR-0009](../adr/0009-gateway-proxy-sincronico-para-requests-del-cliente.md)). **El gateway no publica al bus:** el evento lo publica el servicio, después de confirmar la escritura en su base.
- Antes de reenviar una request autenticada, el gateway consulta una **blacklist en Redis** para verificar que el token no fue revocado por un logout ([ADR-0010](../adr/0010-revocacion-de-tokens-con-redis.md)). `identity` escribe el `jti` en Redis al hacer logout; el registro expira solo con el TTL del token.
- **Entre servicios backend, asíncrono siempre.** No hay llamadas sincrónicas servicio→servicio: el [ADR-0004](../adr/0004-comunicaciones-sincronicas.md) las evaluó y las rechazó. Un servicio que necesita un dato ajeno lo recibe por evento y lo proyecta localmente.
- **Una base de datos por servicio.** Ningún servicio lee la base de otro; si necesita un dato ajeno, llega por evento.
- `metrics` se suscribe a los eventos de **todos** los servicios.

## Restricciones duras de la consigna

Cualquier propuesta se chequea contra esta lista antes de discutirla:

- [x] Servicios con base de datos independiente
- [x] API Gateway como punto único de entrada
- [x] 4 artefactos: backend + web + backoffice + mobile
- [x] ≥2 lenguajes de backend (Python, Go)
- [x] ≥1 base SQL (PostgreSQL) y ≥1 NoSQL (MongoDB)
- [x] Comunicación asíncrona por defecto; lo sincrónico va con ADR → entre servicios no hay nada sincrónico ([ADR-0004](../adr/0004-comunicaciones-sincronicas.md)); el tráfico cliente↔gateway↔servicio sí lo es, justificado en el [ADR-0009](../adr/0009-gateway-proxy-sincronico-para-requests-del-cliente.md)
- [x] Pub/Sub obligatorio para mensajería
- [ ] Deploy en la nube con CI/CD → [ADR-0006](../adr/0006-proveedor-cloud-y-cicd.md)
- [ ] Cobertura de tests ≥70% → sin estrategia definida
- Red lines: **CI roto** o **secretos en el repo** bloquean la evaluación → [ADR-0007](../adr/0007-gestion-de-secretos.md)

## Cómo ver el diagrama

- GitHub renderiza Mermaid en Markdown. Para verlo en el navegador, pegá el contenido del `.mmd` en un bloque ` ```mermaid ` o abrilo en [mermaid.live](https://mermaid.live).
- En VS Code: extensión *Markdown Preview Mermaid Support*.
- Para exportar a PNG/SVG en una entrega: `mmdc -i arquitectura-discordia.mmd -o arquitectura.png` (`npm i -g @mermaid-js/mermaid-cli`).
