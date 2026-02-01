#!/bin/bash

# Dotfiles Installation Script
# This script creates symlinks from $HOME to the dotfiles in this repository

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Files to install (relative to dotfiles directory)
FILES=(
    ".tmux.conf"
    ".vimrc"
    ".vimrc.plug"
)

# Directories to install (relative to dotfiles directory)
DIRS=(
    ".config/nvim"
)

backup_and_link() {
    local src="$1"
    local dest="$2"

    # If destination exists (file, directory, or symlink)
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        # Create backup directory if it doesn't exist
        mkdir -p "$BACKUP_DIR"

        # Move existing file/dir to backup
        local backup_path="$BACKUP_DIR/$(basename "$dest")"
        info "Backing up existing $dest to $backup_path"
        mv "$dest" "$backup_path"
    fi

    # Create symlink
    ln -s "$src" "$dest"
    info "Linked $dest -> $src"
}

main() {
    echo "=========================================="
    echo "       Dotfiles Installation Script      "
    echo "=========================================="
    echo ""
    info "Dotfiles directory: $DOTFILES_DIR"
    info "Home directory: $HOME"
    echo ""

    # Install regular files
    for file in "${FILES[@]}"; do
        src="$DOTFILES_DIR/$file"
        dest="$HOME/$file"

        if [ -f "$src" ]; then
            backup_and_link "$src" "$dest"
        else
            warn "Source file not found: $src"
        fi
    done

    # Install directories
    for dir in "${DIRS[@]}"; do
        src="$DOTFILES_DIR/$dir"
        dest="$HOME/$dir"

        if [ -d "$src" ]; then
            # Ensure parent directory exists
            mkdir -p "$(dirname "$dest")"
            backup_and_link "$src" "$dest"
        else
            warn "Source directory not found: $src"
        fi
    done

    echo ""
    echo "=========================================="
    info "Installation complete!"

    if [ -d "$BACKUP_DIR" ]; then
        info "Backups saved to: $BACKUP_DIR"
    fi

    echo ""
    echo "Installed configurations:"
    echo "  - tmux     (~/.tmux.conf)"
    echo "  - vim      (~/.vimrc, ~/.vimrc.plug)"
    echo "  - neovim   (~/.config/nvim/)"
    echo ""
    echo "Note: You may need to:"
    echo "  - Run 'tmux source ~/.tmux.conf' to reload tmux config"
    echo "  - Run ':PlugInstall' in vim to install plugins"
    echo "  - Run ':PlugInstall' in neovim to install plugins"
    echo "=========================================="
}

# Run main function
main "$@"
