FROM archlinux:latest

RUN pacman -Syu --noconfirm && pacman -S --noconfirm curl git sudo && pacman -Scc --noconfirm

RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/testuser/dotfiles
COPY . .
RUN chown -R testuser:testuser /home/testuser

USER testuser
ENV HOME=/home/testuser

ENV MAIL_MODE=direct
RUN ./install.sh --name "Test User" --email "test@example.com"

# Verify packages installed via packages/pacman.txt
RUN command -v tmux && command -v nvim && command -v neomutt && command -v zsh && command -v ghostty \
    && command -v mbsync && command -v notmuch \
    && command -v gpg && command -v secret-tool \
    && command -v fzf && command -v rg

# Verify dotfile symlinks created
RUN test -L "$HOME/.tmux.conf" \
    && test -L "$HOME/.vimrc" \
    && test -L "$HOME/.vimrc.plug" \
    && test -L "$HOME/.zshrc" \
    && test -L "$HOME/.neomuttrc" \
    && test -L "$HOME/.config/nvim" \
    && test -L "$HOME/.config/clangd" \
    && test -L "$HOME/.config/git/config" \
    && test -L "$HOME/.config/git/kernel.config" \
    && test -L "$HOME/.config/git/kernel-commit-template" \
    && test -L "$HOME/.slconfig" \
    && test -L "$HOME/.ripgreprc" \
    && test -L "$HOME/.neomutt/linux.rc" \
    && test -L "$HOME/bin"

# A $HOME backup captures a symlink, not what it points at.
RUN for f in .zshrc.local .neomutt/local.rc .mbsyncrc .notmuch-config .signature; do \
        test -f "$HOME/$f" || { echo "missing: $f"; exit 1; }; \
        test ! -L "$HOME/$f" || { echo "still a symlink: $f"; exit 1; }; \
    done \
    && test ! -e "$HOME/dotfiles/.mbsyncrc"

# The patch workflow is configured for sending, unsigned.
RUN test "$(git config --global --get sendemail.smtpserver)" = "smtp.fastmail.com" \
    && git config --global --get-all 'credential.smtp://smtp.fastmail.com:587.helper' | grep -q mail-pass \
    && test "$(git config --global --get b4.send-no-patatt-sign)" = "yes"

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
