## Purpose

Permite levantar el servidor VPN completo con un solo comando, deduciendo del
propio entorno de red todos los valores de configuración que son observables,
de modo que el usuario no tenga que editar ficheros a mano antes del primer
despliegue.

## ADDED Requirements

### Requirement: Despliegue con un único comando

El sistema SHALL exponer un único punto de entrada ejecutable que, partiendo de
un clon limpio del repositorio y sin fichero de configuración previo, deje el
servidor VPN operativo y al menos un cliente listo para usar.

El sistema MUST NOT requerir que el usuario ejecute varios scripts en un orden
determinado ni que edite ningún fichero antes de ese comando.

#### Scenario: Primer despliegue sobre un clon limpio

- **WHEN** el usuario ejecuta el comando de despliegue en una máquina con Docker
  y sin fichero `.env` presente
- **THEN** el sistema genera la configuración, arranca el servidor VPN, crea un
  primer cliente y muestra por pantalla cómo importarlo

#### Scenario: Re-ejecución sobre un despliegue existente

- **WHEN** el usuario vuelve a ejecutar el comando de despliegue sobre una
  instalación ya funcionando
- **THEN** el sistema conserva la configuración y las claves existentes, no
  invalida los clientes ya distribuidos, y termina sin error

#### Scenario: Falta un requisito previo

- **WHEN** el comando de despliegue se ejecuta en una máquina sin Docker o sin
  Docker Compose v2
- **THEN** el sistema aborta antes de modificar nada e indica qué falta y cómo
  instalarlo

### Requirement: Autodetección del entorno de red

El sistema SHALL detectar automáticamente, sin intervención del usuario: la IP
pública actual del hogar, la subred LAN a la que pertenece el servidor y la
interfaz de red por la que el servidor sale a internet.

Cada valor detectado SHALL poder ser sobrescrito por el usuario mediante el
fichero de configuración o variables de entorno; el valor explícito del usuario
MUST tener prioridad sobre el detectado.

#### Scenario: Detección correcta

- **WHEN** el servidor tiene conectividad a internet y una única interfaz con
  ruta por defecto
- **THEN** el sistema determina la IP pública, la subred LAN y la interfaz de
  salida, y muestra los tres valores al usuario antes de continuar

#### Scenario: El usuario fija un valor explícito

- **WHEN** el usuario ha definido el nombre de host público en la configuración
- **THEN** el sistema usa ese valor y no lo reemplaza por la IP pública detectada

#### Scenario: No hay conectividad para detectar la IP pública

- **WHEN** la detección de la IP pública falla
- **THEN** el sistema informa del fallo y solicita el nombre de host o IP pública
  al usuario, en lugar de continuar con un valor vacío o incorrecto

### Requirement: Configuración generada, no editada

El sistema SHALL generar el fichero de configuración a partir de los valores
detectados. El fichero generado SHALL estar comentado indicando qué valor fue
autodetectado y cuál es su origen.

El sistema MUST NOT sobrescribir un fichero de configuración ya existente.

#### Scenario: Generación inicial

- **WHEN** no existe fichero de configuración
- **THEN** el sistema lo crea con los valores detectados y deja constancia en él
  de cuáles se autodetectaron

#### Scenario: Configuración preexistente

- **WHEN** ya existe un fichero de configuración
- **THEN** el sistema lo respeta sin modificarlo y lo usa como fuente de verdad

### Requirement: Secretos fuera del control de versiones

El sistema SHALL impedir que material sensible — claves privadas, claves
precompartidas, contraseñas y configuraciones de cliente generadas — llegue al
repositorio.

#### Scenario: Estado del repositorio tras un despliegue

- **WHEN** el usuario ejecuta el despliegue completo dentro del clon del
  repositorio y consulta el estado de git
- **THEN** ningún fichero con claves, contraseñas o configuración de cliente
  aparece como pendiente de commit
