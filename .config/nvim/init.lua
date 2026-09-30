-- Minimal Neovim config for C/C++ development with LSP

-- Without this guard an older nvim dies partway through with a traceback that
-- says nothing about the real cause ("attempt to index field 'cmd'" on 0.6).
if vim.fn.has('nvim-0.8') ~= 1 then
  local ok, v = pcall(vim.version)
  local found = (ok and type(v) == 'table')
    and string.format('%d.%d.%d', v.major, v.minor, v.patch) or 'an older release'
  error(('this config requires Neovim 0.8 or newer (found %s)'):format(found), 0)
end

-- vim-plug is bootstrapped by install.sh; nothing to do here.

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
vim.call('plug#', 'MunifTanjim/nui.nvim')   -- required by noice
vim.call('plug#', 'folke/noice.nvim')       -- floating : cmdline (see below)
vim.call('plug#', 'NMAC427/guess-indent.nvim') -- best guess indentation convention

-- vim-visual-multi: Ctrl+D selects the next occurrence (Ctrl+N is taken by NERDTree)
vim.g.VM_maps = {
  ['Find Under'] = '<C-d>',
  ['Find Subword Under'] = '<C-d>',
}
vim.call('plug#end')

-- fallback only if .editorconfig and guess-indent don't set it for us
vim.opt.number = true
vim.opt.expandtab = true
vim.opt.tabstop = 8
vim.opt.shiftwidth = 4
vim.opt.softtabstop = -1 -- follow shiftwidth
vim.opt.autoindent = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 300

-- Color scheme: match VSCode's default dark theme (Dark+/Dark Modern)
vim.opt.termguicolors = true
vim.o.background = 'dark'
-- vim.cmd('...') not vim.cmd.colorscheme(...): Lua evaluates the argument
-- first, so the index would happen outside the pcall and take the config down.
pcall(vim.cmd, 'colorscheme vscode')

-- Match an existing file's indentation when no .editorconfig speaks for it
pcall(function()
  require('guess-indent').setup({})
end)

-- command_palette centres the : cmdline; bottom_search deliberately leaves /
-- and ? on the last line. noice wants 0.9, so on 0.8 the pcall leaves the
-- stock cmdline in place.
pcall(function()
  require('noice').setup({
    presets = {
      command_palette = true,
      bottom_search = true,
      long_message_to_split = true,
    },
  })
end)

-- Auto-highlight other uses of the word under the cursor (VSCode-style)
pcall(function()
  require('illuminate').configure({
    providers = { 'lsp', 'treesitter', 'regex' },
    delay = 100,
  })
end)

vim.g.NERDTreeShowHidden = 1          -- show dotfiles
vim.g.NERDTreeMinimalUI = 1           -- hide the help hint / bookmarks header
vim.g.NERDTreeQuitOnOpen = 0          -- keep the tree open after opening a file
vim.keymap.set('n', '<C-n>', ':NERDTreeToggle<CR>', { silent = true })   -- open/close
vim.keymap.set('n', '<leader>n', ':NERDTreeFind<CR>', { silent = true }) -- reveal current file

-- fzf fuzzy finder (needs system fzf + ripgrep, installed via packages)
vim.keymap.set('n', '<C-p>', ':Files<CR>', { silent = true })        -- fuzzy file names
vim.keymap.set('n', '<leader>fg', ':Rg<CR>', { silent = true })      -- grep file contents
vim.keymap.set('n', '<leader>fb', ':Buffers<CR>', { silent = true }) -- open buffers

vim.opt.grepprg = 'rg --vimgrep'
vim.opt.grepformat = '%f:%l:%c:%m'

vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = 'grep',
  command = 'cwindow',
})

vim.keymap.set('n', ']q', ':cnext<CR>', { silent = true })
vim.keymap.set('n', '[q', ':cprevious<CR>', { silent = true })
vim.keymap.set('n', '<leader>qf', ':copen<CR>', { silent = true })

local on_attach = function(client, bufnr)
  local opts = { noremap=true, silent=true, buffer=bufnr }

  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
  vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
  vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)

  -- Visual mode formats only the selection: don't reformat code you didn't
  -- touch in a kernel patch.
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

-- Registered by the machine-local config at the bottom of this file. Called
-- with the current file's directory, returns nil or:
--   { root = <dir>, cmd = {...}, cmd_cwd = <dir>, settings = {...} }
-- First match wins, Cargo detection is the fallback. Non-Cargo builds need a
-- different server invocation, hence cmd and settings and not just a root.
_G.rust_project_detectors = {}

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
      -- Search upward from the FILE: vim.fs.find defaults `path` to the cwd,
      -- which silently yields a nil root and "failed to discover workspace".
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

-- Registered by the machine-local config at the bottom of this file. Called
-- with the current file's directory, returns nil or:
--   { root = <dir>, bin = <clangd path>, header_insertion = "iwyu"|"never" }
-- First match wins; built-in detection runs when none match. Keeps
-- site-specific monorepo and toolchain knowledge out of this repo.
_G.cpp_project_detectors = {}

-- Unlike a detector this applies to every project type, including kernel
-- trees, which never reach the detectors.
_G.clangd_extra_candidates = {}

local function clangd_bin()
  local exe = vim.fn.exepath('clangd')
  if exe ~= '' then return exe end
  local candidates = { '/opt/homebrew/opt/llvm/bin/clangd' }
  vim.list_extend(candidates, _G.clangd_extra_candidates)
  for _, p in ipairs(candidates) do
    if vim.fn.executable(p) == 1 then return p end
  end
  return 'clangd'
end

-- Kbuild+Kconfig+MAINTAINERS at the same dir is a kernel-tree signal that
-- other C projects won't trip.
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

-- clangd writes .cache/clangd/ under the project root and the kernel's tracked
-- .gitignore doesn't cover it; .git/info/exclude is never committed.
local excluded = {}
local function exclude_clangd_cache(root)
  if not root or excluded[root] then return end
  excluded[root] = true
  local info = root .. "/.git/info"
  if vim.fn.isdirectory(info) == 0 then return end   -- not a plain git clone
  local path = info .. "/exclude"
  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  for _, l in ipairs(lines) do
    if l == ".cache/" then return end
  end
  table.insert(lines, ".cache/")
  pcall(vim.fn.writefile, lines, path)
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sh" },
  callback = function(ev)
    local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(ev.buf))
    if kernel_root(dir) then
      vim.bo[ev.buf].expandtab = false
      vim.bo[ev.buf].shiftwidth = 8
      vim.bo[ev.buf].softtabstop = 0
    end
  end,
  desc = "Tab-indent shell scripts in kernel trees",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = {"c", "cpp"},
  callback = function()
    local kroot = kernel_root()
    exclude_clangd_cache(kroot)
    local proj
    if not kroot then
      local dir = vim.fn.expand("%:p:h")
      for _, detect in ipairs(_G.cpp_project_detectors) do
        proj = detect(dir)
        if proj then break end
      end
    end
    -- Detectors take precedence over the nearest compile DB / .clangd / git
    -- root: a monorepo's nearest .clangd can sit well below its compile DB.
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
        -- Kernel include rules aren't IWYU, so its suggestions are wrong there.
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

-- :KernelCCDB [objdir] — needs a built tree (the target scans make's .cmd
-- files). For an O= build pass the objdir, or set vim.g.kernel_objdir once:
-- the .cmd files live there. Run :LspRestart after.
vim.api.nvim_create_user_command("KernelCCDB", function(opts)
  local root = kernel_root()
  if not root then
    vim.notify("KernelCCDB: not inside a Linux kernel tree", vim.log.levels.ERROR)
    return
  end
  local objdir = opts.args ~= "" and vim.fn.fnamemodify(opts.args, ":p:h")
    or vim.g.kernel_objdir
  local cmd = { "make", "-C", root }
  if objdir then table.insert(cmd, "O=" .. objdir) end
  table.insert(cmd, "compile_commands.json")

  vim.notify("KernelCCDB: make compile_commands.json in " .. (objdir or root) .. " ...")
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("KernelCCDB failed:\n" .. out, vim.log.levels.ERROR)
    return
  end

  if objdir then
    -- Link rather than copy so a later regeneration in the objdir is picked
    -- up without re-running this.
    local link = root .. "/compile_commands.json"
    local target = objdir .. "/compile_commands.json"
    if vim.fn.resolve(link) ~= target then
      vim.fn.delete(link)
      vim.fn.system({ "ln", "-s", target, link })
      if vim.v.shell_error ~= 0 then
        vim.notify("KernelCCDB: generated " .. target ..
          " but could not link it into " .. root, vim.log.levels.WARN)
        return
      end
    end
  end
  vim.notify("KernelCCDB: done — run :LspRestart to pick up the new DB")
end, { nargs = "?", complete = "dir", desc = "Regenerate the kernel compile_commands.json" })

-- Loaded last so it can override anything above. Outside ~/.config/nvim,
-- which is a symlink into this repo, so private settings stay unpublished.
local local_init = vim.fn.expand("~/.config/nvim-local/init.lua")
if vim.fn.filereadable(local_init) == 1 then
  local ok, err = pcall(dofile, local_init)
  if not ok then
    vim.notify("nvim-local/init.lua failed:\n" .. tostring(err), vim.log.levels.ERROR)
  end
end
