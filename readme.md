# dotfiles

Personal configuration files, managed with symlinks.

## Contents

- `.zshrc` — zsh configuration
- `.neomuttrc` — neomutt config with patch syntax highlighting, sidebar, and vim
keybindings
- `.config/nvim/init.lua` — neovim config with LSP (clangd, rust-analyzer) and nvim-cmp
- `.tmux.conf` — tmux configuration
- `.vimrc` / `.vimrc.plug` — vim configuration

## Setup

```sh
./install.sh    # symlink dotfiles into ~
./uninstall.sh  # remove symlinks

Neovim

After install, open nvim and run :PlugInstall to install plugins.
```
