#!/usr/bin/env bash
# =============================================================================
# run-tests.sh - Prueba el proyecto de extremo a extremo contra un servidor
#                VPN REAL, no simulado.
#
#   ./tests/run-tests.sh
#
# Qué comprueba: que el despliegue deja el túnel operativo, el alta en sus dos
# modos, el listado, la revocación (incluido que el dispositivo revocado deje de
# poder conectar de verdad) y la copia con su restauración.
#
# Cómo obtiene WireGuard:
#   - Si el kernel lo soporta, lo usa tal cual. Es el caso normal en tu equipo.
#   - Si no, compila la implementación en espacio de usuario (necesita Go).
#   - Si no puede ninguna de las dos, OMITE las pruebas de túnel y lo dice.
#     Nunca las da por superadas.
#
# NO toca tu instalación: usa un proyecto de Compose, un volumen y una
# configuración propios, y lo borra todo al terminar aunque algo falle.
# =============================================================================

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_ROOT/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

# Nombres propios del banco: no coinciden con los del producto, de modo que una
# ejecución no pueda destruir las claves de una instalación en uso.
PROYECTO="vpntest$$"
IMAGEN_PRUEBA="wg-easy-test:banco"
CONTENEDOR="wg-easy"
CLIENTE_CT="$PROYECTO-cliente"
TMPDIR_TEST="$(mktemp -d)"
PASSWORD_TEST="BancoDePruebas123"

PASA=0
FALLA=0
OMITE=0
MODO_WG="ninguno"

# ---------------------------------------------------------------------------
# Utilidades de comprobación
# ---------------------------------------------------------------------------
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

omitir() {
  printf '  %s[omitida]%s %s\n' "$_C_YELLOW" "$_C_RESET" "$1"
  OMITE=$((OMITE + 1))
}

# ---------------------------------------------------------------------------
# Limpieza. Va en un trap y no al final: si una comprobación falla bajo 'set -e'
# el final nunca se alcanzaría y quedarían contenedores y volúmenes huérfanos
# que además harían fallar la siguiente ejecución por conflicto de puertos.
# ---------------------------------------------------------------------------
limpiar() {
  local codigo=$?
  docker rm -f "$CLIENTE_CT" >/dev/null 2>&1 || true
  if [[ -f "$TMPDIR_TEST/docker-compose.yml" ]]; then
    (cd "$TMPDIR_TEST" && docker compose -p "$PROYECTO" down -v >/dev/null 2>&1) || true
  fi
  rm -rf "$TMPDIR_TEST"
  exit "$codigo"
}
trap limpiar EXIT

# ---------------------------------------------------------------------------
head1 "Preparando el banco"
# ---------------------------------------------------------------------------

require_cmd docker "Instálalo con: curl -fsSL https://get.docker.com | sh"
docker compose version >/dev/null 2>&1 || die "Falta Docker Compose v2."
docker info >/dev/null 2>&1 || die "El servicio Docker no responde."

# Decidir de dónde sale WireGuard (decisión D1 del diseño).
if kernel_has_wireguard && ip link add wgtest-probe type wireguard >/dev/null 2>&1; then
  ip link del wgtest-probe >/dev/null 2>&1 || true
  MODO_WG="kernel"
  IMAGEN_PRUEBA="ghcr.io/wg-easy/wg-easy:14"
  ok "WireGuard disponible en el kernel: se usa la imagen del producto"
elif has_cmd go; then
  info "El kernel no soporta WireGuard; compilando la implementación en espacio de usuario…"
  if [[ -z "$(docker images -q "$IMAGEN_PRUEBA" 2>/dev/null)" ]]; then
    BUILD="$TMPDIR_TEST/build"
    mkdir -p "$BUILD"
    if git clone -q --depth 1 https://git.zx2c4.com/wireguard-go "$BUILD/src" >/dev/null 2>&1 \
       && (cd "$BUILD/src" && CGO_ENABLED=0 go build -o "$BUILD/wireguard-go" . >/dev/null 2>&1); then
      cat > "$BUILD/Dockerfile" <<'EOF'
FROM ghcr.io/wg-easy/wg-easy:14
COPY wireguard-go /usr/bin/wireguard-go
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go
EOF
      if docker build -q -t "$IMAGEN_PRUEBA" "$BUILD" >/dev/null 2>&1; then
        MODO_WG="userspace"
        ok "Implementación en espacio de usuario lista"
      fi
    fi
  else
    MODO_WG="userspace"
    ok "Reutilizando la imagen de pruebas ya construida"
  fi
fi

if [[ "$MODO_WG" == "ninguno" ]]; then
  warn "Este equipo no puede levantar un túnel WireGuard."
  warn "Las pruebas que lo necesitan se OMITEN (no se dan por superadas)."
  warn "Para ejecutarlas: usa un equipo con WireGuard en el kernel, o instala Go."
fi

# ---------------------------------------------------------------------------
head1 "Levantando un servidor de pruebas"
# ---------------------------------------------------------------------------

if [[ "$MODO_WG" == "ninguno" ]]; then
  omitir "todas las pruebas de extremo a extremo (sin WireGuard disponible)"
else
  # Puertos altos propios para no chocar con una instalación en uso.
  PUERTO_UDP=$(( 52820 + (RANDOM % 200) ))
  PUERTO_UI=$(( 52821 + (RANDOM % 200) ))
  HASH="$(docker run --rm "$IMAGEN_PRUEBA" wgpw "$PASSWORD_TEST" 2>/dev/null \
    | sed -n "s/^PASSWORD_HASH='\(.*\)'$/\1/p")"
  [[ -n "$HASH" ]] || die "No se pudo generar el hash de la contraseña de pruebas."

  # Un hash bcrypt lleva '$' y compose los interpreta como variables al leer el
  # fichero, dejando un hash truncado con el que el panel rechaza la contraseña.
  # Duplicarlos es la forma de escaparlos. Es la misma trampa que documenta
  # .env.example; aquí volvió a morder durante el desarrollo del propio banco.
  HASH_ESCAPADO="${HASH//\$/\$\$}"

  cat > "$TMPDIR_TEST/docker-compose.yml" <<EOF
services:
  wg-easy:
    image: $IMAGEN_PRUEBA
    container_name: $CONTENEDOR
    devices:
      - /dev/net/tun
    environment:
      - WG_HOST=banco.example.org
      - WG_PORT=$PUERTO_UDP
      - PASSWORD_HASH=$HASH_ESCAPADO
      - WG_ALLOWED_IPS=0.0.0.0/0
      - WG_DEFAULT_ADDRESS=10.9.0.x
      - WG_PERSISTENT_KEEPALIVE=25
    volumes:
      - datos:/etc/wireguard
    ports:
      - "127.0.0.1:$PUERTO_UI:51821/tcp"
      - "$PUERTO_UDP:51820/udp"
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
volumes:
  datos:
EOF

  (cd "$TMPDIR_TEST" && docker compose -p "$PROYECTO" up -d >/dev/null 2>&1) \
    || die "No se pudo levantar el servidor de pruebas."

  TUNEL="no"
  for _ in $(seq 1 25); do
    if docker exec "$CONTENEDOR" wg show wg0 >/dev/null 2>&1; then TUNEL="si"; break; fi
    sleep 1
  done
  comprobar "el servidor arranca con el túnel operativo" "si" "$TUNEL"

  [[ "$TUNEL" == "si" ]] || die "Sin túnel no tiene sentido seguir."

  # Configuración propia del banco. NUNCA se toca el .env de la raíz.
  cat > "$TMPDIR_TEST/.env" <<EOF
WG_HOST=banco.example.org
WG_PORT=$PUERTO_UDP
WG_UI_BIND=127.0.0.1
WG_EASY_PASSWORD=$PASSWORD_TEST
EOF
  chmod 600 "$TMPDIR_TEST/.env"
fi

# Los scripts del producto leen .env y clients/ del directorio del repo. Para no
# tocar los del usuario se ejecutan sobre una copia del árbol.
ejecutar_script() {
  local script="$1"; shift
  (cd "$COPIA_REPO" && ./scripts/"$script" "$@")
}

# Igual que ejecutar_script, pero si el comando falla enseña su salida y aborta.
# Un banco que muere en silencio no sirve para diagnosticar nada.
ejecutar_o_morir() {
  local script="$1"; shift
  local salida
  if ! salida="$( (cd "$COPIA_REPO" && ./scripts/"$script" "$@") 2>&1 )"; then
    fail "Falló ./scripts/$script $*"
    printf '%s\n' "$salida" | sed 's/^/         /'
    exit 1
  fi
}

if [[ "$MODO_WG" != "ninguno" ]]; then
  COPIA_REPO="$TMPDIR_TEST/repo"
  mkdir -p "$COPIA_REPO"
  cp -r "$REPO_ROOT/scripts" "$COPIA_REPO/"
  cp "$REPO_ROOT/docker-compose.yml" "$COPIA_REPO/"
  cp "$TMPDIR_TEST/.env" "$COPIA_REPO/.env"
  # El panel del banco escucha en un puerto propio; los scripts asumen 51821.
  sed -i "s/:51821/:$PUERTO_UI/g" "$COPIA_REPO/scripts/lib.sh"
fi

# ---------------------------------------------------------------------------
head1 "Ciclo de dispositivos"
# ---------------------------------------------------------------------------

if [[ "$MODO_WG" == "ninguno" ]]; then
  omitir "alta, listado y revocación de dispositivos"
else
  ejecutar_o_morir add-client.sh movil
  CONF_MOVIL="$COPIA_REPO/clients/movil.conf"
  comprobar "el alta crea el fichero de configuración" \
    "si" "$([[ -f "$CONF_MOVIL" ]] && echo si || echo no)"
  comprobar "el modo por defecto es túnel completo" \
    "si" "$(grep -q 'AllowedIPs = 0.0.0.0/0' "$CONF_MOVIL" && echo si || echo no)"

  LAN_CIDR_OVERRIDE=192.168.77.0/24 ejecutar_o_morir add-client.sh portatil --solo-lan
  CONF_LAN="$COPIA_REPO/clients/portatil.conf"
  comprobar "el modo sólo-LAN acota AllowedIPs a la subred" \
    "si" "$(grep -q 'AllowedIPs = 192.168.77.0/24' "$CONF_LAN" && echo si || echo no)"
  comprobar "el modo sólo-LAN no deja túnel completo" \
    "no" "$(grep -q '0.0.0.0/0' "$CONF_LAN" && echo si || echo no)"
  comprobar "el modo sólo-LAN elimina la línea DNS" \
    "no" "$(grep -q '^DNS' "$CONF_LAN" && echo si || echo no)"

  HUELLA_ANTES="$(sha256sum "$CONF_MOVIL" | cut -d' ' -f1)"
  set +e; ejecutar_script add-client.sh movil >/dev/null 2>&1; CODIGO_DUP=$?; set -e
  comprobar "un nombre duplicado sale con código 2" "2" "$CODIGO_DUP"
  comprobar "y no altera el fichero del dispositivo existente" \
    "$HUELLA_ANTES" "$(sha256sum "$CONF_MOVIL" | cut -d' ' -f1)"

  LISTADO="$(ejecutar_script list-clients.sh 2>/dev/null)"
  comprobar "el listado identifica los dispositivos por su nombre" \
    "si" "$(printf '%s' "$LISTADO" | grep -q 'movil' && echo si || echo no)"

  PEERS_ANTES="$(docker exec "$CONTENEDOR" wg show wg0 peers 2>/dev/null | grep -c . || true)"
  ejecutar_script remove-client.sh portatil --si >/dev/null 2>&1
  PEERS_DESPUES="$(docker exec "$CONTENEDOR" wg show wg0 peers 2>/dev/null | grep -c . || true)"
  comprobar "revocar elimina el peer del servidor" \
    "$((PEERS_ANTES - 1))" "$PEERS_DESPUES"
  LISTADO_POST="$(ejecutar_script list-clients.sh 2>&1 || true)"
  comprobar "y no afecta a los demás dispositivos" \
    "si" "$(printf '%s' "$LISTADO_POST" | grep -q 'movil' && echo si || echo no)"
  if ! printf '%s' "$LISTADO_POST" | grep -q 'movil'; then
    printf '         salida del listado:\n%s\n' "$(printf '%s' "$LISTADO_POST" | sed 's/^/           /')"
  fi

  set +e; ejecutar_script remove-client.sh no-existe --si >/dev/null 2>&1; CODIGO_NX=$?; set -e
  comprobar "revocar un nombre inexistente falla" "1" "$CODIGO_NX"
fi

# ---------------------------------------------------------------------------
head1 "Túnel real"
# ---------------------------------------------------------------------------

if [[ "$MODO_WG" == "ninguno" ]]; then
  omitir "negociación real y comprobación de que el revocado deja de conectar"
else
  SERVER_IP="$(docker inspect "$CONTENEDOR" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
  # El cliente de prueba no tiene resolvconf ni init: la línea DNS lo tumbaría.
  grep -v '^DNS' "$CONF_MOVIL" \
    | sed "s|^Endpoint = .*|Endpoint = ${SERVER_IP}:${PUERTO_UDP}|" > "$TMPDIR_TEST/cliente.conf"

  docker run -d --name "$CLIENTE_CT" --privileged --device /dev/net/tun \
    --network "${PROYECTO}_default" \
    --entrypoint sleep "$IMAGEN_PRUEBA" 600 >/dev/null 2>&1
  docker cp "$TMPDIR_TEST/cliente.conf" "$CLIENTE_CT:/etc/wireguard/wg0.conf" >/dev/null 2>&1
  docker exec "$CLIENTE_CT" sh -c \
    'WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go wg-quick up wg0' >/dev/null 2>&1 || true
  sleep 6

  ESTADO_CLIENTE="$(docker exec "$CLIENTE_CT" wg show wg0 2>&1 || true)"
  comprobar "el cliente establece la negociación con el servidor" \
    "si" "$(printf '%s' "$ESTADO_CLIENTE" | grep -q 'latest handshake' && echo si || echo no)"
  if ! printf '%s' "$ESTADO_CLIENTE" | grep -q 'latest handshake'; then
    printf '         estado del cliente:\n%s\n' "$(printf '%s' "$ESTADO_CLIENTE" | sed 's/^/           /')"
    printf '         endpoint configurado: %s\n' "$(grep Endpoint "$TMPDIR_TEST/cliente.conf" || true)"
    printf '         red del servidor: %s\n' "$(docker inspect "$CONTENEDOR" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{end}}')"
    printf '         red del cliente : %s\n' "$(docker inspect "$CLIENTE_CT" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{end}}')"
  fi

  # Ahora se revoca con el túnel levantado y se comprueba que deja de responder.
  ejecutar_script remove-client.sh movil --si >/dev/null 2>&1
  docker exec "$CLIENTE_CT" sh -c \
    'wg-quick down wg0 >/dev/null 2>&1; WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go wg-quick up wg0' >/dev/null 2>&1 || true
  sleep 12

  comprobar "el dispositivo revocado ya no consigue negociar" \
    "no" "$(docker exec "$CLIENTE_CT" wg show wg0 2>/dev/null | grep -q 'latest handshake' && echo si || echo no)"

  RX="$(docker exec "$CLIENTE_CT" wg show wg0 transfer 2>/dev/null | awk '{print $2}' | head -1)"
  comprobar "el revocado envía pero no recibe nada del servidor" "0" "${RX:-0}"
fi

# ---------------------------------------------------------------------------
head1 "Enrutado del modo sólo-LAN"
# ---------------------------------------------------------------------------

if [[ "$MODO_WG" == "ninguno" ]]; then
  omitir "comprobación de la tabla de rutas del cliente"
else
  LAN_CIDR_OVERRIDE=192.168.77.0/24 ejecutar_script add-client.sh solo-lan --solo-lan >/dev/null 2>&1
  SERVER_IP="$(docker inspect "$CONTENEDOR" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
  sed "s|^Endpoint = .*|Endpoint = ${SERVER_IP}:${PUERTO_UDP}|" \
    "$COPIA_REPO/clients/solo-lan.conf" > "$TMPDIR_TEST/lan.conf"

  docker rm -f "$CLIENTE_CT" >/dev/null 2>&1 || true
  docker run -d --name "$CLIENTE_CT" --privileged --device /dev/net/tun \
    --network "${PROYECTO}_default" \
    --entrypoint sleep "$IMAGEN_PRUEBA" 600 >/dev/null 2>&1
  docker cp "$TMPDIR_TEST/lan.conf" "$CLIENTE_CT:/etc/wireguard/wg0.conf" >/dev/null 2>&1
  docker exec "$CLIENTE_CT" sh -c \
    'WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go wg-quick up wg0' >/dev/null 2>&1 || true
  sleep 5

  RUTAS="$(docker exec "$CLIENTE_CT" ip route 2>/dev/null || true)"
  comprobar "la subred doméstica se enruta por el túnel" \
    "si" "$(printf '%s' "$RUTAS" | grep -q '192.168.77.0/24 dev wg0' && echo si || echo no)"
  comprobar "la ruta por defecto NO pasa por el túnel" \
    "no" "$(printf '%s' "$RUTAS" | grep '^default' | grep -q 'wg0' && echo si || echo no)"
fi

# ---------------------------------------------------------------------------
head1 "Copia de seguridad"
# ---------------------------------------------------------------------------

if [[ "$MODO_WG" == "ninguno" ]]; then
  omitir "copia y restauración"
else
  VOL="${PROYECTO}_datos"
  HUELLA_ORIG="$(docker run --rm -v "$VOL":/d alpine sha256sum /d/wg0.json 2>/dev/null | cut -d' ' -f1)"

  docker run --rm -v "$VOL":/d:ro -v "$TMPDIR_TEST":/b alpine \
    tar czf /b/copia.tar.gz -C /d . >/dev/null 2>&1
  comprobar "la copia contiene el estado del servidor" \
    "si" "$(tar tzf "$TMPDIR_TEST/copia.tar.gz" 2>/dev/null | grep -q 'wg0.json' && echo si || echo no)"

  docker run --rm -v "$VOL":/d alpine sh -c 'echo "{}" > /d/wg0.json' >/dev/null 2>&1
  docker run --rm -v "$VOL":/d -v "$TMPDIR_TEST":/b:ro alpine \
    sh -c 'rm -rf /d/* && tar xzf /b/copia.tar.gz -C /d' >/dev/null 2>&1
  comprobar "restaurar devuelve el estado al de la copia" \
    "$HUELLA_ORIG" "$(docker run --rm -v "$VOL":/d alpine sha256sum /d/wg0.json 2>/dev/null | cut -d' ' -f1)"

  echo "no soy un tar" > "$TMPDIR_TEST/roto.tar.gz"
  HUELLA_PREV="$(docker run --rm -v "$VOL":/d alpine sha256sum /d/wg0.json 2>/dev/null | cut -d' ' -f1)"
  set +e
  (cd "$COPIA_REPO" && ./scripts/backup.sh --restaurar "$TMPDIR_TEST/roto.tar.gz" --si) >/dev/null 2>&1
  set -e
  comprobar "un archivo corrupto no altera el estado" \
    "$HUELLA_PREV" "$(docker run --rm -v "$VOL":/d alpine sha256sum /d/wg0.json 2>/dev/null | cut -d' ' -f1)"
fi

# ---------------------------------------------------------------------------
head1 "Resumen"
# ---------------------------------------------------------------------------

printf '  WireGuard usado: %s\n\n' "$MODO_WG"

if ((FALLA == 0 && OMITE == 0)); then
  ok "$PASA comprobaciones superadas. Todo correcto."
  exit 0
elif ((FALLA == 0)); then
  warn "$PASA superadas, $OMITE OMITIDAS por limitaciones del entorno."
  warn "Las omitidas NO están verificadas: no las des por buenas."
  exit 0
else
  fail "$FALLA fallidas, $PASA superadas, $OMITE omitidas."
  exit 1
fi
