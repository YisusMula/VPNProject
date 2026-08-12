#!/usr/bin/env bash
# =============================================================================
# lib-test.sh - Comprueba las funciones de detección de scripts/lib.sh.
#
#   ./tests/lib-test.sh
#
# Cubre escenarios que NO se pueden reproducir en el equipo donde se ejecuta
# —CGNAT, doble NAT, herramientas ausentes— pasando salidas fijas conocidas a
# las funciones de clasificación. Son justo los caminos que más le importan al
# usuario (el aviso de CGNAT decide si el proyecto le sirve) y los que nunca se
# ejercitan en el uso normal.
#
# No levanta contenedores ni toca nada del sistema.
# =============================================================================

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_ROOT/.." && pwd)"
FIXTURES="$TEST_ROOT/fixtures"

# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

PASA=0
FALLA=0

# comprobar <descripción> <esperado> <obtenido>
comprobar() {
  local desc="$1" esperado="$2" obtenido="$3"
  if [[ "$esperado" == "$obtenido" ]]; then
    printf '  %s[ok]%s %s\n' "$_C_GREEN" "$_C_RESET" "$desc"
    PASA=$((PASA + 1))
  else
    printf '  %s[FALLA]%s %s\n' "$_C_RED" "$_C_RESET" "$desc"
    printf '         esperado: %s\n' "$esperado"
    printf '         obtenido: %s\n' "$obtenido"
    FALLA=$((FALLA + 1))
  fi
}

# comprobar_cierto <descripción> <comando...>
comprobar_cierto() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    comprobar "$desc" "cierto" "cierto"
  else
    comprobar "$desc" "cierto" "falso"
  fi
}

comprobar_falso() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    comprobar "$desc" "falso" "cierto"
  else
    comprobar "$desc" "falso" "falso"
  fi
}

# Simulador de traceroute: imprime la salida fija que se le indique.
preparar_traceroute_falso() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/traceroute" <<'EOF'
#!/usr/bin/env bash
cat "$TRACE_FIXTURE"
EOF
  chmod +x "$dir/traceroute"
}

# ---------------------------------------------------------------------------
head1 "Clasificación de direcciones"
# ---------------------------------------------------------------------------

comprobar_cierto "192.168.1.1 es una IPv4 válida"        is_ipv4 192.168.1.1
comprobar_falso  "300.1.1.1 no es válida (octeto > 255)" is_ipv4 300.1.1.1
comprobar_falso  "cadena vacía no es válida"             is_ipv4 ""
comprobar_falso  "'abc' no es válida"                    is_ipv4 abc

comprobar_cierto "10.0.0.1 es privada"        is_private_ipv4 10.0.0.1
comprobar_cierto "172.16.0.1 es privada"      is_private_ipv4 172.16.0.1
comprobar_cierto "172.31.255.254 es privada"  is_private_ipv4 172.31.255.254
comprobar_falso  "172.32.0.1 NO es privada"   is_private_ipv4 172.32.0.1
comprobar_cierto "192.168.1.1 es privada"     is_private_ipv4 192.168.1.1
comprobar_falso  "8.8.8.8 no es privada"      is_private_ipv4 8.8.8.8

comprobar_cierto "100.64.0.1 está en el rango CGNAT"      is_cgnat_ipv4 100.64.0.1
comprobar_cierto "100.127.255.254 está en el rango CGNAT" is_cgnat_ipv4 100.127.255.254
comprobar_falso  "100.63.0.1 queda fuera del CGNAT"       is_cgnat_ipv4 100.63.0.1
comprobar_falso  "100.128.0.1 queda fuera del CGNAT"      is_cgnat_ipv4 100.128.0.1

# ---------------------------------------------------------------------------
head1 "Escenarios de red (con trazas fijas)"
# ---------------------------------------------------------------------------

TMPBIN="$(mktemp -d)"
trap 'rm -rf "$TMPBIN"' EXIT
preparar_traceroute_falso "$TMPBIN"

clasificar_con() {
  PATH="$TMPBIN:$PATH" TRACE_FIXTURE="$FIXTURES/$1" bash -c \
    "source '$REPO_ROOT/scripts/lib.sh'; classify_nat"
}

comprobar "un solo router: 1 nivel, sin CGNAT" \
  "1 no ok" "$(clasificar_con nat-simple.txt)"

comprobar "routers en cascada: 2 niveles, sin CGNAT" \
  "2 no ok" "$(clasificar_con nat-doble.txt)"

comprobar "CGNAT detectado" \
  "2 yes ok" "$(clasificar_con nat-cgnat.txt)"

comprobar "traza que no llega a un salto público: no concluyente" \
  "1 no unknown" "$(clasificar_con nat-sin-respuesta.txt)"

comprobar "IP pública directa: 0 niveles de NAT" \
  "0 no ok" "$(clasificar_con nat-sin-nat.txt)"

# ---------------------------------------------------------------------------
head1 "Degradación sin herramientas"
# ---------------------------------------------------------------------------

# El caso importa: bajo 'set -e', una función que falla en vez de degradar tumba
# el diagnóstico entero y el usuario se queda sin ninguna comprobación.
VACIO="$(mktemp -d)"
trap 'rm -rf "$TMPBIN" "$VACIO"' EXIT

sin_herramientas() {
  PATH="$VACIO" "$(command -v bash)" -c \
    "set -euo pipefail; source '$REPO_ROOT/scripts/lib.sh'; $1"
}

comprobar "sin traceroute: no concluyente, sin abortar" \
  "0 no unknown" "$(sin_herramientas classify_nat)"

comprobar "sin ping: MTU no concluyente, sin abortar" \
  "0 unknown" "$(sin_herramientas detect_path_mtu)"

comprobar "sin curl: desviación horaria no concluyente" \
  "0 unknown" "$(sin_herramientas detect_clock_skew)"

# ---------------------------------------------------------------------------
head1 "Medición de MTU"
# ---------------------------------------------------------------------------

IFACE_LOCAL="$(detect_iface || true)"
GW_LOCAL="$(detect_gateway || true)"

if [[ -z "$GW_LOCAL" ]] || ! has_cmd ping; then
  warn "  omitida: hace falta una puerta de enlace alcanzable y 'ping'"
elif ! ping -c1 -W2 "$GW_LOCAL" >/dev/null 2>&1; then
  warn "  omitida: la puerta de enlace no responde a ICMP"
else
  MTU_ENLACE="$(ip link show "$IFACE_LOCAL" 2>/dev/null | grep -oE 'mtu [0-9]+' | grep -oE '[0-9]+')"
  read -r MTU_MEDIDO MTU_ESTADO < <(MTU_PROBE_TARGET="$GW_LOCAL" detect_path_mtu)
  comprobar "la sonda mide el MTU real del enlace ($MTU_ENLACE)" \
    "$MTU_ENLACE ok" "$MTU_MEDIDO $MTU_ESTADO"
fi

# ---------------------------------------------------------------------------
head1 "Desviación horaria"
# ---------------------------------------------------------------------------

read -r SKEW_VAL SKEW_EST < <(detect_clock_skew)
if [[ "$SKEW_EST" != "ok" ]]; then
  warn "  omitida: no hay referencia horaria externa disponible"
else
  if ((SKEW_VAL < 60)); then
    comprobar "el reloj de este equipo se lee como correcto" "menor que 60" "menor que 60"
  else
    comprobar "el reloj de este equipo se lee como correcto" "menor que 60" "$SKEW_VAL"
  fi
fi

# ---------------------------------------------------------------------------
head1 "Resumen"
# ---------------------------------------------------------------------------

if ((FALLA == 0)); then
  ok "$PASA comprobaciones superadas, ninguna fallida."
  exit 0
else
  fail "$FALLA fallidas de $((PASA + FALLA))."
  exit 1
fi
