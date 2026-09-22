#!/usr/bin/env bash
# Tests config_install.sh end-to-end against the CURRENT contents of this
# directory by snapshotting it into a throwaway local git repo 
# Usage: ./test_bootstrap_in_docker.sh [tier]
set -euo pipefail

if ! command -v docker &> /dev/null; then
    echo "docker is not installed (or not on PATH) — can't run this test." >&2
    exit 1
fi

TIER="${1:-core}"
SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SNAPSHOT_DIR="$(mktemp -d)"
trap 'rm -rf "$SNAPSHOT_DIR"' EXIT

cp -a "$SETUP_DIR/." "$SNAPSHOT_DIR/"
git -C "$SNAPSHOT_DIR" init -q -b main
git -C "$SNAPSHOT_DIR" add -A
git -C "$SNAPSHOT_DIR" -c user.email=test@test -c user.name=test commit -q -m snapshot
chmod -R a+rX "$SNAPSHOT_DIR"

docker run --rm -i -v "$SNAPSHOT_DIR:/fake-remote:ro" ubuntu:24.04 bash -s <<EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq sudo > /dev/null
useradd -m -s /bin/bash tester
echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
printf '[safe]\n\tdirectory = *\n' > /home/tester/.gitconfig
chown tester:tester /home/tester/.gitconfig
su - tester -c "REPO_URL=file:///fake-remote BRANCH=main bash /fake-remote/config_install.sh $TIER"
EOF

echo "bootstrap test ($TIER) completed successfully"
