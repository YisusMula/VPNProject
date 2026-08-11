#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Despliegue completo del servidor VPN con un solo comando.
#
#   git clone <repo> && cd VPNProject && ./deploy.sh
#
# Qué hace:
#   1. Comprueba requisitos previos (antes de tocar nada)
#   2. Autodetecta interfaz de salida, IP local, subred y IP pública
#   3. Genera .env si no existe (nunca pisa uno ya presente)
#   4. Arranca el stack, con DDNS si hay token configurado
#   5. Crea el primer cliente y explica cómo importarlo
#
# Es idempotente: re-ejecutarlo no regenera claves ni invalida clientes.
#
# Variables de entorno reconocidas (tienen prioridad sobre lo autodetectado):
#   WG_HOST, WG_PORT, WG_EASY_PASSWORD, WG_UI_BIND,
#   DUCKDNS_SUBDOMAIN, DUCKDNS_TOKEN, FIRST_CLIENT
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

ENV_FILE="$REPO_ROOT/.env"

# Valores que el usuario pasó por entorno. Se capturan ANTES de leer el .env
# para que un `WG_HOST=... ./deploy.sh` gane sobre el fichero y sobre la
# autodetección.
CLI_WG_HOST="${WG_HOST:-}"
CLI_WG_PORT="${WG_PORT:-}"
CLI_WG_EASY_PASSWORD="${WG_EASY_PASSWORD:-}"
CLI_WG_UI_BIND="${WG_UI_BIND:-}"
CLI_DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-}"
CLI_DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"

# ---------------------------------------------------------------------------
# 1. Requisitos previos - se comprueban todos antes de escribir nada
# ---------------------------------------------------------------------------
head1 "1/5  Comprobando requisitos"

require_cmd docker "Instálalo con: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 \
  || die "Falta Docker Compose v2. Instala el plugin: 'docker-compose-plugin' (apt) o Docker Desktop."
docker info >/dev/null 2>&1 \
  || die "Docker está instalado pero no responde. Arráncalo con: sudo systemctl start docker (o ejecuta este script con sudo)."
require_cmd ip "Instala iproute2:  sudo apt install iproute2"
require_cmd curl "Instala curl:  sudo apt install curl"
# Lo necesita scripts/add-client.sh para hablar con la API del panel. Se
# comprueba aquí para fallar antes de desplegar, no al final.
require_cmd python3 "Instala python3:  sudo apt install python3"

ok "Docker, Compose v2 y utilidades de red disponibles"

if kernel_has_wireguard; then
  ok "El kernel soporta WireGuard"
else
  warn "Este kernel ($(uname -r)) no parece soportar WireGuard."
  warn "Si el servidor se queda reiniciándose con 'Cannot find device wg0', instala:"
  warn "    sudo apt install wireguard-dkms wireguard-tools"
  warn "Se continúa por si la detección se equivoca."
fi

# ---------------------------------------------------------------------------
# 2. Autodetección del entorno de red
# ---------------------------------------------------------------------------
head1 "2/5  Detectando la red"

IFACE="$(detect_iface)" || true
[[ -n "$IFACE" ]] \
  || die "No se pudo determinar la interfaz de salida. Revisa 'ip route show default' y define WG_UI_BIND a mano."

LAN_IP="$(detect_lan_ip "$IFACE")" || true
[[ -n "$LAN_IP" ]] \
  || die "No se pudo determinar la IP local del servidor en la interfaz '$IFACE'."

LAN_CIDR="$(detect_lan_cidr "$IFACE")" || true
GATEWAY="$(detect_gateway)" || true

info "Interfaz de salida : $IFACE"
info "IP local           : $LAN_IP"
info "Subred local       : ${LAN_CIDR:-desconocida}"
info "Puerta de enlace   : ${GATEWAY:-desconocida}"

PUBLIC_IP=""
if PUBLIC_IP="$(detect_public_ip)"; then
  info "IP pública         : $PUBLIC_IP"
else
  warn "No se pudo consultar la IP pública (¿sin salida a internet?)."
fi

# ---------------------------------------------------------------------------
# 3. Configuración: se lee la existente o se genera
# ---------------------------------------------------------------------------
head1 "3/5  Preparando la configuración"

if [[ -f "$ENV_FILE" ]]; then
  ok "Usando el .env existente (no se sobrescribe)"
  load_env_file "$ENV_FILE"
else
  info "No hay .env: se generará a partir de lo detectado"
fi

# Prioridad en cascada:  entorno del usuario  >  .env  >  autodetección
WG_HOST="${CLI_WG_HOST:-${WG_HOST:-}}"
WG_PORT="${CLI_WG_PORT:-${WG_PORT:-51820}}"
WG_EASY_PASSWORD="${CLI_WG_EASY_PASSWORD:-${WG_EASY_PASSWORD:-}}"
WG_UI_BIND="${CLI_WG_UI_BIND:-${WG_UI_BIND:-0.0.0.0}}"
DUCKDNS_SUBDOMAIN="${CLI_DUCKDNS_SUBDOMAIN:-${DUCKDNS_SUBDOMAIN:-}}"
DUCKDNS_TOKEN="${CLI_DUCKDNS_TOKEN:-${DUCKDNS_TOKEN:-}}"

# Origen del punto de conexión, para dejarlo anotado en el .env generado.
WG_HOST_ORIGEN=""
if [[ -n "$WG_HOST" ]]; then
  WG_HOST_ORIGEN="definido por ti"
elif [[ -n "$DUCKDNS_SUBDOMAIN" ]]; then
  WG_HOST="${DUCKDNS_SUBDOMAIN}.duckdns.org"
  WG_HOST_ORIGEN="derivado de DUCKDNS_SUBDOMAIN"
elif [[ -n "$PUBLIC_IP" ]]; then
  WG_HOST="$PUBLIC_IP"
  WG_HOST_ORIGEN="autodetectado (IP pública)"
  warn "Sin dominio DDNS: los clientes apuntarán a la IP $PUBLIC_IP."
  warn "Tu IP es dinámica, así que DEJARÁN DE CONECTAR cuando cambie."
  warn "Para evitarlo: crea un dominio gratis en https://www.duckdns.org y"
  warn "vuelve a ejecutar con  DUCKDNS_SUBDOMAIN=tu-dominio DUCKDNS_TOKEN=tu-token ./deploy.sh"
else
  die "No hay WG_HOST definido y no se pudo detectar la IP pública. Ejecuta:  WG_HOST=tu-dominio-o-ip ./deploy.sh"
fi

info "Punto de conexión  : $WG_HOST  ($WG_HOST_ORIGEN)"

# Contraseña del panel: aleatoria si el usuario no fijó ninguna.
PASSWORD_GENERADA="no"
if [[ -z "$WG_EASY_PASSWORD" ]]; then
  WG_EASY_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20)"
  PASSWORD_GENERADA="si"
fi

# La imagen sólo acepta la contraseña como hash bcrypt. Se reutiliza el hash ya
# guardado si sigue correspondiendo a la contraseña actual; sólo se recalcula
# cuando hace falta, para no recrear el contenedor en cada ejecución.
if [[ -z "${PASSWORD_HASH:-}" || "${WG_EASY_PASSWORD_HASHED_FROM:-}" != "$WG_EASY_PASSWORD" ]]; then
  info "Calculando el hash de la contraseña del panel…"
  PASSWORD_HASH="$(
    docker run --rm ghcr.io/wg-easy/wg-easy:14 wgpw "$WG_EASY_PASSWORD" 2>/dev/null \
      | sed -n "s/^PASSWORD_HASH='\(.*\)'$/\1/p"
  )"
  [[ -n "$PASSWORD_HASH" ]] \
    || die "No se pudo generar el hash de la contraseña. Comprueba que la imagen ghcr.io/wg-easy/wg-easy:14 se descarga bien."
  HASH_RECALCULADO="si"
else
  HASH_RECALCULADO="no"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  cat > "$ENV_FILE" <<EOF
# ============================================================================
# Configuración generada por ./deploy.sh el $(date '+%Y-%m-%d %H:%M:%S')
# ----------------------------------------------------------------------------
# Puedes editar cualquier valor y volver a ejecutar ./deploy.sh: este fichero
# manda sobre la autodetección y no se sobrescribe nunca.
# NO lo subas a git (ya está en .gitignore): contiene la contraseña del panel.
# ============================================================================

# Punto de conexión que se escribe en las configuraciones de cliente.
# Origen: $WG_HOST_ORIGEN
WG_HOST=$WG_HOST

# Puerto UDP del túnel. Es el único que hay que reenviar en los routers.
WG_PORT=$WG_PORT

# Dirección en la que se publica el panel de administración.
# 0.0.0.0 = todas las interfaces. Accesible desde tu red de casa, nunca desde
# internet: en el router sólo se reenvía el puerto UDP del túnel.
#
# NO pongas aquí la IP local del servidor: si el DHCP se la cambia, Docker no
# puede publicar el puerto y el servidor VPN deja de arrancar entero.
# Para aislamiento estricto usa 127.0.0.1 y llega por túnel SSH.
WG_UI_BIND=$WG_UI_BIND

# Contraseña del panel de administración, en claro.
# La necesitan los scripts para hablar con la API del panel.
WG_EASY_PASSWORD=$WG_EASY_PASSWORD

# Hash bcrypt de la contraseña anterior: es lo que consume el contenedor.
# Se recalcula solo si cambias WG_EASY_PASSWORD y vuelves a ejecutar ./deploy.sh
# Las comillas simples son obligatorias: sin ellas, docker compose interpretaría
# los '\$' del hash y el panel quedaría con una contraseña que no es la tuya.
PASSWORD_HASH='$PASSWORD_HASH'
WG_EASY_PASSWORD_HASHED_FROM=$WG_EASY_PASSWORD

# DNS que usarán los clientes. Viaja por el túnel, así que no hay fugas de DNS.
WG_DEFAULT_DNS=1.1.1.1,8.8.8.8

# Rango de direcciones del túnel. El servidor ocupa el .1
WG_DEFAULT_ADDRESS=10.8.0.x

# ---- DDNS (opcional pero recomendado con IP dinámica) ----------------------
# Rellénalos con tu dominio de https://www.duckdns.org y vuelve a ejecutar
# ./deploy.sh para que el registro se mantenga solo.
# Si usas otro proveedor DDNS, deja esto vacío y pon tu dominio en WG_HOST.
DUCKDNS_SUBDOMAIN=$DUCKDNS_SUBDOMAIN
DUCKDNS_TOKEN=$DUCKDNS_TOKEN

# ---- Sólo informativo: valores detectados en el despliegue inicial ---------
# INTERFAZ_DETECTADA=$IFACE
# IP_LOCAL_DETECTADA=$LAN_IP
# SUBRED_DETECTADA=${LAN_CIDR:-desconocida}
# IP_PUBLICA_DETECTADA=${PUBLIC_IP:-desconocida}
EOF
  chmod 600 "$ENV_FILE"
  ok "Escrito .env (permisos 600)"
elif [[ "$HASH_RECALCULADO" == "si" ]]; then
  # Cambiaste la contraseña en .env: se persiste el hash nuevo para no tener
  # que recalcularlo (y recrear el contenedor) en cada ejecución.
  umask 077
  {
    grep -v -E "^(PASSWORD_HASH|WG_EASY_PASSWORD_HASHED_FROM)=" "$ENV_FILE"
    printf "PASSWORD_HASH='%s'\n" "$PASSWORD_HASH"
    printf "WG_EASY_PASSWORD_HASHED_FROM=%s\n" "$WG_EASY_PASSWORD"
  } > "${ENV_FILE}.tmp"
  mv "${ENV_FILE}.tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  ok "Hash de la contraseña actualizado en .env"
fi

# El resto de valores los lee docker compose del propio .env, de modo que
# 'docker compose up -d' o 'docker compose logs' funcionan sin este script.
export WG_HOST WG_PORT WG_EASY_PASSWORD WG_UI_BIND DUCKDNS_SUBDOMAIN DUCKDNS_TOKEN

# ---------------------------------------------------------------------------
# 4. Arranque del stack
# ---------------------------------------------------------------------------
head1 "4/5  Arrancando el servidor VPN"

COMPOSE_ARGS=()
if [[ -n "$DUCKDNS_TOKEN" && -n "$DUCKDNS_SUBDOMAIN" ]]; then
  COMPOSE_ARGS+=(--profile ddns)
  info "DDNS activado para ${DUCKDNS_SUBDOMAIN}.duckdns.org"
else
  info "DDNS no configurado: se omite ese contenedor"
fi

docker compose "${COMPOSE_ARGS[@]}" up -d

# El panel tarda un par de segundos en aceptar peticiones.
# La IP local sólo se usa para MOSTRAR una URL que el usuario pueda teclear:
# el panel se publica en todas las interfaces, y "http://0.0.0.0:51821" no
# sirve de nada escrito en un navegador.
if [[ "$WG_UI_BIND" == "0.0.0.0" ]]; then
  UI_URL="http://${LAN_IP}:51821"
else
  UI_URL="http://${WG_UI_BIND}:51821"
fi
info "Esperando a que el panel responda en $UI_URL ..."
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 --noproxy '*' "$UI_URL/api/session" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if curl -fsS --max-time 3 --noproxy '*' "$UI_URL/api/session" >/dev/null 2>&1; then
  ok "Servidor VPN en marcha"
else
  warn "El panel aún no responde. Revisa el estado con: docker compose logs wg-easy"
fi

# ---------------------------------------------------------------------------
# 5. Primer cliente
# ---------------------------------------------------------------------------
head1 "5/5  Creando el primer cliente"

FIRST_CLIENT="${FIRST_CLIENT:-movil}"
# add-client.sh devuelve 2 cuando el dispositivo ya existe (re-ejecución normal
# de deploy.sh) y 1 ante un fallo real. Distinguirlos evita informar de un
# "ya existía" tranquilizador cuando en realidad el panel no respondió.
set +e
"$REPO_ROOT/scripts/add-client.sh" "$FIRST_CLIENT"
ADD_STATUS=$?
set -e

case "$ADD_STATUS" in
  0) ;;
  2) info "El dispositivo '$FIRST_CLIENT' ya existía: se conserva tal cual." ;;
  *)
    fail "No se pudo crear el primer dispositivo."
    info "Revisa el servidor con:  docker compose logs wg-easy"
    info "Y cuando responda:       ./scripts/add-client.sh $FIRST_CLIENT"
    ;;
esac

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
head1 "Listo. Lo que falta lo tienes que hacer en el router"

cat <<EOF

  Reenvía el puerto  ${WG_PORT}/UDP  hasta ${LAN_IP}
  (si tienes dos routers en cascada, hay que hacerlo en los dos:
   consulta el README, sección "Abrir el puerto")

  Comprueba que todo está bien:   ./scripts/doctor.sh
  Añade más dispositivos:         ./scripts/add-client.sh portatil
  Panel de administración:        $UI_URL
EOF

if [[ "$PASSWORD_GENERADA" == "si" ]]; then
  cat <<EOF

  Contraseña del panel (generada, guardada en .env):
      ${_C_BOLD}${WG_EASY_PASSWORD}${_C_RESET}
EOF
fi

echo
