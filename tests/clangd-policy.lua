local test_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local repo = vim.fs.dirname(vim.fs.dirname(test_path))
local module = repo .. '/.config/nvim/lua/dotfiles/clangd.lua'
local policy = dofile(module)
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local defaults = root .. '/fallback.yaml'
vim.fn.writefile({ 'CompileFlags:', '  Add: [-DPERSONAL_FALLBACK]' }, defaults)
local original = table.concat(vim.fn.readfile(defaults), '\n')
local binary = vim.env.CLANGD_TEST_BIN or vim.fn.exepath('clangd')
local source = {
  '#ifdef PERSONAL_FALLBACK',
  '#warning personal fallback',
  '#elif defined(UPDATED_POLICY)',
  '#warning updated repository policy',
  '#else',
  '#warning repository policy',
  '#endif',
  'int selected() { return 0; }',
}
local function file(name, config)
  local path = root .. '/' .. name .. '/file.cpp'
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(source, path)
  if config then
    vim.fn.writefile(config.lines, vim.fs.dirname(path) .. '/' .. config.name)
  end
  return path
end

local start
start = function(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local env = policy.prepare(path, root)
  if binary ~= '' then
    return vim.lsp.start({
      name = 'clangd',
      cmd = { binary, '--background-index=false', '--clang-tidy', '--log=error' },
      root_dir = root,
      cmd_env = env,
    }, { bufnr = buf })
  end
end
policy.setup(start, defaults)

local function open(path, expected)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = 'cpp'
  if binary ~= '' then
    assert(vim.wait(15000, function()
      for _, d in ipairs(vim.diagnostic.get(buf)) do
        if d.message:lower():find(expected, 1, true) then return true end
      end
      return false
    end, 20), path .. ': expected diagnostic ' .. expected
      .. '\n' .. vim.inspect(vim.diagnostic.get(buf))
      .. '\nclients: ' .. #vim.lsp.get_clients({ name = 'clangd' }))
  end
  return buf
end

local plain = file('plain')
local managed = file('managed', { name = '.clangd', lines = { 'CompileFlags:', '  Add: [-DREPO_POLICY]' } })
local tidy = file('tidy', { name = '.clang-tidy', lines = { 'Checks: "-*"' } })
local nested = file('plain/nested', {
  name = '.clangd', lines = { 'If:', '  PathMatch: never-matches', 'CompileFlags:', '  Add: [-DREPO_POLICY]' },
})
local synthetic = file('synthetic')
vim.fn.mkdir(vim.fs.dirname(synthetic) .. '/.clangd', 'p')
vim.fn.mkdir(vim.fs.dirname(synthetic) .. '/.clang-tidy', 'p')
local special = root .. '/plain/a[1](b)+$.cpp'
vim.fn.writefile(source, special)

local env = policy.prepare(managed, root)
open(managed, 'repository policy')
assert(table.concat(vim.fn.readfile(env.XDG_CONFIG_HOME .. '/clangd/config.yaml'), '\n'):match('^{}%s*$'),
  'repository-only configuration should be a valid YAML mapping')
for _, d in ipairs(vim.diagnostic.get()) do
  assert(d.source ~= 'clangd-config' or d.severity ~= vim.diagnostic.severity.ERROR,
    'generated config has an error: ' .. d.message)
end
open(plain, 'personal fallback')
open(managed, 'repository policy')
open(tidy, 'repository policy')
open(nested, 'repository policy')
open(synthetic, 'personal fallback')
open(special, 'personal fallback')
assert(policy.prepare(managed, root).XDG_CONFIG_HOME == env.XDG_CONFIG_HOME)
local generated = table.concat(vim.fn.readfile(env.XDG_CONFIG_HOME .. '/clangd/config.yaml'), '\n')
assert(generated:find('PERSONAL_FALLBACK', 1, true))
assert(not generated:find(managed, 1, true))
assert(not generated:find(tidy, 1, true))
assert(not generated:find(nested, 1, true))

-- Config creation, edits and removal must update a buffer that is already open.
local config = vim.fs.dirname(plain) .. '/.clangd'
vim.fn.writefile({ 'CompileFlags:', '  Add: [-DREPO_POLICY]' }, config)
vim.api.nvim_exec_autocmds('BufWritePost', { pattern = config })
open(plain, 'repository policy')
vim.fn.writefile({ 'CompileFlags:', '  Add: [-DUPDATED_POLICY]' }, config)
vim.api.nvim_exec_autocmds('FocusGained', {})
open(plain, 'updated repository policy')
vim.fn.delete(config)
vim.api.nvim_exec_autocmds('BufEnter', { buffer = vim.fn.bufnr(plain) })
open(plain, 'personal fallback')

assert(table.concat(vim.fn.readfile(defaults), '\n') == original, 'defaults were overwritten')
assert(not env.XDG_CONFIG_HOME:find(repo, 1, true), 'generated paths entered the public repo')
if binary ~= '' then
  assert(vim.wait(5000, function()
    local clients = vim.lsp.get_clients({ name = 'clangd' })
    return #clients == 1 and clients[1].initialized
  end, 20), 'buffers should share one project client')
  local client = vim.lsp.get_clients({ name = 'clangd' })[1]
  local external = vim.fn.bufadd(root .. '/unattached-config.yaml')
  vim.fn.bufload(external)
  vim.diagnostic.set(vim.lsp.diagnostic.get_namespace(client.id), external, {
    { lnum = 0, col = 0, message = 'stale config diagnostic', severity = vim.diagnostic.severity.ERROR },
  })
  policy.restart()
  assert(vim.wait(15000, function()
    local active = vim.lsp.get_clients({ name = 'clangd' })
    return #active == 1 and active[1].id ~= client.id and active[1].initialized
  end, 20), 'clangd did not restart')
  assert(#vim.diagnostic.get(external) == 0, 'stopped client left config diagnostics behind')
  print('Repository, tidy-only, nested, synthetic-directory, special-path and refresh scenarios passed with clangd')
else
  print('Discovery passed; set CLANGD_TEST_BIN to verify live diagnostics')
end
vim.fn.delete(root, 'rf')
