#!/usr/bin/env bash
# =============================================================================
# doctor.sh - Diagnóstico de la VPN: dice exactamente qué falla y qué hacer.
#
#   ./scripts/doctor.sh
#
# Es de sólo lectura: no cambia ninguna configuración, ni del sistema ni de los
# contenedores. Puedes ejecutarlo tantas veces como quieras.
#
# Código de salida:  0 si todo pasa,  1 si alguna comprobación falla.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

FALLOS=0
AVISOS=0

check_ok()   { ok "$*"; }
check_warn() { warn "$*"; AVISOS=$((AVISOS + 1)); }
check_fail() { fail "$*"; FALLOS=$((FALLOS + 1)); }
accion()     { printf '        %s\n' "$*"; }

ENV_FILE="$REPO_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  load_env_file "$ENV_FILE"
else
  warn "No hay .env todavía. Ejecuta ./deploy.sh primero."
fi

WG_PORT="${WG_PORT:-51820}"

# ---------------------------------------------------------------------------
head1 "1. Tu conexión a internet"
# ---------------------------------------------------------------------------

PUBLIC_IP=""
if PUBLIC_IP="$(detect_public_ip)"; then
  check_ok "IP pública actual: $PUBLIC_IP"
else
  check_fail "No se pudo averiguar tu IP pública."
  accion "Comprueba que este equipo tiene salida a internet."
fi

read -r NAT_LEVELS NAT_CGNAT NAT_STATE < <(classify_nat)

if [[ "$NAT_STATE" == "unknown" ]]; then
  check_warn "No se pudo trazar la ruta hacia internet: NAT y CGNAT sin determinar."
  accion "Instala traceroute para un diagnóstico completo:  sudo apt install traceroute"
elif [[ "$NAT_CGNAT" == "yes" ]]; then
  check_fail "Tu operadora te tiene detrás de CGNAT (rango 100.64.0.0/10)."
  accion "Esto es BLOQUEANTE: no compartes una IP pública propia, así que"
  accion "NINGUNA configuración de reenvío de puertos hará que te conecten."
  accion "Opciones reales:"
  accion "  1. Pedir a tu operadora una IP pública (a veces gratis, sólo hay que pedirla)."
  accion "  2. Alquilar un VPS barato y poner ahí el servidor VPN."
  accion "  3. Usar una malla tipo Tailscale/ZeroTier, que atraviesa CGNAT."
else
  check_ok "Sin CGNAT: tienes una IP pública propia, el reenvío de puertos es viable."
fi

# ---------------------------------------------------------------------------
head1 "2. Tus routers"
# ---------------------------------------------------------------------------

LAN_IP="$(detect_lan_ip || true)"
GATEWAY="$(detect_gateway || true)"
if [[ -n "$LAN_IP" ]]; then
  info "IP de este servidor: $LAN_IP"
fi
if [[ -n "$GATEWAY" ]]; then
  info "Router más cercano : $GATEWAY"
fi

if [[ "$NAT_STATE" == "unknown" ]]; then
  : # ya avisado arriba
elif ((NAT_LEVELS >= 2)); then
  check_warn "Detectados $NAT_LEVELS niveles de NAT: tienes routers en cascada."
  accion "Hay que reenviar el puerto en LOS DOS, o no entrará nada:"
  accion ""
  accion "  a) En el router SECUNDARIO (el Archer, el más cercano a este equipo):"
  accion "       Protocolo UDP, puerto externo $WG_PORT, puerto interno $WG_PORT"
  accion "       Destino: ${LAN_IP:-<la IP de este servidor>}"
  accion ""
  accion "  b) En el router PRINCIPAL (el de la operadora, el Huawei):"
  accion "       Protocolo UDP, puerto externo $WG_PORT, puerto interno $WG_PORT"
  accion "       Destino: la IP WAN del router secundario"
  accion ""
  accion "  Alternativa que ahorra el paso (b): poner el router secundario en"
  accion "  modo punto de acceso. Así sólo queda un nivel de NAT."
elif ((NAT_LEVELS == 1)); then
  check_ok "Un solo nivel de NAT: basta con una regla de reenvío."
  accion "En tu router: UDP $WG_PORT -> ${LAN_IP:-<la IP de este servidor>}"
else
  check_warn "No se detectó NAT entre este equipo e internet (¿IP pública directa?)."
fi

# ---------------------------------------------------------------------------
head1 "3. El servidor VPN"
# ---------------------------------------------------------------------------

CONTENEDOR_OK="no"
if ! has_cmd docker; then
  check_fail "Docker no está instalado."
elif ! docker inspect wg-easy >/dev/null 2>&1; then
  check_fail "El contenedor 'wg-easy' no existe."
  accion "Ejecuta:  ./deploy.sh"
else
  ESTADO="$(docker inspect -f '{{.State.Status}}' wg-easy 2>/dev/null || echo desconocido)"
  case "$ESTADO" in
    running)
      check_ok "El servidor VPN está en ejecución."
      CONTENEDOR_OK="si"
      ;;
    restarting)
      check_fail "El servidor VPN está en bucle de reinicio."
      accion "Mira la causa con:  docker compose logs --tail 30 wg-easy"
      accion "Si dice \"Cannot find device wg0\", al kernel le falta WireGuard:"
      accion "    sudo apt install wireguard-dkms wireguard-tools"
      ;;
    *)
      check_fail "El servidor VPN no está corriendo (estado: $ESTADO)."
      accion "Arráncalo con:  docker compose up -d"
      ;;
  esac
fi

if ! kernel_has_wireguard; then
  check_warn "Este kernel ($(uname -r)) podría no soportar WireGuard."
  accion "Si el contenedor se reinicia sin parar:  sudo apt install wireguard-dkms wireguard-tools"
fi

# Reenvío IP en el anfitrión: sin esto el tráfico entra por el túnel y muere ahí.
if [[ -r /proc/sys/net/ipv4/ip_forward ]]; then
  if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]]; then
    check_ok "El reenvío de paquetes IP está activado."
  else
    check_fail "El reenvío de paquetes IP está desactivado (net.ipv4.ip_forward = 0)."
    accion "Actívalo de forma persistente:"
    accion "    echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-vpn.conf"
    accion "    sudo sysctl --system"
  fi
else
  check_warn "No se pudo leer net.ipv4.ip_forward."
fi

# ---------------------------------------------------------------------------
head1 "4. El puerto $WG_PORT/UDP visto desde fuera"
# ---------------------------------------------------------------------------

# Un puerto UDP abierto y uno filtrado se comportan igual desde fuera: ambos
# callan. Por eso sólo se afirma que está abierto cuando hay prueba positiva
# (una negociación real), y en el resto de casos se dice "no concluyente" en
# lugar de mandar al usuario a reconfigurar routers que quizá ya estaban bien.
HANDSHAKES=""
if [[ "$CONTENEDOR_OK" == "si" ]]; then
  HANDSHAKES="$(docker exec wg-easy wg show wg0 latest-handshakes 2>/dev/null || true)"
fi

PEERS_TOTAL=0
PEERS_CON_HANDSHAKE=0
if [[ -n "$HANDSHAKES" ]]; then
  while read -r _pub ts; do
    [[ -n "${ts:-}" ]] || continue
    PEERS_TOTAL=$((PEERS_TOTAL + 1))
    # Con 'set -e', un '[[ ... ]] && VAR=...' aborta el script cuando la
    # condición es falsa, que aquí es el caso normal (peer sin negociar).
    if [[ "$ts" != "0" ]]; then
      PEERS_CON_HANDSHAKE=$((PEERS_CON_HANDSHAKE + 1))
    fi
  done <<<"$HANDSHAKES"
fi

if [[ "$CONTENEDOR_OK" != "si" ]]; then
  check_fail "Puerto NO alcanzable: el servidor ni siquiera está escuchando."
  accion "Arregla primero el apartado 3."
elif ((PEERS_CON_HANDSHAKE > 0)); then
  check_ok "Puerto alcanzable CONFIRMADO: $PEERS_CON_HANDSHAKE de $PEERS_TOTAL dispositivos han negociado alguna vez."
elif ((PEERS_TOTAL == 0)); then
  check_warn "No concluyente: aún no hay ningún dispositivo dado de alta."
  accion "Crea uno con:  ./scripts/add-client.sh movil"
else
  check_warn "No concluyente: hay $PEERS_TOTAL dispositivos, pero ninguno ha conectado nunca."
  accion "Una comprobación de puerto UDP desde fuera no es fiable, así que la"
  accion "prueba de verdad es esta:"
  accion "  1. Coge el móvil y APAGA el WiFi (usa datos móviles)."
  accion "  2. Activa el túnel de WireGuard."
  accion "  3. Vuelve a ejecutar este diagnóstico."
  accion "Si sigue sin conectar, falta el reenvío del puerto (apartado 2)."
fi

# ---------------------------------------------------------------------------
head1 "5. Dispositivos dados de alta"
# ---------------------------------------------------------------------------

if [[ "$CONTENEDOR_OK" != "si" ]]; then
  info "Se omite: el servidor no está en marcha."
elif ((PEERS_TOTAL == 0)); then
  check_warn "No hay ningún dispositivo dado de alta."
  accion "Crea uno con:  ./scripts/add-client.sh movil"
else
  check_ok "$PEERS_TOTAL dispositivos dados de alta, $PEERS_CON_HANDSHAKE han conectado alguna vez."
  AHORA="$(date +%s)"
  while read -r pub ts; do
    [[ -n "${ts:-}" ]] || continue
    CORTO="${pub:0:12}…"
    if [[ "$ts" == "0" ]]; then
      printf '        %-16s nunca ha conectado\n' "$CORTO"
    else
      printf '        %-16s última conexión hace %s s\n' "$CORTO" "$((AHORA - ts))"
    fi
  done <<<"$HANDSHAKES"
fi

# ---------------------------------------------------------------------------
head1 "6. Tu IP dinámica"
# ---------------------------------------------------------------------------

if [[ -z "${WG_HOST:-}" ]]; then
  check_warn "WG_HOST no está definido."
elif is_ipv4 "$WG_HOST"; then
  check_warn "Los dispositivos apuntan a la IP literal $WG_HOST."
  accion "Tu IP es dinámica: cuando cambie, TODOS dejarán de conectar."
  accion "Solución: crea un dominio gratis en https://www.duckdns.org y ejecuta"
  accion "    DUCKDNS_SUBDOMAIN=tu-dominio DUCKDNS_TOKEN=tu-token ./deploy.sh"
  if [[ -n "$PUBLIC_IP" && "$WG_HOST" != "$PUBLIC_IP" ]]; then
    check_fail "Además, tu IP YA cambió: los dispositivos apuntan a $WG_HOST pero ahora tienes $PUBLIC_IP."
    accion "Los dispositivos actuales ya no conectan. Configura DDNS y regenéralos."
  fi
else
  RESUELVE=""
  if has_cmd getent; then
    RESUELVE="$(getent ahostsv4 "$WG_HOST" 2>/dev/null | awk '{print $1; exit}' || true)"
  fi

  if [[ -z "$RESUELVE" ]]; then
    check_warn "El dominio $WG_HOST no resuelve a ninguna IP ahora mismo."
    accion "Comprueba que el dominio existe y que el DDNS está funcionando."
  elif [[ -z "$PUBLIC_IP" ]]; then
    check_warn "$WG_HOST resuelve a $RESUELVE, pero no se pudo comparar con tu IP pública."
  elif [[ "$RESUELVE" == "$PUBLIC_IP" ]]; then
    check_ok "$WG_HOST resuelve a $RESUELVE, que es tu IP pública actual."
  else
    check_fail "El dominio está desincronizado."
    accion "  $WG_HOST resuelve a : $RESUELVE"
    accion "  Tu IP pública es    : $PUBLIC_IP"
    accion "Nadie podrá conectar hasta que el DDNS se ponga al día."
    if [[ -n "${DUCKDNS_TOKEN:-}" ]]; then
      accion "Revisa el actualizador:  docker compose logs --tail 20 ddns"
    else
      accion "No tienes el actualizador DDNS activado. Configúralo con:"
      accion "    DUCKDNS_SUBDOMAIN=tu-dominio DUCKDNS_TOKEN=tu-token ./deploy.sh"
    fi
  fi
fi

# ---------------------------------------------------------------------------
head1 "Resumen"
# ---------------------------------------------------------------------------

if ((FALLOS == 0 && AVISOS == 0)); then
  ok "Todo correcto."
  exit 0
elif ((FALLOS == 0)); then
  warn "$AVISOS aviso(s), ningún fallo. Revisa lo señalado arriba."
  exit 0
else
  fail "$FALLOS fallo(s) y $AVISOS aviso(s). Empieza por el primer fallo de la lista."
  exit 1
fi
