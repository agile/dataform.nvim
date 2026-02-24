local T = MiniTest.new_set()

local function setup_buffer(lines, cursor)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, cursor)
  return bufnr
end

T['signatures'] = MiniTest.new_set()

T['signatures']['detects ref() start'] = function()
  setup_buffer({ 'SELECT ${ref( ' }, { 1, 13 })
  local help = require('dataform.signatures').get_signature_at_cursor()

  MiniTest.expect.equality(help.name, 'ref')
  MiniTest.expect.equality(help.active_param, 0)
end

T['signatures']['detects ref() second param'] = function()
  setup_buffer({ 'SELECT ${ref("schema", ' }, { 1, 23 })
  local help = require('dataform.signatures').get_signature_at_cursor()

  MiniTest.expect.equality(help.name, 'ref')
  MiniTest.expect.equality(help.active_param, 1)
end

T['signatures']['detects resolve()'] = function()
  setup_buffer({ 'SELECT ${resolve( ' }, { 1, 17 })
  local help = require('dataform.signatures').get_signature_at_cursor()

  MiniTest.expect.equality(help.name, 'resolve')
end

T['signatures']['detects config block'] = function()
  setup_buffer({ 'config { ' }, { 1, 9 })
  local help = require('dataform.signatures').get_signature_at_cursor()

  MiniTest.expect.equality(help.name, 'config')
end

T['signatures']['detects local js functions'] = function()
  setup_buffer({
    'js {',
    '  function myLocalFunc(a, b) { return a + b; }',
    '}',
    'SELECT ${myLocalFunc( '
  }, { 4, 21 })

  local help = require('dataform.signatures').get_signature_at_cursor()
  MiniTest.expect.equality(help.name, 'myLocalFunc')
  MiniTest.expect.equality(help.sig.params[1], 'a')
  MiniTest.expect.equality(help.sig.params[2], 'b')
end

T['signatures']['detects includes js functions'] = function()
  -- Setup temporary includes file
  vim.fn.mkdir('includes', 'p')
  local f = io.open('includes/utils.js', 'w')
  f:write('function myExternalFunc(param1, param2) { return 1; }')
  f:close()

  setup_buffer({ 'SELECT ${utils.myExternalFunc( ' }, { 1, 31 })

  local help = require('dataform.signatures').get_signature_at_cursor()

  -- Cleanup
  os.remove('includes/utils.js')
  os.remove('includes')

  MiniTest.expect.equality(help.name, 'utils.myExternalFunc')
  MiniTest.expect.equality(help.sig.params[1], 'param1')
  MiniTest.expect.equality(help.sig.params[2], 'param2')
end

T['signatures']['ignores unrelated text'] = function()
  setup_buffer({ 'SELECT * FROM table' }, { 1, 10 })
  local help = require('dataform.signatures').get_signature_at_cursor()

  MiniTest.expect.equality(help, nil)
end

return T
