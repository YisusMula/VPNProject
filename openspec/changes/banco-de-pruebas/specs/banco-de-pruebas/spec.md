## Purpose

Comprueba de forma repetible que el proyecto hace lo que promete, ejecutando el
ciclo completo contra un servidor VPN real en lugar de contra un simulador, de
modo que una regresión se detecte antes de llegar al equipo del usuario.

## ADDED Requirements

### Requirement: Verificación contra un servidor real

El banco SHALL ejercitar las operaciones del proyecto contra una instancia real
del servidor VPN, con una interfaz de túnel real, y comprobar el **resultado
observable** de cada operación, no sólo que el comando termine sin error.

El banco MUST NOT sustituir el servidor por un simulador de su API: un simulador
escrito a partir de suposiciones sólo confirma esas suposiciones.

#### Scenario: Ejecución completa correcta

- **WHEN** se ejecuta el banco en un entorno capaz de levantar el túnel
- **THEN** se comprueban el alta de dispositivos, el listado, la revocación, los
  dos modos de túnel y la copia con su restauración, y el banco termina
  indicando que todo pasó

#### Scenario: Una comprobación falla

- **WHEN** cualquier comprobación no obtiene el resultado esperado
- **THEN** el banco lo indica señalando qué se esperaba y qué se obtuvo, y
  termina con un código de salida distinto de cero

### Requirement: Obtención de WireGuard según el entorno

El banco SHALL usar el WireGuard del kernel cuando el equipo lo soporte y, si no,
SHALL intentar una implementación en espacio de usuario.

Cuando no pueda obtener ninguna de las dos, el banco SHALL omitir explícitamente
las pruebas que requieren túnel e indicar por qué. MUST NOT darlas por
superadas.

#### Scenario: Equipo con WireGuard en el kernel

- **WHEN** el kernel del equipo soporta WireGuard
- **THEN** el banco lo usa directamente, sin compilar nada

#### Scenario: Kernel sin soporte pero con herramientas para compilar

- **WHEN** el kernel no soporta WireGuard y el equipo puede compilar la
  implementación en espacio de usuario
- **THEN** el banco la construye y ejecuta las pruebas con ella

#### Scenario: Entorno incapaz de levantar un túnel

- **WHEN** no hay WireGuard en el kernel ni forma de obtener la implementación
  en espacio de usuario
- **THEN** el banco informa de qué pruebas omite y por qué, y no las cuenta como
  superadas

### Requirement: Aislamiento de la instalación real

El banco MUST NOT modificar ni destruir la configuración, las claves ni los
dispositivos de una instalación en uso.

Todo lo que cree SHALL quedar identificado como propio del banco y SHALL
eliminarse al terminar, incluso si alguna comprobación falla.

#### Scenario: Banco ejecutado sobre una instalación en uso

- **WHEN** se ejecuta el banco en un equipo que ya tiene el servidor desplegado
  con dispositivos dados de alta
- **THEN** al terminar, la configuración, las claves y los dispositivos previos
  siguen intactos

#### Scenario: Limpieza tras un fallo

- **WHEN** una comprobación falla a mitad de la ejecución
- **THEN** el banco elimina igualmente los recursos que había creado

### Requirement: Cobertura de escenarios no reproducibles

El banco SHALL comprobar, mediante entradas fijas conocidas, la lógica de los
escenarios que no se pueden reproducir en el equipo donde se ejecuta: presencia
de CGNAT, varios niveles de NAT, ausencia de herramientas de medición y reloj
desviado.

#### Scenario: Escenario de red no reproducible

- **WHEN** se comprueba la clasificación de un escenario de red que el equipo no
  tiene, como CGNAT
- **THEN** la comprobación se realiza sobre una entrada fija conocida y verifica
  la clasificación resultante

#### Scenario: Ausencia de una herramienta

- **WHEN** se comprueba el comportamiento sin una herramienta de medición
  disponible
- **THEN** se verifica que el resultado es "no concluyente" y que no aborta la
  ejecución
