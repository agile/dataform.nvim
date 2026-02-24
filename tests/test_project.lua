local T = MiniTest.new_set()

local function setup_buffer(lines, cursor)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, cursor)
  return bufnr
end

T['get_context_at_cursor()'] = MiniTest.new_set()

T['get_context_at_cursor()']['identifies project variables'] = function()
  setup_buffer({ 'SELECT ${dataform.projectConfig.vars.my_var} FROM table' }, { 1, 35 })

  local context = require('dataform.project').get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'variable')
  MiniTest.expect.equality(context.var_name, 'my_var')
end

T['get_context_at_cursor()']['identifies ref() calls'] = function()
  setup_buffer({ 'SELECT * FROM ${ref("my_table")}' }, { 1, 25 })

  local context = require('dataform.project').get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.table_name, 'my_table')
end

T['get_context_at_cursor()']['identifies schema and table in ref()'] = function()
  setup_buffer({ 'SELECT * FROM ${ref("my_schema", "my_table")}' }, { 1, 24 }) -- On "my_schema"

  local context = require('dataform.project').get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.schema, 'my_schema')
  MiniTest.expect.equality(context.table_name, 'my_table')
end

T['get_context_at_cursor()']['identifies js functions'] = function()
  setup_buffer({ 'const x = my_func(123)' }, { 1, 12 })

  local context = require('dataform.project').get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'function')
  MiniTest.expect.equality(context.func_name, 'my_func')
end

T['get_context_at_cursor()']['handles dots in words'] = function()
  setup_buffer({ 'SELECT ${constants.TAX_RATE} FROM table' }, { 1, 15 })

  local context = require('dataform.project').get_context_at_cursor()
  MiniTest.expect.equality(context.word, 'constants.TAX_RATE')
end

T['actions'] = MiniTest.new_set()

T['actions']['go_to_ref() handles local js function'] = function()
  setup_buffer({
    'js {',
    '  function myLocalFunc() {}',
    '}',
    'SELECT ${myLocalFunc()}'
  }, { 4, 12 })

  -- Mock open_file to avoid actually opening a file
  local old_open = require('dataform.utils').open_file
  require('dataform.utils').open_file = function() end

  require('dataform.project').go_to_ref()

  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2) -- Should move to line 2

  require('dataform.utils').open_file = old_open
end

T['actions']['hover() handles js function'] = function()
  local df = require('dataform.project')
  df.compiled_project_table = {
    tables = {
      {
        target = { database = "db", schema = "s", name = "my_table" },
        fileName = "definitions/my_table.sqlx",
        type = "table"
      }
    }
  }
  setup_buffer({ 'SELECT ${ref("my_table")}' }, { 1, 15 })

  -- Mock open_floating_preview
  local captured_lines = {}
  local old_preview = vim.lsp.util.open_floating_preview
  vim.lsp.util.open_floating_preview = function(lines) captured_lines = lines end

  require('dataform.project').hover()
  MiniTest.expect.equality(captured_lines[1]:find("my_table") ~= nil, true)

  -- Test JS function hover
  captured_lines = {}
  setup_buffer({ 'js { function test() {} }', 'SELECT ${test( ' }, { 2, 12 })

  require('dataform.project').hover()
  MiniTest.expect.equality(captured_lines[1] ~= nil and captured_lines[1]:find("Function: test") ~= nil, true)

  vim.lsp.util.open_floating_preview = old_preview
end

return T

