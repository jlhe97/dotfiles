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
./install.sh                                   # symlink dotfiles into ~
./install.sh --name "Jane Smith" --email "jane@example.com"  # non-interactive / CI
./uninstall.sh                                 # remove symlinks
```

Re-running `install.sh` is safe — it skips packages already installed, leaves
correct symlinks alone, and only rewrites `~/.neomutt/local.rc` when the
identity actually changes.

After install, open nvim and run `:PlugInstall` to install plugins.

## Testing

Run the full test suite locally (requires [bats-core](https://github.com/bats-core/bats-core)):

```sh
bats tests/
```

Or against an isolated Ubuntu / Fedora environment via Docker:

```sh
docker compose run --rm ubuntu
docker compose run --rm fedora
```

CI runs automatically on every push and pull request across Ubuntu, Fedora,
and macOS via GitHub Actions (`.github/workflows/test.yml`).
