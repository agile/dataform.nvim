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

---@class SQLXBlock
---@field exists boolean
---@field start_line integer
---@field end_line integer

---@class SQLXBlocks
---@field config SQLXBlock
---@field js SQLXBlock
---@field pre_operations SQLXBlock[]
---@field post_operations SQLXBlock[]
---@field sql SQLXBlock

--- Parse the current SQLX file into its constituent blocks.
---@return SQLXBlocks
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

--- Calculate a structural hash of the SQLX file to detect meaningful changes.
---@param bufnr integer
---@return string
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

--- Get all models (tables, declarations, operations, assertions) from the compiled project.
---@return table[]
function M.get_all_models()
  local all_models = {}
  local keys = { "tables", "operations", "declarations", "assertions" }
  for _, key in ipairs(keys) do
    for _, item in ipairs(state.compiled_project_table[key] or {}) do
      table.insert(all_models, item)
    end
  end
  return all_models
end

--- Find a model by its source file path.
---@param all_models table[]
---@param target_file_path string?
---@return table|nil
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

--- Find a model's file path by its schema and name.
---@param all_models table[]
---@param schema string
---@param name string
---@return string|nil
function M.find_file_name_by_schema_name(all_models, schema, name)
  for _, model in pairs(all_models) do
    if model.target.schema == schema and model.target.name == name then
      return model.fileName
    end
  end
  return nil
end

--- Get arguments for a Dataform subcommand, merging global and specific args.
---@param subcommand string
---@param extra_args string[]?
---@return string[]
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

---@class CursorContext
---@field word string
---@field row integer
---@field col integer
---@field current_line string
---@field lines string[]
---@field type "table"|"variable"|"function"|"js_module"|"tag"|nil
---@field table_name string?
---@field schema string?
---@field var_name string?
---@field func_name string?
---@field tag_name string?

--- Extract semantic context at the current cursor position.
---@return CursorContext
function M.get_context_at_cursor()
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
        local vars = state.compiled_project_table.projectConfig and state.compiled_project_table.projectConfig.vars or {}
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

  -- 5. Check if we are inside a tags block (could be multi-line)
  local blocks = M.get_sqlx_blocks()
  if blocks.config.exists and row >= blocks.config.start_line and row <= blocks.config.end_line then
    -- We are in config block. Search backwards for 'tags:'
    local is_tag = false
    for r = row, blocks.config.start_line, -1 do
      local l = lines[r]
      if l:find("tags%s*:") then
        is_tag = true
        break
      end
      -- If we hit another key before 'tags:', then we are likely not in a tags list
      -- but this is a simple heuristic.
      if r < row and l:find("[%w_]+%s*:") then break end
    end

    if is_tag and (current_line:find('["\']' .. lua_escaped_word .. '["\']') or current_line:find(lua_escaped_word)) then
      context.type = "tag"
      context.tag_name = word
      return context
    end
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

return M
