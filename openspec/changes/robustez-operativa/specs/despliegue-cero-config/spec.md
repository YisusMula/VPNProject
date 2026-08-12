## ADDED Requirements

### Requirement: El despliegue no se declara correcto sin túnel

El sistema MUST NOT informar de un despliegue correcto basándose únicamente en
que la interfaz de administración responda: esa interfaz se levanta con
independencia del túnel.

El sistema SHALL verificar que la interfaz del túnel existe y está operativa
antes de declarar el despliegue correcto. Si no lo está, SHALL indicarlo y
señalar dónde mirar la causa.

#### Scenario: El túnel no llega a levantarse

- **WHEN** el servidor arranca y su interfaz de administración responde, pero la
  interfaz del túnel no llega a crearse
- **THEN** el despliegue se reporta como incorrecto, indicando la causa probable
  y el comando para inspeccionarla

#### Scenario: Despliegue correcto

- **WHEN** el servidor arranca y su interfaz de túnel está operativa
- **THEN** el despliegue se reporta como correcto
