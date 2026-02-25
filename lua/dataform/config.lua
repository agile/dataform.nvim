local M = {}

---@class DataformConfig
---@field dataform_bin string Path to dataform binary or wrapper script.
---@field dataform_args string[] Global arguments for dataform (e.g. {"--schema-suffix", "dev"}).
---@field compile_on_save boolean Automatically compile Dataform project on saving a .sqlx file.
---@field format_on_save boolean Automatically format SQL blocks on save.
---@field lint_on_save boolean Automatically lint SQL blocks on save.
---@field formatter_bin string Path to formatter binary (sqlfluff).
---@field formatter_options string[] Arguments for the formatter.
---@field linter_bin string Path to linter binary (sqlfluff).
---@field linter_options string[] Arguments for the linter.
---@field preview_style "vsplit"|"float" Style of the compiled SQL preview.
---@field use_treesitter boolean Use tree-sitter for parsing if available.
---@field logging boolean Enable internal logging.
---@field clear_log_on_start boolean Clear log file on startup.

---@type DataformConfig
local default_config = {
  dataform_bin = "dataform",
  dataform_args = {},
  compile_on_save = true,
  format_on_save = false,
  lint_on_save = false,
  formatter_bin = "sqlfluff",
  formatter_options = { "fix", "--force", "-q" },
  linter_bin = "sqlfluff",
  linter_options = { "lint", "--format", "json" },
  preview_style = "vsplit",
  use_treesitter = true,
  logging = false,
  clear_log_on_start = true,
}

M.options = vim.deepcopy(default_config)

--- Setup the plugin with user configuration.
---@param user_config DataformConfig?
function M.setup(user_config)
  M.options = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- Handle logging initialization if needed
  if M.options.logging and M.options.clear_log_on_start then
    require("dataform.utils").clear_log()
  end
end

return M
