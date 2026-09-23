# Install nodejs (needed by coc.nvim) and the server tier's extra neovim plugins.
set -euo pipefail
if ! command -v node >/dev/null; then
    curl -fsSL https://install-node.vercel.app/lts | sudo bash -s -- -y
fi
nvim --headless -c "PlugInstall --sync" -c qa
