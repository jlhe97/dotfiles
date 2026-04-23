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
    ".slconfig"
)

# Directories to install (relative to dotfiles directory)
DIRS=(
    ".config/nvim"
    ".claude/skills"
    "bin"
)

install_ghostty() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if command -v ghostty &> /dev/null; then
        info "ghostty is already installed"
    else
        info "Installing ghostty..."
        if command -v apt &> /dev/null; then
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
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if command -v sl &> /dev/null; then
        info "sapling is already installed"
    else
        info "Installing sapling..."
        if command -v apt &> /dev/null || command -v dnf &> /dev/null; then
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

configure_git() {
    if ! command -v git &>/dev/null; then
        return 0
    fi

    local current_name current_email
    current_name="$(git config --global user.name 2>/dev/null || true)"
    current_email="$(git config --global user.email 2>/dev/null || true)"
    if [[ "$current_name" == "$1" && "$current_email" == "$2" ]]; then
        info "git identity already set: $1 <$2>"
        return 0
    fi
    git config --global user.name "$1"
    git config --global user.email "$2"
    info "git identity set to: $1 <$2>"
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

set_default_shell() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
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
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "oh-my-zsh is already installed"
    else
        info "Installing oh-my-zsh..."
        # Install oh-my-zsh without running zsh or modifying .zshrc
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        info "oh-my-zsh installed successfully"
    fi
}

install_via_brewfile() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if ! command -v brew &>/dev/null; then
        warn "Homebrew not found — install from https://brew.sh then re-run"
        return 1
    fi
    info "Installing packages via Brewfile..."
    brew bundle install --no-upgrade --file="$DOTFILES_DIR/Brewfile"
    info "Brewfile packages installed"
}

install_via_packagefile() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    local pkg_file install_cmd
    if command -v apt &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/apt.txt"
        install_cmd="sudo apt install -y"
        info "Updating apt..."
        sudo apt update
    elif command -v dnf &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/dnf.txt"
        install_cmd="sudo dnf install -y"
    elif command -v pacman &>/dev/null; then
        pkg_file="$DOTFILES_DIR/packages/pacman.txt"
        install_cmd="sudo pacman -S --noconfirm"
    else
        warn "No supported package manager found (apt/dnf/pacman)"
        return 1
    fi
    if [[ ! -f "$pkg_file" ]]; then
        warn "Package file not found: $pkg_file"
        return 1
    fi
    info "Installing packages from $(basename "$pkg_file")..."
    local pkg
    while IFS= read -r pkg || [[ -n "$pkg" ]]; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        $install_cmd "$pkg" || warn "failed to install $pkg — skipping"
    done < "$pkg_file"
    info "Package installation complete"
}

install_vim_plugins() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if ! command -v vim &>/dev/null; then
        return 0
    fi
    local plug_path="$HOME/.vim/autoload/plug.vim"
    if [[ ! -f "$plug_path" ]]; then
        info "Bootstrapping vim-plug..."
        curl -fLo "$plug_path" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    fi
    info "Installing vim plugins..."
    vim -es -u "$HOME/.vimrc" +"PlugInstall --sync" +qall
    info "vim plugins installed"
}

install_nvim_plugins() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if ! command -v nvim &>/dev/null; then
        return 0
    fi
    local plug_path="$HOME/.local/share/nvim/site/autoload/plug.vim"
    if [[ ! -f "$plug_path" ]]; then
        info "Bootstrapping vim-plug for nvim..."
        curl -fLo "$plug_path" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    fi
    info "Installing nvim plugins..."
    nvim --headless +"PlugInstall --sync" +qall 2>/dev/null
    info "nvim plugins installed"
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
        local backup_path
        backup_path="$BACKUP_DIR/$(basename "$dest")"
        info "Backing up existing $dest to $backup_path"
        mv "$dest" "$backup_path"
    fi

    ln -s "$src" "$dest"
    info "Linked $dest -> $src"
}

resolve_identity() {
    local local_rc="$DOTFILES_DIR/.neomutt/local.rc"
    local existing_name="" existing_email=""

    if [ -f "$local_rc" ]; then
        existing_name="$(grep 'real_name' "$local_rc" 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')"
        existing_email="$(grep 'imap_user' "$local_rc" 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')"
    fi

    # --name/--email flags take priority (CI-friendly, allows override)
    if [ -n "$USER_NAME" ] && [ -n "$USER_EMAIL" ]; then
        info "Using provided identity: $USER_NAME <$USER_EMAIL>"
        return 0
    fi

    # Reuse existing identity silently — no prompt needed
    if [ -n "$existing_name" ] && [ -n "$existing_email" ]; then
        info "Using existing identity: $existing_name <$existing_email>"
        USER_NAME="$existing_name"
        USER_EMAIL="$existing_email"
        return 0
    fi

    # No identity anywhere — must prompt interactively
    read -r -p "Enter your full name (e.g. Jane Smith): " USER_NAME
    echo ""
    read -r -p "Enter your email address: " USER_EMAIL
    echo ""
}

main() {
    USER_NAME=""
    USER_EMAIL=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                USER_NAME="${2:-}"
                shift 2
                ;;
            --email)
                USER_EMAIL="${2:-}"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                echo "Usage: $0 [--name 'Full Name'] [--email 'user@example.com']"
                exit 1
                ;;
        esac
    done

    if { [ -n "$USER_NAME" ] && [ -z "$USER_EMAIL" ]; } || \
       { [ -z "$USER_NAME" ] && [ -n "$USER_EMAIL" ]; }; then
        error "--name and --email must be used together"
        exit 1
    fi

    echo "=========================================="
    echo "       Dotfiles Installation Script      "
    echo "=========================================="
    echo ""
    info "Dotfiles directory: $DOTFILES_DIR"
    info "Home directory: $HOME"
    echo ""

    resolve_identity

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: declarative install via Brewfile (tmux, neovim, neomutt, sapling, b4, ghostty, zsh)
        install_via_brewfile || warn "Brewfile install incomplete — some packages may be missing"
        echo ""
    else
        # Linux: package list file (apt/dnf/pacman) for standard packages,
        # then individual functions for tools needing custom install steps
        install_via_packagefile || warn "some packages failed — check output above"
        echo ""
        install_sapling || true
        echo ""
        install_ghostty || true
        echo ""
    fi

    configure_git "$USER_NAME" "$USER_EMAIL" || true
    configure_sapling "$USER_NAME" "$USER_EMAIL" || true
    install_ohmyzsh || warn "oh-my-zsh installation failed — continuing without it"
    set_default_shell || warn "could not set default shell — run: chsh -s \$(which zsh)"
    echo ""

    # Create local override files if they don't exist (gitignored, machine-specific)
    if [ ! -f "$DOTFILES_DIR/.zshrc.local" ]; then
        touch "$DOTFILES_DIR/.zshrc.local"
        info "Created .zshrc.local (add machine-specific shell config here)"
    fi
    local local_rc="$DOTFILES_DIR/.neomutt/local.rc"
    if [ -f "$local_rc" ] && \
       grep -qF "set real_name = \"${USER_NAME}\"" "$local_rc" && \
       grep -qF "set imap_user = \"${USER_EMAIL}\"" "$local_rc"; then
        info "Identity in .neomutt/local.rc is already up to date"
    else
        {
            echo "set imap_user = \"$USER_EMAIL\""
            echo "set from = \"$USER_EMAIL\""
            echo "set real_name = \"$USER_NAME\""
            echo "set smtp_url = \"smtp://${USER_EMAIL}@smtp.fastmail.com:587/\""
        } > "$local_rc"
        info "Written .neomutt/local.rc with identity config for $USER_NAME <$USER_EMAIL>"
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

    # Plugin install runs after symlinks so ~/.config/nvim/init.lua exists
    install_vim_plugins  || warn "vim plugin install failed — run ':PlugInstall' in vim manually"
    install_nvim_plugins || warn "nvim plugin install failed — run ':PlugInstall' in nvim manually"

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
    echo "  - claude   (~/.claude/skills/)"
  echo "  - scripts  (~/bin/)"
    echo ""
    echo "Note: You may need to:"
    echo "  - Restart your terminal for zsh to take effect"
    echo "  - Run 'tmux source ~/.tmux.conf' to reload tmux config"
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
