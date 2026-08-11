## Purpose

Mantiene el servidor VPN alcanzable desde fuera cuando la operadora cambia la IP
pública del hogar, de forma que los clientes ya distribuidos sigan conectando sin
tener que regenerarlos.

## ADDED Requirements

### Requirement: Punto de conexión estable frente a IP cambiante

El sistema SHALL permitir que los clientes se configuren contra un nombre de
dominio estable en lugar de contra una dirección IP literal.

Cuando el usuario proporciona un dominio dinámico, el sistema SHALL usarlo como
punto de conexión en todas las configuraciones de cliente que genere.

#### Scenario: Cliente generado con dominio dinámico configurado

- **WHEN** el usuario ha configurado un dominio DDNS y se genera un cliente
- **THEN** la configuración del cliente apunta a ese dominio, no a la IP pública
  literal

#### Scenario: Cliente generado sin dominio dinámico

- **WHEN** no hay dominio DDNS configurado y se genera un cliente
- **THEN** el sistema usa la IP pública detectada y advierte explícitamente al
  usuario de que la conexión dejará de funcionar cuando esa IP cambie

### Requirement: Actualización automática del registro DDNS

Cuando el usuario aporta credenciales de un proveedor DDNS, el sistema SHALL
mantener el registro del dominio apuntando a la IP pública actual del hogar de
forma continua y sin intervención manual, incluyendo tras un reinicio de la
máquina servidora.

El componente de actualización DDNS SHALL ser opcional: su ausencia MUST NOT
impedir el despliegue del servidor VPN.

#### Scenario: Cambio de IP pública

- **WHEN** la operadora asigna una IP pública distinta al hogar
- **THEN** el registro del dominio pasa a resolver a la nueva IP sin que el
  usuario intervenga, y los clientes existentes vuelven a conectar

#### Scenario: Reinicio de la máquina servidora

- **WHEN** la máquina que aloja el servidor se reinicia
- **THEN** tanto el servidor VPN como la actualización DDNS vuelven a estar
  activos automáticamente

#### Scenario: Despliegue sin credenciales DDNS

- **WHEN** el usuario despliega sin aportar credenciales DDNS
- **THEN** el servidor VPN se levanta con normalidad y no se ejecuta ningún
  componente de actualización DDNS

### Requirement: Diagnóstico de desincronización DDNS

El sistema SHALL poder informar de si el dominio configurado resuelve
actualmente a la IP pública del hogar.

#### Scenario: Dominio desincronizado

- **WHEN** el dominio configurado resuelve a una IP distinta de la IP pública
  actual del hogar
- **THEN** el sistema lo reporta como problema, indicando ambos valores
