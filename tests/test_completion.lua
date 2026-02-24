local T = MiniTest.new_set()

T['completion'] = MiniTest.new_set()

T['completion']['js_symbols() finds local symbols'] = function()
  local project = require('dataform.project')
  local utils = require('dataform.completion.utils')

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    'js {',
    '  const LOCAL_VAR = 1;',
    '  function localFunc() {}',
    '}'
  })
  vim.api.nvim_win_set_buf(0, bufnr)

  local symbols = utils.js_symbols()

  local found_var = false
  local found_func = false
  for _, s in ipairs(symbols) do
    if s.label == 'LOCAL_VAR' then found_var = true end
    if s.label == 'localFunc' then found_func = true end
  end

  MiniTest.expect.equality(found_var, true)
  MiniTest.expect.equality(found_func, true)
end

T['completion']['js_symbols() finds includes symbols'] = function()
  local utils = require('dataform.completion.utils')

  -- Setup temporary includes file
  vim.fn.mkdir('includes', 'p')
    local f = io.open('includes/test_mod.js', 'w')
    f:write([[const MOD_CONST = 1;
  function modFunc() {}]])
    f:close()

      local symbols = utils.js_symbols("")

      -- Cleanup
      os.remove('includes/test_mod.js')
      os.remove('includes')

      local found_mod = false
      for _, s in ipairs(symbols) do
        if s.label == 'test_mod' then found_mod = true end
      end

      MiniTest.expect.equality(found_mod, true)
    end


T['completion']['js_symbols() handles dot-notation for modules'] = function()
  local utils = require('dataform.completion.utils')

  vim.fn.mkdir('includes', 'p')
  local f = io.open('includes/test_mod.js', 'w')
  f:write([[const MOD_CONST = 1;
function modFunc() {}]])
  f:close()

  -- Test without dot (shows module itself)
  local symbols1 = utils.js_symbols("")
  local found_mod = false
  for _, s in ipairs(symbols1) do
    if s.label == 'test_mod' then found_mod = true end
  end
  MiniTest.expect.equality(found_mod, true)

  -- Test with dot (shows members)
  local symbols2 = utils.js_symbols("test_mod.")
  local found_const = false
  local found_func = false
  for _, s in ipairs(symbols2) do
    if s.label == 'MOD_CONST' then found_const = true end
    if s.label == 'modFunc' then found_func = true end
  end

  MiniTest.expect.equality(found_const, true)
  MiniTest.expect.equality(found_func, true)

  os.remove('includes/test_mod.js')
  os.remove('includes')
end

return T
