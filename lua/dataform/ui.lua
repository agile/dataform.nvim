local M = {}

--- Returns the current model's BigQuery target path (schema.name)
--- Suitable for Winbar or Statusline
---@return string?
function M.target_path()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)

  if model and model.target then
    return string.format("%s.%s", model.target.schema or "", model.target.name or "")
  end
  return nil
end

--- Returns the current model's target schema
---@return string?
function M.target_schema()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)
  return model and model.target and model.target.schema
end

--- Returns the current model's target table name
---@return string?
function M.target_table()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)
  return model and model.target and model.target.name
end

--- Returns the canonical (logical) target path (schema.name)
---@return string?
function M.canonical_path()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)

  if model and model.canonicalTarget then
    return string.format("%s.%s", model.canonicalTarget.schema or "", model.canonicalTarget.name or "")
  end
  return nil
end

--- Returns the current model's canonical schema
---@return string?
function M.canonical_schema()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)
  return model and model.canonicalTarget and model.canonicalTarget.schema
end

--- Returns the current model's canonical table name
---@return string?
function M.canonical_table()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)
  return model and model.canonicalTarget and model.canonicalTarget.name
end

--- Returns true if the resolved target matches the canonical target
---@return boolean
function M.is_canonical()
  local df = require('dataform')
  local all_models = df.get_all_models()
  local target_file_path = require('dataform.utils').get_current_file_path()
  local model = df.find_model_by_file_path(all_models, target_file_path)

  if model and model.target and model.canonicalTarget then
    local t = model.target
    local c = model.canonicalTarget
    return t.schema == c.schema and t.database == c.database and t.name == c.name
  end
  return true -- Default to true if we can't tell
end

--- Returns a status string with icon and dry-run stats if available
--- Suitable for Lualine or standard Statusline
---@return string
function M.status()
  local state = require('dataform.state')
  local utils = require('dataform.utils')

  -- Check for compilation errors first
  if state.compiled_project_table and state.compiled_project_table.graphErrors and
     state.compiled_project_table.graphErrors.compilationErrors and
     #state.compiled_project_table.graphErrors.compilationErrors > 0 then
    return "󱓞 Error"
  end

  -- Try to get dry run stats from virtual text namespace (last successful run)
  local bufnr = vim.api.nvim_get_current_buf()
  local vt_ns = vim.api.nvim_get_namespaces()["dataform_virtual_text"]
  if vt_ns then
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, vt_ns, 0, -1, { details = true })
    if #marks > 0 and marks[1][4] and marks[1][4].virt_text then
      local text = marks[1][4].virt_text[1][1]
      -- Text is usually "󱓞 Dry run: 1.23 MiB (~$0.00001)"
      -- We'll return a shortened version for the statusline
      local stats = text:match("Dry run: (.*)")
      if stats then
        return "󱓞 " .. stats
      end
    end
  end

  return "󱓞 OK"
end

--- Returns a project-wide summary
---@return string
function M.project_summary()
  local state = require('dataform.state')
  if not state.compiled_project_table or not state.compiled_project_table.tables then
    return "DF: -"
  end

  local tables = #(state.compiled_project_table.tables or {})
  local decls = #(state.compiled_project_table.declarations or {})
  return string.format("DF: %d models / %d sources", tables, decls)
end

return M
