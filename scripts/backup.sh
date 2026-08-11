#!/usr/bin/env bash
# =============================================================================
# backup.sh - Copia de seguridad y restauración de las claves de la VPN.
#
#   ./scripts/backup.sh                          # crear copia
#   ./scripts/backup.sh --restaurar <fichero>    # restaurar
#   ./scripts/backup.sh --restaurar <fichero> --si
#
# Qué se copia: el volumen de Docker con las claves del servidor y las de TODOS
# los dispositivos. Es el único estado del proyecto. Si lo pierdes, hay que dar
# de alta de nuevo todos los dispositivos, uno a uno.
#
# El fichero resultante CONTIENE CLAVES PRIVADAS EN CLARO. Guárdalo fuera de
# este equipo y trátalo como tratarías la contraseña del router.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

BACKUP_DIR="$REPO_ROOT/backups"

# ---------- argumentos --------------------------------------------------------
ACCION="crear"
FICHERO=""
SIN_PREGUNTAR="no"

while (($#)); do
  case "$1" in
    --restaurar)
      ACCION="restaurar"
      shift
      FICHERO="${1:-}"
      [[ -n "$FICHERO" ]] || die "Falta el fichero. Uso:  ./scripts/backup.sh --restaurar <fichero>" ;;
    --si|--yes) SIN_PREGUNTAR="si" ;;
    -h|--help)  sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          die "Argumento no reconocido: $1. Usa --help." ;;
  esac
  shift
done

require_cmd docker "Instálalo con: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 || die "Falta Docker Compose v2."

# ---------- localizar el volumen ----------------------------------------------
# Se pregunta a compose en vez de codificar el nombre: depende de cómo se llame
# el directorio del proyecto, así que codificarlo se rompería al renombrarlo.
VOLUMEN="$(docker compose config --format json 2>/dev/null \
  | python3 -c '
import json, sys
try:
    cfg = json.load(sys.stdin)
except Exception:
    sys.exit(0)
vols = cfg.get("volumes") or {}
for nombre, datos in vols.items():
    print((datos or {}).get("name") or nombre)
    break
' 2>/dev/null || true)"

if [[ -z "$VOLUMEN" ]]; then
  # Respaldo: compose nombra el volumen <proyecto>_<volumen>.
  VOLUMEN="$(basename "$REPO_ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')_wg_data"
fi

docker volume inspect "$VOLUMEN" >/dev/null 2>&1 \
  || die "No se encuentra el volumen '$VOLUMEN'. ¿Has ejecutado ./deploy.sh alguna vez?"

# =============================================================================
# Crear copia
# =============================================================================
if [[ "$ACCION" == "crear" ]]; then
  mkdir -p "$BACKUP_DIR"
  NOMBRE="vpn-$(date +%Y-%m-%d-%H%M).tar.gz"
  DESTINO="$BACKUP_DIR/$NOMBRE"

  info "Copiando el volumen '$VOLUMEN'…"
  # No hace falta parar el servidor: el estado vive en el volumen, no en el
  # proceso.
  docker run --rm \
    -v "$VOLUMEN":/data:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/$NOMBRE" -C /data . \
    || die "Falló la copia."

  chmod 600 "$DESTINO"
  ok "Copia creada: backups/$NOMBRE  ($(du -h "$DESTINO" | cut -f1))"
  echo
  warn "Este fichero contiene las CLAVES PRIVADAS de todos tus dispositivos."
  warn "Guárdalo fuera de este equipo. Quien lo tenga puede entrar en tu red."
  echo
  info "Para restaurarlo:  ./scripts/backup.sh --restaurar backups/$NOMBRE"
  exit 0
fi

# =============================================================================
# Restaurar
# =============================================================================
[[ -f "$FICHERO" ]] || die "No existe el fichero: $FICHERO"

# Se valida ANTES de tocar nada: restaurar a medias con un fichero corrupto
# dejaría el servidor sin claves y sin copia a la que volver.
info "Comprobando el fichero…"
tar tzf "$FICHERO" >/dev/null 2>&1 \
  || die "'$FICHERO' no es un archivo tar.gz legible. No se ha tocado nada."

CONTENIDO="$(tar tzf "$FICHERO" 2>/dev/null | head -20)"
if ! printf '%s' "$CONTENIDO" | grep -q "wg0.json\|wg0.conf"; then
  warn "El archivo no parece una copia de esta VPN: no contiene wg0.json ni wg0.conf."
  warn "Contenido:"
  printf '%s\n' "$CONTENIDO" | sed 's/^/          /'
  [[ "$SIN_PREGUNTAR" == "si" ]] || die "Abortado por precaución. Usa --si si sabes lo que haces."
fi

if [[ "$SIN_PREGUNTAR" != "si" ]]; then
  head1 "Vas a restaurar una copia de seguridad"
  printf '        Fichero : %s\n' "$FICHERO"
  printf '        Volumen : %s\n' "$VOLUMEN"
  echo
  warn "Se REEMPLAZA el estado actual: las claves de ahora se pierden."
  warn "Los dispositivos creados después de esa copia dejarán de conectar."
  echo
  read -r -p "  ¿Seguro? Escribe 'si' para continuar: " RESPUESTA
  if [[ "$RESPUESTA" != "si" ]]; then
    info "Cancelado. No se ha tocado nada."
    exit 0
  fi
fi

info "Parando el servidor…"
docker compose down >/dev/null 2>&1 || true

info "Restaurando el volumen…"
FICHERO_ABS="$(cd "$(dirname "$FICHERO")" && pwd)/$(basename "$FICHERO")"
docker run --rm \
  -v "$VOLUMEN":/data \
  -v "$(dirname "$FICHERO_ABS")":/backup:ro \
  alpine sh -c "rm -rf /data/* /data/..?* 2>/dev/null; tar xzf '/backup/$(basename "$FICHERO_ABS")' -C /data" \
  || die "Falló la restauración. El servidor está parado; revisa el fichero y reintenta."

ok "Volumen restaurado."

info "Arrancando el servidor…"
if [[ -f "$REPO_ROOT/.env" ]]; then
  docker compose up -d >/dev/null 2>&1 && ok "Servidor en marcha." \
    || warn "No arrancó. Ejecuta ./deploy.sh para revisarlo."
else
  warn "No hay .env. Ejecuta ./deploy.sh para levantar el servidor."
fi

echo
info "Comprueba que todo está bien:  ./scripts/list-clients.sh"
