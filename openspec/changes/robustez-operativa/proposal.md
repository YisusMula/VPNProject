## Why

Los dos cambios anteriores resolvieron el despliegue y el uso diario. Este
aborda una pregunta distinta: **qué hace que un servidor doméstico deje de
funcionar bien meses después**, cuando ya nadie lo está mirando.

Todos los puntos siguientes se comprobaron sobre el proyecto tal y como está,
no son hipótesis:

1. **El MTU no se configura en ninguna parte.** WireGuard usa 1420 por defecto.
   Si el camino real es más pequeño —PPPoE, habitual en fibra española, deja
   1492; y aquí mismo la interfaz física tiene 1400— los paquetes grandes se
   pierden. Como los routers domésticos suelen filtrar el ICMP que avisaría, el
   resultado es un agujero negro silencioso: el túnel conecta, las webs
   pequeñas cargan, y las descargas o las páginas grandes **se quedan colgadas**.
   Es el fallo más común de WireGuard y el más difícil de diagnosticar sin
   saberlo de antemano.
2. **Nadie comprueba el reloj del sistema.** El intercambio de claves de
   WireGuard lleva marca de tiempo para impedir repeticiones. Una Raspberry Pi
   no tiene reloj con pila: tras un corte de luz arranca con la hora
   equivocada y, hasta que NTP la corrige, **los clientes no pueden conectar**.
   El síntoma no menciona la hora por ningún lado.
3. **Nadie comprueba que Docker arranque solo.** `restart: unless-stopped`
   revive el contenedor, pero sólo si el servicio Docker se inicia con el
   equipo. Si `docker.service` está deshabilitado, un corte de luz deja la VPN
   caída **para siempre**, hasta que alguien entre a mano.
4. **Los registros crecen sin límite.** No se define política de rotación, así
   que el controlador por defecto acumula sin tope. En la tarjeta SD de una
   Raspberry, eso acaba llenando el disco y tumbando el equipo entero.
5. **`deploy.sh` da por bueno un servidor roto.** Sólo espera a que responda el
   panel web, que se levanta con independencia del túnel. Si `wg0` no llega a
   crearse, el script informa de éxito igualmente. Ocurrió durante el
   desarrollo: "Servidor VPN en marcha" seguido del fallo al crear el
   dispositivo.
6. **El consejo de reenvío ignora `WG_CONFIG_PORT`.** Si se usa esa variable
   para publicar un puerto externo distinto, `doctor.sh` sigue diciendo que se
   abra `WG_PORT`, que ya no es el puerto correcto.

## What Changes

- `doctor.sh` mide el **MTU real del camino** y avisa cuando el valor efectivo
  de WireGuard no cabe, indicando el `WG_MTU` concreto que hay que poner.
  *Justificación*: sin esta comprobación, el usuario ve "conecta pero va mal" y
  no tiene ninguna pista que le lleve al MTU.
- Se expone `WG_MTU` como variable configurable, sin valor por defecto: se deja
  el de WireGuard salvo que el diagnóstico indique otro.
- `doctor.sh` comprueba el **reloj del sistema** contra una referencia externa y
  avisa si la desviación es suficiente para romper los intercambios de claves.
- `doctor.sh` comprueba que **Docker esté habilitado para arrancar con el
  equipo**, e indica el comando exacto para habilitarlo.
- El stack define **rotación de registros** acotada.
  *Justificación*: es una línea de configuración que evita que el disco se
  llene solo con el tiempo.
- `deploy.sh` deja de fiarse del panel: verifica que la **interfaz del túnel
  existe** antes de declarar el despliegue correcto, y si no, señala la causa.
- El consejo de reenvío de puertos usa el **puerto de cara al exterior**
  correcto, distinguiéndolo del puerto interno cuando difieren.

## Capabilities

### New Capabilities
- `salud-operativa`: comprobaciones sobre las condiciones del anfitrión que
  hacen que la VPN funcione mal o deje de funcionar con el tiempo — tamaño de
  paquete, hora del sistema, arranque automático y crecimiento de registros.

### Modified Capabilities
- `despliegue-cero-config`: el despliegue no puede darse por bueno sin que el
  túnel exista.
- `diagnostico-red`: el consejo de reenvío debe referirse al puerto que
  realmente usan los clientes.

## Impact

- **Ficheros modificados**: `scripts/doctor.sh` (cuatro comprobaciones nuevas y
  corrección del puerto), `scripts/lib.sh` (medición de MTU y de desviación
  horaria), `deploy.sh` (verificación del túnel), `docker-compose.yml`
  (rotación de registros y `WG_MTU`), `.env.example`, `README.md`.
- **Dependencias**: ninguna nueva. La medición de MTU usa `ping`, presente en
  cualquier sistema; si falta, la comprobación se declara no concluyente en
  lugar de fallar.
- **Compatibilidad**: no cambia el comportamiento de los túneles existentes.
  `WG_MTU` queda sin definir por defecto, así que nada se altera salvo que el
  usuario lo fije siguiendo el consejo del diagnóstico.
