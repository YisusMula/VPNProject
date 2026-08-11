## ADDED Requirements

### Requirement: Modo sólo-LAN como alternativa al túnel completo

El sistema SHALL permitir generar un dispositivo en modo **sólo-LAN**: alcanza
la red doméstica a través del túnel, mientras el resto de su tráfico sale
directamente por la red en la que se encuentre.

El modo por defecto SHALL seguir siendo el túnel completo, porque es el que
resuelve la salida a internet por la IP del hogar.

El modo elegido SHALL quedar visible para el usuario en el momento de crear el
dispositivo, junto con su consecuencia práctica.

#### Scenario: Dispositivo en modo sólo-LAN

- **WHEN** el usuario crea un dispositivo pidiendo explícitamente el modo
  sólo-LAN
- **THEN** ese dispositivo alcanza los equipos de la red doméstica por el túnel,
  y su tráfico hacia internet no pasa por la conexión del hogar

#### Scenario: Modo por defecto sin cambios

- **WHEN** el usuario crea un dispositivo sin indicar modo
- **THEN** se genera en túnel completo, con toda su salida a internet por la IP
  pública del hogar

#### Scenario: La subred doméstica no se puede determinar

- **WHEN** se pide el modo sólo-LAN y el sistema no puede determinar la subred
  de la red doméstica
- **THEN** el sistema aborta e indica cómo especificarla, en lugar de generar un
  dispositivo que no alcanzaría nada

### Requirement: Identificación de dispositivos por nombre en el diagnóstico

El diagnóstico SHALL identificar cada dispositivo por el nombre que le puso el
usuario. MUST NOT presentar material criptográfico como identificador principal.

Cuando el nombre no pueda obtenerse, el sistema SHALL indicarlo explícitamente
en lugar de sustituirlo en silencio por otro identificador.

#### Scenario: Diagnóstico con dispositivos dados de alta

- **WHEN** el usuario ejecuta el diagnóstico y hay dispositivos dados de alta
- **THEN** cada uno aparece con su nombre y su última conexión

#### Scenario: Nombres no disponibles

- **WHEN** el diagnóstico no puede recuperar los nombres desde el panel
- **THEN** informa de esa limitación y presenta la información de la que
  disponga, señalando que los identificadores no son los nombres
