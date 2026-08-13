FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/testuser/dotfiles
COPY . .
RUN chown -R testuser:testuser /home/testuser

USER testuser
ENV HOME=/home/testuser

RUN ./install.sh --name "Test User" --email "test@example.com"

# Verify packages installed via packages/apt.txt
RUN command -v tmux && command -v nvim && command -v neomutt && command -v zsh \
    && command -v mbsync && command -v notmuch \
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
    && test -L "$HOME/.claude/skills" \
    && test -L "$HOME/bin"

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
