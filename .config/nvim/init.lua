-- Minimal Neovim config for C/C++ development with LSP

-- vim-plug is bootstrapped by install.sh; nothing to do here.


-- Plugins
vim.call('plug#begin', vim.fn.stdpath('data') .. '/plugged')
vim.call('plug#', 'hrsh7th/nvim-cmp')
vim.call('plug#', 'hrsh7th/cmp-nvim-lsp')
vim.call('plug#', 'hrsh7th/cmp-buffer')
vim.call('plug#', 'rust-lang/rust.vim')
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

-- Auto-start rust-analyzer for Rust files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"rust"},
  callback = function()
    vim.lsp.start({
      name = "rust_analyzer",
      cmd = {"rust-analyzer"},
      root_dir = vim.fs.dirname(vim.fs.find("Cargo.toml", { upward = true })[1]),
      capabilities = capabilities,
      on_attach = on_attach,
      settings = {
        ["rust-analyzer"] = {
          checkOnSave = { command = "clippy" },
        },
      },
    })
  end,
})

-- Setup nvim-cmp for autocompletion
local ok_cmp, cmp = pcall(require, 'cmp')
if ok_cmp then
  cmp.setup({
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
      ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        else
          fallback()
        end
      end, { 'i', 's' }),
      ['<S-Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        else
          fallback()
        end
      end, { 'i', 's' }),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'buffer' },
    })
  })
end

-- Auto-start clangd for C/C++ files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp"},
  callback = function()
    vim.lsp.start({
      name = "clangd",
      cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
      },
      capabilities = capabilities,
      on_attach = on_attach,
    })
  end,
})
