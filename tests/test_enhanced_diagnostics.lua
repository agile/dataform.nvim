local T = MiniTest.new_set()

local function setup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

T['enhanced_diagnostics'] = MiniTest.new_set()

T['enhanced_diagnostics']['finds unresolved project variables'] = function()
  local df = _G.reload_dataform()

  -- Mock compiled graph with one variable
  df.compiled_project_table = {
    projectConfig = {
      vars = {
        existing_var = "value"
      }
    }
  }

  local bufnr = setup_buffer({
    'SELECT ${dataform.projectConfig.vars.existing_var}',
    'SELECT ${dataform.projectConfig.vars.missing_var}'
  })

  local diagnostics = df.check_unresolved_references(bufnr)

  MiniTest.expect.equality(#diagnostics, 1)
  MiniTest.expect.equality(diagnostics[1].message:find("missing_var") ~= nil, true)
  MiniTest.expect.equality(diagnostics[1].severity, vim.diagnostic.severity.WARN)
  MiniTest.expect.equality(diagnostics[1].lnum, 1) -- 0-indexed, so line 2
end

T['enhanced_diagnostics']['finds unresolved js references'] = function()
  local df = _G.reload_dataform()

  -- Mock no JS symbols
  local sig_mod = require('dataform.signatures')
  local old_sig = sig_mod.get_signature_for_name
  sig_mod.get_signature_for_name = function(name)
    if name == "utils.exists" then return { label = name, params = {} } end
    return nil
  end

  local bufnr = setup_buffer({
    'SELECT ${utils.exists}',
    'SELECT ${utils.missing}'
  })

  local diagnostics = df.check_unresolved_references(bufnr)

  MiniTest.expect.equality(#diagnostics, 1)
  MiniTest.expect.equality(diagnostics[1].message:find("utils.missing") ~= nil, true)
  MiniTest.expect.equality(diagnostics[1].lnum, 1)

  sig_mod.get_signature_for_name = old_sig
end

return T
