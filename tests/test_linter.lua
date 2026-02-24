local T = MiniTest.new_set()

local function setup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

T['linter'] = MiniTest.new_set()

T['linter']['lint() parses sqlfluff output'] = function()
  local df = _G.reload_dataform()
  local utils = require('dataform.utils')

  -- Mock execute_job to return fake sqlfluff json
  local old_job = utils.execute_job
  utils.execute_job = function(cmd, args, opts)
    local fake_json = [[
[
  {
    "filepath": "temp.sql",
    "violations": [
      {
        "line_no": 1,
        "line_pos": 5,
        "code": "L001",
        "description": "Unnecessary whitespace"
      }
    ]
  }
]
]]
    if opts.callback then
      opts.callback(0, fake_json, "")
    end
    return { shutdown = function() end }
  end

  -- Mock diagnostics
  local lint_ns = vim.api.nvim_create_namespace("dataform_linter")
  local diagnostics_set = false
  local old_set = vim.diagnostic.set
  vim.diagnostic.set = function(ns, bufnr, diags)
    if ns == lint_ns then
      diagnostics_set = true
      MiniTest.expect.equality(#diags, 1)
      MiniTest.expect.equality(diags[1].message:find("L001") ~= nil, true)
    end
  end

  setup_buffer({ 'SELECT 1' })
  df.lint()

  MiniTest.expect.equality(diagnostics_set, true)

  -- Clean up
  utils.execute_job = old_job
  vim.diagnostic.set = old_set
end

return T
