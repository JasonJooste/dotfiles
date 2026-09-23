#!/usr/bin/env bash
# Bootstrap script for a fresh machine that doesn't have this repo yet, e.g.:
#   curl -fsSL https://raw.githubusercontent.com/JasonJooste/dotfiles/main/config_install.sh | bash -s -- core
# Installs git, clones this repo, then hands off to install.sh for the tier.
#
# REPO_URL / BRANCH / TARGET_DIR are overridable — mainly so this script can
# be tested against a local snapshot instead of the real GitHub remote. See
# test_bootstrap_in_docker.sh.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/JasonJooste/dotfiles.git}"
BRANCH="${BRANCH:-native-nvim-plugin-management}"
TARGET_DIR="${TARGET_DIR:-$HOME/.setup}"
TIER="${1:-core}"

if ! command -v git > /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq git
fi

if [ -d "$TARGET_DIR" ]; then
    echo "$TARGET_DIR already exists — leaving it in place, not re-cloning" >&2
else
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

exec "$TARGET_DIR/install.sh" "$TIER"
