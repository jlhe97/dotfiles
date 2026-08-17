FROM archlinux:latest

RUN pacman -Syu --noconfirm && pacman -S --noconfirm curl git sudo && pacman -Scc --noconfirm

RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/testuser/dotfiles
COPY . .
RUN chown -R testuser:testuser /home/testuser

USER testuser
ENV HOME=/home/testuser

RUN ./install.sh --name "Test User" --email "test@example.com"

# Verify packages installed via packages/pacman.txt
RUN command -v tmux && command -v nvim && command -v neomutt && command -v zsh && command -v ghostty \
    && command -v mbsync && command -v notmuch \
    && command -v gpg && command -v pinentry && command -v secret-tool \
    && command -v fzf && command -v rg

# Verify dotfile symlinks created
RUN test -L "$HOME/.tmux.conf" \
    && test -L "$HOME/.vimrc" \
    && test -L "$HOME/.vimrc.plug" \
    && test -L "$HOME/.zshrc" \
    && test -L "$HOME/.neomuttrc" \
    && test -L "$HOME/.config/nvim" \
    && test -L "$HOME/.config/clangd" \
    && test -L "$HOME/.slconfig" \
    && test -L "$HOME/.neomutt/linux.rc" \
    && test -L "$HOME/.gnupg/gpg.conf" \
    && test -L "$HOME/.gnupg/gpg-agent.conf" \
    && test -L "$HOME/.claude/skills" \
    && test -L "$HOME/bin"

# gpg refuses to use a homedir other users can read.
RUN test "$(stat -c %a "$HOME/.gnupg")" = "700"

# The patch workflow is configured for sending...
RUN test "$(git config --global --get sendemail.smtpserver)" = "smtp.fastmail.com" \
    && git config --global --get-all 'credential.smtp://smtp.fastmail.com:587.helper' | grep -q mail-pass

# ...but signing stays off, because this container holds no secret key.
RUN test -z "$(git config --global --get patatt.signingkey || true)" \
    && test -z "$(git config --global --get user.signingKey || true)"

# Verify nvim plugins installed
RUN test -d "$HOME/.local/share/nvim/plugged"

# Verify init.lua actually loads and exposes the machine-local extension points
# (the symlink checks above pass even if the Lua is broken).
RUN nvim --headless \
    -c 'lua assert(type(_G.cpp_project_detectors) == "table", "cpp_project_detectors missing")' \
    -c 'lua assert(type(_G.rust_project_detectors) == "table", "rust_project_detectors missing")' \
    -c 'lua assert(vim.fn.exists(":KernelCCDB") == 2, "KernelCCDB missing")' \
    -c 'qa' 2>&1 | tee /tmp/nvim-load.log \
    && ! grep -qiE '^(E[0-9]+:|Error)' /tmp/nvim-load.log
