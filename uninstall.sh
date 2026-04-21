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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Files and directories to uninstall
TARGETS=(
    "$HOME/.tmux.conf"
    "$HOME/.vimrc"
    "$HOME/.vimrc.plug"
    "$HOME/.config/nvim"
    "$HOME/.zshrc"
    "$HOME/.neomuttrc"
    "$HOME/.slconfig"
    "$HOME/.neomutt/macos.rc"
    "$HOME/.neomutt/linux.rc"
    "$HOME/.claude/skills"
)

uninstall_via_packagefile() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    local pkg_file remove_cmd
    if command -v apt &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/apt.txt"
        remove_cmd="sudo apt remove -y"
    elif command -v dnf &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/dnf.txt"
        remove_cmd="sudo dnf remove -y"
    elif command -v pacman &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/pacman.txt"
        remove_cmd="sudo pacman -Rs --noconfirm"
    else
        warn "No supported package manager found (apt/dnf/pacman)"
        return 1
    fi
    if [[ ! -f "$pkg_file" ]]; then
        warn "Package file not found: $pkg_file"
        return 1
    fi
    info "Removing packages from $(basename "$pkg_file")..."
    local pkg
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        $remove_cmd "$pkg" || warn "failed to remove $pkg — skipping"
    done < "$pkg_file"
    info "Package removal complete"
}

uninstall_ghostty() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if command -v ghostty &> /dev/null; then
        info "Uninstalling ghostty..."
        if command -v brew &> /dev/null; then
            brew uninstall ghostty
        elif command -v apt &> /dev/null; then
            sudo apt remove -y ghostty
            # Optionally remove the repository
            sudo rm -f /etc/apt/sources.list.d/ghostty.list
            sudo rm -f /usr/share/keyrings/ghostty-keyring.gpg
        elif command -v dnf &> /dev/null; then
            sudo dnf remove -y ghostty
        elif command -v pacman &> /dev/null; then
            sudo pacman -Rs --noconfirm ghostty
        else
            warn "Could not detect package manager. Please uninstall ghostty manually."
            return 1
        fi
        info "ghostty uninstalled"
    else
        info "ghostty is not installed"
    fi
}

uninstall_ohmyzsh() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Removing oh-my-zsh..."
        rm -rf "$HOME/.oh-my-zsh"
        info "oh-my-zsh removed"
    else
        info "oh-my-zsh is not installed"
    fi
}

restore_default_shell() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
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

main() {
    local skip_packages=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-packages)
                skip_packages=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                echo "Usage: $0 [--skip-packages]"
                exit 1
                ;;
        esac
    done

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

    if [ "$skip_packages" = true ]; then
        info "Skipping package uninstallation (--skip-packages)"
    else
        read -p "Do you want to uninstall packages (tmux, neovim, neomutt, ghostty, zsh, oh-my-zsh)? [y/N] " -n 1 -r
        echo ""
    fi

    if [ "$skip_packages" = false ] && [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        uninstall_via_packagefile || warn "package removal incomplete — check output above"
        echo ""
        uninstall_ghostty || warn "ghostty uninstallation failed — remove manually"
        echo ""
        uninstall_ohmyzsh || warn "oh-my-zsh removal failed — remove manually"
        echo ""
        restore_default_shell || warn "could not restore default shell — run: chsh -s \$(which bash)"
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
