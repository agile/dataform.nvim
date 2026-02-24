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

return T
