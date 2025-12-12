# Neovim Configuration

Minimal Neovim configuration for C/C++ development with LSP support, optimized for Linux kernel development.

## Features

- **Built-in LSP support** using `vim.lsp` (no external plugin dependencies)
- **Clangd integration** for C/C++ intellisense
- **Autocompletion** with nvim-cmp
- **Linux kernel coding style** (8-space tabs for C/C++ files)

## Requirements

- Neovim 0.6.1 or later
- clangd (language server)

## Installation

### 1. Install Neovim

```bash
# Ubuntu/Debian
sudo apt-get install -y neovim

# Or download latest from https://github.com/neovim/neovim/releases
```

### 2. Install clangd

```bash
# Ubuntu/Debian
sudo apt-get install -y clangd

# Or download from https://github.com/clangd/clangd/releases
```

### 3. Copy configuration

```bash
mkdir -p ~/.config/nvim
cp init.lua ~/.config/nvim/
```

### 4. Install plugins

Open Neovim and the plugins will auto-install on first run:

```bash
nvim
```

Or manually install:

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

### Linux Kernel Development

When working on kernel code, generate `compile_commands.json` in your kernel source directory:

```bash
cd /path/to/linux
scripts/clang-tools/gen_compile_commands.py
```

This enables accurate intellisense for kernel macros and structures.

## Configuration Details

- Uses vim-plug for plugin management
- Leverages Neovim's built-in LSP client
- nvim-cmp for autocompletion
- Clangd configured with kernel-friendly options:
  - Background indexing
  - Clang-tidy integration
  - Include-what-you-use header insertion
  - Detailed completion style

## Customization

Edit `init.lua` to customize:
- Key bindings (lines 34-39)
- Clangd options (lines 80-86)
- Tab settings (lines 21-24)
- Completion behavior (lines 45-64)
