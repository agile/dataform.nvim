local utils = require("dataform.utils")

local dataform = {}
dataform.compiled_project_table = {}

---@alias DataformUserConfig table
---@field compile_on_save boolean? (default: true) Automatically compile Dataform project on saving a .sqlx file.

local default_config = {
  compile_on_save = true,
  format_on_save = false,
  formatter_bin = "sqlfluff",
  formatter_options = { "fix", "--force", "-q" },
  preview_style = "vsplit", -- Options: 'vsplit', 'float'
  use_treesitter = true,    -- Use tree-sitter for parsing if available
  logging = false,          -- Enable internal logging
  clear_log_on_start = true, -- Clear log file on startup
}
dataform.config = vim.deepcopy(default_config)

-- Internal Helpers

local function is_treesitter_available()
  if not dataform.config.use_treesitter then return false end
  local ok, _ = pcall(vim.treesitter.get_parser, 0, "dataform")
  return ok
end

local function get_blocks_via_treesitter()
  local parser = vim.treesitter.get_parser(0, "dataform")
  local tree = parser:parse()[1]
  local root = tree:root()

  local blocks = {
    config = { exists = false, start_line = 0, end_line = 0 },
    js = { exists = false, start_line = 0, end_line = 0 },
    pre_operations = {},
    post_operations = {},
    sql = { exists = false, start_line = 0, end_line = 0 }
  }

  local query = vim.treesitter.query.parse("dataform", [[
    (config_block) @config
    (js_block) @js
    (pre_operations_block) @pre_ops
    (post_operations_block) @post_ops
    (sql_block) @sql
  ]])

  for id, node in query:iter_captures(root, 0) do
    local name = query.captures[id]
    local start_row, _, end_row, _ = node:range()
    -- range() is 0-indexed, but our plugin uses 1-indexed for lines
    local s = start_row + 1
    local e = end_row + 1

    if name == "config" then
      blocks.config = { exists = true, start_line = s, end_line = e }
    elseif name == "js" then
      blocks.js = { exists = true, start_line = s, end_line = e }
    elseif name == "pre_ops" then
      table.insert(blocks.pre_operations, { exists = true, start_line = s, end_line = e })
    elseif name == "post_ops" then
      table.insert(blocks.post_operations, { exists = true, start_line = s, end_line = e })
    elseif name == "sql" then
      if not blocks.sql.exists then
        blocks.sql = { exists = true, start_line = s, end_line = e }
      else
        -- Update end_line for subsequent SQL chunks if necessary
        blocks.sql.end_line = e
      end
    end
  end

  return blocks
end

local function get_dataform_definitions_file_path()
  local file = utils.get_current_file_path()
  utils.log("get_dataform_definitions_file_path: current file=" .. file)
  if file:find("/definitions/") then
    return file
  end
  utils.log("get_dataform_definitions_file_path: FAILED, file not in /definitions/")
  return utils.notify(
    "Error: File does not exist inside dataform definitions folder.",
    vim.log.levels.ERROR
  )
end

local function get_all_models()
  local tables = vim.deepcopy(dataform.compiled_project_table.tables or {})
  local operations = dataform.compiled_project_table.operations or {}
  local declarations = dataform.compiled_project_table.declarations or {}
  local assertions = dataform.compiled_project_table.assertions or {}
  local all_models = vim.fn.extend(tables, operations)
  all_models = vim.fn.extend(all_models, declarations)

  return vim.fn.extend(all_models, assertions)
end

local function find_model_by_file_path(all_models, target_file_path)
  if not target_file_path then return nil end
    local target_abs = vim.fn.fnamemodify(target_file_path, ":p")
    utils.log("find_model_by_file_path: target_abs=" .. target_abs)

    for _, model in pairs(all_models) do
      if model.fileName then
      local model_abs = vim.fn.fnamemodify(model.fileName, ":p")
      if model_abs == target_abs then
        utils.log("find_model_by_file_path: MATCH FOUND for " .. model.target.name)
        return model
      end
    end
  end
  utils.log("find_model_by_file_path: NO MATCH FOUND")
  return nil
end
local function find_file_name_by_schema_name(all_models, schema, name)
  for _, model in pairs(all_models) do
    if model.target.schema == schema and model.target.name == name then
      return model.fileName
    end
  end
  return nil
end

function dataform.get_sqlx_blocks()
  if is_treesitter_available() then
    local ok, blocks = pcall(get_blocks_via_treesitter)
    if ok then return blocks end
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local in_major_block = false
  local brace_depth = 0
  local current_block_name = ""

  local blocks = {
    config = { exists = false, start_line = 0, end_line = 0 },
    js = { exists = false, start_line = 0, end_line = 0 },
    pre_operations = {},
    post_operations = {},
    sql = { exists = false, start_line = 0, end_line = 0 }
  }

  local start_line = 0

  for i, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if #trimmed > 0 then
      local _, open_braces = line:gsub("{", "")
      local _, closed_braces = line:gsub("}", "")
      brace_depth = brace_depth + open_braces - closed_braces

      if not in_major_block then
        if trimmed:find("^config%s*{") then
          current_block_name = "config"
          blocks.config.start_line = i
          in_major_block = true
          if brace_depth == 0 then
            blocks.config.end_line = i
            blocks.config.exists = true
            in_major_block = false
          end
        elseif trimmed:find("^js%s*{") then
          current_block_name = "js"
          blocks.js.start_line = i
          in_major_block = true
          if brace_depth == 0 then
            blocks.js.end_line = i
            blocks.js.exists = true
            in_major_block = false
          end
        elseif trimmed:find("^pre_operations%s*{") then
          current_block_name = "pre_operations"
          start_line = i
          in_major_block = true
          if brace_depth == 0 then
            table.insert(blocks.pre_operations, { start_line = i, end_line = i, exists = true })
            in_major_block = false
          end
        elseif trimmed:find("^post_operations%s*{") then
          current_block_name = "post_operations"
          start_line = i
          in_major_block = true
          if brace_depth == 0 then
            table.insert(blocks.post_operations, { start_line = i, end_line = i, exists = true })
            in_major_block = false
          end
        else
          if not blocks.sql.exists then
            blocks.sql.start_line = i
            blocks.sql.exists = true
          end
          blocks.sql.end_line = i
        end
      elseif brace_depth == 0 then
        if current_block_name == "config" then
          blocks.config.end_line = i
          blocks.config.exists = true
        elseif current_block_name == "js" then
          blocks.js.end_line = i
          blocks.js.exists = true
        elseif current_block_name == "pre_operations" then
          table.insert(blocks.pre_operations, { start_line = start_line, end_line = i, exists = true })
        elseif current_block_name == "post_operations" then
          table.insert(blocks.post_operations, { start_line = start_line, end_line = i, exists = true })
        end
        in_major_block = false
        current_block_name = ""
      end
    end
  end
  return blocks
end

---@param user_config DataformUserConfig?
function dataform.setup(user_config)
  user_config = user_config or {}
  for key, value in pairs(user_config) do
    if default_config[key] ~= nil then
      dataform.config[key] = value
    end
  end
end

function dataform.set_dataform_workdir_project_path()
  if dataform.config.clear_log_on_start then
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
  utils.os_execute_with_status("dataform --version", false, true)
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

function dataform.get_context_at_cursor()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = lines[row] or ""

  -- Extract word under cursor (including dots)
  local line = current_line
  local col_start = col
  while col_start > 0 and line:sub(col_start, col_start):match("[%w_%.]") do
    col_start = col_start - 1
  end
  local col_end = col + 1
  while col_end <= #line and line:sub(col_end, col_end):match("[%w_%.]") do
    col_end = col_end + 1
  end
  local word = line:sub(col_start + 1, col_end - 1)
  if word == "" then word = vim.fn.expand("<cword>") end

  local context = {
    word = word,
    row = row,
    col = col,
    current_line = current_line,
    lines = lines,
  }

  local lua_escaped_word = word:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

  -- 1. Check for ref/resolve (Support multi-line blocks)
  local start_row, start_col, end_row, end_col
  -- Find start of ${
  for r = row, 1, -1 do
    local l = lines[r]
    local search_start = (r == row) and col or #l
    local s = l:sub(1, search_start + 1):reverse():find("{$", 1, true)
    if s then
      start_row = r
      start_col = #l:sub(1, search_start + 1) - s
      break
    end
  end

  -- Find end of }
  if start_row then
    for r = row, #lines do
      local l = lines[r]
      local search_start = (r == row) and col or 0
      local e = l:find("}", search_start + 1, true)
      if e then
        end_row = r
        end_col = e
        break
      end
    end
  end

  if start_row and end_row then
    local block_content = ""
    for r = start_row, end_row do
      local l = lines[r]
      if r == start_row and r == end_row then
        block_content = l:sub(start_col + 1, end_col)
      elseif r == start_row then
        block_content = l:sub(start_col + 1)
      elseif r == end_row then
        block_content = block_content .. "\n" .. l:sub(1, end_col)
      else
        block_content = block_content .. "\n" .. l
      end
    end

    -- Improved Extraction logic for table/schema
    local function resolve_val(val)
      if not val then return nil end
      val = vim.trim(val)
      -- If it's a project variable, try to resolve it
      local var_match = val:match("dataform%.projectConfig%.vars%.([%w_]+)")
      if var_match then
        local vars = dataform.compiled_project_table.projectConfig and dataform.compiled_project_table.projectConfig.vars or {}
        return vars[var_match]
      end
      -- Strip quotes if it's a literal
      return val:match('^["\'](.*)["\']$') or val
    end

    local schema, table_name
    -- Match 2-arg: ref(arg1, arg2)
    local s_raw, t_raw = block_content:match('ref%(%s*([^,%s]+)%s*,%s*([^%s%)]+)%s*%)')
    if not s_raw then
      s_raw, t_raw = block_content:match('resolve%(%s*([^,%s]+)%s*,%s*([^%s%)]+)%s*%)')
    end

    if s_raw and t_raw then
      schema = resolve_val(s_raw)
      table_name = resolve_val(t_raw)
    else
      -- Match 1-arg: ref(arg1)
      local raw = block_content:match('ref%(%s*([^%s%)]+)%s*%)')
      if not raw then raw = block_content:match('resolve%(%s*([^%s%)]+)%s*%)') end
      if raw then
        table_name = resolve_val(raw)
      end
    end

    if table_name then
      -- If cursor is on the word, or if we are inside the block, default to the table
      if word == table_name or word == schema or word:find(table_name, 1, true) or block_content:find(lua_escaped_word, 1, true) then
        context.type = "table"
        context.table_name = table_name
        context.schema = schema
        return context
      end
    end
  end

  -- 2. Check for project variables
  if word:find("dataform%.projectConfig%.vars%.") or current_line:find("dataform%.projectConfig%.vars%." .. lua_escaped_word) then
    context.type = "variable"
    context.var_name = word:match("([^%.]+)$")
    return context
  end

  -- 3. Check for JS functions (word followed by '(')
  if current_line:find(lua_escaped_word .. "%s*%(") then
    context.type = "function"
    context.func_name = word
    return context
  end

  -- 4. Check for JS module/dot-notation references (e.g., docs.columns.my_col)
  if word:find(".", 1, true) then
    context.type = "js_module"
  end

  utils.log({
    event = "get_context_at_cursor",
    word = context.word,
    type = context.type,
    table = context.table_name,
    schema = context.schema,
    func = context.func_name,
    var = context.var_name
  })

  return context
end

function dataform.go_to_ref()
  local context = dataform.get_context_at_cursor()
  local word = context.word
  local lines = context.lines
  local row = context.row

  -- 1. Check for CTE navigation (SQL files only or SQL blocks)
  local cte_pattern = "WITH%s+" .. word .. "%s+AS%s*%("
  local cte_pattern_comma = ",%s*" .. word .. "%s+AS%s*%("
  for i, line in ipairs(lines) do
    if line:find(cte_pattern) or line:find(cte_pattern_comma) then
      vim.api.nvim_win_set_cursor(0, {i, 0})
      return
    end
  end

  if context.type == "table" then
    local df_tables = dataform.compiled_project_table.tables or {}
    local df_declarations = dataform.compiled_project_table.declarations or {}
    local df_ops = dataform.compiled_project_table.operations or {}
    local all_nodes = {}
    for _, v in ipairs(df_tables) do table.insert(all_nodes, v) end
    for _, v in ipairs(df_declarations) do table.insert(all_nodes, v) end
    for _, v in ipairs(df_ops) do table.insert(all_nodes, v) end

    for _, node in pairs(all_nodes) do
      if node.target.name == context.table_name and (node.target.schema == context.schema or not context.schema) then
        return utils.open_file(node.fileName)
      end
    end
  end

  if context.type == "variable" then
    local var_path = context.var_name
    local settings_file = "workflow_settings.yaml"
    if vim.fn.filereadable(settings_file) == 1 then
      utils.open_file(settings_file)
      local file_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for i, line in ipairs(file_lines) do
        if line:find("^" .. var_path .. ":") or line:find(" " .. var_path .. ":") then
          vim.api.nvim_win_set_cursor(0, {i, 0})
          return
        end
      end
    end
  end

  -- JS navigation (Module navigation like module.func)
  if word:find("%.") then
    local parts = vim.split(word, "%.")
    local js_module = parts[1]
    local var_name = parts[2]

    -- Check in includes/
    local includes_file = "includes/" .. js_module .. ".js"
    if vim.fn.filereadable(includes_file) == 1 then
      utils.open_file(includes_file)
      local file_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local patterns = {
        "const%s+" .. var_name .. "%s*=",
        "let%s+" .. var_name .. "%s*=",
        "function%s+" .. var_name .. "%s*%(",
        var_name .. "%s*[:=]%s*function"
      }
      for i, line in ipairs(file_lines) do
        for _, pattern in ipairs(patterns) do
          if line:find(pattern) then
            vim.api.nvim_win_set_cursor(0, {i, 0})
            return
          end
        end
      end
      return
    end
  end

  -- Search for local JS definition
  local blocks = dataform.get_sqlx_blocks()
  local var_patterns = {
    "const%s+" .. word .. "%s*=",
    "let%s+" .. word .. "%s*=",
    "var%s+" .. word .. "%s*=",
    "function%s+" .. word .. "%s*%(",
    word .. "%s*[:=]%s*function"
  }

  if blocks.js.exists then
    for i = blocks.js.start_line, blocks.js.end_line do
      local line = lines[i]
      for _, pattern in ipairs(var_patterns) do
        if line:find(pattern) then
          vim.api.nvim_win_set_cursor(0, {i, 0})
          return
        end
      end
    end
  end
end

function dataform.hover()
  local context = dataform.get_context_at_cursor()
  local word = context.word
  if word == "" then return end

  local hover_content = {}

  if context.type == "table" then
    local all_models = get_all_models()
    local found = false
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
        table.insert(hover_content, "# " .. node.target.database .. "." .. node.target.schema .. "." .. node.target.name)
        table.insert(hover_content, "---")
        table.insert(hover_content, "**Type:** " .. (node.type or "table"))
        table.insert(hover_content, "**File:** " .. node.fileName)
        if node.actionDescriptor and node.actionDescriptor.description then
           table.insert(hover_content, "")
           table.insert(hover_content, node.actionDescriptor.description)
        end
        found = true
        break
      end
    end

    if not found and #all_models > 0 then
       -- Fallback: try matching by name only if schema provided but no exact match
       if context.schema then
         for _, node in pairs(all_models) do
           if node.target.name == context.table_name then
             table.insert(hover_content, "# " .. node.target.database .. "." .. node.target.schema .. "." .. node.target.name)
             table.insert(hover_content, "---")
             table.insert(hover_content, "**Type:** " .. (node.type or "table"))
             table.insert(hover_content, "**File:** " .. node.fileName .. " (Schema mismatch: expected " .. context.schema .. ")")
             found = true
             break
           end
         end
       end
    end
  end

  -- Column hover
  if #hover_content == 0 then
    local all_models = get_all_models()
    local found_columns = {}
    for _, node in pairs(all_models) do
      if node.actionDescriptor and node.actionDescriptor.columns then
        for _, col_meta in ipairs(node.actionDescriptor.columns) do
          local col_name = col_meta.path[#col_meta.path]
          if col_name == word then
            table.insert(found_columns, {
              table = node.target.schema .. "." .. node.target.name,
              description = col_meta.description or "No description provided."
            })
          end
        end
      end
    end

    if #found_columns > 0 then
      table.insert(hover_content, "# Column: " .. word)
      table.insert(hover_content, "---")
      for _, col in ipairs(found_columns) do
        table.insert(hover_content, "**Table:** " .. col.table)
        table.insert(hover_content, col.description)
        table.insert(hover_content, "")
      end
    end
  end

  -- Project Variables hover
  if #hover_content == 0 and context.type == "variable" then
    local var_path = context.var_name
    local vars = dataform.compiled_project_table.projectConfig and dataform.compiled_project_table.projectConfig.vars
    if vars and vars[var_path] then
      table.insert(hover_content, "# Project Variable: " .. var_path)
      table.insert(hover_content, "---")
      table.insert(hover_content, "**Value:** `" .. tostring(vars[var_path]) .. "`")
      table.insert(hover_content, "**Defined in:** `workflow_settings.yaml`")
    end
  end

  -- Config block hovers
  if #hover_content == 0 then
    local assertions_help = {
      nonNull = "This condition asserts that the specified columns are not null across all table rows.",
      uniqueKey = "This condition asserts that, in a specified column, no table rows have the same value.",
      rowConditions = "This condition asserts that all table rows follow the custom logic you define."
    }
    if assertions_help[word] then
      table.insert(hover_content, "# assertion: " .. word)
      table.insert(hover_content, "---")
      table.insert(hover_content, assertions_help[word])
    end
  end

  -- 5. JS Symbol hover (Functions or Modules/Constants)
  if #hover_content == 0 and (context.type == "function" or context.type == "js_module") then
    local sig = require("dataform.signatures").get_signature_for_name(word)
    if sig then
      table.insert(hover_content, "# JS Symbol: " .. word)
      table.insert(hover_content, "---")
      if context.type == "function" then
        table.insert(hover_content, "**Signature:** `" .. word .. "(" .. table.concat(sig.params, ", ") .. ")`")
      end
      if sig.doc and sig.doc ~= "" then
        if context.type == "function" then table.insert(hover_content, "") end
        table.insert(hover_content, sig.doc)
      end
    end
  end

  -- 6. Tag hover
  if #hover_content == 0 then
    -- Check if word is inside tags: [ "tag" ]
    local lua_escaped_word = word:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if context.current_line:find('tags%s*:%s*%[[^%]]*["\']' .. lua_escaped_word .. '["\']') then
      table.insert(hover_content, "# Tag: " .. word)
      table.insert(hover_content, "---")
      table.insert(hover_content, "This is a Dataform tag. Use `:DataformCodeAction` to view the dependency tree for all models with this tag.")
    end
  end

  if #hover_content > 0 then
    vim.lsp.util.open_floating_preview(hover_content, "markdown", {
      border = "rounded",
      focusable = true,
      focus_id = "dataform_hover",
    })
  end
end

local ns = vim.api.nvim_create_namespace("dataform_diagnostics")
local vt_ns = vim.api.nvim_create_namespace("dataform_virtual_text")

function dataform.check_unresolved_references(bufnr)
  local diagnostics = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local vars = dataform.compiled_project_table.projectConfig and dataform.compiled_project_table.projectConfig.vars or {}

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
         local sig = require("dataform.signatures").get_signature_for_name(ref)
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

function dataform.set_diagnostics(compiled_json)
  vim.diagnostic.reset(ns)
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
        local local_diagnostics = dataform.check_unresolved_references(bufnr)
        for _, ld in ipairs(local_diagnostics) do
          table.insert(diagnostics, ld)
        end
      end
      vim.diagnostic.set(ns, bufnr, diagnostics)
    end
  end

  -- If current buffer wasn't in diagnostics_by_file, check it specifically for local errors
  local cur_buf = vim.api.nvim_get_current_buf()
  local cur_file = vim.api.nvim_buf_get_name(cur_buf)
  if not diagnostics_by_file[cur_file] then
     local local_diagnostics = dataform.check_unresolved_references(cur_buf)
     if #local_diagnostics > 0 then
        vim.diagnostic.set(ns, cur_buf, local_diagnostics)
     end
  end
end

function dataform.clear_diagnostics()
  vim.diagnostic.reset(ns)
end

function dataform.format()
  local bufnr = vim.api.nvim_get_current_buf()
  local blocks = dataform.get_sqlx_blocks()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if not blocks.sql.exists or not dataform.config.formatter_bin or dataform.config.formatter_bin == "" then
    return
  end

  local sql_lines = {}
  for i = blocks.sql.start_line, blocks.sql.end_line do
    table.insert(sql_lines, lines[i])
  end

  local tmp_sql = os.tmpname() .. ".sql"
  local f = io.open(tmp_sql, "w")
  if not f then return end
  f:write(table.concat(sql_lines, "\n"))
  f:close()

  local options = table.concat(dataform.config.formatter_options or {}, " ")
  local cmd = string.format("%s %s %s > /dev/null 2>&1",
    dataform.config.formatter_bin, options, tmp_sql)

  os.execute(cmd)

  local f_in = io.open(tmp_sql, "r")
  if f_in then
    local formatted_sql = f_in:read("*all")
    f_in:close()
    os.remove(tmp_sql)

    local formatted_sql_lines = vim.split(formatted_sql, "\n")
    if formatted_sql_lines[#formatted_sql_lines] == "" then
      table.remove(formatted_sql_lines)
    end

    vim.api.nvim_buf_set_lines(bufnr, blocks.sql.start_line - 1, blocks.sql.end_line, false, formatted_sql_lines)
    utils.notify("SQL block formatted with " .. dataform.config.formatter_bin .. ".", vim.log.levels.INFO)
  else
    os.remove(tmp_sql)
  end
end

function dataform.show_dependency_tree(models)
  utils.log("show_dependency_tree: triggered")
  local all_models = get_all_models()
  local target_models = {}

  if models then
    target_models = models
  else
    local target_file_path = get_dataform_definitions_file_path()
    local target_model = find_model_by_file_path(all_models, target_file_path)
    if target_model then
      table.insert(target_models, target_model)
    end
  end

  if #target_models == 0 then
    utils.notify("No models found to build tree.", vim.log.levels.WARN)
    return
  end

  local tree_lines = {}
  local line_to_file = {}
  local title = #target_models == 1
    and ("Dependency Tree for: " .. target_models[1].target.schema .. "." .. target_models[1].target.name)
    or "Scoped Dependency Tree"

  table.insert(tree_lines, title)
  table.insert(tree_lines, string.rep("=", #tree_lines[1]))
  table.insert(tree_lines, "")
  table.insert(tree_lines, "Tip: Press <CR> on a node to jump to file, 'q' to close.")
  table.insert(tree_lines, "")

  local seen = {}
  local function build_tree(model, indent, is_last)
    local prefix = indent .. (is_last and "└── " or "├── ")
    local node_name = model.target.schema .. "." .. model.target.name
    table.insert(tree_lines, prefix .. node_name .. " (" .. (model.type or "table") .. ")")
    line_to_file[#tree_lines] = model.fileName

    if seen[node_name] then
      tree_lines[#tree_lines] = tree_lines[#tree_lines] .. " (recursive)"
      return
    end
    seen[node_name] = true

    local deps = model.dependencyTargets or {}
    for i, dep_target in ipairs(deps) do
      local dep_model = nil
      for _, m in pairs(all_models) do
        if m.target.schema == dep_target.schema and m.target.name == dep_target.name then
          dep_model = m
          break
        end
      end

      if dep_model then
        local new_indent = indent .. (is_last and "    " or "│   ")
        build_tree(dep_model, new_indent, i == #deps)
      else
        local dep_prefix = indent .. (is_last and "    " or "│   ") .. (i == #deps and "└── " or "├── ")
        table.insert(tree_lines, dep_prefix .. dep_target.schema .. "." .. dep_target.name .. " (unresolved)")
      end
    end
  end

  for i, model in ipairs(target_models) do
    build_tree(model, "", i == #target_models)
  end

  local keymaps = {
    ['<CR>'] = function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local file = line_to_file[line]
      if file then
        vim.cmd("close")
        utils.open_file(file)
      end
    end
  }

  utils.open_interactive_buffer(table.concat(tree_lines, "\n"), "dataform_tree", "Dataform Dependencies", keymaps)
end

function dataform.show_tag_dependency_tree(tag)
  if not tag or tag == "" then return end
  local all_models = get_all_models()
  local filtered = {}
  for _, model in pairs(all_models) do
    if model.tags then
      for _, t in ipairs(model.tags) do
        if t == tag then
          table.insert(filtered, model)
          break
        end
      end
    end
  end

  if #filtered > 0 then
    dataform.show_dependency_tree(filtered)
  else
    utils.notify("No models found with tag: " .. tag, vim.log.levels.WARN)
  end
end

function dataform.estimate_tag_cost(tag)
  if not tag or tag == "" then
    utils.notify("Please provide a tag name.", vim.log.levels.WARN)
    return
  end

  local all_models = get_all_models()
  local filtered = {}
  for _, model in pairs(all_models) do
    if model.tags then
      for _, t in ipairs(model.tags) do
        if t == tag then
          table.insert(filtered, model)
          break
        end
      end
    end
  end

  if #filtered == 0 then
    utils.notify("No models found with tag: " .. tag, vim.log.levels.WARN)
    return
  end

  utils.notify("Estimating cost for tag: " .. tag .. " (" .. #filtered .. " models)... This may take a while.", vim.log.levels.INFO)

  local total_bytes = 0
  local errors = {}

  for _, model in ipairs(filtered) do
    local query = ""
    local target_name = model.target.database .. "." .. model.target.schema .. "." .. model.target.name

    if model.type == "view" then
      query = "CREATE OR REPLACE VIEW `" .. target_name .. "` AS " .. model.query
    elseif model.type == "table" then
      query = "CREATE OR REPLACE TABLE `" .. target_name .. "` AS " .. model.query
    elseif model.type == "incremental" then
      query = "CREATE OR REPLACE TABLE `" .. target_name .. "` AS " .. (model.incrementalQuery or model.query)
    elseif model.query then
      query = model.query
    elseif model.queries then
      query = table.concat(model.queries, ";\n")
    end

    if query ~= "" then
      local bq_command = "echo " .. vim.fn.shellescape(query) .. " | bq query --dry_run"
      local status, result = utils.os_execute_with_status(bq_command, false, true)

      if status == 0 then
        local bytes = result:match("process%s+(%d+)%s+bytes")
        if bytes then
          total_bytes = total_bytes + tonumber(bytes)
        end
      else
        table.insert(errors, target_name)
      end
    end
  end

  local stats = utils.parse_dry_run_stats("process " .. total_bytes .. " bytes")
  local msg = "Tag '" .. tag .. "' Cost Estimation:\n" .. stats
  if #errors > 0 then
    msg = msg .. "\nErrors encountered in " .. #errors .. " models: " .. table.concat(errors, ", ")
  end

  utils.notify(msg, vim.log.levels.INFO)
end

function dataform.show_dry_run_virtual_text()
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local model = find_model_by_file_path(all_models, target_file_path)

  if not model or not model.query then return end

  local target_name = model.target.database .. "." .. model.target.schema .. "." .. model.target.name
  local query = ""

  if model.type == "view" then
    query = "CREATE OR REPLACE VIEW `" .. target_name .. "` AS " .. model.query
  elseif model.type == "table" then
    query = "CREATE OR REPLACE TABLE `" .. target_name .. "` AS " .. model.query
  elseif model.type == "incremental" then
    query = "CREATE OR REPLACE TABLE `" .. target_name .. "` AS " .. (model.incrementalQuery or model.query)
  else
    query = model.query
  end

  local bq_command = "echo " .. vim.fn.shellescape(query) .. " | bq query --dry_run"
  -- Use background execution if possible, but for now we'll do it synchronously
  local status, result = utils.os_execute_with_status(bq_command, false, true)

  if status == 0 then
    local stats = utils.parse_dry_run_stats(result)
    if stats then
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_clear_namespace(bufnr, vt_ns, 0, -1)
      vim.api.nvim_buf_set_extmark(bufnr, vt_ns, 0, 0, {
        virt_text = { { "󱓞 " .. stats, "DiagnosticInfo" } },
        virt_text_pos = "right_align",
      })
    end
  end
end

function dataform.compile()
  local command = "dataform compile"
  -- Use quiet=true to avoid the automatic notification from os_execute_with_status
  local status, content = utils.os_execute_with_status(command .. " --json", true, true)

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if ok then
    dataform.compiled_project_table = decoded
    dataform.set_diagnostics(decoded)

    utils.log({
      event = "compilation_summary",
      tables = #(decoded.tables or {}),
      declarations = #(decoded.declarations or {}),
      operations = #(decoded.operations or {}),
      assertions = #(decoded.assertions or {}),
      graph_errors = #(decoded.graphErrors and decoded.graphErrors.compilationErrors or {})
    })

    if status == 0 then
      utils.notify("Dataform compiled successfully.", vim.log.levels.INFO)
    else
      utils.notify("Dataform compiled with errors (see diagnostics).", vim.log.levels.WARN)
    end
  else
    -- JSON decode failed, likely a hard compilation error
    local _, content_error = utils.os_execute_with_status(command, false, true)

    -- Truncate very long errors
    local lines = vim.split(content_error, "\n")
    local msg = content_error
    if #lines > 15 then
       msg = table.concat(vim.list_slice(lines, 1, 15), "\n") .. "\n... (truncated)"
    end

    utils.notify(
      "Error: Dataform compile failed. \n\n" .. msg,
      vim.log.levels.ERROR
    )
  end
end

function dataform.get_compiled_sql_job(incremental)
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local table = find_model_by_file_path(all_models, target_file_path)

  if table then
    local preOpsKey = incremental and "incrementalPreOps" or "preOps"
    local postOpsKey = incremental and "incrementalPostOps" or "postOps"
    local queryKey = incremental and "incrementalQuery" or "query"

    local preOps = type(table[preOpsKey]) == "table" and table[preOpsKey][1] or ""
    local postOps = type(table[postOpsKey]) == "table" and table[postOpsKey][1] or ""

    local preOpsClean = preOps:gsub("%s+$", "")
    if preOpsClean:sub(-1) ~= ";" and preOps ~= "" then preOps = preOps .. ";" end

    local composite_query = preOps .. table[queryKey] .. ";\n" .. postOps
    local bq_command = "echo " .. vim.fn.shellescape(composite_query) .. " | bq query --dry_run"

    local _, result = utils.os_execute_with_status(bq_command)

    local stats = utils.parse_dry_run_stats(result)
    local header = ""
    if stats then
      header = "-- " .. stats .. "\n\n"
      utils.notify(stats, vim.log.levels.INFO)
    else
      header = "-- Dry run failed or stats unavailable\n-- " .. result:gsub("\n", "\n-- ") .. "\n\n"
      utils.notify(result, vim.log.levels.WARN)
    end

    local final_content = header .. composite_query
    if dataform.config.preview_style == "float" then
      return utils.open_floating_window(final_content, "sql", "Dataform Preview")
    else
      return utils.open_buffer_with_content(final_content, "sql", "Dataform Preview")
    end
  end
end

function dataform.run_all()
  local command = "dataform run"
  local status, content = utils.os_execute_with_status(command)
  if status == 0 then
    return utils.notify(
      "Dataform run executed successfully.",
      vim.log.levels.INFO
    )
  end
  return utils.notify(
    "Error: Dataform run failed. \n\n" .. content,
    vim.log.levels.ERROR
  )
end

function dataform.run_tag(args)
  local tags = args or ""
  local command = "dataform run --tags=" .. tags
  local status, content = utils.os_execute_with_status(command)
  if status == 0 then
    return utils.notify(
      "Dataform tag run executed successfully.",
      vim.log.levels.INFO
    )
  end

  return utils.notify(
    "Error: Dataform tag run failed. \n\n" .. content,
    vim.log.levels.ERROR
  )
end

function dataform.run_action_job(full_refresh)
  local full_refresh = full_refresh or false
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local table = find_model_by_file_path(all_models, target_file_path)

  if table then
    local action = table.target.database .. "." .. table.target.schema .. "." .. table.target.name
    local command = "dataform run --full-refresh=" .. tostring(full_refresh) .. " --actions=" .. action

    local status, content = utils.os_execute_with_status(command)

    if status == 0 then
      return utils.notify(
        "Dataform run executed successfully.",
        vim.log.levels.INFO
      )
    end
    return utils.notify(
      "Error: Dataform run failed. \n\n" .. content,
      vim.log.levels.ERROR
    )
  end
end

function dataform.run_assertions_job()
  local assertions = dataform.compiled_project_table.assertions or {}
  local target_assertions = {}
  local target_file_path = get_dataform_definitions_file_path()
  if not target_file_path then return end
  local target_abs = vim.fn.fnamemodify(target_file_path, ":p")

  for _, assertion in pairs(assertions) do
    if assertion.fileName and vim.fn.fnamemodify(assertion.fileName, ":p") == target_abs then
      local action = assertion.target.database .. "." .. assertion.target.schema .. "." .. assertion.target.name
      table.insert(target_assertions, action)
    end
  end
  -- check if target_assertions is still empty and if it is raise error
  if vim.tbl_isempty(target_assertions) then
    return utils.notify(
      "Error: There is no assertions for this file.",
      vim.log.levels.ERROR
    )
  end

  for _, assertion in pairs(target_assertions) do
    local command = "dataform run " .. "--actions=" .. assertion
    local status, content = utils.os_execute_with_status(command)

    if status == 0 then
      utils.notify(
        "Dataform assertion: \n" .. assertion .. "\nexecuted successfully.",
        vim.log.levels.INFO
      )
    else
      utils.notify(
        "Error: Dataform assertions failed. \n\n" .. content,
        vim.log.levels.ERROR
      )
    end
  end
end

function dataform.find_model_dependents()
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local target_model = find_model_by_file_path(all_models, target_file_path)
  local target_paths = {}

  if not target_model then
    return utils.custom_picker("Model Dependents", target_paths)
  end

  local schema = target_model.target.schema
  local name = target_model.target.name

  for _, model in pairs(all_models) do
    local dependency_targets = model.dependencyTargets
    if dependency_targets then
      for _, dependency in pairs(dependency_targets) do
        if dependency.schema == schema and dependency.name == name then
          table.insert(target_paths, model.fileName)
        end
      end
    end
  end

  return utils.custom_picker("Model Dependents", target_paths)
end

function dataform.find_model_dependencies()
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local target_model = find_model_by_file_path(all_models, target_file_path)
  local target_paths = {}

  if not target_model then
    return utils.custom_picker("Model Dependencies", target_paths)
  end

  local dependencies = target_model.dependencyTargets
  if dependencies then
    for _, dependency in pairs(dependencies) do
      local schema = dependency.schema
      local name = dependency.name
      local target_path = find_file_name_by_schema_name(all_models, schema, name)
      table.insert(target_paths, target_path)
    end
  end

  return utils.custom_picker("Model Dependencies", target_paths)
end

function dataform.compile_on_save()
  if dataform.config.compile_on_save then
    dataform.compile()
    -- Only run dry run if compilation was successful (we can check compiled_project_table)
    if dataform.compiled_project_table and not (dataform.compiled_project_table.graphErrors and #dataform.compiled_project_table.graphErrors.compilationErrors > 0) then
       dataform.show_dry_run_virtual_text()
    end
  end
end

function dataform.toggle_compile_on_save()
  dataform.config.compile_on_save = not dataform.config.compile_on_save
  local status = dataform.config.compile_on_save and "enabled" or "disabled"
  utils.notify("Dataform compile on save " .. status .. ".", vim.log.levels.INFO)
end

function dataform.format_on_save()
  if dataform.config.format_on_save then
    dataform.format()
  end
end

function dataform.toggle_format_on_save()
  dataform.config.format_on_save = not dataform.config.format_on_save
  local status = dataform.config.format_on_save and "enabled" or "disabled"
  utils.notify("Dataform format on save " .. status .. ".", vim.log.levels.INFO)
end

function dataform.toggle_preview_style()
  if dataform.config.preview_style == "float" then
    dataform.config.preview_style = "vsplit"
  else
    dataform.config.preview_style = "float"
  end
  utils.notify("Dataform preview style set to: " .. dataform.config.preview_style, vim.log.levels.INFO)
end

function dataform.toggle_treesitter()
  dataform.config.use_treesitter = not dataform.config.use_treesitter
  local status = dataform.config.use_treesitter and "enabled" or "disabled"
  utils.notify("Dataform Tree-sitter integration " .. status .. ".", vim.log.levels.INFO)
end

function dataform.toggle_logging()
  dataform.config.logging = not dataform.config.logging
  local status = dataform.config.logging and "enabled" or "disabled"
  utils.notify("Dataform logging " .. status .. ".", vim.log.levels.INFO)
end

function dataform.create_declaration(schema, name)
  local file_path = "definitions/sources/" .. (schema or "external") .. "/" .. name .. ".sqlx"
  local dir_path = vim.fn.fnamemodify(file_path, ":h")

  if vim.fn.isdirectory(dir_path) == 0 then
    vim.fn.mkdir(dir_path, "p")
  end

  if vim.fn.filereadable(file_path) == 1 then
    utils.notify("Declaration file already exists: " .. file_path, vim.log.levels.WARN)
    return utils.open_file(file_path)
  end

  local content = string.format([[config {
  type: "declaration",
  database: "YOUR_DATABASE",
  schema: "%s",
  name: "%s",
  description: "External table declaration."
}
]], schema or "YOUR_SCHEMA", name)

  local f = io.open(file_path, "w")
  if f then
    f:write(content)
    f:close()
    utils.notify("Created declaration: " .. file_path, vim.log.levels.INFO)
    utils.open_file(file_path)
  end
end

function dataform.code_action()
  local context = dataform.get_context_at_cursor()
  local actions = {}

  if context.type == "table" then
    -- Check if table exists in graph
    local all_models = get_all_models()
    local found = false
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
        found = true
        break
      end
    end

    if not found then
      table.insert(actions, {
        title = "Create declaration for '" .. context.table_name .. "'",
        handler = function() dataform.create_declaration(context.schema, context.table_name) end
      })
    end
  end

  -- Check if on a tag
  local lua_escaped_word = context.word:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  if context.current_line:find('tags%s*:%s*%[[^%]]*["\']' .. lua_escaped_word .. '["\']') then
    table.insert(actions, {
      title = "Show dependency tree for tag '" .. context.word .. "'",
      handler = function() dataform.show_tag_dependency_tree(context.word) end
    })
  end

  if #actions == 0 then
    utils.notify("No code actions available at cursor.", vim.log.levels.INFO)
    return
  end

  vim.ui.select(actions, {
    prompt = "Dataform Code Actions:",
    format_item = function(item) return item.title end,
  }, function(choice)
    if choice then
      choice.handler()
    end
  end)
end

function dataform.find_variable_references()
  local context = dataform.get_context_at_cursor()
  local word = context.word

  if word == "" then
    utils.notify("No symbol under cursor.", vim.log.levels.WARN)
    return
  end

  local search_patterns = {}
  local label = word
  local escaped_word = word:gsub("%.", "\\.")

  if context.type == "variable" then
    local escaped_var = context.var_name:gsub("%.", "\\.")
    table.insert(search_patterns, "dataform\\.projectConfig\\.vars\\." .. escaped_var)
    table.insert(search_patterns, "^" .. escaped_var .. ":")
    label = "variable: " .. context.var_name
  elseif context.type == "table" then
    local escaped_table = context.table_name:gsub("%.", "\\.")
    -- Search for ref("table"), ref("schema", "table"), resolve("table"), etc.
    table.insert(search_patterns, "ref%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
    table.insert(search_patterns, "resolve%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
    -- Search in dependencies list: dependencies: [ "table" ]
    table.insert(search_patterns, "dependencies%s*:%s*%[[^%]]*[\"']" .. escaped_table .. "[\"'][^%]]*%]")
    -- Search for definition: name: "table"
    table.insert(search_patterns, 'name%s*:%s*["\']' .. escaped_table .. '["\']')

    if context.schema then
       local escaped_schema = context.schema:gsub("%.", "\\.")
       -- Add a pattern specifically matching this schema and table
       table.insert(search_patterns, "ref%s*%(%s*[\"']" .. escaped_schema .. "[\"']%s*,%s*[\"']" .. escaped_table .. "[\"']%s*%)")
       label = "table: " .. context.schema .. "." .. context.table_name
    else
       label = "table: " .. context.table_name
    end
  elseif context.type == "function" then
    table.insert(search_patterns, escaped_word .. "%s*%(")
    table.insert(search_patterns, "function%s+" .. escaped_word)
    table.insert(search_patterns, escaped_word .. "%s*[:=]%s*function")
    table.insert(search_patterns, "module%.exports%s*=%s*{[^}]*" .. escaped_word)
    label = "function: " .. word
  else
    -- Fallback
    table.insert(search_patterns, escaped_word)
    label = "symbol: " .. word
  end

  utils.notify("Finding references for " .. label .. "...", vim.log.levels.INFO)

  -- Use grep to find all occurrences
  local combined_pattern = table.concat(search_patterns, "|")
  local cmd = string.format("grep -rnE %s . --include='*.sqlx' --include='*.js' --include='workflow_settings.yaml' --include='*.yaml' --include='*.json' 2>/dev/null",
    vim.fn.shellescape(combined_pattern))

  local _, output = utils.os_execute_with_status(cmd, false, true)

  local results = {}
  local seen = {}
  for line in output:gmatch("[^\r\n]+") do
    if not seen[line] then
      table.insert(results, line)
      seen[line] = true
    end
  end

  if #results == 0 then
    utils.notify("No references found for " .. label, vim.log.levels.INFO)
    return
  end

  -- Show results in a quickfix list
  local qf_list = {}
  for _, line in ipairs(results) do
    local file, lnum, text = line:match("([^:]+):(%d+):(.*)")
    if file and lnum then
      table.insert(qf_list, {
        filename = file,
        lnum = tonumber(lnum),
        text = vim.trim(text)
      })
    end
  end

  vim.fn.setqflist(qf_list)
  vim.cmd("copen")
end

return dataform
