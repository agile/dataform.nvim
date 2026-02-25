local M = {}

-- Lazy-load sub-modules
local function lazy(module)
  return function(...)
    return require("dataform." .. module)[...]
  end
end

-- Backward compatibility metatable
-- This allows accessing functions from sub-modules directly on require('dataform')
setmetatable(M, {
  __index = function(_, key)
    -- Map special keys
    if key == "config" then return require("dataform.config").options end

    -- Check sub-modules for the requested key
    local sub_modules = { "state", "parser", "diagnostics", "actions", "lsp", "utils", "ui" }
    for _, mod_name in ipairs(sub_modules) do
      local mod = require("dataform." .. mod_name)
      if mod[key] ~= nil then
        return mod[key]
      end
    end

    -- Special mappings for functions that moved
    if key == "open_log" then return require("dataform.utils").open_log end
    if key == "clear_log" then return require("dataform.utils").clear_log end
    if key == "show_signature_help" then return require("dataform.signatures").show_signature_help end
    if key == "completion_cmp_source" then return require("dataform.completion.cmp") end

    return nil
  end,
  __newindex = function(_, key, value)
    if key == "config" then
      require("dataform.config").options = value
    else
      -- Check if it belongs to state
      local state_keys = {
        compiled_project_table = true,
        lsp_client_id = true,
        current_compile_job = true,
        current_dry_run_job = true,
        structural_hashes = true
      }
      if state_keys[key] then
        require("dataform.state")[key] = value
      else
        rawset(M, key, value)
      end
    end
  end
})

--- Setup the Dataform plugin.
---@param user_config table?
function M.setup(user_config)
  require("dataform.config").setup(user_config)

  -- Register as a pseudo-LSP to work with tiny-code-action.nvim, etc.
  require("dataform.lsp").register_lsp_source()
end

return M
