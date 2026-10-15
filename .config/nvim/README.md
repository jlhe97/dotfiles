# Neovim config

C/C++ and Rust with the built-in LSP client (no lspconfig), tuned for Linux
kernel trees. Requires Neovim 0.8+.

Symlinked to `~/.config/nvim` by `install.sh` — don't copy the files. Plugins
bootstrap on first launch, or `nvim +PlugInstall +qall`.

## Keys

| | |
|---|---|
| `Space p` / `Space ff` | find files with FZF |
| `Space fg` / `Space sg` / `Space /` | Git files / grep / grep |
| `Space fb` / `Space fr` | buffers / recent files |
| `Space sb` / `Space sB` | lines in current / all open buffers |
| `Space sw` | grep word under cursor |
| `Space sh` / `Space sk` | help tags / keymaps |
| `Space sc` / `Space sC` | command history / available commands |
| `Space e` / `Space fe` | NERDTree toggle / reveal current file |
| `Space bn` / `Space bp` / `Space bq` | next / previous / close buffer |
| arrows or `C-h/j/k/l` | move between windows |
| `gd` `gD` `gr` `gI` `gy` | definition, declaration, references, implementation, type |
| `K` / `gK` | hover docs / signature help |
| `Space cr` / `Space ca` | rename / code actions |
| `Space cl` | attached LSP clients and roots |
| `[d` / `]d` / `Space sd` / `Space xx` | previous / next / list diagnostics |
| `Space f` | format — visual mode formats the selection only |
| `Tab` / `S-Tab` / `CR` | completion: next, previous, accept |
| `C-Space` | trigger completion |
| `Space n` / `Space uh` | message/notification history |
| `]q` `[q` `Space qf` | quickfix next, previous, open |

The old `C-p` file picker, `C-n` tree toggle, `gi` implementation, and
`Space rn` rename bindings remain available as compatibility aliases.

## How the server finds your project

| Language | Project | Root |
|---|---|---|
| C/C++ | kernel tree | `Kbuild` + `Kconfig` + `MAINTAINERS` at the root |
| C/C++ | anything else | nearest `compile_commands.json`, `.clangd`, or `.git` |
| Rust | Cargo | nearest `Cargo.toml`, searched upward **from the file**, not the cwd |
| either | no match | a detector from the machine-local config (takes precedence) |

clangd needs a `compile_commands.json` — see the repo README for how to
generate one per build system.

In a kernel tree clangd starts with `--header-insertion=never` and is rooted at
the tree. Build the tree, then `:KernelCCDB [objdir]` (or `bin/kernel-ccdb`)
and `:LspRestart`. Pass the objdir for `O=` builds.

## Machine-local config

`init.lua` loads `~/.config/nvim-local/init.lua` last, if present. It lives
outside this repo so work machines can register private detectors:

```lua
_G.cpp_project_detectors   -- dir -> nil | { root, bin, header_insertion }
_G.rust_project_detectors  -- dir -> nil | { root, cmd, cmd_cwd, settings }
_G.clangd_extra_candidates -- absolute clangd paths when none is on PATH
```

First detector to return a table wins; built-in detection is the fallback.
Rust detectors can replace `cmd` and `settings` too, since a non-Cargo build
needs a different server invocation.

## File map

`init.lua`, top to bottom: version guard, plugins, editor options, colorscheme
and UI plugins, NERDTree/fzf/quickfix keys, `on_attach` and LSP keys,
rust-analyzer resolver + detectors + autocmd, nvim-cmp, clangd resolver +
kernel detection + autocmd, `:KernelCCDB`, machine-local loader.
