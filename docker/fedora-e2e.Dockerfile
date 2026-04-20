FROM fedora:latest

RUN dnf install -y curl git sudo && dnf clean all

RUN useradd -m -s /bin/bash testuser \
    && echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/testuser/dotfiles
COPY . .
RUN chown -R testuser:testuser /home/testuser

USER testuser
ENV HOME=/home/testuser

RUN ./install.sh --name "Test User" --email "test@example.com"

# Verify packages installed via packages/dnf.txt
RUN command -v tmux && command -v nvim && command -v neomutt && command -v zsh

# Verify dotfile symlinks created
RUN test -L "$HOME/.tmux.conf" \
    && test -L "$HOME/.vimrc" \
    && test -L "$HOME/.zshrc" \
    && test -L "$HOME/.config/nvim"

# Verify nvim plugins installed
RUN test -d "$HOME/.local/share/nvim/plugged"
