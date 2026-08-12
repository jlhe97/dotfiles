-- Minimal Neovim config for C/C++ development with LSP

-- vim-plug is bootstrapped by install.sh; nothing to do here.


-- Plugins
vim.call('plug#begin', vim.fn.stdpath('data') .. '/plugged')
vim.call('plug#', 'hrsh7th/nvim-cmp')
vim.call('plug#', 'hrsh7th/cmp-nvim-lsp')
vim.call('plug#', 'hrsh7th/cmp-buffer')
vim.call('plug#', 'hrsh7th/vim-vsnip')      -- snippet engine (nvim 0.8 has no built-in vim.snippet)
vim.call('plug#', 'hrsh7th/cmp-vsnip')      -- vsnip source for nvim-cmp
vim.call('plug#', 'rust-lang/rust.vim')
vim.call('plug#', 'preservim/nerdtree')
vim.call('plug#', 'junegunn/fzf')
vim.call('plug#', 'junegunn/fzf.vim')
vim.call('plug#', 'Mofiqul/vscode.nvim')
vim.call('plug#', 'RRethy/vim-illuminate')
vim.call('plug#', 'mg979/vim-visual-multi')

-- vim-visual-multi: Ctrl+D selects the next occurrence (Ctrl+N is taken by NERDTree)
vim.g.VM_maps = {
  ['Find Under'] = '<C-d>',
  ['Find Subword Under'] = '<C-d>',
}
vim.call('plug#end')

-- Basic settings
vim.opt.number = true
vim.opt.expandtab = false
vim.opt.tabstop = 8
vim.opt.shiftwidth = 8
vim.opt.softtabstop = 8
vim.opt.autoindent = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 300

-- Color scheme: match VSCode's default dark theme (Dark+/Dark Modern)
vim.opt.termguicolors = true
vim.o.background = 'dark'
pcall(vim.cmd.colorscheme, 'vscode')

-- Auto-highlight other uses of the word under the cursor (VSCode-style)
pcall(function()
  require('illuminate').configure({
    providers = { 'lsp', 'treesitter', 'regex' },
    delay = 100,
  })
end)

-- NERDTree file explorer
vim.g.NERDTreeShowHidden = 1          -- show dotfiles
vim.g.NERDTreeMinimalUI = 1           -- hide the help hint / bookmarks header
vim.g.NERDTreeQuitOnOpen = 0          -- keep the tree open after opening a file
vim.keymap.set('n', '<C-n>', ':NERDTreeToggle<CR>', { silent = true })   -- open/close
vim.keymap.set('n', '<leader>n', ':NERDTreeFind<CR>', { silent = true }) -- reveal current file

-- fzf fuzzy finder (needs system fzf + ripgrep, installed via packages)
vim.keymap.set('n', '<C-p>', ':Files<CR>', { silent = true })        -- fuzzy file names
vim.keymap.set('n', '<leader>fg', ':Rg<CR>', { silent = true })      -- grep file contents
vim.keymap.set('n', '<leader>fb', ':Buffers<CR>', { silent = true }) -- open buffers

-- LSP settings
local on_attach = function(client, bufnr)
  local opts = { noremap=true, silent=true, buffer=bufnr }

  -- Keybindings
  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
  vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
end

local ok_lsp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
local capabilities = ok_lsp
  and cmp_nvim_lsp.default_capabilities()
  or vim.lsp.protocol.make_client_capabilities()

-- Locate rust-analyzer across platforms:
--   PATH (dnf on the Fedora devvm, or anything already exported)
--   ~/.cargo/bin (rustup: `rustup component add rust-analyzer`) on macOS/Ubuntu
--   Homebrew prefixes on macOS
local function rust_analyzer_bin()
  local exe = vim.fn.exepath('rust-analyzer')
  if exe ~= '' then return exe end
  local candidates = {
    vim.fn.expand('~/.cargo/bin/rust-analyzer'),
    '/opt/homebrew/bin/rust-analyzer',   -- Apple Silicon Homebrew
    '/usr/local/bin/rust-analyzer',      -- Intel Homebrew
  }
  for _, p in ipairs(candidates) do
    if vim.fn.executable(p) == 1 then return p end
  end
  return 'rust-analyzer'
end

-- Auto-start rust-analyzer for Rust files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"rust"},
  callback = function()
    vim.lsp.start({
      name = "rust_analyzer",
      cmd = {rust_analyzer_bin()},
      root_dir = vim.fs.dirname(vim.fs.find("Cargo.toml", { upward = true })[1]),
      capabilities = capabilities,
      on_attach = on_attach,
      settings = {
        ["rust-analyzer"] = {
          checkOnSave = true,
          check = { command = "clippy" },
        },
      },
    })
  end,
})

-- Setup nvim-cmp for autocompletion
local ok_cmp, cmp = pcall(require, 'cmp')
if ok_cmp then
  cmp.setup({
    snippet = {
      expand = function(args)
        vim.fn['vsnip#anonymous'](args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
      ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif vim.fn['vsnip#jumpable'](1) == 1 then
          vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Plug>(vsnip-jump-next)', true, true, true), '')
        else
          fallback()
        end
      end, { 'i', 's' }),
      ['<S-Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif vim.fn['vsnip#jumpable'](-1) == 1 then
          vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Plug>(vsnip-jump-prev)', true, true, true), '')
        else
          fallback()
        end
      end, { 'i', 's' }),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'vsnip' },
      { name = 'buffer' },
    })
  })
end

local function clangd_bin()
  local exe = vim.fn.exepath('clangd')
  if exe ~= '' then return exe end
  local candidates = {
    '/opt/homebrew/opt/llvm/bin/clangd',
    '/opt/llvm/stable/Toolchains/llvm-sand.xctoolchain/usr/bin/clangd',
    '/opt/llvm/lkg/Toolchains/llvm-sand.xctoolchain/usr/bin/clangd',
  }
  for _, p in ipairs(candidates) do
    if vim.fn.executable(p) == 1 then return p end
  end
  return 'clangd'
end

-- Auto-start clangd for C/C++ files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp"},
  callback = function()
    vim.lsp.start({
      name = "clangd",
      cmd = {
        clangd_bin(),
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders=1",
      },
      capabilities = capabilities,
      on_attach = on_attach,
    })
  end,
})
