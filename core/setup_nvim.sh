# Install neovim (official release tarball, so no apt/PPA or root needed), vim-plug and the plugins.
# Assumes install.sh has already symlinked ~/.config/nvim/init.vim via apply_tier_dotfiles.
# Downloads are skipped when already present, so reruns only check for missing plugins.
set -euo pipefail
OPT_DIR="$HOME/.local/opt"
NVIM_DIR="$OPT_DIR/nvim"
BIN_DIR="$HOME/.local/bin"
PLUG_VIM="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim"

install_nvim() {
    local arch tmp
    case "$(uname -m)" in
        x86_64) arch=x86_64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) echo "no neovim release build for $(uname -m)" >&2; return 1 ;;
    esac
    # Extract next to the final location, then swap it in, so a failed download never leaves a half-installed nvim
    mkdir -p "$OPT_DIR"
    tmp="$(mktemp -d "$OPT_DIR/.nvim.XXXXXX")"
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$arch.tar.gz" \
        | tar -xz -C "$tmp" --strip-components=1
    rm -rf "$NVIM_DIR"
    mv "$tmp" "$NVIM_DIR"
}

# Both downloads run in parallel
pids=()
if [ ! -x "$NVIM_DIR/bin/nvim" ]; then
    install_nvim & pids+=($!)
fi
if [ ! -f "$PLUG_VIM" ]; then
    curl -fsSLo "$PLUG_VIM" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim & pids+=($!)
fi
for pid in "${pids[@]}"; do
    wait "$pid"
done

mkdir -p "$BIN_DIR"
ln -sf "$NVIM_DIR/bin/nvim" "$BIN_DIR/nvim"

"$BIN_DIR/nvim" --headless -c "PlugInstall --sync" -c qa
