## 1. Cliente de API compartido

- [x] 1.1 Mover a `lib.sh` la lógica de sesión como `api_login`, distinguiendo contraseña rechazada, servidor sin responder y respuesta inesperada. Verificar: `bash -n scripts/lib.sh`
- [x] 1.2 Añadir `api_get`, `api_post` y `api_delete` sobre el mismo tarro de cookies. Verificar: ejercitarlas contra el simulador de la API
- [x] 1.3 Añadir `api_clients_json` y un ayudante para localizar un cliente por nombre. Verificar: devuelve el id de un nombre existente y vacío para uno inexistente
- [x] 1.4 Reescribir `add-client.sh` sobre los nuevos ayudantes, sin cambiar su comportamiento. Verificar: los casos ya probados (alta, duplicado→2, contraseña mala, servidor caído) siguen dando el mismo resultado

## 2. Modo sólo-LAN

- [x] 2.1 Aceptar `--solo-lan` en `add-client.sh` y rechazar opciones desconocidas. Verificar: `./scripts/add-client.sh x --opcion-mala` sale con error
- [x] 2.2 Reescribir `AllowedIPs` en la configuración descargada con la subred doméstica detectada (decisión D1). Verificar: el `.conf` generado contiene la subred y no `0.0.0.0/0`
- [x] 2.3 Eliminar la línea `DNS` en modo sólo-LAN (decisión D1). Verificar: el `.conf` generado no contiene `DNS =`
- [x] 2.4 Abortar si no se puede determinar la subred doméstica, indicando cómo fijarla. Verificar: forzar la detección a vacío y comprobar que aborta sin crear el dispositivo
- [x] 2.5 Mostrar el modo y su consecuencia al crear el dispositivo, incluida la advertencia de que sólo-LAN no protege en WiFi público. Verificar: comparar la salida en ambos modos
- [x] 2.6 Mantener el túnel completo como modo por defecto. Verificar: sin opciones, el `.conf` contiene `AllowedIPs = 0.0.0.0/0`

## 3. Revocación de dispositivos

- [x] 3.1 Crear `scripts/remove-client.sh <nombre>` con `set -euo pipefail`. Verificar: `bash -n scripts/remove-client.sh`
- [x] 3.2 Mostrar nombre y última conexión y pedir confirmación antes de revocar; aceptar `--si` para omitirla. Verificar: responder que no deja el dispositivo intacto
- [x] 3.3 Revocar vía `DELETE /api/wireguard/client/:clientId`. Verificar: tras revocar, el dispositivo no aparece en el listado
- [x] 3.4 No afectar al resto de dispositivos. Verificar: dar de alta tres, revocar uno, comprobar que los otros dos siguen presentes con su misma clave
- [x] 3.5 Informar si el nombre no existe, sin revocar nada. Verificar: código de salida distinto de cero y listado sin cambios
- [x] 3.6 Señalar el `.conf` local que queda obsoleto y ofrecer borrarlo. Verificar: tras revocar, la salida menciona el fichero

## 4. Listado de dispositivos

- [x] 4.1 Crear `scripts/list-clients.sh` mostrando nombre, dirección del túnel y última conexión. Verificar: `bash -n scripts/list-clients.sh`
- [x] 4.2 Distinguir el dispositivo que nunca ha conectado. Verificar: contrastar con un dispositivo recién creado
- [x] 4.3 Mensaje propio para el listado vacío, sugiriendo cómo crear uno. Verificar: sin dispositivos, no imprime una tabla vacía
- [x] 4.4 Distinguir "no hay dispositivos" de "el servidor no responde". Verificar: con el servidor parado, el mensaje es el de servidor caído

## 5. Nombres en el diagnóstico

- [x] 5.1 Obtener nombre, dirección y última conexión desde la API en `doctor.sh` (decisión D3). Verificar: la sección 5 muestra nombres
- [x] 5.2 Mantener `wg show` como respaldo cuando la API no responda. Verificar: con credenciales incorrectas, el diagnóstico sigue funcionando
- [x] 5.3 Al usar el respaldo, indicar explícitamente que los identificadores no son nombres. Verificar: la salida lo dice
- [x] 5.4 Seguir usando la evidencia de negociación previa para el estado del puerto. Verificar: los tres estados siguen comportándose igual que antes

## 6. Publicación robusta del panel

- [x] 6.1 Cambiar el valor por defecto de `WG_UI_BIND` a `0.0.0.0` en `deploy.sh` y `docker-compose.yml` (decisión D4). Verificar: un `.env` nuevo no fija la IP local
- [x] 6.2 Respetar un `WG_UI_BIND` ya presente en un `.env` existente. Verificar: fijarlo a mano, re-ejecutar, comprobar que persiste
- [x] 6.3 Comprobar que el servidor arranca aunque la IP local del anfitrión haya cambiado. Verificar: reproducir el fallo original y comprobar que ya no ocurre
- [x] 6.4 Advertir en `doctor.sh` si `WG_UI_BIND` fija una dirección que ya no existe en el anfitrión. Verificar: fijar una IP inexistente y comprobar el aviso
- [x] 6.5 Advertir en `doctor.sh` si el panel está en todas las interfaces y además no se detecta NAT. Verificar: forzar el escenario sin NAT y comprobar el aviso
- [x] 6.6 Usar la IP local detectada sólo para *mostrar* la URL del panel, no para publicarlo. Verificar: la URL sigue siendo utilizable desde la red doméstica

## 7. Copia de seguridad

- [x] 7.1 Crear `scripts/backup.sh` que produzca un `tar.gz` fechado del volumen. Verificar: `bash -n scripts/backup.sh` y el fichero existe tras ejecutarlo
- [x] 7.2 Resolver el nombre del volumen preguntando a `docker compose`, sin codificarlo (decisión D5). Verificar: funciona con el proyecto renombrado
- [x] 7.3 Funcionar con el servidor parado. Verificar: parar el stack, hacer copia, comprobar el contenido del `tar.gz`
- [x] 7.4 Advertir de que el fichero contiene claves privadas. Verificar: la salida lo dice en cada ejecución
- [x] 7.5 Implementar `--restaurar <fichero>` con confirmación y `--si`. Verificar: restaurar y comprobar que el estado vuelve al de la copia
- [x] 7.6 Validar el fichero antes de tocar el estado actual. Verificar: intentar restaurar un fichero corrupto y comprobar que el estado no cambia
- [x] 7.7 Añadir `backups/` a `.gitignore`. Verificar: `git status --porcelain` no lista la copia

## 8. Documentación

- [x] 8.1 Documentar en el README el ciclo de vida completo del dispositivo: alta, listado, revocación. Verificar: la sección existe
- [x] 8.2 Documentar el modo sólo-LAN, cuándo interesa y su limitación en WiFi público. Verificar: la sección existe
- [x] 8.3 Sustituir el `docker run … tar` manual por `backup.sh` y documentar la restauración. Verificar: el README ya no contiene el comando manual
- [x] 8.4 Documentar el cambio de publicación del panel y cómo endurecerlo. Verificar: la sección existe
- [x] 8.5 Actualizar `.env.example` con el nuevo valor por defecto de `WG_UI_BIND` y su motivo. Verificar: el comentario menciona el fallo de arranque

## 9. Verificación final

> **Alcance de la verificación.** Se ejecutaron de verdad, contra Docker real:
> el arranque con la nueva publicación del panel (grupo 6, incluida la
> reproducción del fallo original y su desaparición), y la copia y restauración
> completas del grupo 7, comprobando por huella que el estado vuelve al de la
> copia y que un archivo corrupto no llega a tocarlo.
>
> El ciclo de dispositivos (grupos 1–5) se ejercitó contra un simulador de la
> API, porque este entorno no puede crear interfaces WireGuard y `wg-easy` no
> llega a levantar el túnel. El simulador no se escribió a partir de
> suposiciones: sus rutas, códigos de respuesta y campos (`id` como UUID,
> `latestHandshakeAt`, `address`, `enabled`) se copiaron de `Server.js`,
> `WireGuard.js` y `config.js` de la imagen `wg-easy:14`.
>
> Queda pendiente en el equipo doméstico: comprobar que un dispositivo revocado
> deja de negociar de verdad contra el servidor, y que un dispositivo sólo-LAN
> alcanza la red de casa sin enrutar por ella el resto de su tráfico.

- [x] 9.1 `bash -n` sobre todos los scripts. Verificar: `for f in deploy.sh scripts/*.sh; do bash -n "$f"; done` sin salida
- [x] 9.2 `shellcheck` a nivel de warning sin avisos. Verificar: `shellcheck -S warning deploy.sh scripts/*.sh`
- [x] 9.3 Validar el cambio en OpenSpec. Verificar: `openspec validate mejorar-gestion-y-uso --strict`
- [x] 9.4 Ejercitar el ciclo completo contra el simulador: alta normal, alta sólo-LAN, listado, revocación, listado. Verificar: cada paso da el resultado esperado
