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
- `.neomuttrc` — neomutt config (local notmuch mail via mbsync) with patch syntax highlighting, sidebar, and vim keybindings
- `.config/nvim/init.lua` — neovim config with LSP (clangd, rust-analyzer), nvim-cmp + vsnip snippets, NERDTree, and fzf
- `.config/clangd/config.yaml` — global clangd config: kernel GCC-flag handling, clang-tidy checks, inlay hints (used by any LSP editor, not just nvim)
- `.tmux.conf` — tmux configuration with cross-platform clipboard (pbcopy / wl-copy / xclip)
- `.vimrc` / `.vimrc.plug` — vim configuration
- `bin/` — helper scripts: `mail-sync` (mbsync + notmuch), `mail-pass` (per-OS password lookup), `mail-timer` (install a periodic-sync launchd/systemd timer), `mutt` (sync-then-neomutt wrapper), `lei-sync` (kernel mailing-list sync), `kernel-ccdb` (regenerate a kernel tree's `compile_commands.json`)

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

## C/C++ & kernel development

Rust "just works" because Cargo hands the LSP everything. C/C++ has no such
manifest, so clangd needs a `compile_commands.json` per project. Generate it
once and clangd (in nvim or any editor) gets accurate includes, flags, and
cross-file navigation:

| Project type | How to generate `compile_commands.json` |
|--------------|------------------------------------------|
| CMake        | Automatic — `.zshrc` exports `CMAKE_EXPORT_COMPILE_COMMANDS=ON`, so it lands in your build dir. Symlink it to the project root once: `ln -s build/compile_commands.json .` |
| Make         | `bear -- make` (bear intercepts the compiler invocations) |
| Linux kernel | `make compile_commands.json` after building (wraps `scripts/clang-tools/gen_compile_commands.py`) |

The kernel's compile DB carries GCC-only flags clang rejects;
`.config/clangd/config.yaml` strips them globally, so kernel trees index
cleanly with no per-tree `.clangd` needed. clang-tidy (bugprone/performance/
portability checks) runs as the C/C++ analog to clippy.

The nvim config tailors itself when it detects a kernel tree (`Kbuild` +
`Kconfig` + `MAINTAINERS` at the root):

- clangd starts with `--header-insertion=never` (kernel include rules aren't
  IWYU, so auto-include suggestions are usually wrong there); personal projects
  keep IWYU. clangd is also rooted at the tree so it finds `compile_commands.json`.
- `<leader>f` formats via the LSP — in a kernel file that means the in-tree
  `.clang-format` (kernel style); visual-mode `<leader>f` formats only the
  selection, so you don't reformat code you didn't touch.
- `:KernelCCDB` (or `bin/kernel-ccdb` from the shell) runs
  `make compile_commands.json` for the current tree; `:LspRestart` to pick it up.

Tooling is installed per platform via the package lists / Brewfile: `clangd`,
`clang-tidy`, `clang-format`, and `bear`. On the Fedora devvm clangd comes from
the Meta `llvm-sand` toolchain, which `init.lua`'s `clangd_bin()` resolver finds
automatically.

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
