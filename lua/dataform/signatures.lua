local signatures = {}
local timer = nil

local df_signatures = {
  ref = {
    label = "ref",
    params = { "name" },
    alt_params = { "schema", "name" },
    doc = "References a table or declaration defined in the project."
  },
  resolve = {
    label = "resolve",
    params = { "name" },
    alt_params = { "schema", "name" },
    doc = "Resolves a table name to its full SQL identifier."
  },
  config = {
    label = "config",
    params = { "{ type, schema?, database?, name?, ... }" },
    doc = "Defines the configuration for the current action."
  }
}

function signatures.get_signature_for_name(name)
  if df_signatures[name] then return df_signatures[name] end

  local parser = require('dataform.parser')
  local utils = require('dataform.utils')
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Search Patterns for JS functions
  local patterns = {
    "function%s+" .. name .. "%s*%((.-)%)",
    "const%s+" .. name .. "%s*=%s*%((.-)%)%s*=>",
    "const%s+" .. name .. "%s*=%s*function%s*%((.-)%)",
    name .. "%s*:%s*function%s*%((.-)%)"
  }

  -- 1. Search in current buffer's JS blocks
  local blocks = parser.get_sqlx_blocks()
  if blocks.js.exists then
    for i = blocks.js.start_line, blocks.js.end_line do
      local line = lines[i]
      for _, pattern in ipairs(patterns) do
        local params = line:match(pattern)
        if params then
          return { label = name, params = vim.split(params, "%s*,%s*"), doc = "Custom JavaScript function." }
        end
      end
    end
  end

    -- 2. Search in includes/ directory
    local parts = vim.split(name, "%.")
    if #parts > 1 then
      local module_name = parts[1]
      -- The target could be nested (e.g., docs.columns.my_col)
      -- We'll try to find the last part as the definition name
      local target_name = parts[#parts]
      local js_path = "includes/" .. module_name .. ".js"
      local ts_path = "includes/" .. module_name .. ".ts"
      local include_path = vim.fn.filereadable(ts_path) == 1 and ts_path or js_path

      if vim.fn.filereadable(include_path) == 1 then
        local f = io.open(include_path, "r")
        if f then
          local content = f:read("*all")
          f:close()

          -- Adjust patterns for the target name (supporting TS 'export' keyword)
          local sub_patterns = {
            "function%s+" .. target_name .. "%s*%((.-)%)",
            "export%s+function%s+" .. target_name .. "%s*%((.-)%)",
            "const%s+" .. target_name .. "%s*=%s*%((.-)%)%s*=>",
            "export%s+const%s+" .. target_name .. "%s*=%s*%((.-)%)%s*=>",
            "const%s+" .. target_name .. "%s*=%s*function%s*%((.-)%)",
            target_name .. "%s*:%s*function%s*%((.-)%)",
            target_name .. "%s*[:=]%s*['\"](.-)['\"]", -- Match simple string constants
            "const%s+" .. target_name .. "%s*=%s*['\"](.-)['\"]",
            "export%s+const%s+" .. target_name .. "%s*=%s*['\"](.-)['\"]",
            target_name .. "%s*[:=]%s*(%b{})", -- Match object definitions
          }

          for _, pattern in ipairs(sub_patterns) do
            local params = content:match(pattern)
            if params then
              local res = { label = name, params = {}, doc = "Imported from " .. include_path }
              if pattern:find("function") or pattern:find("=>") then
                 res.params = vim.split(params, "%s*,%s*")
              else
                 -- For constants, show the value as doc if it's short, or just note it
                 if #params < 100 then
                   res.doc = res.doc .. "\n\n**Value:** " .. params
                 end
              end
              return res
            end
          end
        end
      end
    end
    return nil
end

function signatures.get_signature_at_cursor()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local col = cursor_pos[2]
  local text_before = line:sub(1, col)

  -- Improved matching to handle dot-notation for JS functions
  local func_name = text_before:match("([%w_%.]+)%s*%(%s*$")
  if not func_name then
    func_name = text_before:match("([%w_%.]+)%s*%(.*,%s*$")
  end

  if not func_name then
    func_name = text_before:match("([%w_]+)%s*{%s*$")
  end

  if func_name then
    local sig = signatures.get_signature_for_name(func_name)
    if not sig then return nil end

    local active_param = 0
    local _, count = text_before:gsub(",", "")
    active_param = count

    return {
      name = func_name,
      sig = sig,
      active_param = active_param
    }
  end

  return nil
end

function signatures.show_signature_help()
  if timer then
    timer:stop()
    timer:close()
  end

  timer = vim.loop.new_timer()
  timer:start(200, 0, vim.schedule_wrap(function()
    local help = signatures.get_signature_at_cursor()
    if not help then return end

    local sig = help.sig
    local label = help.name .. "(" .. table.concat(sig.params, ", ") .. ")"

    if sig.alt_params and help.active_param >= 1 then
       label = help.name .. "(" .. table.concat(sig.alt_params, ", ") .. ")"
    end

    local lines = {
      "**Signature:** `" .. label .. "`",
      "---",
      sig.doc
    }

    vim.lsp.util.open_floating_preview(lines, "markdown", {
      border = "rounded",
      focusable = false,
      focus_id = "dataform_signature",
      close_events = { "CursorMoved", "BufLeave", "InsertLeave" }
    })
  end))
end

return signatures
