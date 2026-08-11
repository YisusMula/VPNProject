## Purpose

Define qué obtiene un dispositivo personal al conectarse al túnel desde fuera de
casa — alcanzar los dispositivos de la red doméstica y salir a internet con la IP
pública del hogar — y cómo se le entregan sus credenciales.

## ADDED Requirements

### Requirement: Acceso a la red local del servidor

Un cliente conectado al túnel SHALL poder alcanzar los dispositivos de la red
local donde está alojado el servidor VPN, usando sus direcciones IP reales de
esa red.

El cliente MUST NOT necesitar rutas estáticas, configuración adicional ni
software extra más allá de la aplicación oficial de WireGuard.

#### Scenario: Alcanzar un dispositivo de la LAN doméstica

- **WHEN** un cliente conectado desde una red externa contacta con la IP LAN de
  un dispositivo de casa (por ejemplo un NAS o una impresora)
- **THEN** la conexión se establece a través del túnel

#### Scenario: Alcanzar la interfaz de administración del router

- **WHEN** un cliente conectado contacta con la IP de la puerta de enlace de la
  red doméstica
- **THEN** obtiene respuesta, permitiendo administrar la red en remoto

### Requirement: Salida a internet por la IP pública del hogar

Por defecto, la totalidad del tráfico de un cliente conectado — incluidas las
consultas DNS — SHALL enrutarse por el túnel y salir a internet por la conexión
del hogar.

Los servicios externos SHALL observar la IP pública del hogar como origen del
tráfico del cliente.

#### Scenario: IP pública observada

- **WHEN** un cliente conectado consulta un servicio de eco de IP pública
- **THEN** el servicio devuelve la IP pública del hogar, no la de la red donde
  se encuentra físicamente el cliente

#### Scenario: Sin fugas de DNS

- **WHEN** un cliente conectado realiza una consulta DNS
- **THEN** la consulta viaja por el túnel y no se resuelve mediante los
  servidores DNS de la red local donde está el cliente

### Requirement: Entrega de credenciales de cliente

El sistema SHALL producir, para cada cliente, un fichero de configuración
importable y una representación en código QR para dispositivos móviles.

El sistema SHALL permitir crear clientes adicionales después del despliegue
inicial sin invalidar los ya existentes.

#### Scenario: Cliente creado en el despliegue inicial

- **WHEN** finaliza el comando de despliegue
- **THEN** existe un primer cliente con su fichero de configuración y su código
  QR accesibles al usuario

#### Scenario: Alta de un cliente adicional

- **WHEN** el usuario solicita un nuevo cliente con un nombre dado
- **THEN** el sistema genera sus credenciales propias y los clientes anteriores
  siguen conectándose con normalidad

#### Scenario: Nombre de cliente duplicado

- **WHEN** el usuario solicita un cliente con un nombre que ya existe
- **THEN** el sistema rechaza la operación e informa, en lugar de sobrescribir
  las credenciales del cliente existente

### Requirement: Interfaz de administración no expuesta a internet

La interfaz web de administración del servidor SHALL escuchar únicamente en la
red local del servidor y MUST NOT ser alcanzable desde internet mediante el
reenvío de puertos documentado.

#### Scenario: Puertos publicados

- **WHEN** se inspeccionan los puertos que el servidor publica hacia el exterior
- **THEN** sólo el puerto UDP del túnel está destinado a reenviarse desde
  internet, y el de administración queda restringido a la red local
