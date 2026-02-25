local M = {}

function M.action_names()
  local state = require('dataform.state')
  local compiled = state.compiled_project_table or {}
  local tables = compiled.tables or {}
  local declarations = compiled.declarations or {}

  local names = {}
  local added = {}

  local function add_nodes(nodes)
    for _, node in ipairs(nodes) do
      local target = node.target or {}
      if target.name ~= nil and not added[target.name] then
        table.insert(
          names,
          {
            label = target.name,
            kind = 9, -- Module
            detail = node.fileName
          }
        )
        added[target.name] = true
      end
    end
  end

  add_nodes(tables)
  add_nodes(declarations)
  return names
end

function M.columns()
  local state = require('dataform.state')
  local compiled = state.compiled_project_table or {}
  local tables = compiled.tables or {}
  local declarations = compiled.declarations or {}

  local columns = {}
  local added = {}

  local function process_nodes(nodes)
    for _, node in ipairs(nodes) do
      if node.actionDescriptor and node.actionDescriptor.columns then
        for _, col in ipairs(node.actionDescriptor.columns) do
          local name = col.path[#col.path]
          if name and not added[name] then
            table.insert(columns, {
              label = name,
              kind = 5, -- Field
              detail = (node.target.schema or "") .. "." .. node.target.name,
              documentation = col.description or ""
            })
            added[name] = true
          end
        end
      end
    end
  end

  process_nodes(tables)
  process_nodes(declarations)
  return columns
end


function M.is_sqlx_js_string_syntax()
  local synID = vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1)
  local synGroupName = vim.fn.synIDattr(synID, "name")
  return synGroupName and (synGroupName == "sqlxJsString" or synGroupName == "sqlxSqlString")
end

function M.is_sqlx_js_syntax()
  local synID = vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1)
  local synGroupName = vim.fn.synIDattr(synID, "name")
  -- Check for JS block groups (they usually start with sqlxJs...)
  return synGroupName and (synGroupName:find("^sqlxJs") ~= nil or synGroupName == "sqlxSqlJsBlock")
end

function M.js_symbols(context_word)
  local symbols = {}
  local added = {}
  local prefix = ""

  if context_word and context_word:find("%.") then
    prefix = context_word:match("^(.-)%.*$")
  end

  -- 1. List files in includes/
  local includes_path = "includes"
  if vim.fn.isdirectory(includes_path) == 1 then
    local files = vim.fn.globpath(includes_path, "*", false, true)
    for _, file in ipairs(files) do
      if file:sub(-3) == ".js" or file:sub(-3) == ".ts" then
        local module_name = vim.fn.fnamemodify(file, ":t:r")

        -- If no prefix, show the module name itself
        if prefix == "" then
          if not added[module_name] then
            table.insert(symbols, {
              label = module_name,
              kind = 9, -- Module
              detail = "Module in includes/"
            })
            added[module_name] = true
          end
        elseif prefix == module_name then
          -- We are completing inside this module
          local f = io.open(file, "r")
          if f then
            local content = f:read("*all")
            f:close()

            -- Find top-level definitions and exports (including TS 'export' keyword)
            for name in content:gmatch("function%s+([%w_]+)%s*%(") do
              if not added[name] then
                table.insert(symbols, { label = name, kind = 3, detail = "Function in " .. module_name })
                added[name] = true
              end
            end
            for name in content:gmatch("export%s+function%s+([%w_]+)%s*%(") do
              if not added[name] then
                table.insert(symbols, { label = name, kind = 3, detail = "Exported function" })
                added[name] = true
              end
            end
            for name in content:gmatch("const%s+([%w_]+)%s*=") do
              if not added[name] then
                table.insert(symbols, { label = name, kind = 6, detail = "Constant in " .. module_name })
                added[name] = true
              end
            end
            for name in content:gmatch("export%s+const%s+([%w_]+)%s*=") do
              if not added[name] then
                table.insert(symbols, { label = name, kind = 6, detail = "Exported constant" })
                added[name] = true
              end
            end
            -- Also check for object property exports: name: function... or name: "..."
            for name in content:gmatch("([%w_]+)%s*:%s*function") do
              if not added[name] then
                table.insert(symbols, { label = name, kind = 3, detail = "Exported function" })
                added[name] = true
              end
            end
          end
        end
      end
    end
  end

  -- 2. Local JS blocks (only if no prefix, or prefix matches local scope - hard to track)
  if prefix == "" then
    local parser = require('dataform.parser')
    local blocks = parser.get_sqlx_blocks()
    if blocks.js.exists then
      local lines = vim.api.nvim_buf_get_lines(0, blocks.js.start_line - 1, blocks.js.end_line, false)
      local content = table.concat(lines, "\n")
      for name in content:gmatch("function%s+([%w_]+)%s*%(") do
        if not added[name] then
          table.insert(symbols, { label = name, kind = 3, detail = "Local function" })
          added[name] = true
        end
      end
      for name in content:gmatch("const%s+([%w_]+)%s*=") do
        if not added[name] then
          table.insert(symbols, { label = name, kind = 6, detail = "Local constant" })
          added[name] = true
        end
      end
    end
  end

  return symbols
end

function M.trigger_characters()
  return { "'", '"', "." }
end

return M
