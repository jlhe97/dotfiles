local M = {}
local files, snapshots = {}, {}
local config_dir, config_text, defaults_path, start_client
local pending = {}
local restart_scheduled = false

local function normalize(path)
  return vim.fs.normalize(path, { expand_env = false })
end

local function policy(path, directory_configs)
  local configs, seen = {}, {}
  for _, file in ipairs({ path, vim.uv.fs_realpath(path) or path }) do
    local dir = vim.fs.dirname(file)
    while dir and not seen[dir] do
      seen[dir] = true
      if not directory_configs[dir] then
        directory_configs[dir] = {}
        for _, name in ipairs({ '.clangd', '.clang-tidy' }) do
          local p = dir .. '/' .. name
          local stat = vim.uv.fs_stat(p)
          if stat and stat.type == 'file' then
            table.insert(directory_configs[dir], p .. ':' .. stat.size .. ':'
              .. stat.mtime.sec .. ':' .. stat.mtime.nsec)
          end
        end
      end
      vim.list_extend(configs, directory_configs[dir])
      local parent = vim.fs.dirname(dir)
      if parent == dir then break end
      dir = parent
    end
  end
  table.sort(configs)
  return table.concat(configs, '\n')
end

local function restart(clients)
  local buffers = {}
  for _, client in ipairs(clients) do
    for buf in pairs(client.attached_buffers) do buffers[buf] = true end
    client:stop()
  end
  local deadline = vim.uv.hrtime() + 3000000000
  local function resume()
    for _, client in ipairs(clients) do
      if not client:is_stopped() then
        if vim.uv.hrtime() < deadline then
          vim.defer_fn(resume, 50)
          return
        end
        client:stop(true)
      end
    end
    for ns, info in pairs(vim.diagnostic.get_namespaces()) do
      local id = info.name:match('^nvim%.lsp%.clangd%.(%d+)')
      local client = id and vim.lsp.get_client_by_id(tonumber(id))
      if id and (not client or client:is_stopped()) then vim.diagnostic.reset(ns) end
    end
    for buf in pairs(buffers) do
      if vim.api.nvim_buf_is_loaded(buf)
        and (vim.bo[buf].filetype == 'c' or vim.bo[buf].filetype == 'cpp') then
        start_client(buf)
      end
    end
  end
  vim.schedule(resume)
end

local function queue_restart(changed)
  for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
    for buf in pairs(client.attached_buffers) do
      if changed[normalize(vim.api.nvim_buf_get_name(buf))] then
        pending[client.id] = client
      end
    end
  end
  if restart_scheduled or not next(pending) then return end
  restart_scheduled = true
  vim.schedule(function()
    local clients = vim.tbl_values(pending)
    pending, restart_scheduled = {}, false
    restart(clients)
  end)
end

local function write_config(text)
  if text == config_text then return end
  if not config_dir then
    config_dir = vim.fn.tempname() .. '-clangd'
    vim.fn.mkdir(config_dir .. '/clangd', 'p', 448)
  end
  local path = config_dir .. '/clangd/config.yaml'
  local tmp = path .. '.tmp'
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), tmp)
  assert(vim.uv.fs_rename(tmp, path))
  config_text = text
end

function M.refresh()
  if vim.fn.has('linux') ~= 1 then return end
  local paths, changed, current, directory_configs = {}, {}, {}, {}
  local defaults = table.concat(vim.fn.readfile(defaults_path), '\n')
  for file in pairs(files) do
    local repo_policy = policy(file, directory_configs)
    current[file] = repo_policy ~= '' and repo_policy or defaults
    if repo_policy == '' then
      for _, path in ipairs({ file, vim.uv.fs_realpath(file) or file }) do
        paths[normalize(path)] = true
      end
    end
    if snapshots[file] and snapshots[file] ~= current[file] then changed[file] = true end
  end
  local patterns = {}
  for path in pairs(paths) do
    patterns[#patterns + 1] = path:gsub('([\\.^$|?*+(){}%[%]])', '\\%1')
  end
  table.sort(patterns)
  local text = '{}\n'
  if #patterns > 0 then
    text = 'If:\n  PathMatch: ' .. vim.json.encode(patterns) .. '\n' .. defaults .. '\n'
  end
  write_config(text)
  snapshots = current
  queue_restart(changed)
end

function M.prepare(file, root)
  if vim.fn.has('linux') ~= 1 then return nil end
  file = normalize(file)
  local is_new = not files[file]
  files[file] = true
  local old_config = config_text
  M.refresh()
  -- clangd caches YAML for five seconds, including on a new file's didOpen.
  if is_new and old_config and old_config ~= config_text then
    for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do
      if client.root_dir == root then pending[client.id] = client end
    end
    queue_restart({})
  end
  return { XDG_CONFIG_HOME = config_dir }
end

function M.restart()
  M.refresh()
  restart(vim.lsp.get_clients({ name = 'clangd' }))
end

function M.setup(start, defaults)
  start_client, defaults_path = start, defaults
  local group = vim.api.nvim_create_augroup('DotfilesClangd', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'c', 'cpp' },
    callback = function(ev) start_client(ev.buf) end,
  })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
    group = group,
    callback = function(ev)
      if config_dir and (ev.event == 'FocusGained'
        or files[normalize(vim.api.nvim_buf_get_name(ev.buf))]) then M.refresh() end
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = { '.clangd', '.clang-tidy', 'config.yaml' },
    callback = function()
      if config_dir then M.refresh() end
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      for _, client in ipairs(vim.lsp.get_clients({ name = 'clangd' })) do client:stop(true) end
      if config_dir then vim.fn.delete(config_dir, 'rf') end
    end,
  })
  vim.api.nvim_create_user_command('ClangdRestart', M.restart, {
    desc = 'Refresh repository policies and restart clangd for its buffers',
  })
end

return M
