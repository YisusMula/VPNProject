#!/usr/bin/env bash
# =============================================================================
# generate-keys.sh – Generate WireGuard key pairs for each peer.
#
# Usage:
#   ./scripts/generate-keys.sh [output-dir]
#
# Output (default: ./keys/):
#   server.{privkey,pubkey}
#   site-a.{privkey,pubkey}
#   site-b.{privkey,pubkey}
#   road-warrior.{privkey,pubkey}
#   preshared-site-a.key
#   preshared-site-b.key
#   preshared-road-warrior.key
#
# Requires: wireguard-tools (wg command)
# =============================================================================

set -euo pipefail

# Ensure all files are created with restrictive permissions from the start.
umask 077

KEYS_DIR="${1:-$(dirname "$0")/../keys}"
mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found. Install wireguard-tools."; exit 1; }
}
require_cmd wg

generate_pair() {
  local name="$1"
  local priv="$KEYS_DIR/${name}.privkey"
  local pub="$KEYS_DIR/${name}.pubkey"

  if [[ -f "$priv" ]]; then
    echo "  [skip] $name keys already exist"
    return
  fi

  wg genkey | tee "$priv" | wg pubkey > "$pub"
  chmod 600 "$priv"
  echo "  [ok]   $name"
}

generate_psk() {
  local name="$1"
  local psk="$KEYS_DIR/preshared-${name}.key"

  if [[ -f "$psk" ]]; then
    echo "  [skip] preshared-$name key already exists"
    return
  fi

  wg genpsk > "$psk"
  chmod 600 "$psk"
  echo "  [ok]   preshared-$name"
}

echo "Generating key pairs..."
generate_pair server
generate_pair site-a
generate_pair site-b
generate_pair road-warrior

echo ""
echo "Generating pre-shared keys (extra layer of post-quantum resistance)..."
generate_psk site-a
generate_psk site-b
generate_psk road-warrior

echo ""
echo "Done. Keys written to: $KEYS_DIR"
echo "IMPORTANT: Keep the *.privkey and preshared-*.key files secret."
echo "           Never commit them to version control."
