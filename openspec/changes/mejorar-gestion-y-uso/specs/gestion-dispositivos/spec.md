## Purpose

Cubre el ciclo de vida completo de un dispositivo autorizado —alta, listado y
baja— desde la terminal del servidor, sin depender del panel web, y con
garantías explícitas de que operar sobre uno no afecta a los demás.

## ADDED Requirements

### Requirement: Revocación de un dispositivo

El sistema SHALL permitir revocar un dispositivo por su nombre desde la
terminal. Tras la revocación, ese dispositivo MUST NOT poder establecer el túnel.

La revocación MUST NOT afectar a la conectividad de los demás dispositivos.

Por tratarse de una operación destructiva e irreversible, el sistema SHALL
solicitar confirmación explícita antes de ejecutarla, y SHALL ofrecer una forma
de omitir esa confirmación para uso desatendido.

#### Scenario: Revocación de un dispositivo existente

- **WHEN** el usuario revoca un dispositivo dado de alta y confirma la operación
- **THEN** el dispositivo desaparece del listado y deja de poder conectarse,
  mientras el resto sigue conectando con normalidad

#### Scenario: Confirmación rechazada

- **WHEN** el usuario lanza la revocación pero no confirma
- **THEN** no se revoca nada y el sistema lo indica

#### Scenario: Dispositivo inexistente

- **WHEN** el usuario intenta revocar un nombre que no existe
- **THEN** el sistema informa de que no existe y no revoca ningún otro
  dispositivo

#### Scenario: Ficheros locales del dispositivo revocado

- **WHEN** se revoca un dispositivo que tenía un fichero de configuración
  guardado en el servidor
- **THEN** ese fichero deja de ser válido y el sistema lo indica al usuario,
  para que no lo distribuya creyendo que sirve

### Requirement: Listado de dispositivos

El sistema SHALL ofrecer un listado de los dispositivos dados de alta que
incluya, para cada uno, su nombre, su dirección en el túnel y cuándo se conectó
por última vez, distinguiendo el que nunca ha conectado.

El listado SHALL identificar los dispositivos por el nombre que les puso el
usuario, no por su material criptográfico.

#### Scenario: Listado con dispositivos dados de alta

- **WHEN** el usuario pide el listado y hay dispositivos dados de alta
- **THEN** obtiene una línea por dispositivo con su nombre, su dirección y su
  última conexión

#### Scenario: Listado vacío

- **WHEN** el usuario pide el listado y no hay ningún dispositivo
- **THEN** el sistema lo indica y sugiere cómo crear uno

#### Scenario: Servidor no disponible

- **WHEN** el usuario pide el listado con el servidor parado
- **THEN** el sistema informa de que el servidor no responde en lugar de
  presentar un listado vacío como si no hubiera dispositivos
