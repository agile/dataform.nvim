local T = MiniTest.new_set()

local function setup_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  return bufnr
end

T['performance'] = MiniTest.new_set()

T['performance']['get_structural_hash() is consistent for SQL changes'] = function()
  local df = _G.reload_dataform()

  -- Version 1
  local bufnr = setup_buffer({
    'config { type: "table" }',
    'SELECT 1 FROM ${ref("a")}'
  })
  local hash1 = df.get_structural_hash(bufnr)

  -- Version 2: Only SQL logic changes
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { 'SELECT 2 FROM ${ref("a")}' })
  local hash2 = df.get_structural_hash(bufnr)

  MiniTest.expect.equality(hash1, hash2)
end

T['performance']['get_structural_hash() changes for config changes'] = function()
  local df = _G.reload_dataform()

  setup_buffer({ 'config { type: "table" }', 'SELECT 1' })
  local hash1 = df.get_structural_hash(0)

  setup_buffer({ 'config { type: "view" }', 'SELECT 1' })
  local hash2 = df.get_structural_hash(0)

  MiniTest.expect.no_equality(hash1, hash2)
end

T['performance']['get_structural_hash() changes for ref changes'] = function()
  local df = _G.reload_dataform()

  setup_buffer({ 'SELECT * FROM ${ref("a")}' })
  local hash1 = df.get_structural_hash(0)

  setup_buffer({ 'SELECT * FROM ${ref("b")}' })
  local hash2 = df.get_structural_hash(0)

  MiniTest.expect.no_equality(hash1, hash2)
end

T['performance']['compile skips job when hash matches'] = function()
  local df = _G.reload_dataform()
  local utils = require('dataform.utils')

  -- Mock execute_job
  local job_called = false
  local old_job = utils.execute_job
  utils.execute_job = function()
    job_called = true
    return { shutdown = function() end }
  end

  setup_buffer({ 'config { type: "v" }', 'SELECT 1' })
  local file = utils.get_current_file_path()
  local h = df.get_structural_hash(0)

  -- Set existing hash
  df.structural_hashes[file] = h

  df.compile()

  MiniTest.expect.equality(job_called, false)

  -- Clean up
  utils.execute_job = old_job
end

T['performance']['compile includes global dataform_args'] = function()
  local df = _G.reload_dataform()
  local utils = require('dataform.utils')

  df.setup({ dataform_args = { "--custom-flag", "custom-value" } })

  local captured_args = {}
  local old_job = utils.execute_job
  utils.execute_job = function(cmd, args, opts)
    captured_args = args
    return { shutdown = function() end }
  end

  setup_buffer({ 'config { type: "v" }', 'SELECT 1' })
  df.compile()

  local found_flag = false
  local found_value = false
  for _, arg in ipairs(captured_args) do
    if arg == "--custom-flag" then found_flag = true end
    if arg == "custom-value" then found_value = true end
  end

  MiniTest.expect.equality(found_flag, true)
  MiniTest.expect.equality(found_value, true)

  -- Cleanup
  utils.execute_job = old_job
end

return T
