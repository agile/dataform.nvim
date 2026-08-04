local M = {}
local state = require("dataform.state")
local parser = require("dataform.parser")
local config = require("dataform.config")
local actions = require("dataform.actions")
local diagnostics = require("dataform.diagnostics")
local utils = require("dataform.utils")

local function find_symbol_location()
  local context = parser.get_context_at_cursor()
  local word = context.word
  local lines = context.lines

  if word == "" then return nil end

  -- 1. Check for CTE navigation (SQL files only or SQL blocks)
  local cte_pattern = "WITH%s+" .. word .. "%s+AS%s*%("
  local cte_pattern_comma = ",%s*" .. word .. "%s+AS%s*%("
  for i, line in ipairs(lines) do
    if line:find(cte_pattern) or line:find(cte_pattern_comma) then
      return {
        uri = "file://" .. vim.api.nvim_buf_get_name(0),
        range = {
          start = { line = i - 1, character = 0 },
          ["end"] = { line = i - 1, character = 0 }
        }
      }
    end
  end

  -- 2. Table navigation
  if context.type == "table" then
    local all_models = parser.get_all_models()
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (node.target.schema == context.schema or not context.schema) then
        return {
          uri = "file://" .. vim.fn.fnamemodify(node.fileName, ":p"),
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 0 }
          }
        }
      end
    end
  end

  -- 3. Variable navigation
  if context.type == "variable" then
    local var_path = context.var_name
    local settings_file = "workflow_settings.yaml"
    if vim.fn.filereadable(settings_file) == 1 then
      local abs_path = vim.fn.fnamemodify(settings_file, ":p")
      local f = io.open(settings_file, "r")
      if f then
        local i = 0
        for line in f:lines() do
          if line:find("^" .. var_path .. ":") or line:find(" " .. var_path .. ":") then
            f:close()
            return {
              uri = "file://" .. abs_path,
              range = {
                start = { line = i, character = 0 },
                ["end"] = { line = i, character = 0 }
              }
            }
          end
          i = i + 1
        end
        f:close()
      end
    end
  end

  -- 4. JS module navigation (Module navigation like module.func)
  if word:find("%.") or context.type == "function" or context.type == "js_module" then
    local parts = vim.split(word, "%.")
    local js_module = parts[1]
    local var_name = parts[#parts]

    -- Detect project root
    local root_markers = { "dataform.json", "workflow_settings.yaml", ".git" }
    local root_file = vim.fs.find(root_markers, { upward = true, path = vim.api.nvim_buf_get_name(0) })[1]
    local root = root_file and vim.fn.fnamemodify(root_file, ":h") or vim.fn.getcwd()

    local js_path = root .. "/includes/" .. js_module .. ".js"
    local ts_path = root .. "/includes/" .. js_module .. ".ts"
    local includes_file = vim.fn.filereadable(ts_path) == 1 and ts_path or js_path

    if vim.fn.filereadable(includes_file) == 1 then
      local f = io.open(includes_file, "r")
      if f then
        local content = f:read("*all")
        f:close()

        local sub_patterns = {
          "function%s+" .. var_name .. "%s*%(",
          "export%s+function%s+" .. var_name .. "%s*%(",
          "const%s+" .. var_name .. "%s*=%s*%(.-%)%s*=>",
          "export%s+const%s+" .. var_name .. "%s*=%s*%(.-%)%s*=>",
          "const%s+" .. var_name .. "%s*=%s*function",
          var_name .. "%s*[:=]%s*function",
          var_name .. "%s*[:=]%s*['\"].-['\"]",
          "const%s+" .. var_name .. "%s*=%s*['\"].-['\"]",
          "export%s+const%s+" .. var_name .. "%s*=%s*['\"].-['\"]",
          var_name .. "%s*[:=]%s*%b{}",
        }

        for _, pattern in ipairs(sub_patterns) do
          local s = content:find(pattern)
          if s then
            local line_num = 0
            local before = content:sub(1, s)
            for _ in before:gmatch("\n") do
              line_num = line_num + 1
            end

            return {
              uri = "file://" .. vim.fn.fnamemodify(includes_file, ":p"),
              range = {
                start = { line = line_num, character = 0 },
                ["end"] = { line = line_num, character = 0 }
              }
            }
          end
        end
      end
    end
  end

  -- 5. Search for local JS definition
  local blocks = parser.get_sqlx_blocks()
  if blocks.js.exists then
    local var_patterns = {
      "const%s+" .. word .. "%s*=",
      "let%s+" .. word .. "%s*=",
      "var%s+" .. word .. "%s*=",
      "function%s+" .. word .. "%s*%(",
      word .. "%s*[:=]%s*function"
    }
    for i = blocks.js.start_line, blocks.js.end_line do
      local line = lines[i]
      if line then
        for _, pattern in ipairs(var_patterns) do
          if line:find(pattern) then
            return {
              uri = "file://" .. vim.api.nvim_buf_get_name(0),
              range = {
                start = { line = i - 1, character = 0 },
                ["end"] = { line = i - 1, character = 0 }
              }
            }
          end
        end
      end
    end
  end

  return nil
end

--- Get the LSP client configuration.
---@param user_lsp_opts table?
---@return table LSP configuration
function M.get_lsp_config(user_lsp_opts)
  local lsp_opts = user_lsp_opts or {}

  local lsp_config = {
    name = "dataform",
    cmd = function(dispatchers)
      local function notify(method, params)
        utils.log("LSP Notify: " .. method)
      end
      local function request(method, params, callback)
        utils.log("LSP Request: " .. method)
        if method == "initialize" then
          callback(nil, {
            capabilities = {
              textDocumentSync = 1,
              hoverProvider = true,
              definitionProvider = true,
              referencesProvider = true,
              renameProvider = true,
              documentSymbolProvider = true,
              documentFormattingProvider = true,
              codeActionProvider = true,
              completionProvider = {
                triggerCharacters = { ".", "'", '"' },
                resolveProvider = false,
              },
              executeCommandProvider = {
                commands = {
                  "dataform.create_declaration",
                  "dataform.add_column_description",
                  "dataform.show_tag_dependency_tree",
                  "dataform.compile",
                  "dataform.preview",
                  "dataform.run_action",
                  "dataform.show_tree",
                }
              }
            }
          })
        elseif method == "initialized" then
          callback(nil, {})
        elseif method == "textDocument/codeAction" then
          local code_actions = actions.get_code_actions()
          callback(nil, code_actions)
        elseif method == "textDocument/completion" then
          local comp_utils = require('dataform.completion.utils')
          local line = vim.api.nvim_get_current_line()
          local col = params.position.character
          local text_before = line:sub(1, col)
          local word = text_before:match("([%w_%.]+)$") or ""

          local items = {}
          if comp_utils.is_sqlx_js_string_syntax() then
            items = comp_utils.action_names()
          elseif comp_utils.is_sqlx_js_syntax() then
            items = comp_utils.js_symbols(word)
          else
            items = comp_utils.columns()
          end
          callback(nil, items)
        elseif method == "textDocument/hover" then
          local context = parser.get_context_at_cursor()
          local all_models = parser.get_all_models()
          local hover_content = {}

          if context.type == "table" then
            for _, node in pairs(all_models) do
              if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
                local target = node.target
                local canonical = node.canonicalTarget

                table.insert(hover_content, "# " .. target.database .. "." .. target.schema .. "." .. target.name)
                table.insert(hover_content, "---")
                table.insert(hover_content, "**Type:** " .. (node.type or "table"))

                if canonical and (canonical.schema ~= target.schema or canonical.database ~= target.database or canonical.name ~= target.name) then
                  table.insert(hover_content, "**Canonical Target:** `" .. (canonical.database or "") .. "." .. (canonical.schema or "") .. "." .. (canonical.name or "") .. "`")
                end

                table.insert(hover_content, "**File:** " .. node.fileName)
                if node.actionDescriptor and node.actionDescriptor.description then
                   table.insert(hover_content, "")
                   table.insert(hover_content, node.actionDescriptor.description)
                end
                break
              end
            end
          elseif context.type == "variable" then
            local vars = state.compiled_project_table.projectConfig and state.compiled_project_table.projectConfig.vars
            if vars and vars[context.var_name] then
              table.insert(hover_content, "# Project Variable: " .. context.var_name)
              table.insert(hover_content, "---")
              table.insert(hover_content, "**Value:** `" .. tostring(vars[context.var_name]) .. "`")
            end
          elseif context.type == "function" or context.type == "js_module" then
            local sig = require("dataform.signatures").get_signature_for_name(context.word)
            if sig then
              table.insert(hover_content, "# JS Symbol: " .. context.word)
              table.insert(hover_content, "---")
              if context.type == "function" then
                table.insert(hover_content, "**Signature:** `" .. context.word .. "(" .. table.concat(sig.params, ", ") .. ")`")
              end
              if sig.doc and sig.doc ~= "" then
                if context.type == "function" then table.insert(hover_content, "") end
                table.insert(hover_content, sig.doc)
              end
            end
          end

          if #hover_content > 0 then
            callback(nil, { contents = { kind = "markdown", value = table.concat(hover_content, "\n") } })
          else
            callback(nil, nil)
          end
        elseif method == "textDocument/definition" then
          local location = find_symbol_location()
          callback(nil, location)
          return true, 1
        elseif method == "textDocument/references" then
          local context = parser.get_context_at_cursor()
          if context.word == "" then callback(nil, nil) return true, 1 end

          local search_patterns = {}
          local escaped_word = context.word:gsub("%.", "\\.")

          if context.type == "variable" then
            local escaped_var = context.var_name:gsub("%.", "\\.")
            table.insert(search_patterns, "dataform\\.projectConfig\\.vars\\." .. escaped_var)
            table.insert(search_patterns, "^" .. escaped_var .. ":")
          elseif context.type == "table" then
            local escaped_table = context.table_name:gsub("%.", "\\.")
            table.insert(search_patterns, "ref%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
            table.insert(search_patterns, "resolve%s*%(%s*([\"'][^\"']+[\"']%s*,%s*)?[\"']" .. escaped_table .. "[\"']%s*%)")
            table.insert(search_patterns, "dependencies%s*:%s*%[[^%]]*[\"']" .. escaped_table .. "[\"'][^%]]*%]")
            table.insert(search_patterns, 'name%s*:%s*["\']' .. escaped_table .. '["\']')
            if context.schema then
               local escaped_schema = context.schema:gsub("%.", "\\.")
               table.insert(search_patterns, "ref%s*%(%s*[\"']" .. escaped_schema .. "[\"']%s*,%s*[\"']" .. escaped_table .. "[\"']%s*%)")
            end
          elseif context.type == "function" or context.type == "js_module" then
            table.insert(search_patterns, escaped_word .. "%s*%(")
            table.insert(search_patterns, "function%s+" .. escaped_word)
            table.insert(search_patterns, escaped_word .. "%s*[:=]%s*function")
            table.insert(search_patterns, "module%.exports%s*=%s*{[^}]*" .. escaped_word)
          else
            table.insert(search_patterns, escaped_word)
          end

          local combined_pattern = table.concat(search_patterns, "|")
          local cmd = string.format("grep -rnE %s . --include='*.sqlx' --include='*.js' --include='*.ts' --include='workflow_settings.yaml' --include='*.yaml' --include='*.json' 2>/dev/null",
            vim.fn.shellescape(combined_pattern))

          utils.system_async(cmd, {
            quiet = true,
            callback = function(code, stdout, stderr)
              local locations = {}
              for line in stdout:gmatch("[^\r\n]+") do
                local file, lnum, text = line:match("([^:]+):(%d+):(.*)")
                if file and lnum then
                  table.insert(locations, {
                    uri = "file://" .. vim.fn.fnamemodify(file, ":p"),
                    range = {
                      start = { line = tonumber(lnum) - 1, character = 0 },
                      ["end"] = { line = tonumber(lnum) - 1, character = 100 }
                    }
                  })
                end
              end
              callback(nil, locations)
            end
          })
          return true, 1
        elseif method == "textDocument/documentSymbol" then
          local blocks = parser.get_sqlx_blocks()
          local symbols = {}
          if blocks.config.exists then
            table.insert(symbols, {
              name = "config", kind = 12,
              range = { start = { line = blocks.config.start_line - 1, character = 0 }, ["end"] = { line = blocks.config.end_line - 1, character = 0 } },
              selectionRange = { start = { line = blocks.config.start_line - 1, character = 0 }, ["end"] = { line = blocks.config.end_line - 1, character = 0 } }
            })
          end
          if blocks.js.exists then
            table.insert(symbols, {
              name = "js", kind = 12,
              range = { start = { line = blocks.js.start_line - 1, character = 0 }, ["end"] = { line = blocks.js.end_line - 1, character = 0 } },
              selectionRange = { start = { line = blocks.js.start_line - 1, character = 0 }, ["end"] = { line = blocks.js.end_line - 1, character = 0 } }
            })
          end
          if blocks.sql.exists then
            table.insert(symbols, {
              name = "sql", kind = 12,
              range = { start = { line = blocks.sql.start_line - 1, character = 0 }, ["end"] = { line = blocks.sql.end_line - 1, character = 0 } },
              selectionRange = { start = { line = blocks.sql.start_line - 1, character = 0 }, ["end"] = { line = blocks.sql.end_line - 1, character = 0 } }
            })
          end
          callback(nil, symbols)
        elseif method == "textDocument/rename" then
          local context = parser.get_context_at_cursor()
          if context.word == "" or context.type ~= "table" then
            callback(nil, nil)
            return true, 1
          end

          actions.get_rename_edits(context.table_name, params.newName, function(workspace_edit)
            callback(nil, workspace_edit)
          end)
          return true, 1
        elseif method == "textDocument/formatting" then
          local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
          local blocks = parser.get_sqlx_blocks()
          if not blocks.sql.exists then callback(nil, nil) return true, 1 end
          local lines = vim.api.nvim_buf_get_lines(bufnr, blocks.sql.start_line - 1, blocks.sql.end_line, false)
          local tmp_sql = os.tmpname() .. ".sql"
          local f = io.open(tmp_sql, "w")
          if f then
            f:write(table.concat(lines, "\n"))
            f:close()
            local opt_str = table.concat(config.options.formatter_options or {}, " ")
            local cmd = string.format("%s %s %s", config.options.formatter_bin, opt_str, tmp_sql)
            utils.system_async(cmd, {
              quiet = true,
              callback = function(code, stdout, stderr)
                os.remove(tmp_sql)
                if code == 0 then
                  callback(nil, { {
                    range = {
                      start = { line = blocks.sql.start_line - 1, character = 0 },
                      ["end"] = { line = blocks.sql.end_line - 1, character = 1000 }
                    },
                    newText = stdout
                  } })
                else
                  callback(nil, nil)
                end
              end
            })
          else
            callback(nil, nil)
          end
          return true, 1
        elseif method == "workspace/executeCommand" then
          if params.command == "dataform.create_declaration" then actions.create_declaration(unpack(params.arguments))
          elseif params.command == "dataform.add_column_description" then actions.add_column_description(unpack(params.arguments))
          elseif params.command == "dataform.fix_semicolon" then actions.fix_semicolon(unpack(params.arguments))
          elseif params.command == "dataform.add_default_config" then actions.add_default_config(unpack(params.arguments))
          elseif params.command == "dataform.show_tag_dependency_tree" then actions.show_tag_dependency_tree(unpack(params.arguments))
          elseif params.command == "dataform.compile" then actions.compile()
          elseif params.command == "dataform.preview" then actions.get_compiled_sql_job()
          elseif params.command == "dataform.run_action" then actions.run_action_job()
          elseif params.command == "dataform.show_tree" then actions.show_dependency_tree()
          end
          callback(nil, {})
        else callback(nil, nil) end
        return true, 1
      end
      return { request = request, notify = notify, is_closing = function() return false end, terminate = function() end }
    end,
    root_dir = vim.fn.getcwd(),
  }

  return vim.tbl_deep_extend("force", lsp_config, lsp_opts)
end

--- Register the Dataform LSP source.
---@param lsp_opts table?
---@return integer|nil client_id
function M.register_lsp_source(lsp_opts)
  if vim.lsp.config then
    local lsp_config = M.get_lsp_config(lsp_opts)
    lsp_config.filetypes = lsp_config.filetypes or { "sqlx" }
    lsp_config.root_markers = lsp_config.root_markers or { "dataform.json", "workflow_settings.yaml", ".git" }
    vim.lsp.config("dataform", lsp_config)
  end

  if #vim.api.nvim_list_uis() == 0 then return end

  if state.lsp_client_id and vim.lsp.get_client_by_id(state.lsp_client_id) then
    return state.lsp_client_id
  end

  local lsp_config = M.get_lsp_config(lsp_opts)
  local client_id = vim.lsp.start(lsp_config)
  state.lsp_client_id = client_id

  return client_id
end

--- Go to the definition/reference of the symbol under the cursor.
function M.go_to_ref()
  local location = find_symbol_location()
  if location then
    local path = location.uri:gsub("^file://", "")
    utils.open_file(path)
    vim.api.nvim_win_set_cursor(0, { location.range.start.line + 1, location.range.start.character })
  else
    utils.notify("No definition found.", vim.log.levels.WARN)
  end
end

--- Show hover information for the symbol under the cursor.
function M.hover()
  local context = parser.get_context_at_cursor()
  local word = context.word
  if word == "" then return end

  local hover_content = {}

  if context.type == "table" then
    local all_models = parser.get_all_models()
    local found = false
    for _, node in pairs(all_models) do
      if node.target.name == context.table_name and (not context.schema or node.target.schema == context.schema) then
        local target = node.target
        local canonical = node.canonicalTarget

        table.insert(hover_content, "# " .. target.database .. "." .. target.schema .. "." .. target.name)
        table.insert(hover_content, "---")
        table.insert(hover_content, "**Type:** " .. (node.type or "table"))

        if canonical and (canonical.schema ~= target.schema or canonical.database ~= target.database or canonical.name ~= target.name) then
          table.insert(hover_content, "**Canonical Target:** `" .. (canonical.database or "") .. "." .. (canonical.schema or "") .. "." .. (canonical.name or "") .. "`")
        end

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

  if #hover_content == 0 then
    local all_models = parser.get_all_models()
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

  if #hover_content == 0 and context.type == "variable" then
    local var_path = context.var_name
    local vars = state.compiled_project_table.projectConfig and state.compiled_project_table.projectConfig.vars
    if vars and vars[var_path] then
      table.insert(hover_content, "# Project Variable: " .. var_path)
      table.insert(hover_content, "---")
      table.insert(hover_content, "**Value:** `" .. tostring(vars[var_path]) .. "`")
      table.insert(hover_content, "**Defined in:** `workflow_settings.yaml`")
    end
  end

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

  if #hover_content == 0 and context.type == "tag" then
    table.insert(hover_content, "# Tag: " .. context.tag_name)
    table.insert(hover_content, "---")
    table.insert(hover_content, "This is a Dataform tag. Use `:DataformCodeAction` to view the dependency tree for all models with this tag.")
  end

  if #hover_content > 0 then
    vim.lsp.util.open_floating_preview(hover_content, "markdown", {
      border = "rounded",
      focusable = true,
      focus_id = "dataform_hover",
    })
  end
end

return M
