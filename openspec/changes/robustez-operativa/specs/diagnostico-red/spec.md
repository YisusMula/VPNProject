## ADDED Requirements

### Requirement: El consejo de reenvío usa el puerto que ven los clientes

Cuando el puerto que los clientes emplean para conectarse difiera del puerto en
el que escucha el servidor, el consejo de reenvío SHALL referirse al puerto
externo correcto y distinguirlo explícitamente del interno.

#### Scenario: Puerto externo distinto del interno

- **WHEN** está configurado un puerto de cara al exterior distinto del puerto de
  escucha
- **THEN** el consejo de reenvío indica el externo como puerto de origen y el de
  escucha como destino, señalando que son distintos

#### Scenario: Ambos puertos coinciden

- **WHEN** no hay un puerto externo distinto configurado
- **THEN** el consejo de reenvío usa el mismo puerto en origen y destino
