local utils = require("dataform.utils")

local dataform = {}
dataform.compiled_project_table = {}

---@alias DataformUserConfig table
---@field compile_on_save boolean? (default: true) Automatically compile Dataform project on saving a .sqlx file.

local default_config = {
  compile_on_save = true,
  formatter_bin = "sqlfluff",
  formatter_options = { "fix", "--force", "-q" },
}
dataform.config = vim.deepcopy(default_config)

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
  local current_path = utils.get_current_file_path()
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

local function get_dataform_definitions_file_path()
  local file = utils.get_current_file_path()
  local pattern = ".*/definitions/"
  local is_match = string.match(file, pattern)
  local dataform_path = string.gsub(file, pattern, "")

  if is_match then
    return "definitions/" .. dataform_path
  end
  return utils.notify(
    "Error: File does not exist inside dataform definitions folder.",
    vim.log.levels.ERROR
  )
end

function dataform.go_to_ref()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = lines[row]

  -- Improve word extraction to handle dots (e.g., constants.TAX_RATE)
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

  -- 1. Check for CTE navigation (SQL files only or SQL blocks)
  local cte_pattern = "WITH%s+" .. word .. "%s+AS%s*%("
  local cte_pattern_comma = ",%s*" .. word .. "%s+AS%s*%("
  for i, line in ipairs(lines) do
    if line:find(cte_pattern) or line:find(cte_pattern_comma) then
      vim.api.nvim_win_set_cursor(0, {i, 0})
      return
    end
  end

  -- 2. Check for ${ ... } blocks (Ref/Resolve/JS)
  local start_row, start_col, end_row, end_col
  -- Find start of ${
  for r = row, 1, -1 do
    local line = lines[r]
    local search_start = (r == row) and col or #line
    -- Search backwards for ${
    local s = line:sub(1, search_start + 1):reverse():find("{$", 1, true)
    if s then
      start_row = r
      start_col = #line:sub(1, search_start + 1) - s
      break
    end
  end

  -- Find end of }
  if start_row then
    for r = row, #lines do
      local line = lines[r]
      local search_start = (r == row) and col or 0
      local e = line:find("}", search_start + 1, true)
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
      local line = lines[r]
      if r == start_row and r == end_row then
        block_content = line:sub(start_col + 1, end_col)
      elseif r == start_row then
        block_content = line:sub(start_col + 1)
      elseif r == end_row then
        block_content = block_content .. "\n" .. line:sub(1, end_col)
      else
        block_content = block_content .. "\n" .. line
      end
    end

    -- Extract ref/resolve
    local _, _, schema, table_name = block_content:find('ref%(%s*["\']([^"\']+)["\']%s*,%s*["\']([^"\']+)["\']%s*%)')
    if not table_name then
      _, _, table_name = block_content:find('ref%(%s*["\']([^"\']+)["\']%s*%)')
    end
    if not table_name then
      _, _, schema, table_name = block_content:find('resolve%(%s*["\']([^"\']+)["\']%s*,%s*["\']([^"\']+)["\']%s*%)')
    end
    if not table_name then
      _, _, table_name = block_content:find('resolve%(%s*["\']([^"\']+)["\']%s*%)')
    end

    if table_name then
      local df_tables = dataform.compiled_project_table.tables or {}
      local df_declarations = dataform.compiled_project_table.declarations or {}
      local df_ops = dataform.compiled_project_table.operations or {}
      local all_nodes = {}
      for _, v in ipairs(df_tables) do table.insert(all_nodes, v) end
      for _, v in ipairs(df_declarations) do table.insert(all_nodes, v) end
      for _, v in ipairs(df_ops) do table.insert(all_nodes, v) end

      for _, node in pairs(all_nodes) do
        if node.target.name == table_name and (node.target.schema == schema or not schema) then
          return utils.open_file(node.fileName)
        end
      end
    end

    -- JS variable navigation within ${ ... }
    if word:find("%.") then
      local parts = vim.split(word, "%.")
      local js_module = parts[1]
      local var_name = parts[2]

      -- Check in includes/
      local includes_file = "includes/" .. js_module .. ".js"
      if vim.fn.filereadable(includes_file) == 1 then
        utils.open_file(includes_file)
        -- Try to find variable in that file
        local file_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local pattern = "const%s+" .. var_name .. "%s*="
        for i, line in ipairs(file_lines) do
          if line:find(pattern) then
            vim.api.nvim_win_set_cursor(0, {i, 0})
            break
          end
        end
        return
      end

      -- Check for require in js block
      local blocks = dataform.get_sqlx_blocks()
      if blocks.js.exists then
        for i = blocks.js.start_line, blocks.js.end_line do
          local line = lines[i]
          local req_pattern = "const%s+" .. js_module .. "%s*=%s*require%([\"'](.+)[\"']%)"
          local _, _, req_path = line:find(req_pattern)
          if req_path then
            if req_path:sub(1,1) ~= "/" and req_path:sub(1,2) ~= "./" then
               req_path = "includes/" .. req_path
            end
            if req_path:sub(-3) ~= ".js" then
               req_path = req_path .. ".js"
            end
            if vim.fn.filereadable(req_path) == 1 then
              utils.open_file(req_path)
              return
            end
          end
        end
      end
    end
  end

  -- 3. Check for local JS variable in JS block
  local blocks = dataform.get_sqlx_blocks()
  if blocks.js.exists then
    if row >= blocks.js.start_line and row <= blocks.js.end_line then
      -- Already in JS block, maybe searching for definition within it
    else
      -- Search for word definition in JS block
      local var_pattern = "const%s+" .. word .. "%s*="
      local var_pattern_let = "let%s+" .. word .. "%s*="
      local var_pattern_var = "var%s+" .. word .. "%s*="
      local func_pattern = "function%s+" .. word .. "%s*%("

      for i = blocks.js.start_line, blocks.js.end_line do
        local line = lines[i]
        if line:find(var_pattern) or line:find(var_pattern_let) or line:find(var_pattern_var) or line:find(func_pattern) then
          vim.api.nvim_win_set_cursor(0, {i, 0})
          return
        end
      end
    end
  end
end

function dataform.hover()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor_pos[1], cursor_pos[2]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = lines[row]

  -- Extraction logic for word under cursor (including dots)
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
  if word == "" then return end

  local hover_content = {}

  -- 1. Check for ref/resolve hover (Table/Declaration metadata)
  local _, _, table_name = current_line:find('ref%(%s*["\']([^"\']+)["\']%s*%)')
  if not table_name then
    _, _, _, table_name = current_line:find('ref%(%s*["\']([^"\']+)["\']%s*,%s*["\']([^"\']+)["\']%s*%)')
  end
  if not table_name then
    _, _, table_name = current_line:find('resolve%(%s*["\']([^"\']+)["\']%s*%)')
  end

  if table_name and word:find(table_name, 1, true) then
    local all_models = get_all_models()
    for _, node in pairs(all_models) do
      if node.target.name == table_name then
        table.insert(hover_content, "# " .. node.target.database .. "." .. node.target.schema .. "." .. node.target.name)
        table.insert(hover_content, "---")
        table.insert(hover_content, "**Type:** " .. (node.type or "table"))
        table.insert(hover_content, "**File:** " .. node.fileName)
        if node.actionDescriptor and node.actionDescriptor.description then
           table.insert(hover_content, "")
           table.insert(hover_content, node.actionDescriptor.description)
        end
        break
      end
    end
  end

  -- 2. Check for Column hover (Search all columns in compiled graph)
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

  -- 3. Config block hovers
  if #hover_content == 0 then
    if word == "nonNull" then
      table.insert(hover_content, "# assertion: nonNull")
      table.insert(hover_content, "---")
      table.insert(hover_content, "This condition asserts that the specified columns are not null across all table rows.")
    elseif word == "uniqueKey" then
      table.insert(hover_content, "# assertion: uniqueKey")
      table.insert(hover_content, "---")
      table.insert(hover_content, "This condition asserts that, in a specified column, no table rows have the same value.")
    elseif word == "rowConditions" then
      table.insert(hover_content, "# assertion: rowConditions")
      table.insert(hover_content, "---")
      table.insert(hover_content, "This condition asserts that all table rows follow the custom logic you define.")
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

function dataform.set_diagnostics(compiled_json)
  vim.diagnostic.reset(ns)
  if not compiled_json or not compiled_json.graphErrors or not compiled_json.graphErrors.compilationErrors then
    return
  end

  local diagnostics_by_file = {}
  for _, err in ipairs(compiled_json.graphErrors.compilationErrors) do
    if err.fileName then
      local file_diagnostics = diagnostics_by_file[err.fileName] or {}
      table.insert(file_diagnostics, {
        lnum = 0, -- Dataform CLI often doesn't give line numbers for graph errors
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        message = err.message,
        source = "Dataform",
      })
      diagnostics_by_file[err.fileName] = file_diagnostics
    end
  end

  for fileName, diagnostics in pairs(diagnostics_by_file) do
    -- Try to find the buffer for this file
    local bufnr = -1
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):find(fileName, 1, true) then
        bufnr = buf
        break
      end
    end

    if bufnr ~= -1 then
      vim.diagnostic.set(ns, bufnr, diagnostics)
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

function dataform.show_dependency_tree()
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local target_model = find_model_by_file_path(all_models, target_file_path)

  if not target_model then
    utils.notify("Model not found in compiled project.", vim.log.levels.WARN)
    return
  end

  local tree_lines = {}
  table.insert(tree_lines, "Dependency Tree for: " .. target_model.target.schema .. "." .. target_model.target.name)
  table.insert(tree_lines, string.rep("=", #tree_lines[1]))
  table.insert(tree_lines, "")

  local seen = {}
  local function build_tree(model, indent, is_last)
    local prefix = indent .. (is_last and "└── " or "├── ")
    local node_name = model.target.schema .. "." .. model.target.name
    table.insert(tree_lines, prefix .. node_name .. " (" .. (model.type or "table") .. ")")

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

  build_tree(target_model, "", true)

  utils.open_buffer_with_content(table.concat(tree_lines, "\n"), "text", "Dataform Dependencies")
end

function dataform.compile()
  local command = "dataform compile"
  local status, content = utils.os_execute_with_status(command .. " --json", true)

  -- Even if status != 0, we might have valid JSON with graph errors
  local ok, decoded = pcall(vim.fn.json_decode, content)
  if ok then
    dataform.compiled_project_table = decoded
    dataform.set_diagnostics(decoded)

    if status == 0 then
      utils.notify("Dataform compiled successfully.", vim.log.levels.INFO)
    else
      utils.notify("Dataform compiled with errors.", vim.log.levels.WARN)
    end
  else
    local _, content_error = utils.os_execute_with_status(command)
    utils.notify(
      "Error: Dataform compile failed. \n\n" .. content_error,
      vim.log.levels.ERROR
    )
  end
end

function dataform.get_compiled_sql_job(incremental)
  local tables = dataform.compiled_project_table.tables

  for _, table in pairs(tables) do
    if table.fileName == get_dataform_definitions_file_path() then
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

            return utils.open_buffer_with_content(header .. composite_query, "sql", "Dataform Preview")

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
  local df_tables = dataform.compiled_project_table.tables or {}
  local df_operations = dataform.compiled_project_table.operations or {}
  local tables = vim.fn.extend(df_tables, df_operations)

  for _, table in pairs(tables) do
    if table.fileName == get_dataform_definitions_file_path() then
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
end

function dataform.run_assertions_job()
  local assertions = dataform.compiled_project_table.assertions
  local target_assertions = {}

  for _, assertion in pairs(assertions) do
    if assertion.fileName == get_dataform_definitions_file_path() then
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

local function get_all_models()
  local tables = dataform.compiled_project_table.tables or {}
  local operations = dataform.compiled_project_table.operations or {}
  local declarations = dataform.compiled_project_table.declarations or {}
  local all_models = vim.fn.extend(tables, operations)

  return vim.fn.extend(all_models, declarations)
end

local function find_model_by_file_path(all_models, target_file_path)
  for _, model in pairs(all_models) do
    if model.fileName == target_file_path then
      return model
    end
  end
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

function dataform.find_model_dependents()
  local all_models = get_all_models()
  local target_file_path = get_dataform_definitions_file_path()
  local target_model = find_model_by_file_path(all_models, target_file_path)
  local target_paths = {}

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
  end
end

function dataform.get_sqlx_blocks()
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

return dataform
