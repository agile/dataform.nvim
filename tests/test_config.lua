local T = MiniTest.new_set()

T['config'] = MiniTest.new_set()

T['config']['setup() overrides defaults'] = function()
  local df = require('dataform.project')

  -- Verify default
  MiniTest.expect.equality(df.config.compile_on_save, true)

  -- Override
  df.setup({ compile_on_save = false, formatter_bin = "custom-bin" })

  MiniTest.expect.equality(df.config.compile_on_save, false)
  MiniTest.expect.equality(df.config.formatter_bin, "custom-bin")

  -- Reset for other tests
  df.setup({ compile_on_save = true, formatter_bin = "sqlfluff" })
end

T['config']['toggle_compile_on_save() works'] = function()
  local df = require('dataform.project')
  df.config.compile_on_save = true

  df.toggle_compile_on_save()
  MiniTest.expect.equality(df.config.compile_on_save, false)

  df.toggle_compile_on_save()
  MiniTest.expect.equality(df.config.compile_on_save, true)
end

T['config']['toggle_format_on_save() works'] = function()
  local df = require('dataform.project')
  df.config.format_on_save = false

  df.toggle_format_on_save()
  MiniTest.expect.equality(df.config.format_on_save, true)

  df.toggle_format_on_save()
  MiniTest.expect.equality(df.config.format_on_save, false)
end

return T
