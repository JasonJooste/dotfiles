#!/usr/bin/env bash
# Runs install.sh for a given tier inside a throwaway ubuntu container.
# Usage: ./test_in_docker.sh [core|server|personal] [ubuntu-image-tag]
#
# Note: only `core` is realistically testable this way. `server` installs
# Docker Engine and tries to start it via systemd, and `personal` installs
# GUI snap packages — neither works in a plain container regardless of
# whether the install scripts themselves are correct.
set -euo pipefail

if ! command -v docker &> /dev/null; then
    echo "docker is not installed (or not on PATH) — can't run this test." >&2
    exit 1
fi

TIER="${1:-core}"
IMAGE="${2:-ubuntu:24.04}"
SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

docker run --rm -i -v "$SETUP_DIR:/setup:ro" "$IMAGE" bash -s <<EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# git is normally already there from cloning this repo, but here the repo is copied in instead
apt-get install -y -qq sudo git > /dev/null
useradd -m -s /bin/bash tester
echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
cp -r /setup /home/tester/.setup
chown -R tester:tester /home/tester/.setup
su - tester -c "cd ~/.setup && ./install.sh $TIER"
EOF

echo "install.sh $TIER completed successfully inside $IMAGE"
