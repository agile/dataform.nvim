local M = {}
local state = require("dataform.state")
local config = require("dataform.config")
local utils = require("dataform.utils")

local function is_treesitter_available()
  if not config.options.use_treesitter then return false end
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

function M.get_sqlx_blocks()
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

function M.get_structural_hash(bufnr)
  local blocks = M.get_sqlx_blocks()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local structure = ""

  if blocks.config.exists then
    -- list_slice is 1-indexed: vim.list_slice(list, start, end)
    structure = structure .. table.concat(vim.list_slice(lines, blocks.config.start_line, blocks.config.end_line), "\n")
  end
  if blocks.js.exists then
    structure = structure .. table.concat(vim.list_slice(lines, blocks.js.start_line, blocks.js.end_line), "\n")
  end

  -- Also include all ref/resolve calls in the whole file
  local content = table.concat(lines, "\n")
  for ref_call in content:gmatch("${%s*ref%s*%(.-%)}?") do
    structure = structure .. ref_call
  end
  for res_call in content:gmatch("${%s*resolve%s*%(.-%)}?") do
    structure = structure .. res_call
  end

  return vim.fn.sha256(structure)
end

function M.get_all_models()
  local tables = vim.deepcopy(state.compiled_project_table.tables or {})
  local operations = state.compiled_project_table.operations or {}
  local declarations = state.compiled_project_table.declarations or {}
  local assertions = state.compiled_project_table.assertions or {}
  local all_models = vim.fn.extend(tables, operations)
  all_models = vim.fn.extend(all_models, declarations)

  return vim.fn.extend(all_models, assertions)
end

function M.find_model_by_file_path(all_models, target_file_path)
  if not target_file_path then return nil end
  local target_abs = vim.fn.fnamemodify(target_file_path, ":p")

  for _, model in pairs(all_models) do
    if model.fileName then
      local model_abs = vim.fn.fnamemodify(model.fileName, ":p")
      if model_abs == target_abs then
        return model
      end
    end
  end
  return nil
end

function M.find_file_name_by_schema_name(all_models, schema, name)
  for _, model in pairs(all_models) do
    if model.target.schema == schema and model.target.name == name then
      return model.fileName
    end
  end
  return nil
end

function M.get_df_args(subcommand, extra_args)
  local args = { subcommand }
  -- Add global args from config
  for _, arg in ipairs(config.options.dataform_args or {}) do
    table.insert(args, arg)
  end
  -- Add subcommand-specific args
  if extra_args then
    for _, arg in ipairs(extra_args) do
      table.insert(args, arg)
    end
  end
  return args
end

return M
