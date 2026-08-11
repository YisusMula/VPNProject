## 1. Limpieza del modelo site-to-site

- [x] 1.1 Eliminar `scripts/generate-keys.sh`, `scripts/setup-server.sh` y `scripts/setup-client.sh`. Verificar: `test ! -e scripts/setup-server.sh`
- [x] 1.2 Eliminar `server/wg0.conf.template` y el directorio `server/`. Verificar: `test ! -d server`
- [x] 1.3 Eliminar `client/site-a.conf.template`, `client/site-b.conf.template` y `client/road-warrior.conf.template`. Verificar: `ls client/*.template 2>/dev/null | wc -l` devuelve `0`
- [x] 1.4 Comprobar que ninguna referencia a `site-a`/`site-b` sobrevive fuera de `openspec/`. Verificar: `grep -ril "site-a" --exclude-dir=openspec --exclude-dir=.git .` no devuelve nada

## 2. Biblioteca compartida de detección

- [x] 2.1 Crear `scripts/lib.sh` con helpers de salida (`info`, `ok`, `warn`, `fail`, `die`) y `require_cmd`. Verificar: `bash -n scripts/lib.sh`
- [x] 2.2 Implementar `detect_iface()` (interfaz de la ruta por defecto). Verificar: devuelve el mismo valor que `ip route show default`
- [x] 2.3 Implementar `detect_lan_cidr()` y `detect_lan_ip()` sobre la interfaz detectada. Verificar: la IP devuelta aparece en `ip -4 addr show`
- [x] 2.4 Implementar `detect_public_ip()` consultando varios servicios de eco con timeout y fallback entre ellos. Verificar: devuelve una IPv4 válida y falla limpiamente si se fuerzan URLs inválidas
- [x] 2.5 Implementar `classify_nat()` a partir de `traceroute`: devuelve número de niveles NAT y si hay saltos en `100.64.0.0/10`. Verificar: ejecutar la función e inspeccionar su salida frente a `traceroute -n 1.1.1.1`
- [x] 2.6 Cubrir el caso de `traceroute` ausente devolviendo estado "no concluyente" en lugar de error. Verificar: `PATH=/nonexistent bash -c 'source scripts/lib.sh; classify_nat'` no aborta

## 3. Despliegue con un solo comando

- [x] 3.1 Crear `deploy.sh` en la raíz con `set -euo pipefail` y comprobación previa de Docker y Compose v2, abortando antes de escribir nada. Verificar: `bash -n deploy.sh`
- [x] 3.2 Generar `.env` a partir de los valores detectados, con comentarios que indiquen cuáles se autodetectaron. Verificar: sobre un clon sin `.env`, tras ejecutar se crea con `WG_HOST` relleno
- [x] 3.3 No sobrescribir un `.env` existente y usarlo como fuente de verdad. Verificar: modificar `WG_HOST` a mano, re-ejecutar, y comprobar que el valor persiste
- [x] 3.4 Dar prioridad al valor explícito del usuario sobre el detectado en cada variable. Verificar: `WG_HOST=ejemplo.duckdns.org ./deploy.sh` no lo reemplaza por la IP pública
- [x] 3.5 Generar una contraseña aleatoria para la interfaz de administración si el usuario no fijó ninguna, y mostrarla una vez. Verificar: `.env` no contiene `changeme`
- [x] 3.6 Arrancar el stack con `docker compose up -d`, activando el perfil `ddns` sólo si hay token DDNS configurado. Verificar: `docker compose ps` muestra `wg-easy` en ejecución
- [x] 3.7 Crear el primer cliente automáticamente al final del despliegue y mostrar cómo importarlo. Verificar: el fichero del cliente existe tras una ejecución limpia
- [x] 3.8 Hacer la re-ejecución idempotente: no regenerar claves ni invalidar clientes existentes. Verificar: ejecutar dos veces seguidas y comprobar que el cliente de la primera sigue presente y con la misma clave pública
- [x] 3.9 Abortar con mensaje accionable si falta Docker o Compose v2. Verificar: `PATH=/usr/bin:/bin ./deploy.sh` en una máquina sin Docker imprime la instrucción de instalación y sale con código distinto de cero

## 4. Stack de Compose

- [x] 4.1 Reescribir `docker-compose.yml` eliminando los overrides de `WG_POST_UP` y `WG_POST_DOWN` (decisión D5). Verificar: `grep -c "eth0" docker-compose.yml` devuelve `0`
- [x] 4.2 Fijar `WG_ALLOWED_IPS=0.0.0.0/0` para que los clientes se generen en túnel completo. Sólo IPv4 (decisión D11: el sysctl de IPv6 impide arrancar en equipos con IPv6 deshabilitado). Verificar: la configuración de un cliente generado contiene `AllowedIPs = 0.0.0.0/0`
- [x] 4.3 Publicar el puerto UDP del túnel en todas las interfaces y el de administración restringido a la LAN. Verificar: `docker compose ps` no muestra el puerto de administración publicado en `0.0.0.0`
- [x] 4.4 Añadir el servicio DDNS bajo `profiles: [ddns]` con `restart: unless-stopped`. Verificar: `docker compose config --profiles` incluye `ddns`, y `docker compose up -d` sin el perfil no lo arranca
- [x] 4.5 Comprobar que el fichero es válido. Verificar: `docker compose config -q`

## 5. Gestión de clientes

- [x] 5.1 Crear `scripts/add-client.sh <nombre>` que dé de alta un peer y escriba su configuración. Verificar: `bash -n scripts/add-client.sh`
- [x] 5.2 Generar el código QR del cliente, con respaldo si `qrencode` no está instalado. Verificar: el QR se muestra o se indica dónde obtenerlo desde la interfaz web
- [x] 5.3 Rechazar un nombre de cliente ya existente sin sobrescribirlo. Verificar: ejecutar dos veces con el mismo nombre; la segunda sale con error y el fichero original no cambia
- [x] 5.4 Usar el dominio DDNS como punto de conexión cuando esté configurado, y la IP pública con advertencia explícita cuando no lo esté. Verificar: inspeccionar la línea `Endpoint` de un cliente generado en ambos casos

## 6. Diagnóstico

- [x] 6.1 Crear `scripts/doctor.sh` de sólo lectura, con `set -euo pipefail` y salida por comprobación (correcto / advertencia / fallo). Verificar: `bash -n scripts/doctor.sh` y `git status --porcelain` vacío tras ejecutarlo
- [x] 6.2 Comprobación de CGNAT usando `classify_nat`, marcada como bloqueante al detectarse. Verificar: la salida nombra el rango `100.64.0.0/10` cuando aplica
- [x] 6.3 Comprobación de niveles de NAT, indicando la regla concreta para el router principal y para el secundario cuando hay dos niveles. Verificar: la salida enumera dos reglas en un entorno de doble NAT
- [x] 6.4 Comprobación de alcanzabilidad del puerto UDP con tres estados (confirmado / no alcanzable / no concluyente), usando la negociación previa como evidencia positiva. Verificar: sin ningún peer conectado nunca, el resultado es "no concluyente", no "fallo"
- [x] 6.5 Comprobación de reenvío IP en el anfitrión, indicando el ajuste persistente si está desactivado. Verificar: la salida menciona `net.ipv4.ip_forward` cuando vale `0`
- [x] 6.6 Comprobación del estado del contenedor y de los peers, distinguiendo peer que nunca negoció de peer que sí lo hizo. Verificar: contrastar con `docker exec wg-easy wg show`
- [x] 6.7 Comprobación de sincronía del dominio DDNS frente a la IP pública actual, mostrando ambos valores al discrepar. Verificar: forzar un `WG_HOST` que resuelva a otra IP y comprobar el reporte
- [x] 6.8 Salir con código cero si todas las comprobaciones pasan y distinto de cero si alguna falla. Verificar: `./scripts/doctor.sh; echo $?`

## 7. Protección de secretos

- [x] 7.1 Actualizar `.gitignore` para cubrir `.env`, las configuraciones de cliente generadas y cualquier QR. Verificar: tras un despliegue completo, `git status --porcelain` no lista ficheros con material sensible
- [x] 7.2 Comprobar que no queda material sensible ya versionado. Verificar: `git ls-files | grep -E '\.env$|\.conf$|\.key$|privkey'` no devuelve nada

## 8. Documentación

- [x] 8.1 Reescribir `README.md` en español con el camino feliz: clonar, `./deploy.sh`, abrir puerto, escanear QR. Verificar: el bloque de inicio rápido cabe en menos de diez líneas de comandos
- [x] 8.2 Documentar el reenvío de puerto en cascada Huawei → Archer, con la regla de cada router. Verificar: el README contiene ambas reglas por separado
- [x] 8.3 Documentar cómo comprobar CGNAT y qué hacer si se confirma. Verificar: la sección existe y remite a `scripts/doctor.sh`
- [x] 8.4 Documentar la opción de poner el Archer en modo punto de acceso como forma de eliminar un nivel de NAT. Verificar: la sección existe
- [x] 8.5 Documentar la ruta estática en el router como mejora opcional (decisión D2) y su beneficio. Verificar: la sección existe y está marcada como opcional
- [x] 8.6 Documentar que el volumen de Docker es el único estado que requiere copia de seguridad. Verificar: la sección existe
- [x] 8.7 Actualizar `.env.example` a las variables del nuevo modelo, sin las de site-to-site. Verificar: `grep -c "SITE_" .env.example` devuelve `0`

## 9. Verificación final

> **Alcance de la verificación.** El entorno donde se implementó este cambio no
> puede crear interfaces WireGuard (`wg0`), así que `wg-easy` no llega a
> arrancar del todo en él. Las tareas que dependen de la API del panel (3.7,
> 5.1–5.4) y del estado de los peers (6.4, 6.6) se verificaron contra
> simuladores de la API de wg-easy v14 y de `docker`, no contra el servidor
> real. Todo lo demás —autodetección, generación de `.env`, idempotencia,
> arranque del stack, perfiles, diagnóstico de red— se ejecutó de verdad.
> Queda pendiente una prueba end-to-end en el equipo doméstico de destino.

- [x] 9.1 Pasar `bash -n` sobre todos los scripts. Verificar: `for f in deploy.sh scripts/*.sh; do bash -n "$f"; done` sin salida
- [x] 9.2 Pasar `shellcheck` sobre todos los scripts si está disponible. Verificar: sin avisos de severidad error
- [x] 9.3 Validar el cambio en OpenSpec. Verificar: `openspec validate simplify-zero-config-deploy --strict`
