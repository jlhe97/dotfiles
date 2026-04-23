# dotfiles

Personal configuration files, managed with symlinks.

| Job | Status |
|-----|--------|
| Ubuntu | [![Ubuntu](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=Ubuntu)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| Fedora | [![Fedora](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=Fedora)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| macOS | [![macOS](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=macOS)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| E2E Ubuntu | [![E2E Ubuntu](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=E2E+Ubuntu)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| E2E Fedora | [![E2E Fedora](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=E2E+Fedora)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| E2E Arch | [![E2E Arch](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=E2E+Arch)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |
| E2E macOS | [![E2E macOS](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml/badge.svg?event=push&job=E2E+macOS)](https://github.com/jlhe97/dotfiles/actions/workflows/test.yml) |

## Contents

- `.zshrc` — zsh configuration
- `.neomuttrc` — neomutt config with patch syntax highlighting, sidebar, and vim keybindings
- `.config/nvim/init.lua` — neovim config with LSP (clangd, rust-analyzer) and nvim-cmp
- `.tmux.conf` — tmux configuration with cross-platform clipboard (pbcopy / wl-copy / xclip)
- `.vimrc` / `.vimrc.plug` — vim configuration
- `bin/` — helper scripts: `lei-sync` (mailing list sync), `mutt` (neomutt wrapper)

## Setup

```sh
git clone https://github.com/jlhe97/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --name "Your Name" --email "you@example.com"
```

Re-running `install.sh` is safe — it skips packages already installed, leaves
correct symlinks alone, and only rewrites `~/.neomutt/local.rc` when the
identity actually changes.

```sh
./uninstall.sh                  # remove symlinks (prompts about packages)
./uninstall.sh --skip-packages  # remove symlinks only, no prompt
```

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

CI runs automatically on every push and pull request across Ubuntu, Fedora, Arch, and macOS via GitHub Actions (`.github/workflows/test.yml`).
