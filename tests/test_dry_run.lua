local T = MiniTest.new_set()

local function setup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

T['dry_run'] = MiniTest.new_set()

T['dry_run']['show_dry_run_virtual_text() sets extmark'] = function()
  local df = require('dataform.project')
  local utils = require('dataform.utils')

  -- Mock compiled graph
  df.compiled_project_table = {
    tables = {
      {
        fileName = "definitions/test.sqlx",
        target = { database = "db", schema = "s", name = "test" },
        query = "SELECT 1",
        type = "view"
      }
    }
  }

  -- Mock current file
  local old_expand = vim.fn.expand
  vim.fn.expand = function(arg)
    if arg == '%:p' then return "/project/definitions/test.sqlx" end
    return old_expand(arg)
  end

  -- Mock bq dry_run output
  local old_exec = utils.os_execute_with_status
  utils.os_execute_with_status = function()
    return 0, "Query successfully validated. This query will process 1099511627776 bytes."
  end

  -- Mock extmark setting
  local extmark_called = false
  local old_extmark = vim.api.nvim_buf_set_extmark
  vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
    extmark_called = true
    MiniTest.expect.equality(opts.virt_text[1][1]:find("1.00 TiB") ~= nil, true)
  end

  setup_buffer({ 'SELECT 1' })
  df.show_dry_run_virtual_text()

  MiniTest.expect.equality(extmark_called, true)

  -- Cleanup
  vim.fn.expand = old_expand
  utils.os_execute_with_status = old_exec
  vim.api.nvim_buf_set_extmark = old_extmark
end

return T
