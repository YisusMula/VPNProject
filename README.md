# VPNProject

> **Self-hosted WireGuard VPN** — unifies two LANs as a single network and lets you route streaming traffic through your home IP while travelling.

---

## Architecture

```
Internet
    │
    ▼
┌───────────────────────────────────────────┐
│  VPN Server  (VPS or home router + DDNS)  │
│  WireGuard   10.8.0.1   UDP :51820        │
│  wg-easy web UI   TCP :51821 (local)      │
└────────────┬──────────────────────────────┘
             │  WireGuard tunnel (UDP/encrypted)
    ┌────────┴────────┐
    │                 │
┌───┴──────┐   ┌──────┴─────┐   ┌──────────────────┐
│ Site-A   │   │  Site-B    │   │  Road-warrior    │
│ Gateway  │   │  Gateway   │   │  (laptop/phone)  │
│ 10.8.0.2 │   │  10.8.0.3  │   │  10.8.0.10       │
│          │   │            │   │                  │
│192.168.  │   │ 192.168.   │   │  Full tunnel:    │
│1.0/24    │   │ 2.0/24     │   │  0.0.0.0/0       │
└──────────┘   └────────────┘   └──────────────────┘
```

| Peer | VPN IP | Purpose |
|------|--------|---------|
| VPN Server | 10.8.0.1 | Hub — routes between all peers |
| Site-A gateway | 10.8.0.2 | Main home network (192.168.1.0/24) |
| Site-B gateway | 10.8.0.3 | Secondary / office network (192.168.2.0/24) |
| Road-warrior | 10.8.0.10+ | Laptop / phone while travelling |

**Site-to-site**: Devices on Site-A can reach devices on Site-B by their real LAN IPs, and vice-versa — no manual routing needed on end devices.

**Road-warrior (full tunnel)**: All traffic, including streaming, exits through the VPN server's public IP. Streaming platforms (Netflix, Disney+, etc.) see the server's IP — typically the same one as your home connection if you self-host on a home server.

---

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| VPN Server OS | Linux, kernel ≥ 5.6 (Ubuntu 22.04+, Debian 11+, etc.) |
| Docker | ≥ 20.10 with Compose v2 |
| wireguard-tools | `apt install wireguard-tools` (for key generation) |
| Firewall | UDP port **51820** open inbound on the server |
| Site gateways | Linux machine/router with `ip_forward` capability |
| Client devices | WireGuard app ([windows](https://www.wireguard.com/install/), [macOS](https://apps.apple.com/app/wireguard/id1451685025), [Android](https://play.google.com/store/apps/details?id=com.wireguard.android), [iOS](https://apps.apple.com/app/wireguard/id1441195209)) |
| Optional | `qrencode` for mobile QR codes: `apt install qrencode` |

---

## Quick Start

### 1 — Configure the environment

```bash
cp .env.example .env
nano .env          # set WG_HOST to your server's public IP or domain
```

Minimum required:

```ini
WG_HOST=203.0.113.42          # or vpn.yourdomain.com
WG_PORT=51820
SITE_A_LAN=192.168.1.0/24
SITE_B_LAN=192.168.2.0/24
WG_EASY_PASSWORD=S3cur3P@ss!  # web UI password
```

### 2 — Start the VPN server (on the VPS / home server)

```bash
./scripts/setup-server.sh
```

This script:
1. Generates key pairs for all peers under `keys/` (idempotent)
2. Renders `server/wg0.conf` with real keys
3. Starts the Docker Compose stack (`wg-easy`)

### 3 — Configure the Site-A gateway

Run on the machine that acts as the gateway for your main LAN:

```bash
# On the VPN server — generate the config
./scripts/setup-client.sh site-a

# Copy the config to the Site-A gateway
scp client/site-a/wg0.conf user@site-a-gateway:/etc/wireguard/wg0.conf

# On the Site-A gateway — start WireGuard
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0   # persist across reboots
```

### 4 — Configure the Site-B gateway

```bash
./scripts/setup-client.sh site-b
scp client/site-b/wg0.conf user@site-b-gateway:/etc/wireguard/wg0.conf
# On Site-B gateway:
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
```

### 5 — Configure a road-warrior client (streaming while travelling)

```bash
./scripts/setup-client.sh road-warrior
# If qrencode is installed, a QR code is also saved to:
#   client/road-warrior/wg0.png
```

Import `client/road-warrior/wg0.conf` into the WireGuard app, or scan the QR code with your phone.

Once connected, **all** traffic (including Netflix, Disney+, etc.) exits through the VPN server's IP.

---

## Web UI

`wg-easy` provides a browser-based interface to manage peers without editing config files:

```bash
# Reach the UI via SSH tunnel (recommended — never expose port 51821 directly)
ssh -L 51821:127.0.0.1:51821 user@your-server
# Then open: http://localhost:51821
```

From the UI you can add new peers, download their configs, and view live traffic stats.

---

## Verifying the Setup

```bash
# On the VPN server — check peers are connected
docker exec wg-easy wg show

# From Site-A, ping a device on Site-B's LAN
ping 192.168.2.100

# From Site-B, ping a device on Site-A's LAN
ping 192.168.1.100

# Road-warrior: confirm your public IP is the VPN server's
curl https://api.ipify.org
```

---

## File Structure

```
VPNProject/
├── docker-compose.yml          # wg-easy server stack
├── .env.example                # documented environment variables
├── .gitignore                  # prevents secrets from being committed
├── scripts/
│   ├── generate-keys.sh        # generate WireGuard key pairs (idempotent)
│   ├── setup-server.sh         # render server config + start Docker stack
│   └── setup-client.sh         # render client config for a given role
├── server/
│   └── wg0.conf.template       # annotated server config template
└── client/
    ├── site-a.conf.template    # Site-A gateway template
    ├── site-b.conf.template    # Site-B gateway template
    └── road-warrior.conf.template  # Full-tunnel client template
```

> **Git safety**: `keys/`, `server/wg0.conf`, and `client/*/wg0.conf` are in `.gitignore`.  
> Private key material and pre-shared keys are **never** committed.

---

## Security Notes

- Private keys are generated locally and never leave the machines where they are used.
- Pre-shared keys (PSK) add a layer of post-quantum resistance to each peer.
- The web UI port (51821) is bound to `127.0.0.1` only — access it via SSH tunnel.
- For production, replace the plaintext `WG_EASY_PASSWORD` with a bcrypt hash:
  ```bash
  docker run ghcr.io/wg-easy/wg-easy wgpw 'YourPassword'
  ```
- Rotate keys periodically by deleting the relevant `keys/*.privkey` files and re-running the setup scripts.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Handshake never completes | Firewall blocking UDP 51820 | Open the port on the server's firewall / security group |
| Site-B can't reach Site-A hosts | `ip_forward` not enabled on gateway | `sysctl -w net.ipv4.ip_forward=1` on the gateway, add to `/etc/sysctl.conf` for persistence |
| Streaming still shows wrong region | DNS leak | Ensure `DNS` in road-warrior config points to the VPN's DNS, and DNS leak test passes at [dnsleaktest.com](https://dnsleaktest.com) |
| `wg show` shows 0 bytes received | Wrong public key on either end | Re-run setup scripts; check keys match between server and client `[Peer]` blocks |
| Container exits immediately | Missing `NET_ADMIN` capability or older kernel | Verify kernel ≥ 5.6: `uname -r`; install `wireguard-dkms` on older kernels |
