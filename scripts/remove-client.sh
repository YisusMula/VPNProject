#!/usr/bin/env bash
# =============================================================================
# remove-client.sh - Revoca un dispositivo. Deja de conectar de inmediato.
#
#   ./scripts/remove-client.sh movil-perdido
#   ./scripts/remove-client.sh movil-perdido --si    # sin preguntar
#
# Es IRREVERSIBLE: para volver a usar ese dispositivo hay que darlo de alta de
# nuevo, con claves nuevas, y volver a importar la configuración.
#
# No afecta al resto de dispositivos.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

# ---------- argumentos --------------------------------------------------------
CLIENT_NAME=""
SIN_PREGUNTAR="no"

while (($#)); do
  case "$1" in
    --si|--yes) SIN_PREGUNTAR="si" ;;
    -h|--help)  sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*)         die "Opción desconocida: $1. Usa --si o --help." ;;
    *)
      [[ -z "$CLIENT_NAME" ]] || die "Sobra el argumento '$1'. Sólo se admite un nombre."
      CLIENT_NAME="$1" ;;
  esac
  shift
done

[[ -n "$CLIENT_NAME" ]] \
  || die "Falta el nombre del dispositivo. Uso:  ./scripts/remove-client.sh <nombre> [--si]"

# ---------- entorno -----------------------------------------------------------
ENV_FILE="$REPO_ROOT/.env"
[[ -f "$ENV_FILE" ]] || die "No existe .env. Ejecuta primero:  ./deploy.sh"
load_env_file "$ENV_FILE"

require_cmd curl "Instala curl:  sudo apt install curl"
require_cmd python3 "Instala python3:  sudo apt install python3"

api_init
api_login

# ---------- localizar ---------------------------------------------------------
DATOS="$(api_clients_json | python3 -c '
import json, sys
nombre = sys.argv[1]
for c in json.load(sys.stdin):
    if c.get("name") == nombre:
        ultima = c.get("latestHandshakeAt") or "nunca"
        print(c["id"], c.get("address", "?"), ultima, sep="\t")
        break
' "$CLIENT_NAME")"

if [[ -z "$DATOS" ]]; then
  fail "No existe ningún dispositivo llamado '$CLIENT_NAME'."
  info "Consulta los que hay con:  ./scripts/list-clients.sh"
  exit 1
fi

IFS=$'\t' read -r CLIENT_ID CLIENT_ADDR CLIENT_LAST <<<"$DATOS"

# ---------- confirmación ------------------------------------------------------
# Se muestran los datos ANTES de preguntar: es la única defensa contra revocar
# el dispositivo equivocado, porque después no hay vuelta atrás.
if [[ "$SIN_PREGUNTAR" != "si" ]]; then
  head1 "Vas a revocar este dispositivo"
  printf '        Nombre          : %s\n' "$CLIENT_NAME"
  printf '        Dirección túnel : %s\n' "$CLIENT_ADDR"
  printf '        Última conexión : %s\n' "$CLIENT_LAST"
  echo
  warn "Dejará de conectar de inmediato. No se puede deshacer."
  echo
  read -r -p "  ¿Seguro? Escribe 'si' para continuar: " RESPUESTA
  if [[ "$RESPUESTA" != "si" ]]; then
    info "Cancelado. No se ha revocado nada."
    exit 0
  fi
fi

# ---------- revocar -----------------------------------------------------------
api_delete "/api/wireguard/client/${CLIENT_ID}" >/dev/null \
  || die "El panel rechazó la revocación."

ok "'$CLIENT_NAME' revocado. Ya no puede conectarse."

# ---------- fichero local obsoleto --------------------------------------------
# El .conf que quedó en disco ya no sirve. Si no se avisa, es fácil dárselo a
# alguien creyendo que funciona.
OBSOLETO="$REPO_ROOT/clients/${CLIENT_NAME}.conf"
if [[ -f "$OBSOLETO" ]]; then
  warn "El fichero clients/${CLIENT_NAME}.conf ya no sirve para nada."
  if [[ "$SIN_PREGUNTAR" == "si" ]]; then
    rm -f "$OBSOLETO"
    ok "Fichero obsoleto borrado."
  else
    read -r -p "  ¿Lo borro? [S/n]: " BORRAR
    if [[ -z "$BORRAR" || "$BORRAR" =~ ^[SsYy]$ ]]; then
      rm -f "$OBSOLETO"
      ok "Fichero obsoleto borrado."
    else
      info "Se conserva. Recuerda que ya no es válido."
    fi
  fi
fi
