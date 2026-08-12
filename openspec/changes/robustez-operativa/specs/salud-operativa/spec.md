## Purpose

Comprueba las condiciones del equipo anfitrión que no impiden desplegar la VPN
pero hacen que funcione mal, o que deje de funcionar meses después sin que nadie
esté mirando: tamaño de paquete, hora del sistema, arranque automático y
crecimiento de los registros.

## ADDED Requirements

### Requirement: Detección de tamaño de paquete incompatible

El sistema SHALL determinar el tamaño máximo de paquete que admite el camino
hacia internet y compararlo con el que va a usar el túnel.

Cuando el túnel use un tamaño que no quepa en ese camino, el sistema SHALL
reportarlo e indicar el valor concreto que hay que configurar, explicando que el
síntoma asociado son las transferencias que se quedan a medias pese a que el
túnel conecta.

Cuando la medición no sea posible, el sistema SHALL declararlo no concluyente en
lugar de dar por buena una configuración que no ha comprobado.

#### Scenario: El camino admite menos de lo que usa el túnel

- **WHEN** el tamaño máximo de paquete del camino es menor que el que emplea el
  túnel
- **THEN** el sistema lo reporta como problema, indica el valor a configurar y
  describe el síntoma que provoca

#### Scenario: El camino admite el tamaño que usa el túnel

- **WHEN** el tamaño máximo del camino da margen suficiente al túnel
- **THEN** el sistema lo reporta como correcto

#### Scenario: No se puede medir

- **WHEN** no existe la herramienta necesaria para medir, o la medición no
  obtiene respuesta
- **THEN** el sistema reporta la comprobación como no concluyente e indica cómo
  proceder si aparecen transferencias que se cuelgan

### Requirement: Detección de hora del sistema incorrecta

El sistema SHALL comparar la hora del equipo con una referencia externa y
reportar una desviación capaz de impedir que los clientes negocien el túnel.

El reporte SHALL explicar la relación entre la hora y el fallo, dado que el
síntoma observable no la sugiere en absoluto.

#### Scenario: Reloj desviado

- **WHEN** la hora del equipo difiere de la referencia externa por encima del
  margen tolerable
- **THEN** el sistema lo reporta como problema, explica que impedirá conectar y
  señala cómo corregirlo de forma permanente

#### Scenario: Reloj en hora

- **WHEN** la hora del equipo coincide con la referencia dentro del margen
- **THEN** el sistema lo reporta como correcto

#### Scenario: Sin referencia externa disponible

- **WHEN** no se puede obtener una referencia horaria externa
- **THEN** el sistema reporta la comprobación como no concluyente

### Requirement: Verificación del arranque automático

El sistema SHALL comprobar que el servicio de contenedores está configurado para
iniciarse junto con el equipo, e informar del comando exacto para habilitarlo
cuando no lo esté.

#### Scenario: Arranque automático deshabilitado

- **WHEN** el servicio de contenedores no está habilitado para iniciarse con el
  equipo
- **THEN** el sistema lo reporta como problema, explica que un corte de luz
  dejaría la VPN caída indefinidamente, e indica el comando que lo habilita

#### Scenario: Arranque automático habilitado

- **WHEN** el servicio está habilitado
- **THEN** el sistema lo reporta como correcto

#### Scenario: Sistema sin gestor de servicios reconocible

- **WHEN** no se puede determinar el estado del servicio
- **THEN** el sistema reporta la comprobación como no concluyente en lugar de
  como fallo

### Requirement: Registros acotados

El sistema SHALL limitar el espacio que pueden ocupar los registros de los
contenedores, de forma que su crecimiento no pueda agotar el disco del equipo.

#### Scenario: Configuración del stack

- **WHEN** se inspecciona la configuración de los servicios
- **THEN** cada uno declara un límite de tamaño y un número máximo de ficheros
  de registro
