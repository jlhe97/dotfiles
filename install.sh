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
    ".zshrc"
    ".neomuttrc"
    ".neomutt/macos.rc"
    ".neomutt/linux.rc"
    ".neomutt/local.rc"
    ".zshrc.local"
    ".claude/settings.local.json"
)

# Directories to install (relative to dotfiles directory)
DIRS=(
    ".config/nvim"
    ".claude/skills"
)

install_tmux() {
    if command -v tmux &> /dev/null; then
        info "tmux is already installed"
    else
        info "Installing tmux..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y tmux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y tmux
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm tmux
        elif command -v brew &> /dev/null; then
            brew install tmux
        else
            error "Could not detect package manager. Please install tmux manually."
            exit 1
        fi
        info "tmux installed successfully"
    fi
}

install_neovim() {
    if command -v nvim &> /dev/null; then
        info "neovim is already installed"
    else
        info "Installing neovim..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y neovim
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y neovim
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm neovim
        elif command -v brew &> /dev/null; then
            brew install neovim
        else
            error "Could not detect package manager. Please install neovim manually."
            exit 1
        fi
        info "neovim installed successfully"
    fi
}

install_neomutt() {
    if command -v neomutt &> /dev/null; then
        info "neomutt is already installed"
    else
        info "Installing neomutt..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y neomutt
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y neomutt
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm neomutt
        elif command -v brew &> /dev/null; then
            brew install neomutt
        else
            error "Could not detect package manager. Please install neomutt manually."
            exit 1
        fi
        info "neomutt installed successfully"
    fi
}

install_ghostty() {
    if command -v ghostty &> /dev/null; then
        info "ghostty is already installed"
    else
        info "Installing ghostty..."
        if command -v brew &> /dev/null; then
            brew install ghostty
        elif command -v apt &> /dev/null; then
            # Add Ghostty apt repository for Debian/Ubuntu
            sudo apt update && sudo apt install -y curl gpg
            curl -fsSL https://pkg.ghostty.org/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/ghostty-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/ghostty-keyring.gpg] https://pkg.ghostty.org/apt stable main" | sudo tee /etc/apt/sources.list.d/ghostty.list
            sudo apt update && sudo apt install -y ghostty
        elif command -v dnf &> /dev/null; then
            sudo dnf copr enable -y pgdev/ghostty && sudo dnf install -y ghostty
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm ghostty
        else
            warn "Could not install ghostty. Install manually from https://ghostty.org"
            return 0
        fi

        if command -v ghostty &> /dev/null; then
            info "ghostty installed successfully"
        else
            warn "ghostty installation failed — skipping (optional dependency)"
        fi
    fi
}

install_sapling() {
    if command -v sl &> /dev/null; then
        info "sapling is already installed"
    else
        info "Installing sapling..."
        if command -v brew &> /dev/null; then
            brew install sapling
        elif command -v apt &> /dev/null || command -v dnf &> /dev/null; then
            local tmp_tar tarball_url
            tmp_tar="$(mktemp /tmp/sapling_XXXXXX.tar.xz)"
            tarball_url="$(curl -fsSL https://api.github.com/repos/facebook/sapling/releases/latest | grep -o 'https://[^"]*linux-x64\.tar\.xz' | head -1)"
            curl -fsSL "$tarball_url" -o "$tmp_tar"
            sudo mkdir -p /usr/local/lib/sapling
            sudo tar -xf "$tmp_tar" -C /usr/local/lib/sapling
            sudo ln -sf /usr/local/lib/sapling/sl /usr/local/bin/sl
            rm -f "$tmp_tar"
        elif command -v pacman &> /dev/null; then
            if command -v yay &> /dev/null; then
                yay -S --noconfirm sapling-scm-bin
            elif command -v paru &> /dev/null; then
                paru -S --noconfirm sapling-scm-bin
            else
                warn "Could not install sapling — install an AUR helper (yay/paru) then run: yay -S sapling-scm-bin"
                return 0
            fi
        else
            warn "Could not install sapling. Install manually from https://sapling-scm.com/docs/introduction/installation"
            return 0
        fi

        if command -v sl &> /dev/null; then
            info "sapling installed successfully"
        else
            warn "sapling installation failed — install manually from https://sapling-scm.com/docs/introduction/installation"
        fi
    fi
}

configure_sapling() {
    if ! command -v sl &> /dev/null; then
        return 0
    fi

    local current
    current="$(sl config ui.username 2>/dev/null || true)"
    if [ -n "$current" ]; then
        info "sapling identity already set: $current"
    else
        sl config --user ui.username "$1 <$2>"
        info "sapling identity set to: $1 <$2>"
    fi
}

install_zsh() {
    if command -v zsh &> /dev/null; then
        info "zsh is already installed"
    else
        info "Installing zsh..."
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y zsh
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zsh
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm zsh
        elif command -v brew &> /dev/null; then
            brew install zsh
        else
            error "Could not detect package manager. Please install zsh manually."
            exit 1
        fi
        info "zsh installed successfully"
    fi
}

set_default_shell() {
    local zsh_path
    zsh_path="$(which zsh)"

    if [ "$SHELL" = "$zsh_path" ]; then
        info "zsh is already the default shell"
    else
        info "Setting zsh as default shell..."
        if ! grep -q "$zsh_path" /etc/shells; then
            info "Adding $zsh_path to /etc/shells"
            echo "$zsh_path" | sudo tee -a /etc/shells
        fi
        if command -v chsh &> /dev/null; then
            chsh -s "$zsh_path"
            info "Default shell changed to zsh (restart your terminal to take effect)"
        else
            warn "chsh not found — change your default shell manually to $zsh_path"
        fi
    fi
}

install_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "oh-my-zsh is already installed"
    else
        info "Installing oh-my-zsh..."
        # Install oh-my-zsh without running zsh or modifying .zshrc
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        info "oh-my-zsh installed successfully"
    fi
}

backup_and_link() {
    local src="$1"
    local dest="$2"

    # Already points to the right place — nothing to do
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        return 0
    fi

    if [ -L "$dest" ]; then
        # Stale symlink pointing somewhere else — just replace it
        rm "$dest"
    elif [ -e "$dest" ]; then
        # Real file or directory — back it up
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(basename "$dest")"
        info "Backing up existing $dest to $backup_path"
        mv "$dest" "$backup_path"
    fi

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

    # Prompt for user identity
    read -r -p "Enter your full name (e.g. Jane Smith): " USER_NAME
    read -r -p "Enter your email address: " USER_EMAIL
    echo ""

    # Install tmux
    install_tmux
    echo ""

    # Install neovim
    install_neovim
    echo ""

    # Install neomutt
    install_neomutt
    echo ""

    # Install sapling
    install_sapling
    configure_sapling "$USER_NAME" "$USER_EMAIL"
    echo ""

    # Install ghostty (optional — may not be available on all platforms)
    install_ghostty || true
    echo ""

    # Install zsh and oh-my-zsh
    install_zsh
    install_ohmyzsh
    set_default_shell
    echo ""

    # Create local override files if they don't exist (gitignored, machine-specific)
    if [ ! -f "$DOTFILES_DIR/.zshrc.local" ]; then
        touch "$DOTFILES_DIR/.zshrc.local"
        info "Created .zshrc.local (add machine-specific shell config here)"
    fi
    if [ ! -f "$DOTFILES_DIR/.neomutt/local.rc" ]; then
        {
            echo "set imap_user = \"$USER_EMAIL\""
            echo "set from = \"$USER_EMAIL\""
            echo "set real_name = \"$USER_NAME\""
            echo "set smtp_url = \"smtp://${USER_EMAIL}@smtp.fastmail.com:587/\""
        } > "$DOTFILES_DIR/.neomutt/local.rc"
        info "Created .neomutt/local.rc with identity config for $USER_NAME <$USER_EMAIL>"
    fi

    # Install regular files
    for file in "${FILES[@]}"; do
        src="$DOTFILES_DIR/$file"
        dest="$HOME/$file"

        if [ -f "$src" ]; then
            mkdir -p "$(dirname "$dest")"
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
    echo "  - zsh      (~/.zshrc + oh-my-zsh)"
    echo "  - tmux     (~/.tmux.conf)"
    echo "  - vim      (~/.vimrc, ~/.vimrc.plug)"
    echo "  - neovim   (~/.config/nvim/)"
    echo "  - neomutt  (~/.neomuttrc, ~/.neomutt/)"
    echo "  - sapling  (vcs — sl)"
    echo "  - ghostty  (terminal emulator)"
    echo "  - claude   (~/.claude/settings.local.json, ~/.claude/skills/)"
    echo ""
    echo "Note: You may need to:"
    echo "  - Restart your terminal for zsh to take effect"
    echo "  - Run 'tmux source ~/.tmux.conf' to reload tmux config"
    echo "  - Run ':PlugInstall' in vim to install plugins"
    echo "  - Run ':PlugInstall' in neovim to install plugins"
    echo ""
    echo "=========================================="
    echo "       Fastmail Neomutt Setup            "
    echo "=========================================="
    echo ""
    echo "To configure neomutt with Fastmail:"
    echo ""
    echo "1. Generate an app-specific password:"
    echo "   - Go to https://www.fastmail.com/settings/security/tokens"
    echo "   - Click 'New App Password'"
    echo "   - Select 'Mail (IMAP/POP/SMTP)' access"
    echo "   - Copy the generated password"
    echo ""
    echo "2. Create the neomutt config directory:"
    echo "   mkdir -p ~/.neomutt"
    echo ""
    echo "3. Encrypt your password with GPG:"
    echo "   # If you don't have a GPG key, generate one first:"
    echo "   gpg --full-generate-key"
    echo ""
    echo "   # Encrypt your app password:"
    echo "   echo 'YOUR_APP_PASSWORD' | gpg --encrypt -r $USER_EMAIL -o ~/.neomutt/fastmail_pass.gpg"
    echo ""
    echo "   # Verify it works:"
    echo "   gpg --quiet --decrypt ~/.neomutt/fastmail_pass.gpg"
    echo ""
    echo "4. Your identity has been written to ~/.neomutt/local.rc:"
    echo "   set imap_user = '$USER_EMAIL'"
    echo "   set from = '$USER_EMAIL'"
    echo "   set real_name = '$USER_NAME'"
    echo "   set smtp_url = 'smtp://${USER_EMAIL}@smtp.fastmail.com:587/'"
    echo ""
    echo "=========================================="
}

# Run main function
main "$@"
