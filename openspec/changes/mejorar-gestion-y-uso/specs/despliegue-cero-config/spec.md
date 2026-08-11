## ADDED Requirements

### Requirement: La publicación del panel no puede impedir el arranque del servidor

La forma en que se publica la interfaz de administración MUST NOT poder impedir
que el servidor VPN arranque.

En concreto, el sistema MUST NOT publicar el panel de forma que dependa de que
una dirección concreta siga existiendo en el anfitrión, porque un cambio de
dirección por DHCP dejaría al servidor sin arrancar y sin túnel.

Se mantiene la garantía de que el panel no es alcanzable desde internet mediante
el reenvío de puertos documentado.

#### Scenario: La dirección local del servidor cambia

- **WHEN** el equipo servidor recibe una dirección distinta en su red local y el
  servidor VPN se reinicia
- **THEN** el servidor VPN arranca con normalidad y el túnel vuelve a estar
  disponible

#### Scenario: El usuario fija una dirección concreta

- **WHEN** el usuario configura explícitamente una dirección de publicación para
  el panel
- **THEN** el sistema la respeta, y el diagnóstico advierte de que esa elección
  puede impedir el arranque si la dirección deja de existir

#### Scenario: Puertos alcanzables desde internet

- **WHEN** se inspecciona qué debe reenviarse desde internet
- **THEN** sigue siendo únicamente el puerto UDP del túnel, nunca el del panel
