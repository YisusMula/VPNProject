#!/usr/bin/env bash
# =============================================================================
# add-client.sh - Da de alta un dispositivo en la VPN.
#
#   ./scripts/add-client.sh portatil              # túnel completo (por defecto)
#   ./scripts/add-client.sh portatil --solo-lan   # sólo llega a tu red de casa
#
# Genera:
#   clients/<nombre>.conf   configuración importable en la app de WireGuard
#   código QR por pantalla  para escanear desde el móvil
#
# Modos:
#   túnel completo  TODO el tráfico sale por la IP pública de tu casa. Es lo
#                   que quieres para streaming, y lo que te protege en un
#                   WiFi público.
#   sólo-LAN        Sólo el tráfico hacia tu red de casa entra en el túnel.
#                   El resto sale directo por la red donde estés: más rápido
#                   para el día a día, pero SIN protección en WiFi público.
#
# Código de salida:  0 creado,  1 error,  2 el nombre ya existe.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

# ---------- argumentos --------------------------------------------------------
CLIENT_NAME=""
MODO="completo"

while (($#)); do
  case "$1" in
    --solo-lan) MODO="solo-lan" ;;
    -h|--help)  sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)         die "Opción desconocida: $1. Usa --solo-lan o --help." ;;
    *)
      [[ -z "$CLIENT_NAME" ]] || die "Sobra el argumento '$1'. Sólo se admite un nombre."
      CLIENT_NAME="$1" ;;
  esac
  shift
done

[[ -n "$CLIENT_NAME" ]] \
  || die "Falta el nombre del dispositivo. Uso:  ./scripts/add-client.sh <nombre> [--solo-lan]"

# El nombre acaba siendo un fichero en disco: se restringe.
[[ "$CLIENT_NAME" =~ ^[A-Za-z0-9_-]+$ ]] \
  || die "Nombre no válido: usa sólo letras, números, guiones y guiones bajos."

# ---------- entorno -----------------------------------------------------------
ENV_FILE="$REPO_ROOT/.env"
[[ -f "$ENV_FILE" ]] || die "No existe .env. Ejecuta primero:  ./deploy.sh"
load_env_file "$ENV_FILE"

require_cmd curl "Instala curl:  sudo apt install curl"
# Se usa para construir y leer el JSON de la API del panel. Viene de serie en
# Raspberry Pi OS, Debian y Ubuntu, pero no en instalaciones mínimas.
require_cmd python3 "Instala python3:  sudo apt install python3"

# En modo sólo-LAN hace falta saber qué subred meter en el túnel. Se resuelve
# antes de crear nada: mejor no dar de alta un dispositivo que no alcanzaría nada.
LAN_CIDR=""
if [[ "$MODO" == "solo-lan" ]]; then
  LAN_CIDR="${LAN_CIDR_OVERRIDE:-$(detect_lan_cidr || true)}"
  [[ -n "$LAN_CIDR" ]] || die "No se pudo determinar la subred de tu red local.
        Indícala a mano, por ejemplo:
            LAN_CIDR_OVERRIDE=192.168.1.0/24 ./scripts/add-client.sh $CLIENT_NAME --solo-lan"
fi

OUT_DIR="$REPO_ROOT/clients"
OUT_FILE="$OUT_DIR/${CLIENT_NAME}.conf"

api_init
api_login

# ---------- ¿ya existe? -------------------------------------------------------
# Se comprueba antes de crear: sobrescribir las credenciales de un dispositivo
# ya dado de alta lo dejaría sin conectar sin avisar a nadie.
if [[ -n "$(api_client_id_by_name "$CLIENT_NAME")" ]]; then
  fail "Ya existe un dispositivo llamado '$CLIENT_NAME'."
  info "Elige otro nombre, o revócalo primero:  ./scripts/remove-client.sh $CLIENT_NAME"
  exit 2
fi

# ---------- alta --------------------------------------------------------------
info "Dando de alta '$CLIENT_NAME'…"
api_post "/api/wireguard/client" "{\"name\":$(json_string "$CLIENT_NAME")}" >/dev/null \
  || die "El panel rechazó el alta del dispositivo."

CLIENT_ID="$(api_client_id_by_name "$CLIENT_NAME")"
[[ -n "$CLIENT_ID" ]] \
  || die "El dispositivo se creó pero no se pudo recuperar su identificador."

# ---------- configuración -----------------------------------------------------
mkdir -p "$OUT_DIR"
umask 077
api_get "/api/wireguard/client/${CLIENT_ID}/configuration" > "$OUT_FILE" \
  || die "No se pudo descargar la configuración del dispositivo."

if [[ "$MODO" == "solo-lan" ]]; then
  # AllowedIPs del lado del cliente es routing: decide qué destinos entran en el
  # túnel. El panel sólo sabe generar túnel completo (WG_ALLOWED_IPS es un
  # ajuste global), así que se acota aquí, sobre el fichero ya descargado.
  #
  # La línea DNS se elimina: con el túnel restringido a la red de casa, ese
  # servidor DNS no sería alcanzable por dentro, y dejarlo cambiaría el DNS del
  # dispositivo sin ninguna ventaja.
  sed -i \
    -e "s|^\s*AllowedIPs\s*=.*|AllowedIPs = $LAN_CIDR|" \
    -e "/^\s*DNS\s*=/d" \
    "$OUT_FILE"
fi
chmod 600 "$OUT_FILE"

ok "Configuración escrita en  clients/${CLIENT_NAME}.conf"

# ---------- resumen del modo --------------------------------------------------
if [[ "$MODO" == "solo-lan" ]]; then
  info "Modo: SÓLO-LAN"
  info "  Llega a $LAN_CIDR por el túnel."
  info "  El resto del tráfico sale por la red donde esté el dispositivo."
  warn "  Esto NO te protege en un WiFi público, y tu IP de salida no será la"
  warn "  de tu casa: para streaming usa el modo normal (sin --solo-lan)."
else
  info "Modo: TÚNEL COMPLETO"
  info "  Todo el tráfico sale por la IP pública de tu casa."
  info "  Sirve para streaming y te protege en WiFi público."
fi

ENDPOINT="$(grep -E '^\s*Endpoint' "$OUT_FILE" | head -n1 | sed 's/.*=\s*//' || true)"
info "Punto de conexión: ${ENDPOINT:-desconocido}"
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
  info "Mientras tanto, el QR está en el panel: $API_URL"
fi

cat <<EOF

Para importarlo:
  Móvil     : escanea el QR, o abre el panel en $API_URL
  Escritorio: WireGuard > Importar túnel desde archivo > clients/${CLIENT_NAME}.conf
EOF
