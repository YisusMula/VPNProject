#!/usr/bin/env bash
# =============================================================================
# add-client.sh - Da de alta un dispositivo en la VPN.
#
#   ./scripts/add-client.sh portatil
#   ./scripts/add-client.sh movil-ana
#
# Genera:
#   clients/<nombre>.conf   configuración importable en la app de WireGuard
#   código QR por pantalla  para escanear desde el móvil
#
# El cliente sale configurado en túnel completo: acceso a la red de casa Y
# salida a internet por la IP pública del hogar.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

CLIENT_NAME="${1:-}"
[[ -n "$CLIENT_NAME" ]] \
  || die "Falta el nombre del dispositivo. Uso:  ./scripts/add-client.sh <nombre>"

# Nombres restringidos: el nombre acaba siendo un fichero en disco.
[[ "$CLIENT_NAME" =~ ^[A-Za-z0-9_-]+$ ]] \
  || die "Nombre no válido: usa sólo letras, números, guiones y guiones bajos."

ENV_FILE="$REPO_ROOT/.env"
[[ -f "$ENV_FILE" ]] || die "No existe .env. Ejecuta primero:  ./deploy.sh"
load_env_file "$ENV_FILE"

require_cmd curl "Instala curl:  sudo apt install curl"
# Se usa para construir y leer el JSON de la API del panel. Viene de serie en
# Raspberry Pi OS, Debian y Ubuntu, pero no en instalaciones mínimas.
require_cmd python3 "Instala python3:  sudo apt install python3"

UI_HOST="${WG_UI_BIND:-127.0.0.1}"
UI_URL="http://${UI_HOST}:51821"
OUT_DIR="$REPO_ROOT/clients"
OUT_FILE="$OUT_DIR/${CLIENT_NAME}.conf"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

# El panel es local: nunca debe salir por el proxy del sistema.
api() { curl -fsS --max-time 10 --noproxy '*' -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$@"; }

# ---------- sesión ------------------------------------------------------------
[[ -n "${WG_EASY_PASSWORD:-}" ]] || die "WG_EASY_PASSWORD no está definido en .env"

# Se mira el código HTTP para distinguir "no responde" de "contraseña mala":
# son dos problemas con arreglos distintos y el mensaje debe decir cuál es.
LOGIN_CODE="$(curl -sS --max-time 10 --noproxy '*' -o /dev/null -w '%{http_code}' \
  -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -X POST "$UI_URL/api/session" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":$(printf '%s' "$WG_EASY_PASSWORD" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
  2>/dev/null || true)"

case "$LOGIN_CODE" in
  2*) ;;
  401|403)
    die "El panel rechazó la contraseña. Revisa WG_EASY_PASSWORD en .env; si la cambiaste, ejecuta ./deploy.sh para regenerar el hash." ;;
  000)
    die "El panel no responde en $UI_URL. Comprueba que está arrancado:  docker compose ps" ;;
  *)
    die "Respuesta inesperada del panel al iniciar sesión (HTTP $LOGIN_CODE)." ;;
esac

# ---------- ¿ya existe? -------------------------------------------------------
# Se comprueba antes de crear: nunca se sobrescriben las credenciales de un
# dispositivo ya dado de alta, porque dejaría de conectar sin avisar.
EXISTING_ID="$(api "$UI_URL/api/wireguard/client" \
  | python3 -c "
import json, sys
name = sys.argv[1]
for c in json.load(sys.stdin):
    if c.get('name') == name:
        print(c['id'])
        break
" "$CLIENT_NAME")"

if [[ -n "$EXISTING_ID" ]]; then
  fail "Ya existe un dispositivo llamado '$CLIENT_NAME'."
  info "Elige otro nombre, o bórralo primero desde el panel: $UI_URL"
  # Código 2 = "ya existe", distinto de 1 = fallo real. deploy.sh los separa.
  exit 2
fi

# ---------- alta --------------------------------------------------------------
info "Dando de alta '$CLIENT_NAME'…"
api -X POST "$UI_URL/api/wireguard/client" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$CLIENT_NAME\"}" >/dev/null \
  || die "El panel rechazó el alta del dispositivo."

CLIENT_ID="$(api "$UI_URL/api/wireguard/client" \
  | python3 -c "
import json, sys
name = sys.argv[1]
for c in json.load(sys.stdin):
    if c.get('name') == name:
        print(c['id'])
        break
" "$CLIENT_NAME")"

[[ -n "$CLIENT_ID" ]] || die "El dispositivo se creó pero no se pudo recuperar su identificador."

# ---------- configuración -----------------------------------------------------
mkdir -p "$OUT_DIR"
umask 077
api "$UI_URL/api/wireguard/client/${CLIENT_ID}/configuration" > "$OUT_FILE" \
  || die "No se pudo descargar la configuración del dispositivo."
chmod 600 "$OUT_FILE"

ok "Configuración escrita en  clients/${CLIENT_NAME}.conf"

# Aviso si el punto de conexión es una IP literal: con IP dinámica caducará.
ENDPOINT="$(grep -E '^\s*Endpoint' "$OUT_FILE" | head -n1 | sed 's/.*=\s*//')"
info "Punto de conexión: $ENDPOINT"
if [[ "${ENDPOINT%%:*}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  warn "Es una IP literal, no un dominio. Cuando tu operadora te cambie la IP"
  warn "pública, este dispositivo dejará de conectar y habrá que regenerarlo."
  warn "Configura DDNS (ver README) para que esto no pase."
fi

# ---------- código QR ---------------------------------------------------------
if has_cmd qrencode; then
  echo
  qrencode -t ANSIUTF8 < "$OUT_FILE"
  echo
  info "Escanea el código con la app WireGuard de tu móvil."
else
  info "Instala 'qrencode' (sudo apt install qrencode) para ver el QR aquí."
  info "Mientras tanto, el QR está en el panel: $UI_URL"
fi

cat <<EOF

Para importarlo:
  Móvil     : escanea el QR, o abre el panel en $UI_URL
  Escritorio: WireGuard > Importar túnel desde archivo > clients/${CLIENT_NAME}.conf
EOF
