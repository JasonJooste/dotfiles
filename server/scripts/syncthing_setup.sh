#!/usr/bin/env bash
# Install Syncthing and set it up for tailnet-only use (see backup_server/README.md).
# Usage: syncthing_setup install    - add Syncthing's apt repo, install it, and allow its port on the tailnet only
#        syncthing_setup configure  - as the user running Syncthing (which must be running): turn off relays, NAT
#                                     traversal, discovery and usage reporting, and listen on TCP only
set -euo pipefail
PORT=22000

install() {
    if ! command -v syncthing > /dev/null; then
        sudo install -d -m 755 /etc/apt/keyrings
        sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
        echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" \
            | sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq syncthing
    fi
    # Syncthing's traffic is authenticated and encrypted, but only the tailnet needs to reach it
    sudo ufw allow in on tailscale0 to any port "$PORT" proto tcp > /dev/null
}

configure() {
    local tries=0
    until syncthing cli show system > /dev/null 2>&1; do
        tries=$((tries + 1))
        [ "$tries" -le 30 ] || { echo "Syncthing isn't running" >&2; return 1; }
        sleep 1
    done
    local api_key
    api_key="$(syncthing cli config gui apikey get)"
    curl -fsS -X PATCH -H "X-API-Key: $api_key" http://127.0.0.1:8384/rest/config/options -d "{
        \"listenAddresses\": [\"tcp://:$PORT\"],
        \"globalAnnounceEnabled\": false,
        \"localAnnounceEnabled\": false,
        \"relaysEnabled\": false,
        \"natEnabled\": false,
        \"urAccepted\": -1,
        \"crashReportingEnabled\": false
    }"
}

case "${1:-}" in
    install) install ;;
    configure) configure ;;
    *) echo "usage: syncthing_setup install|configure" >&2; exit 1 ;;
esac
