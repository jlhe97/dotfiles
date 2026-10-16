
if vim.fn.has('nvim-0.12') ~= 1 then
  local ok, v = pcall(vim.version)
  local found = (ok and type(v) == 'table')
    and string.format('%d.%d.%d', v.major, v.minor, v.patch) or 'an older release'
  error(('this config requires Neovim 0.12 or newer (found %s)'):format(found), 0)
end

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

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
vim.call('plug#', 'lewis6991/gitsigns.nvim')
vim.call('plug#', 'folke/trouble.nvim')
vim.call('plug#', 'nvim-treesitter/nvim-treesitter', { branch = 'main' })
vim.call('plug#', 'nvim-treesitter/nvim-treesitter-textobjects', { branch = 'main' })
vim.call('plug#', 'folke/persistence.nvim')
vim.call('plug#', 'mg979/vim-visual-multi')
vim.call('plug#', 'MunifTanjim/nui.nvim')   -- required by noice
vim.call('plug#', 'folke/noice.nvim')       -- floating : cmdline (see below)
vim.call('plug#', 'folke/which-key.nvim')   -- discoverable Space-prefix keymaps
vim.call('plug#', 'NMAC427/guess-indent.nvim') -- best guess indentation convention

-- vim-visual-multi: Ctrl+D selects the next occurrence (Ctrl+N is taken by NERDTree)
vim.g.VM_maps = {
  ['Find Under'] = '<C-d>',
  ['Find Subword Under'] = '<C-d>',
}
vim.call('plug#end')

pcall(function()
  local which_key = require('which-key')
  which_key.setup({
    delay = 300,
    icons = { mappings = false },
  })
  which_key.add({
    { '<leader>b', group = 'buffers' },
    { '<leader>c', group = 'code / LSP' },
    { '<leader>f', group = 'file / find' },
    { '<leader>g', group = 'git' },
    { '<leader>gh', group = 'hunks' },
    { '<leader>q', group = 'session / quickfix' },
    { '<leader>s', group = 'search' },
    { '<leader>u', group = 'UI' },
    { '<leader>x', group = 'diagnostics' },
  })
end)

-- fallback only if .editorconfig and guess-indent don't set it for us
vim.opt.number = true
vim.opt.expandtab = true
vim.opt.tabstop = 8
vim.opt.shiftwidth = 4
vim.opt.softtabstop = -1 -- follow shiftwidth
vim.opt.autoindent = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 300

vim.opt.termguicolors = true
vim.o.background = 'dark'
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

pcall(function()
  require('gitsigns').setup({
    signs = {
      add = { text = '│' },
      change = { text = '│' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
      untracked = { text = '┆' },
    },
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns
      local function git_map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, {
          buffer = bufnr,
          silent = true,
          desc = desc,
        })
      end

      git_map('n', ']h', function()
        if vim.wo.diff then
          vim.cmd.normal({ ']c', bang = true })
        else
          gs.nav_hunk('next')
        end
      end, 'Next Git hunk')
      git_map('n', '[h', function()
        if vim.wo.diff then
          vim.cmd.normal({ '[c', bang = true })
        else
          gs.nav_hunk('prev')
        end
      end, 'Previous Git hunk')
      git_map('n', ']H', function() gs.nav_hunk('last') end, 'Last Git hunk')
      git_map('n', '[H', function() gs.nav_hunk('first') end, 'First Git hunk')
      git_map({ 'n', 'x' }, '<leader>ghs', ':Gitsigns stage_hunk<CR>', 'Stage Git hunk')
      git_map({ 'n', 'x' }, '<leader>ghr', ':Gitsigns reset_hunk<CR>', 'Reset Git hunk')
      git_map('n', '<leader>ghS', gs.stage_buffer, 'Stage Git buffer')
      git_map('n', '<leader>ghp', gs.preview_hunk_inline, 'Preview Git hunk')
      git_map('n', '<leader>ghb', function()
        gs.blame_line({ full = true })
      end, 'Blame current line')
      git_map('n', '<leader>ghB', gs.blame, 'Blame current buffer')
      git_map('n', '<leader>ghd', gs.diffthis, 'Diff current buffer')
      git_map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', 'Select Git hunk')
    end,
  })
end)

pcall(function()
  require('trouble').setup({
    modes = {
      lsp = { win = { position = 'right' } },
    },
  })
end)

-- Do not download parsers during startup: that makes editor startup depend on
-- network/proxy state. :TSInstallCore explicitly installs the portable set.
local treesitter_languages = {
  'bash',
  'c',
  'cmake',
  'cpp',
  'diff',
  'json',
  'lua',
  'make',
  'markdown',
  'markdown_inline',
  'python',
  'query',
  'rust',
  'toml',
  'vim',
  'vimdoc',
  'yaml',
}

pcall(function()
  require('nvim-treesitter').setup({
    install_dir = vim.fn.stdpath('data') .. '/site',
  })

  vim.api.nvim_create_user_command('TSInstallCore', function()
    require('nvim-treesitter').install(treesitter_languages)
  end, { desc = 'Install the configured Treesitter parsers' })

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('PortableTreesitter', { clear = true }),
    pattern = treesitter_languages,
    callback = function(event)
      local lang = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)
      if lang then pcall(vim.treesitter.start, event.buf, lang) end
    end,
  })
end)

pcall(function()
  require('nvim-treesitter-textobjects').setup({
    move = { set_jumps = true },
  })

  local move = require('nvim-treesitter-textobjects.move')
  local repeat_move = require('nvim-treesitter-textobjects.repeatable_move')
  local modes = { 'n', 'x', 'o' }
  local function ts_map(lhs, rhs, desc)
    vim.keymap.set(modes, lhs, rhs, { silent = true, desc = desc })
  end

  ts_map(']f', function()
    move.goto_next_start('@function.outer', 'textobjects')
  end, 'Next function start')
  ts_map('[f', function()
    move.goto_previous_start('@function.outer', 'textobjects')
  end, 'Previous function start')
  ts_map(']F', function()
    move.goto_next_end('@function.outer', 'textobjects')
  end, 'Next function end')
  ts_map('[F', function()
    move.goto_previous_end('@function.outer', 'textobjects')
  end, 'Previous function end')

  ts_map(']c', function()
    move.goto_next_start('@class.outer', 'textobjects')
  end, 'Next class start')
  ts_map('[c', function()
    move.goto_previous_start('@class.outer', 'textobjects')
  end, 'Previous class start')
  ts_map(']C', function()
    move.goto_next_end('@class.outer', 'textobjects')
  end, 'Next class end')
  ts_map('[C', function()
    move.goto_previous_end('@class.outer', 'textobjects')
  end, 'Previous class end')

  ts_map(']o', function()
    move.goto_next_start({ '@loop.inner', '@loop.outer' }, 'textobjects')
  end, 'Next loop')
  ts_map('[o', function()
    move.goto_previous_start({ '@loop.inner', '@loop.outer' }, 'textobjects')
  end, 'Previous loop')
  ts_map(']s', function()
    move.goto_next_start('@local.scope', 'locals')
  end, 'Next local scope')
  ts_map('[s', function()
    move.goto_previous_start('@local.scope', 'locals')
  end, 'Previous local scope')
  ts_map(']z', function()
    move.goto_next_start('@fold', 'folds')
  end, 'Next fold')
  ts_map('[z', function()
    move.goto_previous_start('@fold', 'folds')
  end, 'Previous fold')

  vim.keymap.set(modes, ';', repeat_move.repeat_last_move,
    { desc = 'Repeat last movement' })
  vim.keymap.set(modes, ',', repeat_move.repeat_last_move_opposite,
    { desc = 'Repeat last movement opposite' })
  vim.keymap.set(modes, 'f', repeat_move.builtin_f_expr, { expr = true })
  vim.keymap.set(modes, 'F', repeat_move.builtin_F_expr, { expr = true })
  vim.keymap.set(modes, 't', repeat_move.builtin_t_expr, { expr = true })
  vim.keymap.set(modes, 'T', repeat_move.builtin_T_expr, { expr = true })
end)

-- Save project sessions only after a real file has been opened. Terminal and
-- help buffers are deliberately excluded from the restored workspace.
vim.opt.sessionoptions = {
  'buffers',
  'curdir',
  'folds',
  'localoptions',
  'tabpages',
  'winpos',
  'winsize',
}
pcall(function()
  require('persistence').setup({
    need = 1,
    branch = true,
  })
end)
vim.keymap.set('n', '<leader>qs', function()
  require('persistence').load()
end, { silent = true, desc = 'Restore project session' })
vim.keymap.set('n', '<leader>qS', function()
  require('persistence').select()
end, { silent = true, desc = 'Select session' })
vim.keymap.set('n', '<leader>ql', function()
  require('persistence').load({ last = true })
end, { silent = true, desc = 'Restore last session' })
vim.keymap.set('n', '<leader>qd', function()
  require('persistence').stop()
end, { silent = true, desc = "Don't save current session" })

vim.g.NERDTreeShowHidden = 1          -- show dotfiles
vim.g.NERDTreeMinimalUI = 1           -- hide the help hint / bookmarks header
vim.g.NERDTreeQuitOnOpen = 0          -- keep the tree open after opening a file
vim.keymap.set('n', '<C-n>', '<cmd>NERDTreeToggle<CR>',
  { silent = true, desc = 'Explorer toggle' })
vim.keymap.set('n', '<leader>e', '<cmd>NERDTreeToggle<CR>',
  { silent = true, desc = 'Explorer toggle' })
vim.keymap.set('n', '<leader>fe', '<cmd>NERDTreeFind<CR>',
  { silent = true, desc = 'Explorer reveal current file' })

-- fzf replaces mnvim's Myles picker in the regular profile. It needs the
-- system fzf and ripgrep packages installed by install.sh.
vim.keymap.set('n', '<C-p>', '<cmd>Files<CR>',
  { silent = true, desc = 'Find files (FZF)' })
vim.keymap.set('n', '<leader>p', '<cmd>Files<CR>',
  { silent = true, desc = 'Find files (FZF)' })
vim.keymap.set('n', '<leader>ff', '<cmd>Files<CR>',
  { silent = true, desc = 'Find files (FZF)' })
vim.keymap.set('n', '<leader>fg', '<cmd>GFiles<CR>',
  { silent = true, desc = 'Find Git files (FZF)' })
vim.keymap.set('n', '<leader>sg', '<cmd>Rg<CR>',
  { silent = true, desc = 'Grep project (FZF)' })
vim.keymap.set('n', '<leader>/', '<cmd>Rg<CR>',
  { silent = true, desc = 'Grep project (FZF)' })
vim.keymap.set('n', '<leader>fb', '<cmd>Buffers<CR>',
  { silent = true, desc = 'Find buffers (FZF)' })
vim.keymap.set('n', '<leader>fr', '<cmd>History<CR>',
  { silent = true, desc = 'Recent files (FZF)' })
vim.keymap.set('n', '<leader>sb', '<cmd>BLines<CR>',
  { silent = true, desc = 'Search current buffer lines (FZF)' })
vim.keymap.set('n', '<leader>sB', '<cmd>Lines<CR>',
  { silent = true, desc = 'Search open buffer lines (FZF)' })
vim.keymap.set('n', '<leader>sh', '<cmd>Helptags<CR>',
  { silent = true, desc = 'Search help tags (FZF)' })
vim.keymap.set('n', '<leader>sk', '<cmd>Maps<CR>',
  { silent = true, desc = 'Search keymaps (FZF)' })
vim.keymap.set('n', '<leader>sc', '<cmd>History:<CR>',
  { silent = true, desc = 'Search command history (FZF)' })
vim.keymap.set('n', '<leader>sC', '<cmd>Commands<CR>',
  { silent = true, desc = 'Search commands (FZF)' })
vim.keymap.set('n', '<leader>sw', ':Rg <C-R><C-W><CR>',
  { silent = true, desc = 'Search word under cursor (FZF)' })

vim.keymap.set('n', '<leader>bn', '<cmd>bnext<CR>',
  { silent = true, desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bp', '<cmd>bprevious<CR>',
  { silent = true, desc = 'Previous buffer' })
vim.keymap.set('n', '<leader>bq', '<cmd>bdelete<CR>',
  { silent = true, desc = 'Close current buffer' })
vim.keymap.set('n', '<Left>', '<C-w>h', { desc = 'Go to left window' })
vim.keymap.set('n', '<Down>', '<C-w>j', { desc = 'Go to lower window' })
vim.keymap.set('n', '<Up>', '<C-w>k', { desc = 'Go to upper window' })
vim.keymap.set('n', '<Right>', '<C-w>l', { desc = 'Go to right window' })
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Go to left window' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Go to lower window' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Go to upper window' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Go to right window' })

vim.keymap.set('n', '<leader>n', '<cmd>messages<CR>',
  { silent = true, desc = 'Notification history' })
vim.keymap.set('n', '<leader>uh', '<cmd>messages<CR>',
  { silent = true, desc = 'Notification history' })

vim.opt.grepprg = 'rg --vimgrep'
vim.opt.grepformat = '%f:%l:%c:%m'

vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = 'grep',
  command = 'cwindow',
})

local trouble_or_quickfix = function(direction)
  local ok, trouble = pcall(require, 'trouble')
  if ok and trouble.is_open() then
    trouble[direction]({ skip_groups = true, jump = true })
    return
  end

  local command = direction == 'next' and 'cnext' or 'cprevious'
  local success, err = pcall(vim.cmd, command)
  if not success then vim.notify(err, vim.log.levels.ERROR) end
end
vim.keymap.set('n', ']q', function() trouble_or_quickfix('next') end,
  { silent = true, desc = 'Next quickfix/Trouble item' })
vim.keymap.set('n', '[q', function() trouble_or_quickfix('prev') end,
  { silent = true, desc = 'Previous quickfix/Trouble item' })
vim.keymap.set('n', '<leader>qf', '<cmd>copen<CR>', { silent = true, desc = 'Open quickfix list' })

local diagnostic_jump = function(count)
  if vim.diagnostic.jump then
    vim.diagnostic.jump({ count = count, float = true })
  elseif count < 0 then
    vim.diagnostic.goto_prev()
  else
    vim.diagnostic.goto_next()
  end
end
vim.keymap.set('n', '[d', function() diagnostic_jump(-1) end,
  { silent = true, desc = 'Previous diagnostic' })
vim.keymap.set('n', ']d', function() diagnostic_jump(1) end,
  { silent = true, desc = 'Next diagnostic' })
vim.keymap.set('n', '<leader>sd', function()
  vim.diagnostic.setloclist({ open = true })
end, { silent = true, desc = 'Document diagnostics' })
vim.keymap.set('n', '<leader>xx', '<cmd>Trouble diagnostics toggle<CR>',
  { silent = true, desc = 'Diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<CR>',
  { silent = true, desc = 'Buffer diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>cs', '<cmd>Trouble symbols toggle<CR>',
  { silent = true, desc = 'Document symbols (Trouble)' })
vim.keymap.set('n', '<leader>cS', '<cmd>Trouble lsp toggle<CR>',
  { silent = true, desc = 'LSP definitions/references (Trouble)' })
vim.keymap.set('n', '<leader>xL', '<cmd>Trouble loclist toggle<CR>',
  { silent = true, desc = 'Location list (Trouble)' })
vim.keymap.set('n', '<leader>xQ', '<cmd>Trouble qflist toggle<CR>',
  { silent = true, desc = 'Quickfix list (Trouble)' })
vim.keymap.set('n', '<leader>cl', function()
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify('No LSP clients attached to this buffer', vim.log.levels.INFO)
    return
  end

  local lines = {}
  for _, client in ipairs(clients) do
    local root = client.root_dir or (client.config and client.config.root_dir) or 'no root'
    table.insert(lines, string.format('%s (id %d) — %s', client.name, client.id, root))
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'LSP clients' })
end, { silent = true, desc = 'LSP info' })

local on_attach = function(client, bufnr)
  local function lsp_map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, {
      noremap = true,
      silent = true,
      buffer = bufnr,
      desc = desc,
    })
  end

  lsp_map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
  lsp_map('n', 'gD', vim.lsp.buf.declaration, 'Go to declaration')
  lsp_map('n', 'K', vim.lsp.buf.hover, 'Hover documentation')
  lsp_map('n', 'gK', vim.lsp.buf.signature_help, 'Signature help')
  lsp_map('i', '<C-k>', vim.lsp.buf.signature_help, 'Signature help')
  lsp_map('n', 'gi', vim.lsp.buf.implementation, 'Go to implementation')
  lsp_map('n', 'gI', vim.lsp.buf.implementation, 'Go to implementation')
  lsp_map('n', 'gy', vim.lsp.buf.type_definition, 'Go to type definition')
  lsp_map('n', 'gr', vim.lsp.buf.references, 'Find references')
  lsp_map('n', '<leader>cr', vim.lsp.buf.rename, 'Rename symbol')
  lsp_map('n', '<leader>rn', vim.lsp.buf.rename, 'Rename symbol (legacy)')
  lsp_map('n', '<leader>ca', vim.lsp.buf.code_action, 'Code action')

  -- Visual mode formats only the selection: don't reformat code you didn't
  -- touch in a kernel patch.
  lsp_map('n', '<leader>f', function()
    vim.lsp.buf.format({ async = true })
  end, 'Format buffer')
  lsp_map('x', '<leader>f', function()
    local s = vim.api.nvim_buf_get_mark(0, '<')
    local e = vim.api.nvim_buf_get_mark(0, '>')
    local ok = pcall(vim.lsp.buf.format, {
      async = true,
      range = { ['start'] = { s[1], 0 }, ['end'] = { e[1], 0 } },
    })
    if not ok then vim.lsp.buf.format({ async = true }) end
  end, 'Format selection')
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
