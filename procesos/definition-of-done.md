# Definition of Done

> **Estado: propuesta.** Hay que validarla en la reunión semanal antes de aplicarla como regla.

Una historia está terminada cuando:

## Código

- [ ] Cumple los criterios de aceptación de la historia en Jira
- [ ] PR mergeado a `develop` con un review aprobado que no es del autor
- [ ] CI en verde
- [ ] Cobertura del repo ≥ 70% (requisito de la consigna) y no bajó respecto de antes del PR
- [ ] Sin secretos, credenciales ni `.env` en el historial

## Integración

- [ ] Los eventos que publica o consume están en [`arquitectura/eventos.md`](../arquitectura/eventos.md)
- [ ] Si expone endpoints, están en el contrato OpenAPI del servicio (task TP-108)
- [ ] Levanta con el `docker-compose` compartido (task TP-107) sin pasos manuales extra

## Documentación

- [ ] Si hubo una decisión de diseño, quedó en un ADR (de servicio o transversal)
- [ ] El README del servicio dice cómo correrlo y qué variables de entorno necesita
- [ ] La historia está en el estado correcto en Jira

## Lo que NO es parte de "done"

- Estar desplegado en la nube: eso pasa en el corte a `main` de cada checkpoint (a revisar: el plan del Sprint 2 pide deploy en la nube para cerrar SCRUM-41).
- Estar demostrado en la reunión: eso es la revisión del sprint.
