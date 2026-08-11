## Purpose

Detecta y explica en lenguaje accionable los fallos de red que impiden que el
túnel funcione — CGNAT, puerto cerrado, doble NAT o reenvío desactivado — para
que el usuario sepa exactamente dónde actuar en lugar de probar a ciegas.

## ADDED Requirements

### Requirement: Detección de CGNAT antes de configurar routers

El sistema SHALL determinar si la conexión del hogar está detrás de CGNAT,
comparando la dirección IP del lado WAN del router con la IP pública observada
desde internet.

Cuando se detecte CGNAT, el sistema SHALL informar de que el reenvío de puertos
no puede funcionar y SHALL indicar las alternativas disponibles.

#### Scenario: Conexión detrás de CGNAT

- **WHEN** la IP del lado WAN del router es una dirección no enrutable en
  internet y difiere de la IP pública observada
- **THEN** el sistema lo reporta como bloqueante, explica que ninguna
  configuración de reenvío de puertos lo resolverá y propone alternativas

#### Scenario: Conexión con IP pública directa

- **WHEN** la IP del lado WAN del router coincide con la IP pública observada
- **THEN** el sistema reporta que el reenvío de puertos es viable

### Requirement: Verificación de alcanzabilidad del puerto del túnel

El sistema SHALL reportar el estado de alcanzabilidad del puerto UDP del túnel
desde internet, distinguiendo tres resultados: alcanzable confirmado, no
alcanzable confirmado y no concluyente.

El sistema MUST NOT presentar como confirmado un resultado que no pueda
verificar, dado que la comprobación de un puerto UDP desde el exterior no es
siempre determinista.

#### Scenario: Alcanzabilidad confirmada por negociación previa

- **WHEN** algún cliente ha completado alguna vez una negociación con el
  servidor desde una red externa
- **THEN** el sistema reporta el puerto como alcanzable confirmado

#### Scenario: Comprobación no concluyente

- **WHEN** ninguna negociación previa consta y la sonda directa al puerto no
  obtiene respuesta ni error explícito
- **THEN** el sistema reporta el resultado como no concluyente e indica cómo
  confirmarlo manualmente desde una red externa

#### Scenario: Puerto no alcanzable por servicio caído

- **WHEN** el servidor VPN no está escuchando en el puerto configurado
- **THEN** el sistema reporta el puerto como no alcanzable confirmado e indica
  el puerto concreto y en qué equipos debe abrirse

### Requirement: Detección de doble NAT en cascada de routers

El sistema SHALL detectar si el servidor está detrás de más de un nivel de NAT,
situación en la que el reenvío de puertos debe configurarse en cada router de la
cadena.

Al detectarlo, el sistema SHALL indicar cuántos niveles hay y qué regla
corresponde a cada uno.

#### Scenario: Servidor detrás de un router secundario en modo router

- **WHEN** la puerta de enlace de la red del servidor tiene a su vez una
  dirección privada en su lado WAN
- **THEN** el sistema reporta doble NAT y describe la regla de reenvío necesaria
  en el router principal y la necesaria en el secundario

#### Scenario: Servidor conectado a un único router

- **WHEN** sólo existe un nivel de NAT entre el servidor e internet
- **THEN** el sistema reporta que basta con una única regla de reenvío

### Requirement: Verificación del estado del túnel y del reenvío

El sistema SHALL comprobar que el servidor VPN está en ejecución, que el reenvío
de paquetes IP está habilitado y qué peers han completado una negociación
reciente.

#### Scenario: Reenvío IP deshabilitado

- **WHEN** el reenvío de paquetes IP está desactivado en el sistema anfitrión
- **THEN** el sistema lo reporta como problema e indica el ajuste a aplicar para
  corregirlo de forma persistente

#### Scenario: Peer sin negociación completada

- **WHEN** un cliente está dado de alta pero nunca ha completado una negociación
  con el servidor
- **THEN** el sistema lo reporta, distinguiéndolo de un cliente que sí conectó
  alguna vez

### Requirement: Informe de diagnóstico accionable

El diagnóstico SHALL presentar cada comprobación con un resultado inequívoco
(correcto, advertencia o fallo) y, para cada fallo, la acción concreta que
resuelve el problema.

El diagnóstico MUST NOT modificar la configuración del sistema: es una operación
de sólo lectura.

#### Scenario: Ejecución del diagnóstico

- **WHEN** el usuario ejecuta el diagnóstico
- **THEN** obtiene una lista de comprobaciones con su resultado y, para las que
  fallan, la acción correctiva correspondiente

#### Scenario: Diagnóstico sobre un sistema sano

- **WHEN** todas las comprobaciones pasan
- **THEN** el sistema lo indica y termina con un código de salida de éxito
