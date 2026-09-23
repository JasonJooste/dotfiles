#!/usr/bin/env bash
# Setup the environment according to a certain tier
# Tiers are cumulative: server implies core, personal implies server+core.
# Always safe to rerun: intended for re-syncing a machine with new settings,
# not just a one-time install.
#
# Usage: ./install.sh <core|server|personal>
set -euo pipefail

TIERS=(core server personal)
SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
BIN_DIR="$HOME/.local/bin"
# Tier scripts install tools here (e.g. nvim), and on a fresh machine it isn't on PATH until the next login
export PATH="$BIN_DIR:$PATH"
DOTFILES_STAGING="$SETUP_DIR/dotfiles"
OLD_DOTFILES_STAGING="$SETUP_DIR/old_dotfiles"

usage() {
    joined="${TIERS[*]}"
    echo "Usage: $0 <${joined// /|}>"
    exit 1
}

TARGET_TIER="${1:-}"
[[ " ${TIERS[*]} " == *" $TARGET_TIER "* ]] || usage

# Every run rebuilds dotfiles/ from scratch. The previous run's staged
# output is kept one generation back in old_dotfiles/, in case it's useful.
rm -rf "$OLD_DOTFILES_STAGING"
if [ -d "$DOTFILES_STAGING" ]; then
    mv "$DOTFILES_STAGING" "$OLD_DOTFILES_STAGING"
fi
mkdir -p "$DOTFILES_STAGING"

# For each file in <tier>/dotfiles/: assemble it into the local dotfiles/
# staging dir (never touched: the tracked <tier>/dotfiles/ source files
# themselves) — copy if no earlier tier already staged that filename this
# run, append if one did — then (re)symlink $HOME to the staged file. Target
# location honors that tier's own dotfile_locations, so files aren't just
# dumped in $HOME. Appending is only attempted for .vim, .sh, and
# no-extension (.bashrc-style) dotfiles, since anything else (e.g. .json)
# can't safely have text tacked onto the end of it.
apply_tier_dotfiles() {
    local tier="$1"
    local dotfiles_dir="$SETUP_DIR/$tier/dotfiles"
    [ -d "$dotfiles_dir" ] || return 0
    local locations_file="$dotfiles_dir/dotfile_locations"
    # For locations outside of home dir
    local -A not_home_paths
    if [ -f "$locations_file" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            not_home_paths["${line%% -> *}"]="${line#* -> }"
        done < "$locations_file"
    fi
    local f base staged target stripped
    for f in "$dotfiles_dir"/* "$dotfiles_dir"/.*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
	if [[ "$base" == dotfile_locations ]]; then continue; fi
	# Warn on temp file
        case "$base" in
            *.replay|*.un~|*.swp|*.swo) echo "$base appears to be a temporary file" >&2; continue ;;
        esac
        staged="$DOTFILES_STAGING/$base"
        target="$HOME/${not_home_paths[$base]:-$base}"
        mkdir -p "$(dirname "$target")"

        if [ ! -e "$staged" ]; then
            cp "$f" "$staged"
        else
            stripped="${base#.}"
            if [[ "$stripped" == *.* && "$base" != *.vim && "$base" != *.sh ]]; then
                echo "  SKIP: don't know how to append to $base safely (unsupported file type)" >&2
                continue
            fi
            cat "$f" >> "$staged"
        fi
        if [ ! -L "$target" ] && [ -e "$target" ]; then
            mkdir -p "$OLD_DOTFILES_STAGING"
            mv "$target" "$OLD_DOTFILES_STAGING/$base"
            echo "  WARNING: existing $target wasn't managed by this tool — moved to $OLD_DOTFILES_STAGING/$base" >&2
        fi
        ln -sf "$staged" "$target"
        echo "  assembled $base -> $target"
    done
}

for tier in "${TIERS[@]}"; do
    echo "[$tier] installing..."
    apply_tier_dotfiles "$tier"
    # Setup the helper scripts for each tier first, so the tier's install scripts can use them
    if [ -d "$SETUP_DIR/$tier/scripts" ]; then
        mkdir -p "$BIN_DIR"
        for file in "$SETUP_DIR/$tier/scripts"/*; do
            [ -f "$file" ] || continue
            name="$(basename "$file")"
            echo "  linking $name -> $BIN_DIR/${name%.*}"
            ln -sf "$file" "$BIN_DIR/${name%.*}"
        done
    fi
    mapfile -t install_scripts < <(find "$SETUP_DIR/$tier" -maxdepth 1 -name '*.sh' | sort)
    tier_failed=0
    # Run all tier install scripts
    for script in "${install_scripts[@]}"; do
        echo "  running $(basename "$script")"
        if bash "$script"; then
            :
        else
            code=$?
            echo "ERROR: $(basename "$script") exited with code $code" >&2
            tier_failed=1
        fi
    done
    if [ "$tier_failed" -eq 1 ]; then
        echo "[$tier] finished with errors" >&2
        exit 1
    fi
    echo "[$tier] done"
    [ "$tier" == "$TARGET_TIER" ] && break
done
