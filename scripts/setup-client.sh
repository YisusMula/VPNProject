#!/usr/bin/env bash
# =============================================================================
# setup-client.sh – Generate a WireGuard client config for a specific peer role.
#
# Usage (run from the repo root after running setup-server.sh once):
#   ./scripts/setup-client.sh site-a
#   ./scripts/setup-client.sh site-b
#   ./scripts/setup-client.sh road-warrior
#
# Output:
#   client/<role>/wg0.conf  – ready to copy to the target gateway or device
#   client/<role>/wg0.png   – QR code (road-warrior only, requires qrencode)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$REPO_ROOT/keys"
ENV_FILE="$REPO_ROOT/.env"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  --> $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. $2"; }

# ---------- validate input ----------------------------------------------------
ROLE="${1:-}"
case "$ROLE" in
  site-a|site-b|road-warrior) ;;
  *) die "Unknown role '$ROLE'. Valid options: site-a | site-b | road-warrior" ;;
esac

[[ -f "$ENV_FILE" ]] || die ".env not found. Run: cp .env.example .env && nano .env"

# shellcheck source=/dev/null
source "$ENV_FILE"

[[ -n "${WG_HOST:-}" ]] || die "WG_HOST is not set in .env"

# ---------- load keys ---------------------------------------------------------
read_key() {
  local f="$KEYS_DIR/$1"
  [[ -f "$f" ]] || die "Key file not found: $f  — run ./scripts/generate-keys.sh first"
  cat "$f"
}

SERVER_PUBKEY=$(read_key server.pubkey)
CLIENT_PRIVKEY=$(read_key "${ROLE}.privkey")
CLIENT_PSK=$(read_key "preshared-${ROLE}.key")

WG_PORT="${WG_PORT:-51820}"
SITE_A_LAN="${SITE_A_LAN:-192.168.1.0/24}"
SITE_B_LAN="${SITE_B_LAN:-192.168.2.0/24}"
SITE_A_VPN_IP="${SITE_A_VPN_IP:-10.8.0.2}"
SITE_B_VPN_IP="${SITE_B_VPN_IP:-10.8.0.3}"
ROAD_WARRIOR_START_IP="${ROAD_WARRIOR_START_IP:-10.8.0.10}"

OUT_DIR="$REPO_ROOT/client/$ROLE"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/wg0.conf"

# ---------- render config per role --------------------------------------------
case "$ROLE" in
  site-a)
    # Gateway for Site-A LAN.  Installs on the router/server that sits in front
    # of the 192.168.1.0/24 network and has a route to it.
    cat > "$OUT_FILE" <<EOF
# WireGuard config – Site-A gateway
# Copy to /etc/wireguard/wg0.conf on the Site-A gateway machine.
# Then: wg-quick up wg0   (or systemctl enable --now wg-quick@wg0)

[Interface]
Address    = ${SITE_A_VPN_IP}/24
PrivateKey = ${CLIENT_PRIVKEY}
DNS        = ${WG_DEFAULT_DNS:-1.1.1.1,8.8.8.8}
# Announce the local LAN to the VPN so Site-B and road-warriors can reach it.
PostUp     = ip route add ${SITE_B_LAN} via ${SITE_A_VPN_IP%.*}.1; \\
             sysctl -w net.ipv4.ip_forward=1; \\
             iptables -A FORWARD -i %i -j ACCEPT; \\
             iptables -A FORWARD -o %i -j ACCEPT; \\
             iptables -t nat -A POSTROUTING -s ${SITE_B_LAN} -o eth0 -j MASQUERADE
PostDown   = ip route del ${SITE_B_LAN} via ${SITE_A_VPN_IP%.*}.1 2>/dev/null || true; \\
             iptables -D FORWARD -i %i -j ACCEPT; \\
             iptables -D FORWARD -o %i -j ACCEPT; \\
             iptables -t nat -D POSTROUTING -s ${SITE_B_LAN} -o eth0 -j MASQUERADE 2>/dev/null || true

[Peer]
# VPN server
PublicKey           = ${SERVER_PUBKEY}
PresharedKey        = ${CLIENT_PSK}
Endpoint            = ${WG_HOST}:${WG_PORT}
# Allow VPN subnet + Site-B LAN through the tunnel
AllowedIPs          = 10.8.0.0/24, ${SITE_B_LAN}
PersistentKeepalive = 25
EOF
    ;;

  site-b)
    # Gateway for Site-B LAN.
    cat > "$OUT_FILE" <<EOF
# WireGuard config – Site-B gateway
# Copy to /etc/wireguard/wg0.conf on the Site-B gateway machine.

[Interface]
Address    = ${SITE_B_VPN_IP}/24
PrivateKey = ${CLIENT_PRIVKEY}
DNS        = ${WG_DEFAULT_DNS:-1.1.1.1,8.8.8.8}
PostUp     = ip route add ${SITE_A_LAN} via ${SITE_B_VPN_IP%.*}.1; \\
             sysctl -w net.ipv4.ip_forward=1; \\
             iptables -A FORWARD -i %i -j ACCEPT; \\
             iptables -A FORWARD -o %i -j ACCEPT; \\
             iptables -t nat -A POSTROUTING -s ${SITE_A_LAN} -o eth0 -j MASQUERADE
PostDown   = ip route del ${SITE_A_LAN} via ${SITE_B_VPN_IP%.*}.1 2>/dev/null || true; \\
             iptables -D FORWARD -i %i -j ACCEPT; \\
             iptables -D FORWARD -o %i -j ACCEPT; \\
             iptables -t nat -D POSTROUTING -s ${SITE_A_LAN} -o eth0 -j MASQUERADE 2>/dev/null || true

[Peer]
# VPN server
PublicKey           = ${SERVER_PUBKEY}
PresharedKey        = ${CLIENT_PSK}
Endpoint            = ${WG_HOST}:${WG_PORT}
# Allow VPN subnet + Site-A LAN through the tunnel
AllowedIPs          = 10.8.0.0/24, ${SITE_A_LAN}
PersistentKeepalive = 25
EOF
    ;;

  road-warrior)
    # Travelling client – all traffic routed through the VPN so the device
    # appears to be at Site-A (streaming platforms see the home IP).
    cat > "$OUT_FILE" <<EOF
# WireGuard config – Road-warrior (full tunnel, streaming-friendly)
# Import into the WireGuard app on your laptop or phone.
# Android/iOS: scan the QR code in client/road-warrior/wg0.png

[Interface]
Address    = ${ROAD_WARRIOR_START_IP}/32
PrivateKey = ${CLIENT_PRIVKEY}
# All DNS queries go through the VPN to avoid leaks
DNS        = ${WG_DEFAULT_DNS:-1.1.1.1,8.8.8.8}

[Peer]
PublicKey           = ${SERVER_PUBKEY}
PresharedKey        = ${CLIENT_PSK}
Endpoint            = ${WG_HOST}:${WG_PORT}
# 0.0.0.0/0 = full tunnel: ALL traffic (including streaming) goes via the VPN.
# The server's POSTROUTING masquerade makes you appear as the server's public IP.
AllowedIPs          = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    # Generate QR code for mobile apps if qrencode is available
    if command -v qrencode >/dev/null 2>&1; then
      qrencode -t PNG -o "$OUT_DIR/wg0.png" < "$OUT_FILE"
      info "QR code written to $OUT_DIR/wg0.png (scan with WireGuard app)"
    else
      info "Install 'qrencode' to generate a QR code for mobile devices."
    fi
    ;;
esac

chmod 600 "$OUT_FILE"
info "Client config written to $OUT_FILE"
info "Copy this file to the target device at /etc/wireguard/wg0.conf"
info "Then run: sudo wg-quick up wg0"
