## Why

El repositorio actual está diseñado para un escenario *site-to-site* (dos sedes
con LANs distintas, `site-a` y `site-b`, más un cliente itinerante). El caso real
es mucho más simple: **una sola casa, un servidor, varios dispositivos personales
que se conectan desde fuera**. Esa generalidad no aportada se paga en
configuración manual: hoy hay que editar `.env` a mano con siete variables
(subredes de dos sedes, IPs de VPN estáticas, rango de itinerantes), ejecutar tres
scripts en orden y, además, resolver por tu cuenta la IP dinámica y el doble NAT.

El objetivo es que desplegar sea: **clonar, ejecutar un comando, abrir un puerto
en cada router, escanear un QR**. Todo lo demás debe autodetectarse o tener un
valor por defecto correcto.

## What Changes

- **BREAKING** — Se eliminan los roles `site-a` y `site-b` y todo el modelo
  site-to-site. *Justificación*: obligaban a declarar dos subredes LAN, dos IPs
  de VPN estáticas y a desplegar un gateway Linux en cada sede. Nada de eso
  existe en el caso de uso real (una sola red doméstica), y era la mayor fuente
  de variables obligatorias en `.env`.
- **BREAKING** — `scripts/setup-server.sh`, `scripts/setup-client.sh` y
  `scripts/generate-keys.sh` se sustituyen por un único `deploy.sh`.
  *Justificación*: el orden de ejecución entre los tres scripts era conocimiento
  implícito que el usuario debía tener; un solo punto de entrada lo elimina.
- **BREAKING** — Se elimina la gestión propia de claves en `keys/` y las
  plantillas `server/wg0.conf.template` + `client/*.conf.template`.
  *Justificación*: wg-easy ya genera y persiste el par de claves del servidor y
  de cada peer en su volumen. Mantener un generador paralelo duplicaba el estado
  y creaba la posibilidad de que las claves del fichero y las del contenedor
  divergieran.
- `.env` pasa a ser **opcional y generado**. `deploy.sh` lo escribe a partir de
  la autodetección; el usuario sólo lo edita si quiere cambiar algo.
  *Justificación*: `WG_HOST`, la subred LAN y la interfaz de salida son
  observables desde la propia máquina; pedirlas era pedir al usuario que
  averiguase datos que el script puede leer.
- Se añade **autodetección** de: IP pública actual, subred LAN del servidor,
  interfaz de red por defecto y presencia de CGNAT.
- Se añade **DDNS integrado** (contenedor opcional en el mismo Compose) para
  resolver la IP pública dinámica sin intervención manual.
  *Justificación*: sin esto, una IP dinámica rompe todos los clientes ya
  distribuidos cada vez que cambia.
- Se añade `scripts/doctor.sh`: diagnóstico que verifica CGNAT, alcanzabilidad
  del puerto UDP desde fuera, reenvío IP y estado del túnel, con mensajes
  accionables por router (Huawei / Archer en cascada).
- Los clientes se generan en **túnel completo por defecto**
  (`AllowedIPs = 0.0.0.0/0, ::/0`), lo que da acceso a la LAN de casa **y**
  salida a internet por la IP de casa con una sola regla y sin rutas manuales en
  el dispositivo cliente.
- Se elimina el override manual de `WG_POST_UP` / `WG_POST_DOWN` con `eth0`
  hardcodeado en `docker-compose.yml`. *Justificación*: la imagen ya aplica por
  defecto las reglas correctas resolviendo la interfaz en tiempo de arranque;
  el override sólo introducía un nombre de interfaz que puede no existir.
- README reescrito en español, orientado al despliegue real: doble NAT
  Huawei + Archer, CGNAT y verificación.

## Capabilities

### New Capabilities
- `despliegue-cero-config`: comando único de despliegue, autodetección del
  entorno de red y generación del fichero de configuración sin edición manual.
- `acceso-remoto`: qué obtiene un dispositivo cliente al conectarse — acceso a
  la LAN doméstica y salida a internet por la IP pública del hogar — y cómo se
  entregan sus credenciales (fichero + QR).
- `ip-dinamica`: mantener alcanzable el servidor cuando la IP pública del hogar
  cambia, mediante DDNS.
- `diagnostico-red`: detección y reporte accionable de los fallos de red que
  impiden el túnel (CGNAT, puerto cerrado, doble NAT, reenvío desactivado).

### Modified Capabilities
<!-- Ninguna: el repositorio no tiene specs previas bajo openspec/specs/. -->

## Impact

- **Ficheros eliminados**: `scripts/generate-keys.sh`, `scripts/setup-server.sh`,
  `scripts/setup-client.sh`, `server/wg0.conf.template`,
  `client/site-a.conf.template`, `client/site-b.conf.template`,
  `client/road-warrior.conf.template`.
- **Ficheros nuevos**: `deploy.sh`, `scripts/doctor.sh`, `scripts/add-client.sh`.
- **Ficheros modificados**: `docker-compose.yml`, `.env.example`, `README.md`,
  `.gitignore`.
- **Dependencias**: se mantiene Docker + Compose v2. Deja de ser obligatorio
  `wireguard-tools` en el servidor (las claves las genera el contenedor);
  `qrencode` sigue siendo opcional, con respaldo al QR que ya renderiza wg-easy.
- **Compatibilidad**: quien tuviera un despliegue previo con `keys/` y
  `server/wg0.conf` debe regenerar los clientes. Es un proyecto sin usuarios en
  producción, por lo que no se aporta ruta de migración.
