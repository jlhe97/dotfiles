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

# curl that works on locked-down work machines, where direct egress to github
# is blocked and external traffic goes through a forward proxy (with
# raw.githubusercontent.com allowlisted through it). Prefer the proxy when the
# host ships a config helper for it, and fall back to a direct call for
# laptops / unrestricted boxes.
proxy_curl() {
    if command -v fwdproxy-config &>/dev/null; then
        # fwdproxy-config emits the right -x/cert flags for this host.
        # shellcheck disable=SC2046
        curl $(fwdproxy-config curl 2>/dev/null) "$@" && return 0
        curl -x fwdproxy:8080 "$@" && return 0
    fi
    curl "$@"
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
    ".mbsyncrc"
    ".notmuch-config"
    ".zshrc.local"
    ".slconfig"
)

# Directories to install (relative to dotfiles directory)
DIRS=(
    ".config/nvim"
    ".config/clangd"
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

# The nvim config requires 0.8+ (see the guard at the top of .config/nvim/init.lua).
# Distro packages lag badly -- Ubuntu 22.04 still ships 0.6 -- so a plain
# `apt install neovim` leaves a broken editor behind: the symlinks all land, then
# init.lua aborts on the first 0.8-only call. Check what the package manager
# actually gave us and top it up from the upstream release when it falls short.
nvim_meets_minimum() {
    command -v nvim &>/dev/null || return 1
    # -u NONE matters: init.lua deliberately errors out on old nvim, so loading
    # it here would make the check fail for the wrong reason (or hang on a
    # prompt). has() is the same test the config itself uses.
    local answer
    answer="$(nvim -u NONE --headless -c 'lua io.write(vim.fn.has("nvim-0.8"))' -c 'qa' 2>/dev/null)"
    [[ "$answer" == "1" ]]
}

install_neovim() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if nvim_meets_minimum; then
        info "neovim is new enough ($(nvim --version | head -1))"
        return 0
    fi

    local arch asset
    arch="$(uname -m)"
    case "$arch" in
        x86_64)         asset='nvim-linux(64|-x86_64)\.tar\.gz' ;;
        aarch64|arm64)  asset='nvim-linux-arm64\.tar\.gz' ;;
        *)
            warn "no upstream neovim build for $arch — install 0.8+ manually from https://github.com/neovim/neovim/releases"
            return 0
            ;;
    esac

    info "neovim is missing or older than 0.8 — installing the upstream release..."
    local tmp_tar tarball_url
    tmp_tar="$(mktemp /tmp/neovim_XXXXXX.tar.gz)"
    # Asset names have changed across releases (nvim-linux64 -> nvim-linux-x86_64),
    # so resolve the current one from the release metadata rather than hardcoding.
    tarball_url="$(proxy_curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
        | grep -oE "https://[^\"]*${asset}" | head -1)"
    if [[ -z "$tarball_url" ]]; then
        warn "could not find an upstream neovim tarball for $arch — install 0.8+ manually"
        rm -f "$tmp_tar"
        return 0
    fi
    proxy_curl -fsSL "$tarball_url" -o "$tmp_tar"
    # Replace any previous upstream install rather than layering a new release
    # over it; stale files in share/nvim/runtime confuse the new binary.
    sudo rm -rf /usr/local/lib/nvim
    sudo mkdir -p /usr/local/lib/nvim
    # --strip-components=1 flattens the versioned top-level dir, so the symlink
    # target below stays stable. nvim resolves its runtime relative to the real
    # binary, so linking bin/nvim into PATH is enough to find share/nvim/runtime.
    sudo tar -xzf "$tmp_tar" -C /usr/local/lib/nvim --strip-components=1
    sudo ln -sf /usr/local/lib/nvim/bin/nvim /usr/local/bin/nvim
    rm -f "$tmp_tar"

    # hash -r: the shell may have cached the old /usr/bin/nvim from earlier steps.
    hash -r 2>/dev/null || true
    if nvim_meets_minimum; then
        info "neovim installed successfully ($(nvim --version | head -1))"
    else
        warn "neovim is still older than 0.8 after install — check that /usr/local/bin precedes /usr/bin in PATH"
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
    zsh_path="$(command -v zsh)"

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
    # compiledb is the macOS bear-equivalent (bear itself is broken under SIP);
    # it has no brew formula, so install it via pipx.
    if command -v pipx &>/dev/null; then
        info "Installing compiledb via pipx..."
        pipx install compiledb || warn "compiledb install failed — run 'pipx install compiledb' manually"
    else
        warn "pipx not found — skipping compiledb (run 'brew install pipx && pipx install compiledb')"
    fi
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
        # </dev/null is load-bearing. The loop reads the package list on stdin,
        # and a package manager that reads stdin itself consumes the rest of it
        # in one go -- the next `read` then sees EOF and the loop ends early,
        # silently, with no warning, because nothing failed. Every remaining
        # package is simply never attempted. Detaching the command's stdin
        # keeps the list intact no matter what the package manager does with it.
        $install_cmd "$pkg" </dev/null || warn "failed to install $pkg — skipping"
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
        proxy_curl -fLo "$plug_path" --create-dirs \
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
        proxy_curl -fLo "$plug_path" --create-dirs \
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

# Echo a `set ssl_ca_certificates_file` line for local.rc ONLY when neomutt is a
# GnuTLS build (Debian/Ubuntu). OpenSSL builds (Fedora/RHEL, macOS) reject the
# option and use the system trust store automatically. Always returns 0.
neomutt_ca_line() {
    command -v neomutt &>/dev/null || return 0
    neomutt -v 2>/dev/null | grep -qi gnutls || return 0
    local f
    for f in /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt \
             /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        if [ -f "$f" ]; then
            echo "set ssl_ca_certificates_file = \"$f\""
            return 0
        fi
    done
    return 0
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

    # neomutt header cache dir (speeds up opening large notmuch vfolders)
    mkdir -p "$HOME/.cache/neomutt"

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: declarative install via Brewfile (tmux, neovim, neomutt, sapling, b4, ghostty, zsh)
        install_via_brewfile || warn "Brewfile install incomplete — some packages may be missing"
        echo ""
    else
        # Linux: package list file (apt/dnf/pacman) for standard packages,
        # then individual functions for tools needing custom install steps
        install_via_packagefile || warn "some packages failed — check output above"
        echo ""
        # After the package file, so it can top up a too-old distro neovim, and
        # before install_nvim_plugins, which runs the config to install plugins.
        install_neovim || warn "neovim install incomplete — the nvim config needs 0.8+"
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
       grep -qF "set imap_user = \"${USER_EMAIL}\"" "$local_rc" && \
       grep -qF "set nm_default_url = " "$local_rc"; then
        info "Identity in .neomutt/local.rc is already up to date"
    else
        local ca_line
        ca_line="$(neomutt_ca_line)"
        {
            echo "set imap_user = \"$USER_EMAIL\""
            echo "set from = \"$USER_EMAIL\""
            echo "set real_name = \"$USER_NAME\""
            echo "set smtp_url = \"smtp://${USER_EMAIL}@smtp.fastmail.com:587/\""
            echo "set nm_default_url = \"notmuch://$HOME/Mail/fastmail\""
            if [ -n "$ca_line" ]; then echo "$ca_line"; fi
        } > "$local_rc"
        info "Written .neomutt/local.rc with identity config for $USER_NAME <$USER_EMAIL>"
    fi

    # Generate ~/.mbsyncrc (gitignored; contains email). Password comes from
    # bin/mail-pass at sync time, so nothing secret is written here.
    local mbsyncrc="$DOTFILES_DIR/.mbsyncrc"
    {
        echo "IMAPAccount fastmail"
        echo "Host imap.fastmail.com"
        echo "Port 993"
        echo "User $USER_EMAIL"
        echo "PassCmd \"\$HOME/bin/mail-pass\""
        echo "TLSType IMAPS"
        echo "AuthMechs LOGIN"
        echo ""
        echo "IMAPStore fastmail-remote"
        echo "Account fastmail"
        echo ""
        echo "MaildirStore fastmail-local"
        echo "Path ~/Mail/fastmail/"
        echo "Inbox ~/Mail/fastmail/INBOX"
        echo "Subfolders Verbatim"
        echo ""
        echo "Channel fastmail"
        echo "Far :fastmail-remote:"
        echo "Near :fastmail-local:"
        echo "Patterns *"
        echo "Create Both"
        echo "Expunge Both"
        echo "SyncState *"
    } > "$mbsyncrc"
    info "Written .mbsyncrc for $USER_EMAIL"

    # Generate ~/.notmuch-config (gitignored; contains identity).
    local notmuch_config="$DOTFILES_DIR/.notmuch-config"
    {
        echo "[database]"
        echo "path=$HOME/Mail/fastmail"
        echo ""
        echo "[user]"
        echo "name=$USER_NAME"
        echo "primary_email=$USER_EMAIL"
        echo ""
        echo "[new]"
        echo "tags=unread;inbox;"
        echo "ignore="
        echo ""
        echo "[search]"
        echo "exclude_tags=deleted;spam;"
        echo ""
        echo "[maildir]"
        echo "synchronize_flags=true"
    } > "$notmuch_config"
    info "Written .notmuch-config for $USER_NAME <$USER_EMAIL>"

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
    echo "       Fastmail Mail Setup (mbsync + notmuch)"
    echo "=========================================="
    echo ""
    echo "Mail syncs locally with mbsync and is indexed by notmuch; neomutt"
    echo "reads the local database. Finish setup on this machine:"
    echo ""
    echo "1. Generate a Fastmail app-specific password:"
    echo "   - https://www.fastmail.com/settings/security/tokens"
    echo "   - 'New App Password' -> 'Mail (IMAP/POP/SMTP)'"
    echo ""
    echo "2. Store it in your OS secret store (read by bin/mail-pass):"
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "   security add-generic-password -s fastmail-imap -a $USER_EMAIL -w"
    else
        echo "   secret-tool store --label=fastmail-imap service fastmail-imap"
        echo "   # or, if you use pass:  pass insert fastmail-imap"
    fi
    echo ""
    echo "3. Do the initial sync + index (first pull can be slow):"
    echo "   mail-sync        # runs: mbsync -a && notmuch new"
    echo ""
    echo "4. Launch neomutt (the 'mutt' wrapper syncs first, then opens neomutt)."
    echo "   Identity was written to ~/.neomutt/local.rc; mbsync/notmuch config"
    echo "   to ~/.mbsyncrc and ~/.notmuch-config."
    echo ""
    echo "=========================================="
}

# Run main function
main "$@"
