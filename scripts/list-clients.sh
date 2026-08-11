#!/usr/bin/env bash
# =============================================================================
# list-clients.sh - Qué dispositivos hay dados de alta y cuándo conectaron.
#
#   ./scripts/list-clients.sh
#
# Sólo lectura: no modifica nada.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

ENV_FILE="$REPO_ROOT/.env"
[[ -f "$ENV_FILE" ]] || die "No existe .env. Ejecuta primero:  ./deploy.sh"
load_env_file "$ENV_FILE"

require_cmd curl "Instala curl:  sudo apt install curl"
require_cmd python3 "Instala python3:  sudo apt install python3"

api_init
# api_login aborta con un mensaje que distingue "el panel no responde" de
# "la contraseña es incorrecta". Así un listado vacío nunca se confunde con
# un servidor caído.
api_login

CLIENTES="$(api_clients_json)" \
  || die "No se pudo obtener el listado del panel."

TOTAL="$(printf '%s' "$CLIENTES" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"

if [[ "$TOTAL" == "0" ]]; then
  info "No hay ningún dispositivo dado de alta."
  info "Crea uno con:  ./scripts/add-client.sh movil"
  exit 0
fi

head1 "Dispositivos dados de alta ($TOTAL)"

printf '%s' "$CLIENTES" | python3 -c '
import json, sys
from datetime import datetime, timezone

clientes = json.load(sys.stdin)
ahora = datetime.now(timezone.utc)

def hace_cuanto(iso):
    if not iso:
        return "nunca ha conectado"
    try:
        t = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return iso
    seg = int((ahora - t).total_seconds())
    if seg < 60:
        return f"hace {seg} s"
    if seg < 3600:
        return f"hace {seg // 60} min"
    if seg < 86400:
        return f"hace {seg // 3600} h"
    return f"hace {seg // 86400} d"

ancho = max(len(c.get("name") or "?") for c in clientes)
for c in sorted(clientes, key=lambda x: x.get("name") or ""):
    nombre = c.get("name") or "?"
    direccion = c.get("address") or "?"
    ultima = hace_cuanto(c.get("latestHandshakeAt"))
    estado = "" if c.get("enabled", True) else "  [DESACTIVADO]"
    print(f"  {nombre:<{ancho}}  {direccion:<12}  {ultima}{estado}")
'

echo
info "Añadir:  ./scripts/add-client.sh <nombre> [--solo-lan]"
info "Revocar: ./scripts/remove-client.sh <nombre>"
