local M = {}
local state = require("dataform.state")
local parser = require("dataform.parser")
local config = require("dataform.config")
local diagnostics = require("dataform.diagnostics")
local utils = require("dataform.utils")

--- Format the SQL block in the current buffer.
function M.format()
  local bufnr = vim.api.nvim_get_current_buf()
  local blocks = parser.get_sqlx_blocks()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if not blocks.sql.exists or not config.options.formatter_bin or config.options.formatter_bin == "" then
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

  local options = table.concat(config.options.formatter_options or {}, " ")
  local cmd = string.format("%s %s %s > /dev/null 2>&1",
    config.options.formatter_bin, options, tmp_sql)

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
    utils.notify("SQL block formatted with " .. config.options.formatter_bin .. ".", vim.log.levels.INFO)
  else
    os.remove(tmp_sql)
  end
end

--- Show an interactive dependency tree for the specified models or current buffer.
---@param models table[]?
function M.show_dependency_tree(models)
  utils.log("show_dependency_tree: triggered")
  local all_models = parser.get_all_models()
  local target_models = {}

  if models then
    target_models = models
  else
    local target_file_path = utils.get_dataform_definitions_file_path()
    local target_model = parser.find_model_by_file_path(all_models, target_file_path)
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
  local highlights = {} -- { { line, col_start, col_end, group }, ... }
  local current_file = utils.get_current_file_path()

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
    local line_text = prefix .. node_name .. " (" .. (model.type or "table") .. ")"
    table.insert(tree_lines, line_text)
    local line_idx = #tree_lines
    line_to_file[line_idx] = model.fileName

    -- Highlight root nodes
    if indent == "" then
      table.insert(highlights, { line = line_idx, start_col = #prefix, end_col = #prefix + #node_name, group = "Title" })
    end

    -- Highlight current file
    if model.fileName == current_file then
      table.insert(highlights, { line = line_idx, start_col = #prefix, end_col = #prefix + #node_name, group = "Keyword" })
    end

    if seen[node_name] then
      tree_lines[line_idx] = tree_lines[line_idx] .. " (recursive)"
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
        table.insert(highlights, { line = #tree_lines, start_col = #dep_prefix, end_col = #dep_prefix + #dep_target.name, group = "Comment" })
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

  local _, bufnr = utils.open_interactive_buffer(table.concat(tree_lines, "\n"), "dataform_tree", "Dataform Dependencies", keymaps)

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dataform_tree_hi")
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns, h.group, h.line - 1, h.start_col, h.end_col)
  end

  -- Add cursorline highlighting
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      -- Re-apply static highlights
      for _, h in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(bufnr, ns, h.group, h.line - 1, h.start_col, h.end_col)
      end
      -- Current line bold highlight
      local curr_line = vim.api.nvim_win_get_cursor(0)[1]
      if line_to_file[curr_line] then
         vim.api.nvim_buf_add_highlight(bufnr, ns, "CursorLineNr", curr_line - 1, 0, -1)
      end
    end
  })
end

--- Show dependency tree for all models matching a tag.
---@param tag string
function M.show_tag_dependency_tree(tag)
  if not tag or tag == "" then return end
  local all_models = parser.get_all_models()
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
    M.show_dependency_tree(filtered)
  else
    utils.notify("No models found with tag: " .. tag, vim.log.levels.WARN)
  end
end

--- Estimate BigQuery cost for all models matching a tag.
---@param tag string
function M.estimate_tag_cost(tag)
  if not tag or tag == "" then
    utils.notify("Please provide a tag name.", vim.log.levels.WARN)
    return
  end

  local all_models = parser.get_all_models()
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
  local completed = 0
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
      local bq_args = { "query", "--dry_run", query }
      utils.execute_job("bq", bq_args, {
        quiet = true,
        callback = function(code, stdout, stderr)
          completed = completed + 1
          local output = stdout .. stderr
          if code == 0 or output:find("process") then
            local bytes = output:match("process%s+(%d+)%s+bytes")
            if bytes then
              total_bytes = total_bytes + tonumber(bytes)
            end
          else
            table.insert(errors, target_name)
          end

          if completed == #filtered then
            local stats = utils.parse_dry_run_stats("process " .. total_bytes .. " bytes")
            local msg = "Tag '" .. tag .. "' Cost Estimation:\n" .. stats
            if #errors > 0 then
              msg = msg .. "\nErrors encountered in " .. #errors .. " models: " .. table.concat(errors, ", ")
            end
            utils.notify(msg, vim.log.levels.INFO)
          end
        end
      })
    else
      completed = completed + 1
      if completed == #filtered then
        local stats = utils.parse_dry_run_stats("process " .. total_bytes .. " bytes")
        utils.notify("Tag '" .. tag .. "' Cost Estimation:\n" .. stats, vim.log.levels.INFO)
      end
    end
  end
end

--- Show dry-run cost and bytes as virtual text in the current buffer.
function M.show_dry_run_virtual_text()
  local all_models = parser.get_all_models()
  local target_file_path = utils.get_dataform_definitions_file_path()
  local model = parser.find_model_by_file_path(all_models, target_file_path)

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

  local bq_command = "bq"
  local bq_args = { "query", "--dry_run", query }

  if state.current_dry_run_job then
    state.current_dry_run_job:shutdown()
    state.current_dry_run_job = nil
  end

  state.current_dry_run_job = utils.execute_job(bq_command, bq_args, {
    quiet = true,
    callback = function(code, stdout, stderr)
      state.current_dry_run_job = nil
      local output = stdout .. stderr
      if code == 0 or output:find("process") then
        local stats = utils.parse_dry_run_stats(output)
        if stats then
          local bufnr = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_clear_namespace(bufnr, diagnostics.vt_ns, 0, -1)
          vim.api.nvim_buf_set_extmark(bufnr, diagnostics.vt_ns, 0, 0, {
            virt_text = { { "󱓞 " .. stats, "DiagnosticInfo" } },
            virt_text_pos = "right_align",
          })
        end
      end
    end
  })
end

--- Compile the Dataform project asynchronously.
---@param on_success function? Callback on successful compilation.
function M.compile(on_success)
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = utils.get_current_file_path()
  local new_hash = parser.get_structural_hash(bufnr)

  if state.structural_hashes[file_path] == new_hash then
    utils.log("Skipping dataform compile: structure hasn't changed.")
    if on_success then on_success() end
    return
  end

  if state.current_compile_job then
    state.current_compile_job:shutdown()
    state.current_compile_job = nil
  end

  local args = parser.get_df_args("compile", { "--json" })
  local notification = utils.notify("Dataform: Compiling project...", vim.log.levels.INFO)

  state.current_compile_job = utils.execute_job(config.options.dataform_bin, args, {
    json = true,
    quiet = true,
    callback = function(code, stdout, stderr)
      state.current_compile_job = nil
      local ok, decoded = pcall(vim.fn.json_decode, stdout)
      if ok then
        state.compiled_project_table = decoded
        diagnostics.set_diagnostics(decoded)
        state.structural_hashes[file_path] = new_hash

        utils.log({
          event = "compilation_summary",
          tables = #(decoded.tables or {}),
          declarations = #(decoded.declarations or {}),
          operations = #(decoded.operations or {}),
          assertions = #(decoded.assertions or {}),
          graph_errors = #(decoded.graphErrors and decoded.graphErrors.compilationErrors or {})
        })

        if code == 0 then
          utils.notify("Dataform: Compiled successfully.", vim.log.levels.INFO, { replace = notification })
          if on_success then on_success() end
        else
          utils.notify("Dataform: Compiled with errors (see diagnostics).", vim.log.levels.WARN, { replace = notification })
        end
      else
        utils.notify("Dataform: Compilation failed (invalid JSON).", vim.log.levels.ERROR, { replace = notification })
        utils.log("Async compile failed to return valid JSON.")
      end
    end
  })
end

--- Preview the compiled SQL for the current buffer.
---@param incremental boolean? Whether to use incremental query if available.
function M.get_compiled_sql_job(incremental)
  local all_models = parser.get_all_models()
  local target_file_path = utils.get_dataform_definitions_file_path()
  local table_node = parser.find_model_by_file_path(all_models, target_file_path)

  if table_node then
    local preOpsKey = incremental and "incrementalPreOps" or "preOps"
    local postOpsKey = incremental and "incrementalPostOps" or "postOps"
    local queryKey = incremental and "incrementalQuery" or "query"

    local preOps = type(table_node[preOpsKey]) == "table" and table_node[preOpsKey][1] or ""
    local postOps = type(table_node[postOpsKey]) == "table" and table_node[postOpsKey][1] or ""

    local preOpsClean = preOps:gsub("%s+$", "")
    if preOpsClean:sub(-1) ~= ";" and preOps ~= "" then preOps = preOps .. ";" end

    local composite_query = preOps .. table_node[queryKey] .. ";\n" .. postOps
    local bq_command = "bq"
    local bq_args = { "query", "--dry_run", composite_query }

    local notification = utils.notify("Dataform: Running dry-run for preview...", vim.log.levels.INFO)

    utils.execute_job(bq_command, bq_args, {
      quiet = true,
      callback = function(code, stdout, stderr)
        local output = stdout .. stderr
        local stats = utils.parse_dry_run_stats(output)
        local header = ""
        if stats then
          header = "-- " .. stats .. "\n\n"
          utils.notify("Dataform: " .. stats, vim.log.levels.INFO, { replace = notification })
        else
          header = "-- Dry run failed or stats unavailable\n-- " .. output:gsub("\n", "\n-- ") .. "\n\n"
          utils.notify("Dataform: Dry run failed.", vim.log.levels.WARN, { replace = notification })
        end

        local final_content = header .. composite_query
        if config.options.preview_style == "float" then
          utils.open_floating_window(final_content, "sql", "Dataform Preview")
        else
          utils.open_buffer_with_content(final_content, "sql", "Dataform Preview")
        end
      end
    })
  end
end

--- Run the entire Dataform project.
function M.run_all()
  local args = parser.get_df_args("run")
  local notification = utils.notify("Dataform: Running entire project...", vim.log.levels.INFO)
  utils.system_async({ config.options.dataform_bin, unpack(args) }, {
    callback = function(code, stdout, stderr)
      if code == 0 then
        utils.notify("Dataform: Project run successfully.", vim.log.levels.INFO, { replace = notification })
      else
        utils.notify("Dataform: Project run failed.", vim.log.levels.ERROR, { replace = notification })
        utils.notify("Error: Dataform run failed. \n\n" .. stderr, vim.log.levels.ERROR)
      end
    end
  })
end

--- Run Dataform actions matching a tag.
---@param args string Tag name
function M.run_tag(args)
  local tags = args or ""
  local df_args = parser.get_df_args("run", { "--tags=" .. tags })
  local notification = utils.notify("Dataform: Running tag " .. tags .. "...", vim.log.levels.INFO)
  utils.system_async({ config.options.dataform_bin, unpack(df_args) }, {
    callback = function(code, stdout, stderr)
      if code == 0 then
        utils.notify("Dataform: Tag " .. tags .. " run successfully.", vim.log.levels.INFO, { replace = notification })
      else
        utils.notify("Dataform: Tag " .. tags .. " run failed.", vim.log.levels.ERROR, { replace = notification })
        utils.notify("Error: Dataform tag run failed. \n\n" .. stderr, vim.log.levels.ERROR)
      end
    end
  })
end

--- Run the Dataform action defined in the current buffer.
---@param full_refresh boolean?
function M.run_action_job(full_refresh)
  full_refresh = full_refresh or false
  local all_models = parser.get_all_models()
  local target_file_path = utils.get_dataform_definitions_file_path()
  local table_node = parser.find_model_by_file_path(all_models, target_file_path)

  if table_node then
    local action = table_node.target.database .. "." .. table_node.target.schema .. "." .. table_node.target.name
    local df_args = parser.get_df_args("run", { "--full-refresh=" .. tostring(full_refresh), "--actions=" .. action })

    local notification = utils.notify("Dataform: Running action " .. action .. "...", vim.log.levels.INFO)

    utils.system_async({ config.options.dataform_bin, unpack(df_args) }, {
      callback = function(code, stdout, stderr)
        if code == 0 then
          utils.notify("Dataform: Action " .. action .. " executed successfully.", vim.log.levels.INFO, { replace = notification })
        else
          utils.notify("Dataform: Action " .. action .. " failed.", vim.log.levels.ERROR, { replace = notification })
          -- We still show detailed error separately if it failed
          utils.notify("Error: Dataform run failed. \n\n" .. stderr, vim.log.levels.ERROR)
        end
      end
    })
  end
end

--- Run assertions for the current model.
function M.run_assertions_job()
  local assertions = state.compiled_project_table.assertions or {}
  local target_assertions = {}
  local target_file_path = utils.get_dataform_definitions_file_path()
  if not target_file_path then return end
  local target_abs = vim.fn.fnamemodify(target_file_path, ":p")

  for _, assertion in pairs(assertions) do
    if assertion.fileName and vim.fn.fnamemodify(assertion.fileName, ":p") == target_abs then
      local action = assertion.target.database .. "." .. assertion.target.schema .. "." .. assertion.target.name
      table.insert(target_assertions, action)
    end
  end

  if vim.tbl_isempty(target_assertions) then
    return utils.notify("Error: There is no assertions for this file.", vim.log.levels.ERROR)
  end

  local actions_str = table.concat(target_assertions, ",")
  local df_args = parser.get_df_args("run", { "--actions=" .. actions_str })

  local notification = utils.notify("Dataform: Running assertions...", vim.log.levels.INFO)

  utils.system_async({ config.options.dataform_bin, unpack(df_args) }, {
    callback = function(code, stdout, stderr)
      if code == 0 then
        utils.notify("Dataform: Assertions executed successfully.", vim.log.levels.INFO, { replace = notification })
      else
        utils.notify("Dataform: Assertions failed.", vim.log.levels.ERROR, { replace = notification })
        utils.notify("Error: Dataform assertions failed. \n\n" .. stderr, vim.log.levels.ERROR)
      end
    end
  })
end


--- Find and show models that depend on the current model.
function M.find_model_dependents()
  local all_models = parser.get_all_models()
  local target_file_path = utils.get_dataform_definitions_file_path()
  local target_model = parser.find_model_by_file_path(all_models, target_file_path)
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

--- Find and show models that the current model depends on.
function M.find_model_dependencies()
  local all_models = parser.get_all_models()
  local target_file_path = utils.get_dataform_definitions_file_path()
  local target_model = parser.find_model_by_file_path(all_models, target_file_path)
  local target_paths = {}

  if not target_model then
    return utils.custom_picker("Model Dependencies", target_paths)
  end

  local dependencies = target_model.dependencyTargets
  if dependencies then
    for _, dependency in pairs(dependencies) do
      local schema = dependency.schema
      local name = dependency.name
      local target_path = parser.find_file_name_by_schema_name(all_models, schema, name)
      table.insert(target_paths, target_path)
    end
  end

  return utils.custom_picker("Model Dependencies", target_paths)
end

--- Helper to trigger compilation on save.
function M.compile_on_save()
  if config.options.compile_on_save then
    M.compile(function()
       M.show_dry_run_virtual_text()
    end)
  end

  if config.options.lint_on_save then
    M.lint()
  end
end

--- Toggle the 'compile_on_save' setting.
function M.toggle_compile_on_save()
  config.options.compile_on_save = not config.options.compile_on_save
  local status = config.options.compile_on_save and "enabled" or "disabled"
  utils.notify("Dataform compile on save " .. status .. ".", vim.log.levels.INFO)
end

--- Helper to trigger formatting on save.
function M.format_on_save()
  if config.options.format_on_save then
    M.format()
  end
end

--- Toggle the 'format_on_save' setting.
function M.toggle_format_on_save()
  config.options.format_on_save = not config.options.format_on_save
  local status = config.options.format_on_save and "enabled" or "disabled"
  utils.notify("Dataform format on save " .. status .. ".", vim.log.levels.INFO)
end

--- Toggle the 'lint_on_save' setting.
function M.toggle_lint_on_save()
  config.options.lint_on_save = not config.options.lint_on_save
  local status = config.options.lint_on_save and "enabled" or "disabled"
  utils.notify("Dataform lint on save " .. status .. ".", vim.log.levels.INFO)
end

--- Lint the SQL block in the current buffer using the configured linter.
function M.lint()
  local bufnr = vim.api.nvim_get_current_buf()
  local blocks = parser.get_sqlx_blocks()
  if not blocks.sql.exists or not config.options.linter_bin or config.options.linter_bin == "" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, blocks.sql.start_line - 1, blocks.sql.end_line, false)
  local tmp_sql = os.tmpname() .. ".sql"
  local f = io.open(tmp_sql, "w")
  if not f then return end
  f:write(table.concat(lines, "\n"))
  f:close()

  local args = vim.deepcopy(config.options.linter_options or {})
  table.insert(args, tmp_sql)

  utils.execute_job(config.options.linter_bin, args, {
    json = true,
    quiet = true,
    callback = function(code, stdout, stderr)
      os.remove(tmp_sql)
      vim.diagnostic.reset(diagnostics.lint_ns, bufnr)

      local ok, decoded = pcall(vim.fn.json_decode, stdout)
      if not ok or type(decoded) ~= "table" then return end

      local lint_diagnostics = {}
      for _, file_report in ipairs(decoded) do
        if file_report.violations then
          for _, v in ipairs(file_report.violations) do
            table.insert(lint_diagnostics, {
              lnum = blocks.sql.start_line - 1 + (v.line_no - 1),
              col = v.line_pos - 1,
              severity = vim.diagnostic.severity.WARN,
              message = string.format("[%s] %s", v.code, v.description),
              source = config.options.linter_bin,
            })
          end
        end
      end

      if #lint_diagnostics > 0 then
        vim.diagnostic.set(diagnostics.lint_ns, bufnr, lint_diagnostics)
      end
    end
  })
end

--- Toggle the preview style between 'float' and 'vsplit'.
function M.toggle_preview_style()
  if config.options.preview_style == "float" then
    config.options.preview_style = "vsplit"
  else
    config.options.preview_style = "float"
  end
  utils.notify("Dataform preview style set to: " .. config.options.preview_style, vim.log.levels.INFO)
end

--- Toggle Tree-sitter integration for block parsing.
function M.toggle_treesitter()
  config.options.use_treesitter = not config.options.use_treesitter
  local status = config.options.use_treesitter and "enabled" or "disabled"
  utils.notify("Dataform Tree-sitter integration " .. status .. ".", vim.log.levels.INFO)
end

--- Toggle internal debug logging.
function M.toggle_logging()
  config.options.logging = not config.options.logging
  local status = config.options.logging and "enabled" or "disabled"
  utils.notify("Dataform logging " .. status .. ".", vim.log.levels.INFO)
end

--- Create a new Dataform declaration (.sqlx) for a missing reference.
---@param schema string?
---@param name string
function M.create_declaration(schema, name)
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

--- Fix a trailing semicolon error in a buffer.
---@param bufnr integer
---@param lnum integer 0-indexed line number
function M.fix_semicolon(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if line then
    local new_line = line:gsub(";%s*$", "")
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
    utils.notify("Removed trailing semicolon.", vim.log.levels.INFO)
  end
end

--- Add a default config block to a new SQLX file.
---@param bufnr integer
function M.add_default_config(bufnr)
  local blocks = parser.get_sqlx_blocks()
  if not blocks.config.exists then
    local content = [[config {
  type: "table",
  description: "New table."
}

]]
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, vim.split(content, "\n"))
    utils.notify("Added default config block.", vim.log.levels.INFO)
  end
end

--- Add a missing column description to the config block.
---@param col_name string
function M.add_column_description(col_name)
  local blocks = parser.get_sqlx_blocks()
  if not blocks.config.exists then
    utils.notify("No config block found to add column description.", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, blocks.config.start_line - 1, blocks.config.end_line, false)
  local config_content = table.concat(lines, "\n")

  local col_block_start = config_content:find("columns%s*:%s*{")

  if col_block_start then
    local insert_line = -1
    for i = blocks.config.start_line, blocks.config.end_line do
      local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if line:find("columns%s*:%s*{") then
        insert_line = i
        break
      end
    end

    if insert_line ~= -1 then
      local indent = vim.api.nvim_buf_get_lines(bufnr, insert_line - 1, insert_line, false)[1]:match("^%s*")
      vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, {
        string.format("%s  %s: \"Description for %s\",", indent, col_name, col_name)
      })
      utils.notify("Added column entry to config.", vim.log.levels.INFO)
    end
  else
    local insert_line = blocks.config.end_line - 1
    local indent = vim.api.nvim_buf_get_lines(bufnr, insert_line, insert_line + 1, false)[1]:match("^%s*") or "  "

    vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, {
      string.format("  columns: {"),
      string.format("    %s: \"Description for %s\"", col_name, col_name),
      string.format("  },")
    })
    utils.notify("Created columns block in config.", vim.log.levels.INFO)
  end
end

--- Get available code actions for the LSP client.
---@return table[] List of LSP code actions
function M.get_code_actions()
  local df = require('dataform')
  local context = df.get_context_at_cursor()
  local lsp_actions = {}
  local all_models = parser.get_all_models()
  local bufnr = vim.api.nvim_get_current_buf()

  local diags = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  for _, d in ipairs(diags) do
    if d.message:find("Actions may only include .* if they create a dataset") then
      table.insert(lsp_actions, {
        title = "Add default config block",
        kind = "quickfix",
        command = { command = "dataform.add_default_config", arguments = { bufnr } }
      })
    end
    if d.message:find("semi%-colon at the end of the query") or d.message:find("Unexpected ';'") then
      table.insert(lsp_actions, {
        title = "Remove trailing semicolon",
        kind = "quickfix",
        command = { command = "dataform.fix_semicolon", arguments = { bufnr, d.lnum } }
      })
    end
  end

  if context.type == "table" then
    local found = false
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
        found = true
        break
      end
    end

    if not found then
      table.insert(lsp_actions, {
        title = "Create declaration for '" .. context.table_name .. "'",
        kind = "quickfix",
        command = {
          command = "dataform.create_declaration",
          arguments = { context.schema, context.table_name }
        }
      })
    end
  end

  local is_known_column = false
  for _, node in pairs(all_models) do
    if node.actionDescriptor and node.actionDescriptor.columns then
      for _, col in ipairs(node.actionDescriptor.columns) do
        if col.path[#col.path] == context.word then
          is_known_column = true
          break
        end
      end
    end
  end

  if not is_known_column and context.word ~= "" and context.type == nil then
     table.insert(lsp_actions, {
       title = "Document column '" .. context.word .. "'",
       kind = "quickfix",
       command = {
         command = "dataform.add_column_description",
         arguments = { context.word }
       }
     })
  end

  if context.type == "tag" then
    table.insert(lsp_actions, {
      title = "Show dependency tree for tag '" .. context.tag_name .. "'",
      kind = "source",
      command = {
        command = "dataform.show_tag_dependency_tree",
        arguments = { context.tag_name }
      }
    })
  end

  table.insert(lsp_actions, {
    title = "Dataform: Compile Project",
    kind = "source",
    command = { command = "dataform.compile" }
  })
  table.insert(lsp_actions, {
    title = "Dataform: Preview SQL",
    kind = "source",
    command = { command = "dataform.preview" }
  })
  table.insert(lsp_actions, {
    title = "Dataform: Run Current Action",
    kind = "source",
    command = { command = "dataform.run_action" }
  })
  table.insert(lsp_actions, {
    title = "Dataform: Show Dependency Tree",
    kind = "source",
    command = { command = "dataform.show_tree" }
  })

  return lsp_actions
end

--- Show a selection UI for available code actions.
function M.code_action()
  local df = require('dataform')
  local context = df.get_context_at_cursor()
  local actions_list = {}

  if context.type == "table" then
    local all_models = parser.get_all_models()
    local found = false
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
        found = true
        break
      end
    end

    if not found then
      table.insert(actions_list, {
        title = "Create declaration for '" .. context.table_name .. "'",
        handler = function() M.create_declaration(context.schema, context.table_name) end
      })
    end
  end

  if context.type == "tag" then
    table.insert(actions_list, {
      title = "Show dependency tree for tag '" .. context.tag_name .. "'",
      handler = function() M.show_tag_dependency_tree(context.tag_name) end
    })
  end

  if #actions_list == 0 then
    utils.notify("No code actions available at cursor.", vim.log.levels.INFO)
    return
  end

  vim.ui.select(actions_list, {
    prompt = "Dataform Code Actions:",
    format_item = function(item) return item.title end,
  }, function(choice)
    if choice then
      choice.handler()
    end
  end)
end

--- Get a set of workspace edits for renaming a model.
---@param old_name string
---@param new_name string
---@param callback function
function M.get_rename_edits(old_name, new_name, callback)
  local search_patterns = {
    "ref%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. old_name:gsub("%.", "%.") .. "[\"']%s*%)",
    "resolve%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. old_name:gsub("%.", "%.") .. "[\"']%s*%)",
    "dependencies%s*:%s*%[[^%]]*[\"']" .. old_name:gsub("%.", "%.") .. "[\"'][^%]]*%]",
    'name%s*:%s*["\']' .. old_name:gsub("%.", "%.") .. '["\']'
  }

  local combined_pattern = table.concat(search_patterns, "|")
  local cmd = string.format("grep -rnE %s . --include='*.sqlx' --include='*.js' --include='*.ts' --include='workflow_settings.yaml' --include='*.yaml' --include='*.json' 2>/dev/null",
    vim.fn.shellescape(combined_pattern))

  utils.system_async(cmd, {
    quiet = true,
    callback = function(code, stdout, stderr)
      local changes = {}
      local documentChanges = {}

      for line in stdout:gmatch("[^\r\n]+") do
        local file, lnum, text = line:match("([^:]+):(%d+):(.*)")
        if file and lnum then
          local abs_path = vim.fn.fnamemodify(file, ":p")
          local uri = "file://" .. abs_path

          local s, e = text:find('["\']' .. old_name .. '["\']')
          if s then
            s = s + 1
            e = e - 1

            changes[uri] = changes[uri] or {}
            table.insert(changes[uri], {
              range = {
                start = { line = tonumber(lnum) - 1, character = s - 1 },
                ["end"] = { line = tonumber(lnum) - 1, character = e }
              },
              newText = new_name
            })
          end
        end
      end

      local all_models = parser.get_all_models()
      for _, model in pairs(all_models) do
        if model.target.name == old_name and model.fileName:find(old_name, 1, true) then
          local new_fileName = model.fileName:gsub(old_name, new_name)
          table.insert(documentChanges, {
            kind = "rename",
            oldUri = "file://" .. vim.fn.fnamemodify(model.fileName, ":p"),
            newUri = "file://" .. vim.fn.fnamemodify(new_fileName, ":p")
          })
        end
      end

      callback({
        changes = changes,
        documentChanges = #documentChanges > 0 and documentChanges or nil
      })
    end
  })
end

--- Find and show all references to the symbol under the cursor.
function M.find_references()
  local df = require('dataform')
  local context = df.get_context_at_cursor()
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
    table.insert(search_patterns, "ref%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
    table.insert(search_patterns, "resolve%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
    table.insert(search_patterns, "dependencies%s*:%s*%[[^%]]*[\"']" .. escaped_table .. "[\"'][^%]]*%]")
    table.insert(search_patterns, 'name%s*:%s*["\']' .. escaped_table .. '["\']')

    if context.schema then
       local escaped_schema = context.schema:gsub("%.", "\\.")
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
    table.insert(search_patterns, escaped_word)
    label = "symbol: " .. word
  end

  utils.notify("Finding references for " .. label .. "...", vim.log.levels.INFO)

  local combined_pattern = table.concat(search_patterns, "|")
  local cmd = string.format("grep -rnE %s . --include='*.sqlx' --include='*.js' --include='*.ts' --include='workflow_settings.yaml' --include='*.yaml' --include='*.json' 2>/dev/null",
    vim.fn.shellescape(combined_pattern))

  utils.system_async(cmd, {
    quiet = true,
    callback = function(code, stdout, stderr)
      local results = {}
      local seen = {}
      for line in stdout:gmatch("[^\r\n]+") do
        if not seen[line] then
          table.insert(results, line)
          seen[line] = true
        end
      end

      if #results == 0 then
        utils.notify("No references found for " .. label, vim.log.levels.INFO)
        return
      end

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
  })
end

return M
