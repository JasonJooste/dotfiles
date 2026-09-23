# Install nodejs (needed by coc.nvim) and the server tier's extra neovim plugins.
set -euo pipefail
if ! command -v node >/dev/null; then
    curl -fsSL https://install-node.vercel.app/lts | sudo bash -s -- -y
fi
# vim.pack.add() in init.vim installs any missing plugins during startup
nvim --headless -c qa
