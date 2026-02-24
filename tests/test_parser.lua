local T = MiniTest.new_set()

local function setup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

T['get_sqlx_blocks()'] = MiniTest.new_set()

T['get_sqlx_blocks()']['parses simple config and sql'] = function()
  setup_buffer({
    'config { type: "view" }',
    '',
    'SELECT 1'
  })

  local blocks = require('dataform.project').get_sqlx_blocks()
  MiniTest.expect.equality(blocks.config.exists, true)
  MiniTest.expect.equality(blocks.config.start_line, 1)
  MiniTest.expect.equality(blocks.config.end_line, 1)

  MiniTest.expect.equality(blocks.sql.exists, true)
  MiniTest.expect.equality(blocks.sql.start_line, 3)
  MiniTest.expect.equality(blocks.sql.end_line, 3)
end

T['get_sqlx_blocks()']['parses multi-line config'] = function()
  setup_buffer({
    'config {',
    '  type: "table",',
    '  schema: "test"',
    '}',
    '',
    'SELECT * FROM table'
  })

  local blocks = require('dataform.project').get_sqlx_blocks()
  MiniTest.expect.equality(blocks.config.exists, true)
  MiniTest.expect.equality(blocks.config.start_line, 1)
  MiniTest.expect.equality(blocks.config.end_line, 4)
  MiniTest.expect.equality(blocks.sql.start_line, 6)
end

T['get_sqlx_blocks()']['parses js blocks'] = function()
  setup_buffer({
    'js {',
    '  const x = 1;',
    '}',
    'config { type: "view" }',
    'SELECT ${x}'
  })

  local blocks = require('dataform.project').get_sqlx_blocks()
  MiniTest.expect.equality(blocks.js.exists, true)
  MiniTest.expect.equality(blocks.js.start_line, 1)
  MiniTest.expect.equality(blocks.js.end_line, 3)
  MiniTest.expect.equality(blocks.config.start_line, 4)
  MiniTest.expect.equality(blocks.sql.start_line, 5)
end

T['get_sqlx_blocks()']['parses pre and post operations'] = function()
  setup_buffer({
    'config { type: "table" }',
    'pre_operations {',
    '  INSERT INTO x SELECT 1',
    '}',
    'SELECT * FROM x',
    'post_operations {',
    '  DROP TABLE temp',
    '}'
  })

  local blocks = require('dataform.project').get_sqlx_blocks()
  MiniTest.expect.equality(#blocks.pre_operations, 1)
  MiniTest.expect.equality(blocks.pre_operations[1].start_line, 2)
  MiniTest.expect.equality(blocks.pre_operations[1].end_line, 4)

  MiniTest.expect.equality(#blocks.post_operations, 1)
  MiniTest.expect.equality(blocks.post_operations[1].start_line, 6)
  MiniTest.expect.equality(blocks.post_operations[1].end_line, 8)

  MiniTest.expect.equality(blocks.sql.start_line, 5)
  MiniTest.expect.equality(blocks.sql.end_line, 5)
end

T['get_sqlx_blocks()']['handles nested braces in config'] = function()
  setup_buffer({
    'config {',
    '  assertions: {',
    '    uniqueKey: ["id"]',
    '  }',
    '}',
    'SELECT 1'
  })

  local blocks = require('dataform.project').get_sqlx_blocks()
  MiniTest.expect.equality(blocks.config.end_line, 5)
  MiniTest.expect.equality(blocks.sql.start_line, 6)
end

return T
