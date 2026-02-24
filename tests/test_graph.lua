local T = MiniTest.new_set()

T['graph'] = MiniTest.new_set()

T['graph']['find_model_dependencies logic'] = function()
  local df = require('dataform.project')
  local utils = require('dataform.utils')

  -- Mock compiled graph
  df.compiled_project_table = {
    tables = {
      {
        fileName = "/path/to/project/definitions/b.sqlx",
        target = { schema = "s", name = "b" },
        dependencyTargets = { { schema = "s", name = "a" } }
      },
      {
        fileName = "/path/to/project/definitions/a.sqlx",
        target = { schema = "s", name = "a" }
      }
    }
  }

  -- Mock current file as b.sqlx
  local old_expand = vim.fn.expand
  vim.fn.expand = function(arg)
    if arg == '%:p' then return "/path/to/project/definitions/b.sqlx" end
    return old_expand(arg)
  end

  -- Mock the picker to capture results
  local captured_results = {}
  local old_picker = utils.custom_picker
  utils.custom_picker = function(title, results)
    captured_results = results
  end

  df.find_model_dependencies()

  MiniTest.expect.equality(#captured_results, 1)
  MiniTest.expect.equality(captured_results[1], "/path/to/project/definitions/a.sqlx")

  -- Cleanup
  vim.fn.expand = old_expand
  utils.custom_picker = old_picker
end

T['graph']['find_model_dependents logic'] = function()
  local df = require('dataform.project')
  local utils = require('dataform.utils')

  -- Mock compiled graph: a depends on nothing, b depends on a
  df.compiled_project_table = {
    tables = {
      {
        fileName = "/path/to/project/definitions/b.sqlx",
        target = { schema = "s", name = "b" },
        dependencyTargets = { { schema = "s", name = "a" } }
      },
      {
        fileName = "/path/to/project/definitions/a.sqlx",
        target = { schema = "s", name = "a" }
      }
    }
  }

  -- Mock current file as a.sqlx
  local old_expand = vim.fn.expand
  vim.fn.expand = function(arg)
    if arg == '%:p' then return "/path/to/project/definitions/a.sqlx" end
    return old_expand(arg)
  end

  -- Mock the picker
  local captured_results = {}
  local old_picker = utils.custom_picker
  utils.custom_picker = function(title, results)
    captured_results = results
  end

  df.find_model_dependents()

  MiniTest.expect.equality(#captured_results, 1)
  MiniTest.expect.equality(captured_results[1], "/path/to/project/definitions/b.sqlx")

  -- Cleanup
  vim.fn.expand = old_expand
  utils.custom_picker = old_picker
end

return T
