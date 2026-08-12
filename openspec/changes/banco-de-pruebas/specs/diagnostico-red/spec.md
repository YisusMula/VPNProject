## ADDED Requirements

### Requirement: El diagnóstico completa todas sus secciones

El diagnóstico SHALL ejecutar todas sus comprobaciones aunque una respuesta del
servidor llegue incompleta o malformada. Un dato que no se puede interpretar
MUST NOT impedir las comprobaciones restantes.

Una respuesta que no se puede interpretar MUST NOT presentarse como ausencia de
dispositivos: son situaciones distintas y llevan a acciones distintas.

#### Scenario: Respuesta malformada del panel

- **WHEN** el panel devuelve una respuesta que no se puede interpretar
- **THEN** el diagnóstico continúa con el resto de secciones y obtiene los datos
  de los dispositivos por la vía alternativa disponible

#### Scenario: No hay ninguna vía para obtener los dispositivos

- **WHEN** ni la respuesta del panel ni la vía alternativa aportan datos
- **THEN** el diagnóstico lo indica como limitación, sin afirmar que no existan
  dispositivos
