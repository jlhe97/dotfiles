#!/bin/bash

# Dotfiles Uninstallation Script
# This script removes the symlinks created by install.sh

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Files and directories to uninstall
TARGETS=(
    "$HOME/.tmux.conf"
    "$HOME/.vimrc"
    "$HOME/.vimrc.plug"
    "$HOME/.config/nvim"
)

main() {
    echo "=========================================="
    echo "      Dotfiles Uninstallation Script     "
    echo "=========================================="
    echo ""

    for target in "${TARGETS[@]}"; do
        if [ -L "$target" ]; then
            # Check if symlink points to our dotfiles directory
            link_target="$(readlink "$target")"
            if [[ "$link_target" == "$DOTFILES_DIR"* ]]; then
                rm "$target"
                info "Removed symlink: $target"
            else
                warn "Skipping $target - symlink points elsewhere: $link_target"
            fi
        elif [ -e "$target" ]; then
            warn "Skipping $target - not a symlink (may be original file)"
        else
            warn "Skipping $target - does not exist"
        fi
    done

    echo ""
    echo "=========================================="
    info "Uninstallation complete!"
    echo ""
    echo "To restore backups, check ~/.dotfiles_backup_* directories"
    echo "=========================================="
}

main "$@"
