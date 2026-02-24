local T = MiniTest.new_set()

local function setup_buffer(lines, cursor)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  if cursor then
    vim.api.nvim_win_set_cursor(0, cursor)
  end
  return bufnr
end

T['code_actions'] = MiniTest.new_set()

T['code_actions']['identifies unresolved ref and offers creation'] = function()
  local df = _G.reload_dataform()

  -- Mock empty graph
  df.compiled_project_table = { tables = {} }

  setup_buffer({ 'SELECT * FROM ${ref("missing_table")}' }, { 1, 25 })

  -- Mock vim.ui.select to capture actions
  local captured_actions = {}
  local old_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    captured_actions = items
  end

  df.code_action()

  MiniTest.expect.equality(#captured_actions, 1)
  MiniTest.expect.equality(captured_actions[1].title:find("missing_table") ~= nil, true)

  -- Cleanup
  vim.ui.select = old_select
end

T['code_actions']['create_declaration logic'] = function()
  local df = _G.reload_dataform()

  -- Mock filesystem calls
  local mkdir_called = false
  local old_mkdir = vim.fn.mkdir
  vim.fn.mkdir = function() mkdir_called = true end

  local file_content = ""
  local old_open = io.open
  io.open = function(path, mode)
    if mode == "w" then
      return {
        write = function(self, content) file_content = content end,
        close = function() end
      }
    end
    return nil
  end

  local old_open_file = require('dataform.utils').open_file
  require('dataform.utils').open_file = function() end

  df.create_declaration("my_schema", "my_table")

  MiniTest.expect.equality(file_content:find('schema: "my_schema"') ~= nil, true)
  MiniTest.expect.equality(file_content:find('name: "my_table"') ~= nil, true)
  MiniTest.expect.equality(file_content:find('type: "declaration"') ~= nil, true)

  -- Cleanup
  vim.fn.mkdir = old_mkdir
  io.open = old_open
  require('dataform.utils').open_file = old_open_file
end

T['code_actions']['offers to document unknown columns'] = function()
  local df = _G.reload_dataform()

  -- Mock graph with no columns
  df.compiled_project_table = { tables = {} }

  setup_buffer({ 'SELECT new_col FROM table' }, { 1, 8 }) -- On new_col

  local actions = df.get_code_actions()
  local found = false
  for _, a in ipairs(actions) do
    if a.title:find("Document column 'new_col'") then found = true end
  end

  MiniTest.expect.equality(found, true)
end

return T
