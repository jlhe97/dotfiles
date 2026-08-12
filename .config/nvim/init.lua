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

  -- <leader>f: format via the LSP (clangd uses the tree's .clang-format, so
  -- kernel files format to kernel style; rust-analyzer uses rustfmt).
  -- Normal mode formats the buffer; visual mode formats just the selection
  -- (important for kernel patches — don't reformat code you didn't touch).
  vim.keymap.set('n', '<leader>f', function() vim.lsp.buf.format({ async = true }) end, opts)
  vim.keymap.set('x', '<leader>f', function()
    local s = vim.api.nvim_buf_get_mark(0, '<')
    local e = vim.api.nvim_buf_get_mark(0, '>')
    local ok = pcall(vim.lsp.buf.format, {
      async = true,
      range = { ['start'] = { s[1], 0 }, ['end'] = { e[1], 0 } },
    })
    if not ok then vim.lsp.buf.format({ async = true }) end
  end, opts)
end

local ok_lsp, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
local capabilities = ok_lsp
  and cmp_nvim_lsp.default_capabilities()
  or vim.lsp.protocol.make_client_capabilities()

-- Locate rust-analyzer across platforms:
--   PATH (a distro package, or anything already exported)
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

-- Extra Rust project detectors, registered by the machine-local config loaded
-- at the bottom of this file (same idea as cpp_project_detectors). Each is
-- called with the current file's directory and returns nil, or:
--   { root = <dir>, cmd = {...}, cmd_cwd = <dir>, settings = {...} }
-- First match wins; plain Cargo detection below is the fallback. Build systems
-- that aren't Cargo need a different server invocation entirely, which is why
-- detectors get to supply cmd and settings and not just a root.
_G.rust_project_detectors = {}

-- Auto-start rust-analyzer for Rust files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"rust"},
  callback = function()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" then dir = vim.fn.getcwd() end

    local proj
    for _, detect in ipairs(_G.rust_project_detectors) do
      proj = detect(dir)
      if proj then break end
    end

    local root = proj and proj.root
    if not root then
      -- Search upward from the FILE, not from nvim's cwd: `nvim some/crate/src/x.rs`
      -- run from anywhere else must still find the manifest. (vim.fs.find defaults
      -- `path` to the cwd, which silently yields a nil root and leaves
      -- rust-analyzer reporting "failed to discover workspace".)
      local manifest = vim.fs.find("Cargo.toml", { upward = true, path = dir })[1]
      if manifest then root = vim.fs.dirname(manifest) end
    end

    vim.lsp.start({
      name = "rust_analyzer",
      cmd = (proj and proj.cmd) or { rust_analyzer_bin() },
      cmd_cwd = proj and proj.cmd_cwd or nil,
      root_dir = root,
      capabilities = capabilities,
      on_attach = on_attach,
      settings = (proj and proj.settings) or {
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

-- Extra C/C++ project detectors, registered by the machine-local config loaded
-- at the bottom of this file. Each is called with the current file's directory
-- and returns nil, or:
--   { root = <dir>, bin = <clangd path>, header_insertion = "iwyu"|"never" }
-- First match wins; the built-in detection below runs when none match. This is
-- the seam that keeps site-specific monorepo and toolchain knowledge out of
-- this repo.
_G.cpp_project_detectors = {}

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

-- Detect the Linux kernel tree containing `start` (defaults to the current
-- file's dir). Returns the tree root, or nil. Kbuild+MAINTAINERS at the same
-- dir is a strong kernel-tree signal that other C projects won't trip.
local function kernel_root(start)
  start = start or vim.fn.expand("%:p:h")
  if start == "" then start = vim.fn.getcwd() end
  local m = vim.fs.find("MAINTAINERS", { upward = true, path = start })[1]
  if not m then return nil end
  local root = vim.fs.dirname(m)
  if vim.fn.filereadable(root .. "/Kbuild") == 1
    and vim.fn.filereadable(root .. "/Kconfig") == 1 then
    return root
  end
  return nil
end

-- Auto-start clangd for C/C++ files
vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp"},
  callback = function()
    local kroot = kernel_root()
    local proj
    if not kroot then
      local dir = vim.fn.expand("%:p:h")
      for _, detect in ipairs(_G.cpp_project_detectors) do
        proj = detect(dir)
        if proj then break end
      end
    end
    -- Root at the kernel tree, or wherever a registered detector says the
    -- project starts (both are where compile_commands.json lives); otherwise
    -- anchor to the nearest compile DB / .clangd / git root. Detectors take
    -- precedence because a monorepo's nearest .clangd can sit well below its
    -- compile DB, which would root clangd in the wrong place.
    local root = kroot or (proj and proj.root)
    if not root then
      local marker = vim.fs.find({ "compile_commands.json", ".clangd", ".git" },
        { upward = true, path = vim.fn.expand("%:p:h") })[1]
      if marker then root = vim.fs.dirname(marker) end
    end
    vim.lsp.start({
      name = "clangd",
      cmd = {
        (proj and proj.bin) or clangd_bin(),
        "--background-index",
        "--clang-tidy",
        -- In kernel trees IWYU auto-include suggestions are usually wrong
        -- (kernel include rules aren't IWYU); disable there, keep elsewhere.
        "--header-insertion=" ..
          (kroot and "never" or (proj and proj.header_insertion) or "iwyu"),
        "--completion-style=detailed",
        "--function-arg-placeholders=1",
      },
      root_dir = root,
      capabilities = capabilities,
      on_attach = on_attach,
    })
  end,
})

-- :KernelCCDB — (re)generate compile_commands.json for the current kernel tree
-- so clangd has an accurate compile database. Requires the tree to be built
-- (the target scans the .cmd files make leaves behind). Run :LspRestart after.
vim.api.nvim_create_user_command("KernelCCDB", function()
  local root = kernel_root()
  if not root then
    vim.notify("KernelCCDB: not inside a Linux kernel tree", vim.log.levels.ERROR)
    return
  end
  vim.notify("KernelCCDB: make compile_commands.json in " .. root .. " ...")
  local out = vim.fn.system({ "make", "-C", root, "compile_commands.json" })
  if vim.v.shell_error ~= 0 then
    vim.notify("KernelCCDB failed:\n" .. out, vim.log.levels.ERROR)
  else
    vim.notify("KernelCCDB: done — run :LspRestart to pick up the new DB")
  end
end, { desc = "Regenerate the kernel compile_commands.json" })

-- Machine-local config, loaded last so it can override anything above and
-- register cpp_project_detectors. Deliberately outside this repo (and outside
-- ~/.config/nvim, which is a symlink into it) so work machines can add private
-- toolchain and monorepo settings that must never be published here.
local local_init = vim.fn.expand("~/.config/nvim-local/init.lua")
if vim.fn.filereadable(local_init) == 1 then
  local ok, err = pcall(dofile, local_init)
  if not ok then
    vim.notify("nvim-local/init.lua failed:\n" .. tostring(err), vim.log.levels.ERROR)
  end
end
