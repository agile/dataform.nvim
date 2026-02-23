local M = {}

function M.action_names()
  local dataform = require('dataform.project')
  local compiled = dataform.compiled_project_table or {}
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
  local dataform = require('dataform.project')
  local compiled = dataform.compiled_project_table or {}
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
  return synGroupName and synGroupName == "sqlxJsString"
end

function M.trigger_characters()
  return { "'", '"' }
end

return M
