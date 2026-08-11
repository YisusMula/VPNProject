## Context

Ver `proposal.md` — Why. Restricciones que condicionan el enfoque, todas
comprobadas leyendo el código de la imagen `wg-easy:14`:

- La API expone `DELETE /api/wireguard/client/:clientId`, que borra el peer y
  guarda la configuración. No hay endpoint para modificar el `AllowedIPs` de un
  cliente: sólo existen `PUT .../name` y `PUT .../address`.
- `WG_ALLOWED_IPS` es un ajuste **global del servidor**, no por cliente. Se
  aplica igual a todas las configuraciones que genera.
- `GET /api/wireguard/client` ya devuelve, por cliente, `name`, `address`,
  `enabled`, `publicKey` y `latestHandshakeAt`, este último rellenado a partir
  de `wg show wg0 dump`.
- Todo el estado vive en el volumen montado en `/etc/wireguard`.

## Goals / Non-Goals

**Goals:**

- Ciclo de vida completo del dispositivo sin abrir el navegador.
- Que el diagnóstico hable el idioma del usuario: nombres, no claves.
- Que el túnel completo deje de ser obligatorio, sin dejar de ser el defecto.
- Que ninguna decisión sobre el panel de administración pueda dejar sin túnel.

**Non-Goals:**

- Sustituir el panel web: sigue siendo la vía para todo lo demás.
- Rotación automática de claves, cuotas o caducidad de dispositivos.
- Copias de seguridad remotas o cifradas: el fichero se produce en local y el
  usuario decide dónde guardarlo.

## Decisions

### D1 — El modo sólo-LAN se aplica reescribiendo la configuración descargada

`AllowedIPs` en el fichero del cliente es **routing del lado del cliente**:
determina qué destinos mete en el túnel. No tiene que coincidir con lo que el
servidor acepta de ese peer, que se sigue rigiendo por su `10.8.0.x/32`.

Como la API no permite fijarlo por cliente y `WG_ALLOWED_IPS` es global, el modo
sólo-LAN se implementa **reescribiendo la línea `AllowedIPs` del fichero ya
descargado**, sustituyendo `0.0.0.0/0` por la subred doméstica detectada.

*Alternativa descartada — cambiar `WG_ALLOWED_IPS` del servidor antes de generar
y restaurarlo después*: es global, así que habría una ventana en la que otro
alta simultánea saldría con el modo equivocado, y un fallo a media operación
dejaría el servidor con el ajuste cambiado de forma permanente.

En modo sólo-LAN se **elimina también la línea `DNS`**. Con el túnel restringido
a la subred doméstica, ese servidor DNS no sería alcanzable por el túnel; dejarlo
haría que el dispositivo mandara todas sus consultas a un DNS que resolvería por
fuera, cambiando la configuración de red del cliente sin ganar nada.

### D2 — Un único cliente de API compartido en `lib.sh`

`add-client.sh`, `remove-client.sh`, `list-clients.sh` y `doctor.sh` necesitan
autenticarse contra el panel. La lógica de sesión (cookie, distinción entre
"contraseña rechazada" y "no responde") se mueve a `lib.sh` como
`api_login` / `api_get` / `api_post` / `api_delete`.

*Motivo*: cuatro copias de la misma lógica divergen. Ya ocurrió con el mensaje de
error del login, que confundía "contraseña incorrecta" con "servidor caído".

### D3 — El diagnóstico obtiene los nombres de la API, no de `wg show`

`doctor.sh` deja de parsear `wg show wg0 latest-handshakes` y pasa a usar
`GET /api/wireguard/client`, que ya trae nombre, dirección y última conexión en
una sola llamada.

*Ventaja*: desaparece el prefijo de clave pública como identificador, que no
significa nada para el usuario.

*Riesgo asumido*: el diagnóstico pasa a depender de que el panel responda y de
que `WG_EASY_PASSWORD` sea correcta. Se mantiene el camino antiguo con `wg show`
como respaldo, y cuando se usa, el informe **dice explícitamente** que los
identificadores no son nombres, en lugar de presentarlos como si lo fueran.

### D4 — El panel se publica en todas las interfaces del anfitrión

Se cambia el valor por defecto de `WG_UI_BIND` de la IP local detectada a
`0.0.0.0`.

*Motivo*: publicar sobre una IP concreta hace que el arranque del contenedor
dependa de que esa dirección siga existiendo. Comprobado: con una dirección que
ya no está en el anfitrión, Docker falla con
`cannot assign requested address` y **el contenedor entero no arranca**. No se
degrada el panel: se cae la VPN, y el mensaje no apunta a la causa.

*Análisis de exposición*: el valor anterior ya hacía el panel alcanzable desde
toda la red doméstica, que es justo lo que se quería. Pasar a `0.0.0.0` añade
únicamente las demás interfaces del anfitrión (redes de Docker y el propio
túnel). Desde internet sigue sin ser alcanzable, porque su puerto TCP no se
reenvía en ningún momento; lo único que se reenvía es el UDP del túnel. La
contraseña sigue guardada como hash bcrypt.

El caso en que `0.0.0.0` sí sería peligroso es un servidor con IP pública
directa, sin NAT. No es el escenario del proyecto, pero `doctor.sh` ya detecta
la ausencia de NAT: se aprovecha para avisar en ese caso concreto.

Quien quiera aislamiento estricto puede fijar `WG_UI_BIND=127.0.0.1` y llegar
por túnel SSH. `doctor.sh` advierte de que fijar una IP concreta reintroduce el
fallo de arranque.

### D5 — La copia de seguridad opera sobre el volumen, no sobre el contenedor

`backup.sh` monta el volumen en un contenedor efímero y produce un `tar.gz`. No
requiere que el servidor esté en marcha, porque el estado está en el volumen y
no en el proceso.

En la restauración se para el servicio, se reemplaza el contenido del volumen y
se vuelve a levantar. Es destructivo sobre el estado actual, así que pide
confirmación, y se valida que el fichero sea un `tar.gz` legible **antes** de
tocar nada.

*Nombre del volumen*: se resuelve preguntando a `docker compose`, no
codificándolo, porque depende del nombre del directorio del proyecto.

### D6 — Las operaciones destructivas piden confirmación, con salida desatendida

Revocar y restaurar piden confirmación explícita por teclado y aceptan `--si`
para uso en scripts.

*Motivo*: revocar es irreversible —hay que regenerar el dispositivo— y restaurar
pisa el estado actual. Pero exigir interacción sin alternativa impediría
automatizar, así que la confirmación se puede omitir de forma explícita, nunca
por defecto.

## Risks / Trade-offs

- **[El usuario revoca el dispositivo equivocado]** → La confirmación muestra el
  nombre y la última conexión antes de pedir el sí. No hay deshacer: se dice
  claramente.
- **[Queda un `.conf` obsoleto en `clients/` tras revocar]** → El fichero local
  ya no sirve y podría distribuirse por error. `remove-client.sh` lo señala y
  ofrece borrarlo.
- **[Un dispositivo sólo-LAN no protege en WiFi público]** → Su tráfico a
  internet sale sin cifrar por la red donde esté. Se advierte al crearlo; el
  modo por defecto sigue siendo el túnel completo.
- **[El modo sólo-LAN se rompe si cambia la subred de casa]** → El fichero lleva
  la subred codificada. Si se cambia la red doméstica, hay que regenerar esos
  dispositivos. Los de túnel completo no se ven afectados.
- **[`0.0.0.0` en un servidor sin NAT expondría el panel]** → Escenario fuera del
  propósito del proyecto; aun así `doctor.sh` avisa cuando no detecta NAT.
- **[La copia contiene todas las claves privadas en claro]** → Se avisa en cada
  ejecución y el directorio queda fuera de control de versiones. No se cifra:
  añadir gestión de contraseñas de cifrado daría más problemas que los que
  resuelve para este caso de uso.

## Migration Plan

No hay ruptura para despliegues existentes:

- Los dispositivos ya generados siguen conectando sin cambios.
- Un `.env` con `WG_UI_BIND` ya fijado se respeta tal cual; sólo cambia el valor
  por defecto de los despliegues nuevos. Quien tenga fijada la IP local y quiera
  el comportamiento robusto, borra esa línea y ejecuta `./deploy.sh`.
