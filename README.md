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

Cargo hands rust-analyzer everything it needs, so Rust is only interesting when
a project *isn't* built by Cargo (see "Non-Cargo and non-CMake projects"). C/C++
has no manifest at all, so clangd needs a `compile_commands.json` per project.
Generate it once and clangd (in nvim or any editor) gets accurate includes,
flags, and cross-file navigation:

| Project type | How to generate `compile_commands.json` |
|--------------|------------------------------------------|
| CMake        | Automatic — `.zshrc` exports `CMAKE_EXPORT_COMPILE_COMMANDS=ON`, so it lands in your build dir. Symlink it to the project root once: `ln -s build/compile_commands.json .` |
| Make         | `bear -- make` (bear intercepts the compiler invocations) |
| Linux kernel | `make compile_commands.json` after building (wraps `scripts/clang-tools/gen_compile_commands.py`) |

The kernel's compile DB carries GCC-only flags clang rejects;
`.config/clangd/config.yaml` strips them globally, so kernel trees index
cleanly with no per-tree `.clangd` needed. That file also adds `-Wno-error`:
kernel builds pass `-Werror`, and under clang the GCC-oriented flags produce
warnings the real build never sees — enough of them to blow clangd's 19-error
limit, after which it reports "too many errors emitted" and silently truncates
diagnostics for the whole file. clang-tidy (bugprone/performance/portability
checks) runs as the C/C++ analog to clippy.

The nvim config tailors itself when it detects a kernel tree (`Kbuild` +
`Kconfig` + `MAINTAINERS` at the root):

- clangd starts with `--header-insertion=never` (kernel include rules aren't
  IWYU, so auto-include suggestions are usually wrong there); personal projects
  keep IWYU. clangd is also rooted at the tree so it finds `compile_commands.json`.
- `<leader>f` formats via the LSP — in a kernel file that means the in-tree
  `.clang-format` (kernel style); visual-mode `<leader>f` formats only the
  selection, so you don't reformat code you didn't touch.
- `:KernelCCDB [objdir]` (or `bin/kernel-ccdb [path] [objdir]` from the shell)
  runs `make compile_commands.json` for the current tree; `:LspRestart` to pick
  it up. For an `O=` build pass the objdir — that's where the `.cmd` files are,
  so the database is generated there and linked back into the source root. The
  nvim command also reads `vim.g.kernel_objdir`, the script `$KERNEL_OBJDIR`.
- `.cache/` is added to the tree's `.git/info/exclude` on first attach, since
  clangd's background index lands there and the kernel's tracked `.gitignore`
  doesn't cover it.

Tooling is installed per platform via the package lists / Brewfile: `clangd`
(`clang-tools-extra` on Fedora), `clang-tidy`, `clang-format`, and `bear`.
`init.lua`'s `clangd_bin()` resolver prefers whatever is on `PATH` and falls
back to known Homebrew and vendored-toolchain locations.

### Non-Cargo and non-CMake projects

Work machines often build C/C++ and Rust with something else entirely — a
monorepo build system with its own toolchain, its own database generator and no
`Cargo.toml` anywhere. Rather than bake any of that in here, `init.lua` exposes
two registries that a machine-local config can extend:

```lua
_G.cpp_project_detectors   -- dir -> nil | { root, bin, header_insertion }
_G.rust_project_detectors  -- dir -> nil | { root, cmd, cmd_cwd, settings }
```

Each detector is called with the current file's directory; the first to return
a table wins, and built-in detection (kernel tree, then nearest
`compile_commands.json`/`.clangd`/`.git`, or nearest `Cargo.toml`) is the
fallback. Rust detectors get to replace `cmd` and `settings` as well as the
root, because a non-Cargo project needs a different server invocation, not just
a different directory.

Registrations go in `~/.config/nvim-local/init.lua`, which `init.lua` loads last
via `dofile` if it exists. That path is deliberately outside `~/.config/nvim`
(a symlink into this repo), so machine-specific settings never end up here.

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
