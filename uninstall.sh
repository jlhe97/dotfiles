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
    "$HOME/.zshrc"
    "$HOME/.neomuttrc"
)

uninstall_tmux() {
    if command -v tmux &> /dev/null; then
        info "Uninstalling tmux..."
        if command -v apt &> /dev/null; then
            sudo apt remove -y tmux
        elif command -v dnf &> /dev/null; then
            sudo dnf remove -y tmux
        elif command -v pacman &> /dev/null; then
            sudo pacman -Rs --noconfirm tmux
        elif command -v brew &> /dev/null; then
            brew uninstall tmux
        else
            warn "Could not detect package manager. Please uninstall tmux manually."
        fi
        info "tmux uninstalled"
    else
        info "tmux is not installed"
    fi
}

uninstall_neovim() {
    if command -v nvim &> /dev/null; then
        info "Uninstalling neovim..."
        if command -v apt &> /dev/null; then
            sudo apt remove -y neovim
        elif command -v dnf &> /dev/null; then
            sudo dnf remove -y neovim
        elif command -v pacman &> /dev/null; then
            sudo pacman -Rs --noconfirm neovim
        elif command -v brew &> /dev/null; then
            brew uninstall neovim
        else
            warn "Could not detect package manager. Please uninstall neovim manually."
        fi
        info "neovim uninstalled"
    else
        info "neovim is not installed"
    fi
}

uninstall_neomutt() {
    if command -v neomutt &> /dev/null; then
        info "Uninstalling neomutt..."
        if command -v apt &> /dev/null; then
            sudo apt remove -y neomutt
        elif command -v dnf &> /dev/null; then
            sudo dnf remove -y neomutt
        elif command -v pacman &> /dev/null; then
            sudo pacman -Rs --noconfirm neomutt
        elif command -v brew &> /dev/null; then
            brew uninstall neomutt
        else
            warn "Could not detect package manager. Please uninstall neomutt manually."
        fi
        info "neomutt uninstalled"
    else
        info "neomutt is not installed"
    fi
}

uninstall_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Removing oh-my-zsh..."
        rm -rf "$HOME/.oh-my-zsh"
        info "oh-my-zsh removed"
    else
        info "oh-my-zsh is not installed"
    fi
}

restore_default_shell() {
    local bash_path
    bash_path="$(which bash)"

    if [ "$SHELL" != "$bash_path" ]; then
        info "Restoring bash as default shell..."
        chsh -s "$bash_path"
        info "Default shell changed to bash (restart your terminal to take effect)"
    else
        info "bash is already the default shell"
    fi
}

uninstall_zsh() {
    if command -v zsh &> /dev/null; then
        info "Uninstalling zsh..."
        if command -v apt &> /dev/null; then
            sudo apt remove -y zsh
        elif command -v dnf &> /dev/null; then
            sudo dnf remove -y zsh
        elif command -v pacman &> /dev/null; then
            sudo pacman -Rs --noconfirm zsh
        elif command -v brew &> /dev/null; then
            brew uninstall zsh
        else
            warn "Could not detect package manager. Please uninstall zsh manually."
        fi
        info "zsh uninstalled"
    else
        info "zsh is not installed"
    fi
}

main() {
    echo "=========================================="
    echo "      Dotfiles Uninstallation Script     "
    echo "=========================================="
    echo ""

    # Remove symlinks
    info "Removing symlinks..."
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

    # Ask about uninstalling packages
    read -p "Do you want to uninstall packages (tmux, neovim, neomutt, zsh, oh-my-zsh)? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        uninstall_tmux
        echo ""
        uninstall_neovim
        echo ""
        uninstall_neomutt
        echo ""
        uninstall_ohmyzsh
        echo ""
        restore_default_shell
        echo ""
        uninstall_zsh
    else
        info "Skipping package uninstallation"
    fi

    echo ""
    echo "=========================================="
    info "Uninstallation complete!"
    echo ""
    echo "To restore backups, check ~/.dotfiles_backup_* directories"
    echo "=========================================="
}

main "$@"
