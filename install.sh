#!/bin/bash

# Dotfiles Installation Script
# Symlinks committed files into $HOME; generates machine-specific ones there.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

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

# shellcheck source=/dev/null
[ -f "$DOTFILES_DIR/install.local" ] && . "$DOTFILES_DIR/install.local"

MAIL_PROVIDER_FILE="${MAIL_PROVIDER_FILE:-$DOTFILES_DIR/bin/mail-provider}"
# shellcheck source=/dev/null
. "$MAIL_PROVIDER_FILE"

http_connect_proxy() {
    local p="${PROXY_HOST_PORT:-}"
    [ -z "$p" ] && p="$(git config --global --get http.proxy 2>/dev/null || true)"
    [ -z "$p" ] && p="${https_proxy:-${http_proxy:-}}"
    [ -z "$p" ] && return 1
    p="${p#*://}"
    echo "${p%/}"
}

proxy_curl() {
    local proxy
    if [ -n "${PROXY_CURL_ARGS_CMD:-}" ] && \
       command -v "${PROXY_CURL_ARGS_CMD%% *}" &>/dev/null; then
        # shellcheck disable=SC2046
        curl $($PROXY_CURL_ARGS_CMD 2>/dev/null) "$@" && return 0
    fi
    if proxy="$(http_connect_proxy)"; then
        curl -x "$proxy" "$@" && return 0
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
    ".gnupg/gpg.conf"
    ".slconfig"
    ".ripgreprc"
)

# Never symlinked: a $HOME backup captures a symlink, not what it points at.
GENERATED=(
    "$HOME/.zshrc.local"
    "$HOME/.neomutt/local.rc"
    "$HOME/.mbsyncrc"
    "$HOME/.notmuch-config"
    "$HOME/.signature"
    "$HOME/.gnupg/gpg-agent.conf"
)

# Directories to install (relative to dotfiles directory)
DIRS=(
    ".config/nvim"
    ".config/clangd"
    "bin"
)

install_ghostty() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    if command -v ghostty &> /dev/null; then
        info "ghostty is already installed"
    else
        info "Installing ghostty..."
        if command -v apt &> /dev/null; then
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

# init.lua requires nvim 0.8+; Ubuntu 22.04 still ships 0.6.
nvim_meets_minimum() {
    command -v nvim &>/dev/null || return 1
    # -u NONE: init.lua errors out on old nvim, failing this for the wrong reason.
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
    # Asset names churn across releases (nvim-linux64 -> nvim-linux-x86_64).
    tarball_url="$(proxy_curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
        | grep -oE "https://[^\"]*${asset}" | head -1)"
    if [[ -z "$tarball_url" ]]; then
        warn "could not find an upstream neovim tarball for $arch — install 0.8+ manually"
        rm -f "$tmp_tar"
        return 0
    fi
    proxy_curl -fsSL "$tarball_url" -o "$tmp_tar"
    # Stale files in share/nvim/runtime confuse a newer binary.
    sudo rm -rf /usr/local/lib/nvim
    sudo mkdir -p /usr/local/lib/nvim
    # --strip-components=1 flattens the versioned dir so the link target is stable.
    sudo tar -xzf "$tmp_tar" -C /usr/local/lib/nvim --strip-components=1
    sudo ln -sf /usr/local/lib/nvim/bin/nvim /usr/local/bin/nvim

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

# The only OS-specific piece of the GnuPG setup, hence gpg-agent.conf being
# per-machine. Curses is the only prompt that works over ssh and headless, and
# it needs GPG_TTY, which .zshrc exports.
pinentry_program() {
    local candidates c
    if [[ "$(uname)" == "Darwin" ]]; then
        candidates=(pinentry-mac pinentry-curses pinentry)
    elif [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
        candidates=(pinentry-gnome3 pinentry-gtk-2 pinentry-qt pinentry-curses pinentry)
    else
        candidates=(pinentry-curses pinentry-tty pinentry)
    fi

    for c in "${candidates[@]}"; do
        if command -v "$c" &>/dev/null; then
            command -v "$c"
            return 0
        fi
    done
    return 1
}

configure_gnupg() {
    local gnupg_home="$HOME/.gnupg"
    # gpg refuses a homedir others can read; the FILES loop would create it 0755.
    mkdir -p "$gnupg_home"
    chmod 700 "$gnupg_home"

    local agent_conf="$gnupg_home/gpg-agent.conf"
    materialize_local_file "$agent_conf"

    local pinentry
    pinentry="$(pinentry_program || true)"
    if [ -z "$pinentry" ]; then
        warn "no pinentry binary found — gpg cannot prompt for a passphrase here"
        warn "  install pinentry-mac (macOS) or pinentry-curses (Linux), then re-run"
    fi

    local desired
    desired="$(
        echo "# Generated by install.sh — machine-specific, not committed."
        echo "# Shared GnuPG options live in gpg.conf; only the pinentry differs per host."
        if [ -n "$pinentry" ]; then
            echo "pinentry-program $pinentry"
        fi
        # One patch series without re-prompting, still expiring within the day.
        echo "default-cache-ttl 3600"
        echo "max-cache-ttl 28800"
    )"

    if [ -f "$agent_conf" ] && [ "$(cat "$agent_conf")" = "$desired" ]; then
        info "gpg-agent.conf is already up to date (pinentry: ${pinentry:-none})"
        return 0
    fi

    printf '%s\n' "$desired" > "$agent_conf"
    info "Written ~/.gnupg/gpg-agent.conf (pinentry: ${pinentry:-none})"

    # Only if an agent is running: gpgconf --reload would otherwise spawn one.
    if command -v gpgconf &>/dev/null; then
        local sock
        sock="$(gpgconf --list-dirs agent-socket 2>/dev/null || true)"
        if [ -n "$sock" ] && [ -S "$sock" ]; then
            gpgconf --reload gpg-agent 2>/dev/null || true
            info "Reloaded the running gpg-agent"
        fi
    fi
}

# Empty when this machine holds no signing key for $1. All signing config keys
# off this, which is what makes install.sh safe to run in a container.
signing_key_fingerprint() {
    command -v gpg &>/dev/null || return 0
    # --with-colons is the only stable output format; fpr field 10 is the print.
    gpg --list-secret-keys --with-colons "$1" 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10; exit }' || true
}

# b4 signs through patatt. The "openpgp:" prefix makes patatt sign via gpg
# instead of writing its own unencrypted ed25519 file into $HOME.
configure_patch_signing() {
    local email="$1" fpr existing

    fpr="$(signing_key_fingerprint "$email")"
    if [ -z "$fpr" ]; then
        info "no OpenPGP secret key for <$email> — leaving patch signing off"
        info "  to enable: gpg-setup --import <file> && gpg-setup --enable-signing"
        return 0
    fi

    # Never clobber a deliberate choice: a work key, a hardware token.
    existing="$(git config --global --get user.signingKey 2>/dev/null || true)"
    if [ -n "$existing" ] && [ "$existing" != "$fpr" ]; then
        warn "user.signingKey is already set to $existing — leaving it alone"
    else
        git config --global user.signingKey "$fpr"
    fi

    existing="$(git config --global --get patatt.signingkey 2>/dev/null || true)"
    if [ -n "$existing" ] && [ "$existing" != "openpgp:$fpr" ]; then
        warn "patatt.signingkey is already set to $existing — leaving it alone"
    else
        git config --global patatt.signingkey "openpgp:$fpr"
    fi

    # Historical opt-out, set while the key was unpublished. It is published now.
    if [ -n "$(git config --global --get b4.send-no-patatt-sign 2>/dev/null || true)" ]; then
        git config --global --unset-all b4.send-no-patatt-sign 2>/dev/null || true
        info "cleared b4.send-no-patatt-sign — b4 will sign again"
    fi

    # commit.gpgsign deliberately NOT set: signing every commit on the machine
    # is a different decision from signing patches mailed to a list.
    info "patch signing enabled with OpenPGP key $fpr"
}

# Every step is skip-and-warn: a devserver with centrally managed git config
# must not fail the whole install.
configure_patch_workflow() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    command -v git &>/dev/null || return 0

    local email="$1"

    if [ "${MAIL_MODE:-direct}" = bridge ]; then
        git config --global sendemail.smtpserver "$(command -v msmtp || echo /usr/bin/msmtp)"
        git config --global --unset sendemail.smtpserverport 2>/dev/null || true
        git config --global --unset sendemail.smtpencryption 2>/dev/null || true
        git config --global --unset sendemail.smtpuser 2>/dev/null || true
    else
        git config --global sendemail.smtpserver     "$MAIL_SMTP_HOST"
        git config --global sendemail.smtpserverport "587"
        git config --global sendemail.smtpencryption "tls"
        git config --global sendemail.smtpuser       "$email"
    fi

    # Must stay unset: b4 only falls back to `git credential fill`, and so to
    # bin/mail-pass, when this is empty.
    if [ -n "$(git config --global --get sendemail.smtppass 2>/dev/null || true)" ]; then
        git config --global --unset-all sendemail.smtppass 2>/dev/null || true
        warn "removed sendemail.smtppass — the password comes from bin/mail-pass"
    fi

    # URL-scoped so the machine's normal helper still serves GitHub. The empty
    # first value resets anything inherited from a broader scope. Single-quoted:
    # $1 and $HOME must reach git's config file unexpanded.
    local scope="credential.smtp://$MAIL_SMTP_HOST:$MAIL_SMTP_PORT.helper"
    # shellcheck disable=SC2016  # not expanding is the whole point: git stores this verbatim
    local helper='!f() { test "$1" = get && echo "password=$($HOME/bin/mail-pass)"; }; f'
    local current expected
    current="$(git config --global --get-all "$scope" 2>/dev/null || true)"
    expected="$(printf '\n%s' "$helper")"
    if [ "$current" = "$expected" ]; then
        info "SMTP credential helper is already configured"
    else
        git config --global --unset-all "$scope" 2>/dev/null || true
        git config --global --add "$scope" ""
        git config --global --add "$scope" "$helper"
        info "SMTP credential helper points at bin/mail-pass"
    fi

    configure_patch_signing "$email"
}

set_default_shell() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR
    local zsh_path
    zsh_path="$(command -v zsh)"

    if [ "${SHELL:-}" = "$zsh_path" ]; then
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
    # bear is broken under SIP; compiledb replaces it and has no brew formula.
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
        # </dev/null is load-bearing: a package manager that reads stdin eats
        # the rest of the list and the loop ends early, silently.
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
    nvim --headless +"PlugInstall --sync" +qall
    info "nvim plugins installed"
}

backup_and_link() {
    local src="$1"
    local dest="$2"

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        return 0
    fi

    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path
        backup_path="$BACKUP_DIR/$(basename "$dest")"
        info "Backing up existing $dest to $backup_path"
        mv "$dest" "$backup_path"
    fi

    ln -s "$src" "$dest"
    info "Linked $dest -> $src"
}

# Must run before the generation code below, which would otherwise write
# through a leftover symlink and silently edit $DOTFILES_DIR instead of $HOME.
materialize_local_file() {
    local dest="$1" link_target

    [ -L "$dest" ] || return 0
    link_target="$(readlink "$dest")"
    [[ "$link_target" == "$DOTFILES_DIR"* ]] || return 0

    if [ -f "$link_target" ]; then
        local tmp
        tmp="$(mktemp "${dest}.XXXXXX")"
        cat "$link_target" > "$tmp"
        mv -f "$tmp" "$dest"
        info "Migrated $dest from a repo symlink to a real file"
    else
        rm -f "$dest"
        info "Removed dangling repo symlink: $dest"
    fi
}

resolve_identity() {
    local local_rc="$HOME/.neomutt/local.rc"
    local existing_name="" existing_email=""

    if [ -f "$local_rc" ]; then
        existing_name="$(sed -n '/real_name/s/.*= *"\(.*\)"/\1/p' "$local_rc")"
        existing_email="$(sed -n '/imap_user/s/.*= *"\(.*\)"/\1/p' "$local_rc")"
    fi

    if [ -n "$USER_NAME" ] && [ -n "$USER_EMAIL" ]; then
        info "Using provided identity: $USER_NAME <$USER_EMAIL>"
        return 0
    fi

    if [ -n "$existing_name" ] && [ -n "$existing_email" ]; then
        info "Using existing identity: $existing_name <$existing_email>"
        USER_NAME="$existing_name"
        USER_EMAIL="$existing_email"
        return 0
    fi

    read -r -p "Enter your full name (e.g. Jane Smith): " USER_NAME
    echo ""
    read -r -p "Enter your email address: " USER_EMAIL
    echo ""
}

# GnuTLS builds only. OpenSSL builds reject the option and use the system
# trust store. Always returns 0.
neomutt_ca_line() {
    command -v neomutt &>/dev/null || return 0
    neomutt -v 2>/dev/null | grep -i '+gnutls' >/dev/null || return 0
    local f
    f="$(ca_bundle_file)" || return 0
    echo "set ssl_ca_certificates_file = \"$f\""
}

ca_bundle_file() {
    local f d
    if [ -n "${CA_BUNDLE_FILE:-}" ] && [ -f "$CA_BUNDLE_FILE" ]; then
        echo "$CA_BUNDLE_FILE"
        return 0
    fi
    for f in /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt \
             /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    # macOS ships no PEM bundle; ask OpenSSL where its own trust store lives.
    if command -v openssl &>/dev/null; then
        d="$(openssl version -d 2>/dev/null | sed -n 's/^OPENSSLDIR: *"\(.*\)"$/\1/p')"
        [ -n "$d" ] && [ -f "$d/cert.pem" ] && { echo "$d/cert.pem"; return 0; }
    fi
    return 1
}

MAIL_BRIDGE_IMAP_PORT=1993
MAIL_BRIDGE_SMTP_PORT=1465

mail_transport_mode() {
    if command -v openssl &>/dev/null && \
       timeout 10 openssl s_client -connect "$MAIL_IMAP_HOST:$MAIL_IMAP_PORT" \
            -brief </dev/null &>/dev/null; then
        echo direct
        return 0
    fi
    if http_connect_proxy >/dev/null 2>&1 && command -v stunnel &>/dev/null; then
        echo bridge
        return 0
    fi
    echo direct
}

configure_mail_bridge() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR

    local email="$1" proxy ca conf
    proxy="$(http_connect_proxy)" || { warn "no proxy found — skipping mail bridge"; return 0; }
    ca="$(ca_bundle_file)" || { warn "no CA bundle found — skipping mail bridge"; return 0; }

    conf="$MAIL_BRIDGE_CONF"
    mkdir -p "$(dirname "$conf")" "$HOME/.local/state"
    {
        echo "; Generated by install.sh — machine-specific, not committed."
        echo "; TLS client that reaches $MAIL_PROVIDER through this host's HTTP CONNECT"
        echo "; proxy. mbsync has no proxy support and msmtp's is SOCKS-only, so"
        echo "; stunnel does the CONNECT and the TLS and hands each tool a plain"
        echo "; socket on loopback."
        echo "foreground = yes"
        echo "; A real file, not /dev/stderr: under systemd --user that path does"
        echo "; not resolve to anything stunnel can open and it exits 1 unbound."
        echo "output = $MAIL_BRIDGE_LOG"
        echo "pid ="
        local svc local_port remote_port host
        while read -r svc local_port remote_port; do
            [ -n "$svc" ] || continue
            case "$svc" in imap) host="$MAIL_IMAP_HOST" ;; *) host="$MAIL_SMTP_HOST" ;; esac
            echo ""
            echo "[$MAIL_PROVIDER-$svc]"
            echo "client = yes"
            echo "accept = localhost:$local_port"
            echo "connect = $proxy"
            echo "protocol = connect"
            echo "protocolHost = $host:$remote_port"
            echo "verifyChain = yes"
            echo "CAfile = $ca"
            echo "checkHost = $host"
            echo "sni = $host"
        done <<EOF
imap $MAIL_BRIDGE_IMAP_PORT 993
smtp $MAIL_BRIDGE_SMTP_PORT 465
EOF
    } > "$conf"
    info "Written stunnel config for the mail bridge"

    if [[ "$(uname)" == "Darwin" ]]; then
        local label="com.jlhe.$MAIL_BRIDGE_NAME" plist
        plist="$HOME/Library/LaunchAgents/$label.plist"
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(command -v stunnel)</string>
        <string>$conf</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$plist"; then
            info "Mail bridge running under launchd ($label)"
        else
            warn "could not load $label — start it with: launchctl bootstrap gui/\$(id -u) $plist"
        fi
    else
        local unit_dir="$HOME/.config/systemd/user"
        mkdir -p "$unit_dir"
        cat > "$unit_dir/$MAIL_BRIDGE_NAME.service" <<EOF
[Unit]
Description=stunnel TLS bridge to $MAIL_PROVIDER via this host's HTTP proxy
Documentation=man:stunnel(8)
After=network-online.target

[Service]
Type=simple
ExecStart=$(command -v stunnel) $conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        if systemctl --user daemon-reload 2>/dev/null && \
           systemctl --user enable --now "$MAIL_BRIDGE_NAME.service" 2>/dev/null; then
            info "Mail bridge running under systemd ($MAIL_BRIDGE_NAME.service)"
        else
            warn "no user service manager here — start the bridge with: systemctl --user enable --now $MAIL_BRIDGE_NAME.service"
        fi
    fi

    if command -v msmtp &>/dev/null; then
        {
            echo "# Generated by install.sh — machine-specific, not committed."
            echo "# $MAIL_PROVIDER via the local stunnel bridge; see $MAIL_BRIDGE_CONF."
            echo "# msmtp's own --proxy-host is SOCKS-only, so it cannot reach an"
            echo "# HTTP CONNECT proxy by itself."
            echo ""
            echo "account $MAIL_PROVIDER"
            echo "host localhost"
            echo "port $MAIL_BRIDGE_SMTP_PORT"
            echo "from $email"
            echo "auth plain"
            echo "user $email"
            echo "# One secret, one store, one accessor — see bin/mail-pass."
            echo "passwordeval \"\$HOME/bin/mail-pass\""
            echo "# Nothing to protect on this hop: it is loopback, and stunnel has"
            echo "# already terminated TLS against $MAIL_SMTP_HOST's certificate."
            echo "tls off"
            echo "logfile ~/.msmtp.log"
            echo ""
            echo "account default : $MAIL_PROVIDER"
        } > "$HOME/.msmtprc"
        chmod 600 "$HOME/.msmtprc"
        info "Written ~/.msmtprc for $email"
    else
        warn "msmtp not installed — the bridge has no send path"
    fi
    trap - ERR
}

build_mail_tools_from_source() {
    trap 'warn "${FUNCNAME[0]}: command failed: $BASH_COMMAND"; trap - ERR' ERR

    local missing=()
    command -v notmuch &>/dev/null || missing+=(notmuch)
    command -v neomutt &>/dev/null || missing+=(neomutt)
    [ ${#missing[@]} -eq 0 ] && return 0

    if ! command -v dnf &>/dev/null; then
        warn "missing ${missing[*]} and no source build defined for this platform"
        return 0
    fi

    info "Building from source (not packaged here): ${missing[*]}"
    sudo dnf install -y gcc gcc-c++ make autoconf automake libtool \
        gettext-devel ncurses-devel openssl-devel cyrus-sasl-devel \
        libidn2-devel xapian-core-devel gmime30-devel glib2-devel \
        libtalloc-devel zlib-devel gpgme-devel lmdb-devel gnupg2-smime \
        || { warn "could not install build dependencies"; return 0; }

    mkdir -p "$HOME/src"
    local m
    for m in "${missing[@]}"; do
        case "$m" in
            notmuch) [ -d "$HOME/src/notmuch" ] || \
                proxy_git_clone https://git.notmuchmail.org/git/notmuch "$HOME/src/notmuch" ;;
            neomutt) [ -d "$HOME/src/neomutt" ] || \
                proxy_git_clone https://github.com/neomutt/neomutt "$HOME/src/neomutt" ;;
        esac
    done

    if [[ " ${missing[*]} " == *" notmuch "* ]] && [ -d "$HOME/src/notmuch" ]; then
        ( cd "$HOME/src/notmuch" && \
          ./configure --prefix="$HOME/.local" --without-emacs --without-ruby \
              --without-docs --without-api-docs --without-desktop && \
          make -j"$(nproc)" && make install ) || warn "notmuch build failed"
    fi
    if [[ " ${missing[*]} " == *" neomutt "* ]] && [ -d "$HOME/src/neomutt" ]; then
        ( cd "$HOME/src/neomutt" && \
          LDFLAGS="-Wl,-rpath,$HOME/.local/lib" \
          ./configure --prefix="$HOME/.local" --notmuch \
              --with-notmuch="$HOME/.local" --ssl --sasl --gpgme --lmdb \
              --disable-doc && \
          make -j"$(nproc)" && make install ) || warn "neomutt build failed"
    fi
    trap - ERR
}

proxy_git_clone() {
    local proxy url="$1" dest="$2"
    if proxy="$(http_connect_proxy)"; then
        git -c http.proxy="$proxy" clone --depth 1 "$url" "$dest" && return 0
    fi
    git clone --depth 1 "$url" "$dest"
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

    mkdir -p "$HOME/.cache/neomutt"

    if [[ "$(uname)" == "Darwin" ]]; then
        install_via_brewfile || warn "Brewfile install incomplete — some packages may be missing"
        echo ""
    else
        install_via_packagefile || warn "some packages failed — check output above"
        echo ""
        # After the package file (may top up an old nvim), before plugin install.
        install_neovim || warn "neovim install incomplete — the nvim config needs 0.8+"
        echo ""
        install_sapling || true
        echo ""
        install_ghostty || true
        echo ""
    fi

    MAIL_MODE="${MAIL_MODE:-$(mail_transport_mode)}"
    if [ "$MAIL_MODE" = bridge ]; then
        info "$MAIL_PROVIDER is not directly reachable — configuring a local TLS bridge"
        configure_mail_bridge "$USER_EMAIL" || warn "mail bridge setup incomplete — check output above"
    fi
    build_mail_tools_from_source || warn "source build incomplete — check output above"
    echo ""

    configure_git "$USER_NAME" "$USER_EMAIL" || true
    configure_sapling "$USER_NAME" "$USER_EMAIL" || true
    # After the package step, so the pinentry it picks is actually installed.
    configure_gnupg || warn "GnuPG configuration incomplete — check output above"
    configure_patch_workflow "$USER_EMAIL" || warn "patch workflow config incomplete — check output above"
    install_ohmyzsh || warn "oh-my-zsh installation failed — continuing without it"
    set_default_shell || warn "could not set default shell — run: chsh -s \$(which zsh)"
    echo ""

    for generated in "${GENERATED[@]}"; do
        mkdir -p "$(dirname "$generated")"
        materialize_local_file "$generated"
    done

    if [ ! -f "$HOME/.zshrc.local" ]; then
        touch "$HOME/.zshrc.local"
        info "Created ~/.zshrc.local (add machine-specific shell config here)"
    fi
    local local_rc="$HOME/.neomutt/local.rc"
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
            if [ "${MAIL_MODE:-direct}" = bridge ]; then
                echo "set sendmail = \"$(command -v msmtp || echo /usr/bin/msmtp)\""
            else
                echo "set smtp_url = \"smtp://${USER_EMAIL}@$MAIL_SMTP_HOST:$MAIL_SMTP_PORT/\""
            fi
            echo "set my_maildir = \"$MAIL_DIR\""
            echo "set nm_default_url = \"notmuch://$MAIL_DIR\""
            if [ -n "$ca_line" ]; then echo "$ca_line"; fi
            if command -v neomutt &>/dev/null && \
               neomutt -Q header_cache_backend &>/dev/null; then
                local hcb
                hcb="$(neomutt -v 2>/dev/null | grep -oE '\+HAVE_(LMDB|GDBM|TOKYOCABINET|KYOTOCABINET|BDB)' | head -1 || true)"
                case "$hcb" in
                    *LMDB*)          echo 'set header_cache_backend = "lmdb"' ;;
                    *GDBM*)          echo 'set header_cache_backend = "gdbm"' ;;
                    *TOKYOCABINET*)  echo 'set header_cache_backend = "tokyocabinet"' ;;
                    *KYOTOCABINET*)  echo 'set header_cache_backend = "kyotocabinet"' ;;
                    *BDB*)           echo 'set header_cache_backend = "bdb"' ;;
                esac
            fi
        } > "$local_rc"
        info "Written ~/.neomutt/local.rc with identity config for $USER_NAME <$USER_EMAIL>"
    fi

    local signature="$HOME/.signature"
    if [ -s "$signature" ]; then
        info "Using existing ~/.signature"
    else
        printf '%s\n' "$USER_NAME" > "$signature"
        info "Written ~/.signature for $USER_NAME"
    fi

    # Password comes from bin/mail-pass at sync time; nothing secret is here.
    local mbsyncrc="$HOME/.mbsyncrc"
    {
        echo "IMAPAccount $MAIL_PROVIDER"
        if [ "${MAIL_MODE:-direct}" = bridge ]; then
            echo "Host localhost"
            echo "Port $MAIL_BRIDGE_IMAP_PORT"
        else
            echo "Host $MAIL_IMAP_HOST"
            echo "Port 993"
        fi
        echo "User $USER_EMAIL"
        echo "PassCmd \"\$HOME/bin/mail-pass\""
        if [ "${MAIL_MODE:-direct}" = bridge ]; then
            echo "SSLType None"
        else
            # Not TLSType: Ubuntu 24.04's isync (1.4.4) predates the 1.5.0 rename.
            echo "SSLType IMAPS"
        fi
        echo "AuthMechs LOGIN"
        echo ""
        echo "IMAPStore $MAIL_PROVIDER-remote"
        echo "Account $MAIL_PROVIDER"
        echo ""
        echo "MaildirStore $MAIL_PROVIDER-local"
        echo "Path $MAIL_DIR/"
        echo "Inbox $MAIL_DIR/INBOX"
        echo "Subfolders Verbatim"
        echo ""
        echo "Channel $MAIL_PROVIDER"
        echo "Far :$MAIL_PROVIDER-remote:"
        echo "Near :$MAIL_PROVIDER-local:"
        echo "Patterns *"
        echo "Create Both"
        echo "Expunge Both"
        echo "SyncState *"
    } > "$mbsyncrc"
    info "Written ~/.mbsyncrc for $USER_EMAIL"

    local notmuch_config="$HOME/.notmuch-config"
    {
        echo "[database]"
        echo "path=$MAIL_DIR"
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
    info "Written ~/.notmuch-config for $USER_NAME <$USER_EMAIL>"

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

    for dir in "${DIRS[@]}"; do
        src="$DOTFILES_DIR/$dir"
        dest="$HOME/$dir"

        if [ -d "$src" ]; then
            mkdir -p "$(dirname "$dest")"
            backup_and_link "$src" "$dest"
        else
            warn "Source directory not found: $src"
        fi
    done

    # The FILES loop's `mkdir -p` would have created it with the umask default.
    [ -d "$HOME/.gnupg" ] && chmod 700 "$HOME/.gnupg"

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
    echo "  - gnupg    (~/.gnupg/gpg.conf, ~/.gnupg/gpg-agent.conf)"
    echo "  - sapling  (vcs — sl)"
    echo "  - ghostty  (terminal emulator)"
    echo "  - scripts  (~/bin/)"
    echo ""
    echo "Note: You may need to:"
    echo "  - Restart your terminal for zsh to take effect"
    echo "  - Run 'tmux source ~/.tmux.conf' to reload tmux config"
    echo ""
    echo "=========================================="
    echo "       Mail Setup: $MAIL_PROVIDER (mbsync + notmuch)"
    echo "=========================================="
    echo ""
    echo "Mail syncs locally with mbsync and is indexed by notmuch; neomutt"
    echo "reads the local database. Finish setup on this machine:"
    echo ""
    echo "1. Generate a $MAIL_PROVIDER app-specific password:"
    echo "   - $MAIL_TOKEN_URL"
    echo "   - 'New App Password' -> 'Mail (IMAP/POP/SMTP)'"
    echo ""
    echo "2. Store it in your OS secret store:"
    echo "   mail-pass --store        # then: mail-pass --check"
    echo ""
    echo "3. Do the initial sync + index (first pull can be slow):"
    echo "   mail-sync        # runs: mbsync -a && notmuch new"
    echo ""
    echo "4. Launch neomutt (the 'mutt' wrapper syncs first, then opens neomutt)."
    echo "   Identity was written to ~/.neomutt/local.rc; mbsync/notmuch config"
    echo "   to ~/.mbsyncrc and ~/.notmuch-config."
    echo ""
    echo "=========================================="
    echo "       Kernel Patch Signing (gpg + b4)"
    echo "=========================================="
    echo ""
    echo "git send-email and b4 are configured to send through $MAIL_PROVIDER, taking"
    echo "the password from the same bin/mail-pass store as mbsync."
    echo ""
    echo "Patch signing turns itself on only when this machine holds the"
    echo "OpenPGP secret key. Check what this host ended up with:"
    echo "   gpg-setup --check"
    echo ""
    echo "To bring the key to a new machine, from one that already has it:"
    echo "   gpg-setup --export /tmp/key.gpg     # encrypted transfer file"
    echo "   scp /tmp/key.gpg <newhost>:/tmp/"
    echo "then on the new machine:"
    echo "   gpg-setup --import /tmp/key.gpg && gpg-setup --enable-signing"
    echo "   gpg-setup --test"
    echo "and delete the transfer file at both ends."
    echo ""
    echo "=========================================="
}

main "$@"
