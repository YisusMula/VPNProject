## Why

El cambio anterior dejó el despliegue en un solo comando, pero el **uso diario**
sigue teniendo huecos. Tres concretos:

1. **No se puede revocar un dispositivo desde la terminal.** Si pierdes el móvil,
   la única vía es abrir el panel web. Es justo el momento en el que quieres
   actuar rápido y sin buscar la contraseña del panel.
2. **El diagnóstico habla en claves públicas.** `doctor.sh` lista
   `abc123def456… nunca ha conectado`, que no identifica ningún dispositivo. El
   usuario no puede saber cuál de sus aparatos es.
3. **El túnel completo es la única opción.** Es lo correcto para el streaming
   (salir por la IP de casa), pero obliga a que *todo* el tráfico pase por la
   subida doméstica. Para trabajar fuera, cuando sólo necesitas llegar al NAS,
   es un peaje innecesario.

Y una copia de seguridad que hoy es un `docker run … tar czf` copiado a mano del
README, cuando perder ese volumen significa regenerar **todos** los dispositivos.

Además, la implementación anterior dejó un fallo de robustez: el panel de
administración se publica sobre la IP local concreta que se detectó en el
despliegue. Si el DHCP le cambia la IP al servidor, Docker no puede publicar ese
puerto y **el contenedor entero no arranca**: no se cae el panel, se cae la VPN,
con el mensaje `cannot assign requested address`, que no apunta a la causa.

## What Changes

- Nuevo `scripts/remove-client.sh <nombre>`: revoca un dispositivo al instante
  sin tocar a los demás. Pide confirmación, porque es destructivo e
  irreversible.
- Nuevo `scripts/list-clients.sh`: listado de dispositivos con nombre, estado y
  última conexión.
- `doctor.sh` pasa a mostrar **nombres de dispositivo** en lugar de prefijos de
  clave pública, cruzando el estado del túnel con el listado del panel.
  *Justificación*: un identificador que el usuario no reconoce no es
  diagnóstico, es ruido.
- `add-client.sh` acepta `--solo-lan`: genera el dispositivo con acceso
  únicamente a la red doméstica, dejando que el resto del tráfico salga por la
  red donde esté el cliente. El comportamiento por defecto **no cambia**: sigue
  siendo túnel completo, que es lo que resuelve el caso del streaming.
- Nuevo `scripts/backup.sh`, con `--restaurar`: copia y restauración del único
  estado del proyecto en un comando, avisando de que el fichero contiene claves
  privadas.
- **BREAKING (operativo, no de interfaz)**: el panel de administración deja de
  publicarse sobre una IP local fija y pasa a publicarse en todas las interfaces
  del anfitrión. *Justificación*: la exposición efectiva no cambia —seguía siendo
  alcanzable desde toda la red local, y desde internet no lo es en ningún caso
  porque su puerto no se reenvía— pero desaparece el fallo que tumbaba la VPN al
  cambiar la IP del servidor. Quien quiera aislamiento estricto puede seguir
  fijando `WG_UI_BIND=127.0.0.1`.
- `doctor.sh` comprueba que el modo de publicación del panel no sea uno que
  pueda dejar de arrancar.

## Capabilities

### New Capabilities
- `gestion-dispositivos`: ciclo de vida completo de un dispositivo desde la
  terminal — alta, listado, baja — y qué garantías tiene cada operación
  respecto a los demás dispositivos.
- `copia-seguridad`: resguardo y restauración del estado que contiene las claves.

### Modified Capabilities
- `acceso-remoto`: se añade el modo sólo-LAN como alternativa al túnel completo,
  y el listado pasa a identificar dispositivos por nombre.
- `despliegue-cero-config`: la publicación del panel de administración no debe
  poder impedir que arranque el servidor VPN.

## Impact

- **Ficheros nuevos**: `scripts/remove-client.sh`, `scripts/list-clients.sh`,
  `scripts/backup.sh`.
- **Ficheros modificados**: `scripts/add-client.sh` (opción `--solo-lan`),
  `scripts/doctor.sh` (nombres y comprobación del panel), `scripts/lib.sh`
  (cliente de la API compartido), `deploy.sh` y `docker-compose.yml` (publicación
  del panel), `README.md`, `.env.example`, `.gitignore` (directorio de copias).
- **Dependencias**: ninguna nueva. Se sigue usando `curl` y `python3`.
- **Compatibilidad**: los dispositivos ya generados siguen funcionando sin
  cambios. Un `.env` existente con `WG_UI_BIND` fijado se respeta; sólo cambia
  el valor por defecto para despliegues nuevos.
