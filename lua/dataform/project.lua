local utils = require("dataform.utils")
local config = require("dataform.config")
local state = require("dataform.state")
local parser = require("dataform.parser")
local diagnostics = require("dataform.diagnostics")
local actions = require("dataform.actions")
local lsp = require("dataform.lsp")

local dataform = {}

-- Expose config, state, parser, diagnostics, actions and lsp functions for backward compatibility and internal access
setmetatable(dataform, {
  __index = function(_, key)
    if key == "config" then return config.options end
    if key == "compiled_project_table" or key == "lsp_client_id" or
       key == "current_compile_job" or key == "current_dry_run_job" or
       key == "structural_hashes" then
      return state[key]
    end
    if parser[key] ~= nil then return parser[key] end
    if diagnostics[key] ~= nil then return diagnostics[key] end
    if actions[key] ~= nil then return actions[key] end
    if lsp[key] ~= nil then return lsp[key] end
    return rawget(dataform, key)
  end,
  __newindex = function(_, key, value)
    if key == "config" then
      config.options = value
    elseif key == "compiled_project_table" or key == "lsp_client_id" or
           key == "current_compile_job" or key == "current_dry_run_job" or
           key == "structural_hashes" then
      state[key] = value
    else
      rawset(dataform, key, value)
    end
  end
})

--- Setup the Dataform plugin.
---@param user_config table?
function dataform.setup(user_config)
  config.setup(user_config)

  -- Register as a pseudo-LSP to work with tiny-code-action.nvim, etc.
  lsp.register_lsp_source()
end

function dataform.set_dataform_workdir_project_path()
  if config.options.clear_log_on_start then
    utils.clear_log()
  end

  local current_path = utils.get_current_file_path()

  utils.log({
    event = "setup_workdir",
    cwd = vim.fn.getcwd(),
    nvim_dir = vim.fn.expand('%:p:h'),
    current_file = current_path
  })

  -- Log versions for environment check
  utils.os_execute_with_status(config.options.dataform_bin .. " --version", false, true)
  utils.os_execute_with_status("bq version", false, true)

  local is_match = string.match(current_path, "/definitions/.*")

  if is_match then
    local parent_path = current_path:gsub("/definitions/.*", "/")
    vim.api.nvim_set_current_dir(parent_path)
  else
    return utils.notify(
      "Error: File does not exist inside dataform definitions folder.",
      vim.log.levels.ERROR
    )
  end
end

return dataform
