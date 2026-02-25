local M = {}
local state = require("dataform.state")
local signatures = require("dataform.signatures")

M.ns = vim.api.nvim_create_namespace("dataform_diagnostics")
M.vt_ns = vim.api.nvim_create_namespace("dataform_virtual_text")
M.lint_ns = vim.api.nvim_create_namespace("dataform_linter")

function M.check_unresolved_references(bufnr)
  local diagnostics = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local vars = state.compiled_project_table.projectConfig and state.compiled_project_table.projectConfig.vars or {}

  for i, line in ipairs(lines) do
    -- 1. Check project variables
    for var_name in line:gmatch("dataform%.projectConfig%.vars%.([%w_]+)") do
      if not vars[var_name] then
        local col_start = line:find("dataform.projectConfig.vars." .. var_name, 1, true)
        if col_start then
          table.insert(diagnostics, {
            lnum = i - 1,
            col = col_start - 1,
            end_col = col_start - 1 + #("dataform.projectConfig.vars." .. var_name),
            severity = vim.diagnostic.severity.WARN,
            message = "Unresolved project variable: " .. var_name,
            source = "Dataform",
          })
        end
      end
    end

    -- 2. Check JS module references in ${ ... } (e.g., ${utils.func})
    -- Exclude 'dataform.' to avoid double-flagging project variables
    for ref in line:gmatch("${%s*([%w_]+%.[%w_%.]+)") do
       -- Skip if it's ref or resolve or starts with dataform.
       if not ref:find("^ref%.") and not ref:find("^resolve%.") and not ref:find("^dataform%.") then
         local sig = signatures.get_signature_for_name(ref)
         if not sig then
            local col_start = line:find(ref, 1, true)
            if col_start then
              table.insert(diagnostics, {
                lnum = i - 1,
                col = col_start - 1,
                end_col = col_start - 1 + #ref,
                severity = vim.diagnostic.severity.WARN,
                message = "Unresolved JS reference: " .. ref,
                source = "Dataform",
              })
            end
         end
       end
    end
  end
  return diagnostics
end

function M.set_diagnostics(compiled_json)
  vim.diagnostic.reset(M.ns)
  if not compiled_json then return end

  local compilation_errors = {}
  if compiled_json.graphErrors and compiled_json.graphErrors.compilationErrors then
    for _, err in ipairs(compiled_json.graphErrors.compilationErrors) do
      table.insert(compilation_errors, err)
    end
  end

  -- Also check top-level compilation errors if they exist
  if compiled_json.compilationErrors then
    for _, err in ipairs(compiled_json.compilationErrors) do
      table.insert(compilation_errors, err)
    end
  end

  if #compilation_errors == 0 then return end

  local diagnostics_by_file = {}
  for _, err in ipairs(compilation_errors) do
    if err.fileName then
      local file_diagnostics = diagnostics_by_file[err.fileName] or {}
      table.insert(file_diagnostics, {
        lnum = (err.lineNumber and err.lineNumber > 0) and (err.lineNumber - 1) or 0,
        col = (err.columnNumber and err.columnNumber > 0) and (err.columnNumber - 1) or 0,
        severity = vim.diagnostic.severity.ERROR,
        message = err.message,
        source = "Dataform",
      })
      diagnostics_by_file[err.fileName] = file_diagnostics
    end
  end

  for fileName, diagnostics in pairs(diagnostics_by_file) do
    -- Robust buffer matching using absolute paths
    local bufnr = -1
    local abs_fileName = vim.fn.fnamemodify(fileName, ":p")

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name ~= "" then
        local abs_buf_name = vim.fn.fnamemodify(buf_name, ":p")
        if abs_buf_name == abs_fileName or abs_buf_name:find(fileName .. "$") then
          bufnr = buf
          break
        end
      end
    end

    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      -- If it's the current buffer, also add local unresolved references
      if bufnr == vim.api.nvim_get_current_buf() then
        local local_diagnostics = M.check_unresolved_references(bufnr)
        for _, ld in ipairs(local_diagnostics) do
          table.insert(diagnostics, ld)
        end
      end
      vim.diagnostic.set(M.ns, bufnr, diagnostics)
    end
  end

  -- If current buffer wasn't in diagnostics_by_file, check it specifically for local errors
  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_file = vim.api.nvim_buf_get_name(cur_buf)
  if not diagnostics_by_file[cur_file] then
     local local_diagnostics = M.check_unresolved_references(cur_buf)
     if #local_diagnostics > 0 then
        vim.diagnostic.set(M.ns, cur_buf, local_diagnostics)
     end
  end
end

function M.clear_diagnostics()
  vim.diagnostic.reset(M.ns)
end

return M
