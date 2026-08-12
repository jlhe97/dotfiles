# Neovim Configuration

Minimal Neovim configuration for C/C++ and Rust development with LSP support,
with extra handling for Linux kernel trees.

## Features

- **Built-in LSP support** using `vim.lsp` (no lspconfig dependency)
- **clangd** for C/C++, **rust-analyzer** for Rust, both auto-started per filetype
- **Autocompletion** with nvim-cmp
- **Linux kernel coding style** (8-space tabs) and kernel-aware clangd settings
- **Machine-local extension point** for build systems that aren't Cargo/CMake

## Requirements

- Neovim 0.8 or later (uses `vim.fs`, `vim.lsp.start`)
- clangd for C/C++, rust-analyzer for Rust

Both are installed by the repo's package lists (`packages/apt.txt`,
`packages/dnf.txt`, `Brewfile`); the resolvers in `init.lua` also fall back to
`~/.cargo/bin` and the usual Homebrew prefixes.

## Installation

`install.sh` at the repo root symlinks this whole directory to
`~/.config/nvim` — don't copy the files. Plugins bootstrap on first launch, or
manually:

```bash
nvim +PlugInstall +qall
```

## Usage

### Key Bindings

- **Tab/Shift-Tab**: Navigate completions
- **Ctrl-Space**: Trigger completion manually
- **Enter**: Accept selected completion
- **gd**: Go to definition
- **gr**: Find references
- **gi**: Go to implementation
- **K**: Show hover documentation
- **\<leader\>rn**: Rename symbol (leader is `\`)
- **\<leader\>ca**: Show code actions
- **\<leader\>f**: Format buffer (visual mode: format the selection only)

### Language servers

Both servers need to know how the project is built:

| Language | Project | Root comes from |
|----------|---------|-----------------|
| C/C++ | anything with a compile DB | nearest `compile_commands.json`, `.clangd`, or `.git` |
| C/C++ | Linux kernel | `Kbuild` + `Kconfig` + `MAINTAINERS` at the tree root |
| Rust | Cargo | nearest `Cargo.toml`, searched upward **from the file** (not the cwd) |
| either | anything else | a detector registered by the machine-local config |

For C/C++ that means generating a `compile_commands.json` — see the repo README
for the per-build-system recipes.

### Linux kernel trees

Detected automatically; clangd then starts with `--header-insertion=never` and
is rooted at the tree. Generate the compile database from inside nvim with
`:KernelCCDB [objdir]` (or `bin/kernel-ccdb` from a shell), then `:LspRestart`.
The tree must already be built — the kernel's `compile_commands.json` target
scans the `.cmd` files the build leaves behind. Pass the objdir for `O=` builds.

## Machine-local configuration

`init.lua` loads `~/.config/nvim-local/init.lua` last, if it exists. That file
is outside this repo on purpose: work machines can register their own project
detectors there without any of it being published here.

```lua
_G.cpp_project_detectors   -- dir -> nil | { root, bin, header_insertion }
_G.rust_project_detectors  -- dir -> nil | { root, cmd, cmd_cwd, settings }
```

First detector to return a table wins; built-in detection is the fallback.

## Customization

Everything lives in `init.lua`, in this order: plugins, editor options,
colorscheme, LSP keymaps/`on_attach`, server resolvers and autocmds, nvim-cmp,
then the user commands and the machine-local loader.
