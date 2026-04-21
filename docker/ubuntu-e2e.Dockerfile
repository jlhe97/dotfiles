FROM ubuntu:22.04
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
RUN command -v tmux && command -v nvim && command -v neomutt && command -v zsh

# Verify dotfile symlinks created
RUN test -L "$HOME/.tmux.conf" \
    && test -L "$HOME/.vimrc" \
    && test -L "$HOME/.zshrc" \
    && test -L "$HOME/.config/nvim" \
    && test -L "$HOME/.slconfig"

# Verify nvim plugins installed
RUN test -d "$HOME/.local/share/nvim/plugged"
