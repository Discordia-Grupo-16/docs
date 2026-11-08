# Discordia — Documentación general

Repositorio de documentación transversal del proyecto **Discordia** (Grupo 16 — Métodos y Modelos II / Ingeniería del Software 2).

Acá vive todo lo que **no pertenece a un solo microservicio**: decisiones de arquitectura (ADR), diagramas, catálogo de eventos, convenciones de trabajo y los informes de cada checkpoint.

> Regla de oro: **una decisión no existe hasta que hay un PR mergeado en este repo.**

---

## Dónde vive cada cosa

| Qué | Dónde | Por qué |
|---|---|---|
| Backlog, historias, tasks, estimaciones | **Jira** | Cambia todas las semanas, no es documentación |
| Coordinación diaria, links, recursos sueltos | **Discord** (canal de recursos) | Efímero, no necesita review |
| Decisiones de arquitectura transversales, diagramas, contratos de eventos, informes | **Este repo** | Necesita historial, review y trazabilidad |
| Decisiones internas de un servicio | **`adr/` del repo del servicio** | Las revierte un solo equipo sin romper a nadie |
| Notas personales de cada uno | Donde cada uno quiera | No son fuente de verdad |

---

## Estructura

```
docs/
├── adr/                    Architecture Decision Records transversales
│   ├── README.md           Índice de TODOS los ADR (globales + de servicio)
│   └── 0000-template.md    Plantilla
├── arquitectura/
│   ├── contexto.md         Visión general, artefactos y límites de servicio
│   ├── servicios.md        Un renglón por servicio: lenguaje, DB, responsabilidad
│   ├── eventos.md          Catálogo de eventos del bus Pub/Sub
│   └── arquitectura-discordia.mmd   Diagrama fuente (Mermaid)
├── procesos/
│   ├── git-workflow.md     Ramas, PRs, reviews
│   ├── definition-of-done.md
│   └── convenciones.md     Naming de repos, servicios, endpoints, tópicos
├── entregas/               Informes por checkpoint (fuente .md)
│   ├── cp0/ cp1/ cp2/ cp3/ final/
│   └── README.md           Cómo generar el PDF si lo piden
└── .github/                Plantillas de PR e issues, CODEOWNERS
```

---

## Por dónde empezar

- **¿Por qué el sistema es así?** → [`adr/README.md`](adr/README.md)
- **¿Qué servicio hace qué?** → [`arquitectura/servicios.md`](arquitectura/servicios.md)
- **¿Cómo mando un cambio?** → [`CONTRIBUTING.md`](CONTRIBUTING.md)
- **¿Qué falta decidir?** → los ADR en estado `Propuesto` en el índice

---

## Estado de las decisiones abiertas

| ADR | Tema | Bloquea a |
|---|---|---|
| [ADR-0012](adr/0012-permisos-por-canal.md) | Permisos por canal, como excepción sobre el modelo del ADR-0011 | SCRUM-66 (sobrescribir permisos en un canal) |
