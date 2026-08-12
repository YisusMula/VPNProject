#!/usr/bin/env bash
# =============================================================================
# lib.sh - Funciones compartidas: salida por pantalla y autodetección de red.
#
# No ejecutar directamente. Se carga con:  source scripts/lib.sh
# =============================================================================

# ---------- salida por pantalla ----------------------------------------------
# Se desactiva el color si la salida no es un terminal (p.ej. al redirigir a fichero).
if [[ -t 1 ]]; then
  _C_RESET=$'\033[0m'; _C_RED=$'\033[31m'; _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'; _C_BLUE=$'\033[34m'; _C_BOLD=$'\033[1m'
else
  _C_RESET=""; _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_BOLD=""
fi

info() { printf '%s->%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$_C_GREEN" "$_C_RESET" "$*"; }
warn() { printf '%s[AVISO]%s %s\n' "$_C_YELLOW" "$_C_RESET" "$*"; }
fail() { printf '%s[FALLO]%s %s\n' "$_C_RED" "$_C_RESET" "$*"; }
head1() { printf '\n%s%s%s\n' "$_C_BOLD" "$*" "$_C_RESET"; }

die() { fail "$*"; exit 1; }

# require_cmd <comando> <mensaje de ayuda si falta>
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "No se encuentra '$1'. $2"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- autodetección -----------------------------------------------------

# Interfaz de red por la que el servidor sale a internet.
detect_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

# IP del servidor en su red local.
detect_lan_ip() {
  local iface="${1:-$(detect_iface)}"
  [[ -n "$iface" ]] || return 1
  ip -4 -oneline addr show dev "$iface" 2>/dev/null \
    | awk '{print $4}' | cut -d/ -f1 | head -n1
}

# Subred local en notación CIDR (p.ej. 192.168.1.0/24).
detect_lan_cidr() {
  local iface="${1:-$(detect_iface)}"
  [[ -n "$iface" ]] || return 1
  ip -4 route show dev "$iface" scope link 2>/dev/null \
    | awk '/\/[0-9]+/ {print $1; exit}'
}

# Puerta de enlace de la red local (el router más cercano al servidor).
detect_gateway() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

# IP pública actual, consultando varios servicios de eco hasta que uno responda.
detect_public_ip() {
  local urls=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
  )
  # Permite inyectar otros servicios en pruebas.
  if [[ -n "${PUBLIC_IP_URLS:-}" ]]; then
    read -r -a urls <<<"$PUBLIC_IP_URLS"
  fi

  has_cmd curl || return 1

  local url ip
  for url in "${urls[@]}"; do
    ip="$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')" || continue
    if is_ipv4 "$ip"; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local octet
  for octet in ${1//./ }; do
    ((octet <= 255)) || return 1
  done
  return 0
}

# Cierto si la IP pertenece a un rango privado RFC1918 (10/8, 172.16/12, 192.168/16).
is_private_ipv4() {
  local ip="$1"
  is_ipv4 "$ip" || return 1
  local a b
  a="${ip%%.*}"; b="${ip#*.}"; b="${b%%.*}"
  # Se usa if/then y no '&& return 0': bajo 'set -e' una lista && cuya
  # condición es falsa aborta al script que llame a esta función.
  if ((a == 10)); then return 0; fi
  if ((a == 172 && b >= 16 && b <= 31)); then return 0; fi
  if ((a == 192 && b == 168)); then return 0; fi
  return 1
}

# Cierto si la IP está en 100.64.0.0/10, el rango reservado para CGNAT.
is_cgnat_ipv4() {
  local ip="$1"
  is_ipv4 "$ip" || return 1
  local a b
  a="${ip%%.*}"; b="${ip#*.}"; b="${b%%.*}"
  ((a == 100 && b >= 64 && b <= 127))
}

# classify_nat - Recorre los primeros saltos hacia internet y deduce la
# topología de NAT que hay entre el servidor y la red pública.
#
# Imprime una línea:  <niveles_nat> <cgnat: yes|no> <estado: ok|unknown>
#
# niveles_nat  numero de saltos privados consecutivos antes del primer salto publico
# cgnat        yes si algun salto cae en 100.64.0.0/10
# estado       unknown si no se pudo sondear (sin traceroute, sin permisos, sin red)
#
# Nunca aborta: si no puede medir, devuelve "0 no unknown".
classify_nat() {
  local tracer=""
  if has_cmd traceroute; then
    tracer="traceroute -n -q1 -w1 -m 8"
  elif has_cmd tracepath; then
    tracer="tracepath -n -m 8"
  else
    printf '0 no unknown\n'
    return 0
  fi

  local target="${NAT_PROBE_TARGET:-1.1.1.1}"
  local output
  # Un traceroute fallido no debe tumbar al script que nos invoca.
  output="$($tracer "$target" 2>/dev/null)" || true

  if [[ -z "$output" ]]; then
    printf '0 no unknown\n'
    return 0
  fi

  local levels=0 cgnat="no" seen_public="no" line hop
  while IFS= read -r line; do
    # Sólo líneas de salto (" 1  192.168.1.1 ..." o " 1:  192.168.1.1 ...").
    # La cabecera de traceroute incluye la IP de destino y falsearía el conteo.
    [[ "$line" =~ ^[[:space:]]*[0-9]+[:[:space:]] ]] || continue
    # Los saltos sin respuesta salen como " 3  * * *": no hay IP que extraer y
    # grep devuelve 1. Sin el '|| true', pipefail tumbaría al script llamante.
    hop="$(printf '%s\n' "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1 || true)"
    is_ipv4 "$hop" || continue

    # Ojo con 'set -e': ((levels++)) devuelve 1 cuando levels vale 0, porque el
    # post-incremento evalúa al valor ANTIGUO. De ahí la forma con $((...)).
    if is_cgnat_ipv4 "$hop"; then
      cgnat="yes"
      # CGNAT es, a efectos de reenvío de puertos, un nivel más de NAT ajeno.
      if [[ "$seen_public" == "no" ]]; then
        levels=$((levels + 1))
      fi
      continue
    fi
    if is_private_ipv4 "$hop"; then
      if [[ "$seen_public" == "no" ]]; then
        levels=$((levels + 1))
      fi
    else
      seen_public="yes"
    fi
  done < <(printf '%s\n' "$output")

  if [[ "$seen_public" == "no" && "$cgnat" == "no" ]]; then
    # No llegamos a ver un salto público: la medición no es fiable.
    printf '%d %s unknown\n' "$levels" "$cgnat"
    return 0
  fi

  printf '%d %s ok\n' "$levels" "$cgnat"
}

# kernel_has_wireguard - Cierto si el kernel del anfitrión sabe crear
# interfaces WireGuard. Sin esto el contenedor arranca, se queda en bucle de
# reinicio y el error que muestra ("Cannot find device wg0") no dice qué hacer.
kernel_has_wireguard() {
  if [[ -d /sys/module/wireguard ]]; then return 0; fi
  if has_cmd modprobe && modprobe wireguard >/dev/null 2>&1; then return 0; fi
  # Desde 5.6 WireGuard va integrado y puede no aparecer como módulo suelto.
  local major minor
  IFS='.' read -r major minor _ < <(uname -r | grep -oE '^[0-9]+\.[0-9]+' || true)
  [[ -n "${major:-}" ]] || return 1
  if ((major > 5)); then return 0; fi
  if ((major == 5 && minor >= 6)); then return 0; fi
  return 1
}

# detect_path_mtu - Mayor paquete que llega entero hasta internet.
#
# Imprime:  <mtu> <estado: ok|unknown>
#
# Se sondea con el bit "no fragmentar" y tamaños decrecientes hasta que uno
# pasa. Leer el MTU de la interfaz local NO serviría: el cuello de botella suele
# estar en el enlace del operador (PPPoE deja 1492), no en la tarjeta de red.
#
# Importa porque cuando el ICMP de "hace falta fragmentar" viene filtrado —lo
# normal en routers domésticos— los paquetes grandes se pierden en silencio: el
# túnel conecta, las webs pequeñas cargan y las descargas se quedan colgadas.
detect_path_mtu() {
  if ! has_cmd ping; then
    printf '0 unknown\n'
    return 0
  fi

  local destino="${MTU_PROBE_TARGET:-1.1.1.1}"
  local carga mtu
  # 28 = 20 de cabecera IP + 8 de cabecera ICMP. La carga útil se sondea, el
  # MTU es la carga más esos 28.
  for carga in 1472 1452 1432 1412 1392 1372 1352 1272 1172; do
    if ping -c1 -W2 -M "do" -s "$carga" "$destino" >/dev/null 2>&1; then
      mtu=$((carga + 28))
      printf '%d ok\n' "$mtu"
      return 0
    fi
  done

  printf '0 unknown\n'
}

# Margen que WireGuard necesita sobre el MTU del camino:
#   20 (IP) + 8 (UDP) + 32 (cabecera y etiqueta WireGuard) + 20 (seguridad)
# shellcheck disable=SC2034  # lo consume doctor.sh, que hace source de aquí
WG_MTU_OVERHEAD=80

# detect_clock_skew - Desviación en segundos entre el reloj del equipo y una
# referencia externa.
#
# Imprime:  <segundos_de_desviacion> <estado: ok|unknown>
#
# Se usa la cabecera Date de una petición HTTPS en vez de un cliente NTP: no
# añade dependencias y la precisión de segundos sobra, porque lo que se quiere
# detectar son desfases de horas (Raspberry Pi sin pila tras un corte de luz).
detect_clock_skew() {
  if ! has_cmd curl || ! has_cmd python3; then
    printf '0 unknown\n'
    return 0
  fi

  local url="${CLOCK_REF_URL:-https://www.cloudflare.com}"
  local fecha
  fecha="$(curl -sS -I --max-time 8 "$url" 2>/dev/null \
    | grep -i '^date:' | head -n1 | sed 's/^[Dd]ate:[[:space:]]*//' | tr -d '\r' || true)"

  if [[ -z "$fecha" ]]; then
    printf '0 unknown\n'
    return 0
  fi

  python3 -c '
import sys
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone
try:
    remoto = parsedate_to_datetime(sys.argv[1])
    if remoto.tzinfo is None:
        remoto = remoto.replace(tzinfo=timezone.utc)
    print(int(abs((datetime.now(timezone.utc) - remoto).total_seconds())), "ok")
except Exception:
    print(0, "unknown")
' "$fecha" 2>/dev/null || printf '0 unknown\n'
}

# Carga un fichero .env exportando sus variables, ignorando comentarios.
load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  set -a
  # shellcheck source=/dev/null
  source "$file"
  set +a
}

# =============================================================================
# Cliente de la API del panel
# -----------------------------------------------------------------------------
# Cuatro scripts necesitan hablar con el panel. Tener la sesión aquí evita que
# cuatro copias de la misma lógica se vayan separando: ya pasó con el mensaje de
# error del login, que culpaba al servidor cuando la causa era la contraseña.
#
# Uso:
#   api_init            # prepara el tarro de cookies y la URL base
#   api_login           # autentica, o aborta con un mensaje que dice la causa
#   api_get <ruta>
#   api_post <ruta> [json]
#   api_delete <ruta>
# =============================================================================

API_URL=""
API_COOKIE_JAR=""

api_init() {
  local bind="${WG_UI_BIND:-127.0.0.1}"
  # 0.0.0.0 significa "todas las interfaces": para hablar con el panel desde el
  # propio servidor hay que dirigirse a una dirección concreta.
  [[ "$bind" == "0.0.0.0" ]] && bind="127.0.0.1"
  API_URL="http://${bind}:51821"

  API_COOKIE_JAR="$(mktemp)"
  # shellcheck disable=SC2064  # se quiere expandir la ruta ahora, no al salir
  trap "rm -f '$API_COOKIE_JAR'" EXIT
}

# --noproxy: el panel es local y nunca debe salir por el proxy del sistema.
_api_curl() {
  curl -fsS --max-time 10 --noproxy '*' \
    -b "$API_COOKIE_JAR" -c "$API_COOKIE_JAR" "$@"
}

api_login() {
  [[ -n "${WG_EASY_PASSWORD:-}" ]] \
    || die "WG_EASY_PASSWORD no está definido en .env"

  local code
  code="$(curl -sS --max-time 10 --noproxy '*' -o /dev/null -w '%{http_code}' \
    -b "$API_COOKIE_JAR" -c "$API_COOKIE_JAR" \
    -X POST "$API_URL/api/session" \
    -H 'Content-Type: application/json' \
    -d "{\"password\":$(json_string "$WG_EASY_PASSWORD")}" \
    2>/dev/null || true)"

  # Se distingue por código HTTP: "no responde" y "contraseña mala" son dos
  # problemas con arreglos distintos, y el mensaje debe decir cuál es.
  case "$code" in
    2*) return 0 ;;
    401|403)
      die "El panel rechazó la contraseña. Revisa WG_EASY_PASSWORD en .env; si la cambiaste, ejecuta ./deploy.sh para regenerar el hash." ;;
    000)
      die "El panel no responde en $API_URL. Comprueba que está arrancado:  docker compose ps" ;;
    *)
      die "Respuesta inesperada del panel al iniciar sesión (HTTP $code)." ;;
  esac
}

api_get()    { _api_curl "$API_URL$1"; }
api_delete() { _api_curl -X DELETE "$API_URL$1"; }

api_post() {
  local path="$1" body="${2:-}"
  if [[ -n "$body" ]]; then
    _api_curl -X POST "$API_URL$path" -H 'Content-Type: application/json' -d "$body"
  else
    _api_curl -X POST "$API_URL$path"
  fi
}

# Listado de dispositivos, tal cual lo devuelve el panel.
api_clients_json() { api_get "/api/wireguard/client"; }

# Codifica una cadena como literal JSON, con sus comillas. Necesario porque la
# contraseña puede llevar comillas o barras invertidas.
json_string() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# Imprime el id del dispositivo con ese nombre, o nada si no existe.
api_client_id_by_name() {
  local name="$1"
  api_clients_json | python3 -c '
import json, sys
nombre = sys.argv[1]
for c in json.load(sys.stdin):
    if c.get("name") == nombre:
        print(c["id"])
        break
' "$name"
}
