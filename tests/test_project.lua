local T = MiniTest.new_set()

local function setup_buffer(lines, cursor)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  if cursor then
    vim.api.nvim_win_set_cursor(0, cursor)
  end
  return bufnr
end

T['get_context_at_cursor()'] = MiniTest.new_set()

T['get_context_at_cursor()']['identifies project variables'] = function()
  local df = _G.reload_dataform()
  setup_buffer({ 'SELECT ${dataform.projectConfig.vars.my_var} FROM table' }, { 1, 35 })

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'variable')
  MiniTest.expect.equality(context.var_name, 'my_var')
end

T['get_context_at_cursor()']['identifies ref() calls'] = function()
  local df = _G.reload_dataform()
  setup_buffer({ 'SELECT * FROM ${ref("my_table")}' }, { 1, 25 })

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.table_name, 'my_table')
end

T['get_context_at_cursor()']['identifies schema and table in ref()'] = function()
  local df = _G.reload_dataform()
  setup_buffer({ 'SELECT * FROM ${ref("my_schema", "my_table")}' }, { 1, 24 }) -- On "my_schema"

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.schema, 'my_schema')
  MiniTest.expect.equality(context.table_name, 'my_table')
end

T['get_context_at_cursor()']['handles multi-line ref blocks'] = function()
  local df = _G.reload_dataform()
  setup_buffer({
    'SELECT * FROM ${',
    '  ref(',
    '    "my_schema",',
    '    "my_table"',
    '  )',
    '}'
  }, { 4, 10 }) -- On "my_table"

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.table_name, 'my_table')
  MiniTest.expect.equality(context.schema, 'my_schema')
end

T['get_context_at_cursor()']['resolves project variable as schema in ref()'] = function()
  local df = _G.reload_dataform()
  df.compiled_project_table = {
    projectConfig = {
      vars = {
        MY_SCHEMA = "resolved_schema"
      }
    }
  }
  setup_buffer({ 'SELECT * FROM ${ref(dataform.projectConfig.vars.MY_SCHEMA, "my_table")}' }, { 1, 65 }) -- On "my_table"

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'table')
  MiniTest.expect.equality(context.schema, 'resolved_schema')
  MiniTest.expect.equality(context.table_name, 'my_table')
end

T['get_context_at_cursor()']['identifies js functions'] = function()
  local df = _G.reload_dataform()
  setup_buffer({ 'const x = my_func(123)' }, { 1, 12 })

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.type, 'function')
  MiniTest.expect.equality(context.func_name, 'my_func')
end

T['get_context_at_cursor()']['handles dots in words'] = function()
  local df = _G.reload_dataform()
  setup_buffer({ 'SELECT ${constants.TAX_RATE} FROM table' }, { 1, 15 })

  local context = df.get_context_at_cursor()
  MiniTest.expect.equality(context.word, 'constants.TAX_RATE')
end

T['actions'] = MiniTest.new_set()

T['actions']['go_to_ref() handles local js function'] = function()
  local df = _G.reload_dataform()
  setup_buffer({
    'js {',
    '  function myLocalFunc() {}',
    '}',
    'SELECT ${myLocalFunc()}'
  }, { 4, 12 })

  -- Mock open_file
  local old_open = require('dataform.utils').open_file
  require('dataform.utils').open_file = function() end

  df.go_to_ref()

  local cursor = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(cursor[1], 2) -- Should move to line 2

  require('dataform.utils').open_file = old_open
end

T['actions']['hover() handles various symbols'] = function()
  local df = _G.reload_dataform()

  -- Mock open_floating_preview
  local captured_lines = {}
  local old_preview = vim.lsp.util.open_floating_preview
  vim.lsp.util.open_floating_preview = function(lines) captured_lines = lines end

  -- 1. Table hover
  df.compiled_project_table = {
    tables = {
      {
        target = { database = "db", schema = "s", name = "my_table" },
        fileName = "definitions/my_table.sqlx",
        type = "table"
      }
    }
  }
  setup_buffer({ 'SELECT ${ref("my_table")}' }, { 1, 15 })
  df.hover()
  MiniTest.expect.equality(captured_lines[1] ~= nil and captured_lines[1]:find("db.s.my_table") ~= nil, true)

  -- 2. JS function hover
  captured_lines = {}
  setup_buffer({ 'js { function test() {} }', 'SELECT ${test( ' }, { 2, 12 })
  df.hover()
  MiniTest.expect.equality(captured_lines[1] ~= nil and captured_lines[1]:find("JS Symbol: test") ~= nil, true)

  -- 3. JS constant hover (from includes)
  vim.fn.mkdir('includes', 'p')
  local f = io.open('includes/docs.js', 'w')
  f:write('const columns = { my_col: "This is a column" }')
  f:close()

  captured_lines = {}
  setup_buffer({ 'columns: { my_col: docs.columns.my_col }' }, { 1, 30 }) -- On docs.columns.my_col

  df.hover()
  MiniTest.expect.equality(captured_lines[1] ~= nil and captured_lines[1]:find("JS Symbol: docs.columns.my_col") ~= nil, true)

  -- 4. 2-arg ref hover
  df.compiled_project_table = {
    tables = {
      {
        target = { database = "db", schema = "my_schema", name = "my_table" },
        fileName = "definitions/my_table.sqlx",
        type = "table"
      }
    }
  }
  setup_buffer({ 'SELECT ${ref("my_schema", "my_table")}' }, { 1, 15 }) -- On "my_schema"
  df.hover()
  MiniTest.expect.equality(captured_lines[1]:find("my_schema.my_table") ~= nil, true)

  -- 5. Tag hover
  captured_lines = {}
  setup_buffer({ 'config { tags: ["daily"] }' }, { 1, 18 }) -- On "daily"
  df.hover()
  MiniTest.expect.equality(captured_lines[1]:find("Tag: daily") ~= nil, true)

  -- 6. Multi-line tag hover
  captured_lines = {}
  setup_buffer({
    'config {',
    '  tags: [',
    '    "hourly"',
    '  ]',
    '}'
  }, { 3, 6 }) -- On "hourly"
  df.hover()
  MiniTest.expect.equality(captured_lines[1]:find("Tag: hourly") ~= nil, true)

  os.remove('includes/docs.js')
  os.remove('includes')

  vim.lsp.util.open_floating_preview = old_preview
end

T['actions']['get_rename_edits logic'] = function()
  local df = _G.reload_dataform()
  local utils = require('dataform.utils')

  -- Mock async system call
  local old_async = utils.system_async
  utils.system_async = function(cmd, opts)
    if opts.callback then
      opts.callback(0, "definitions/test.sqlx:1:SELECT * FROM ${ref('old_name')}", "")
    end
  end

  local captured_edit
  df.get_rename_edits("old_name", "new_name", function(edit)
    captured_edit = edit
  end)

  local found_edit = false
  if captured_edit and captured_edit.changes then
    for uri, changes in pairs(captured_edit.changes) do
      if uri:find("test.sqlx") then
        for _, change in ipairs(changes) do
          if change.newText == "new_name" then found_edit = true end
        end
      end
    end
  end

  MiniTest.expect.equality(found_edit, true)

  -- Cleanup
  utils.system_async = old_async
end

return T
