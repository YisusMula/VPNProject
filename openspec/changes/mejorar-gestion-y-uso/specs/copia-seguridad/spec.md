## Purpose

Permite resguardar y restaurar el único estado del proyecto —las claves del
servidor y las de todos los dispositivos—, cuya pérdida obligaría a regenerar
todos los dispositivos uno a uno.

## ADDED Requirements

### Requirement: Copia de seguridad en un comando

El sistema SHALL producir, con una sola orden, un fichero que contenga todo el
estado necesario para reconstruir el servidor: claves del servidor y de cada
dispositivo dado de alta.

El sistema SHALL advertir de que el fichero contiene claves privadas y de que
debe guardarse fuera del equipo.

El fichero producido MUST NOT quedar bajo control de versiones.

#### Scenario: Copia realizada

- **WHEN** el usuario solicita una copia de seguridad
- **THEN** se genera un fichero identificable por fecha, se informa de su
  ubicación y se advierte de que contiene claves privadas

#### Scenario: Copia con el servidor parado

- **WHEN** el usuario solicita una copia y el servidor no está en ejecución
- **THEN** la copia se realiza igualmente, porque el estado no depende de que el
  servicio esté levantado

#### Scenario: Estado del repositorio tras la copia

- **WHEN** se consulta el estado de git después de generar una copia
- **THEN** el fichero de copia no aparece como pendiente de commit

### Requirement: Restauración desde una copia

El sistema SHALL permitir restaurar el estado a partir de un fichero de copia.
Tras la restauración, los dispositivos que existían en el momento de la copia
SHALL poder conectarse de nuevo.

Por tratarse de una operación que reemplaza el estado actual, el sistema SHALL
solicitar confirmación explícita antes de ejecutarla.

#### Scenario: Restauración completa

- **WHEN** el usuario restaura una copia válida y confirma
- **THEN** el servidor arranca con las claves de la copia y los dispositivos que
  existían entonces vuelven a conectar

#### Scenario: Fichero de copia inválido o inexistente

- **WHEN** el usuario intenta restaurar un fichero que no existe o que no es una
  copia válida
- **THEN** el sistema aborta sin tocar el estado actual e informa del motivo

#### Scenario: Confirmación rechazada

- **WHEN** el usuario lanza la restauración pero no confirma
- **THEN** el estado actual queda intacto
