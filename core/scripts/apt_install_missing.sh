#!/usr/bin/env bash
# Install the given apt packages. Skips apt entirely when they're all installed already, and only
# refreshes the package lists if installing from the current ones fails (e.g. fresh containers).
# Usage: apt_install_missing <package>...
set -euo pipefail

missing=()
for pkg in "$@"; do
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null)" = installed ] || missing+=("$pkg")
done
[ ${#missing[@]} -eq 0 ] && exit 0

apt_install() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}"
}
# The first attempt's errors are hidden since failing there is expected when the lists are empty or stale
apt_install 2>/dev/null || { sudo apt-get update -qq && apt_install; }
