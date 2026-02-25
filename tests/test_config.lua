local T = MiniTest.new_set()

T['config'] = MiniTest.new_set()

T['config']['setup() overrides defaults'] = function()
  local df = require('dataform')

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
  local df = require('dataform')
  df.config.compile_on_save = true

  df.toggle_compile_on_save()
  MiniTest.expect.equality(df.config.compile_on_save, false)

  df.toggle_compile_on_save()
  MiniTest.expect.equality(df.config.compile_on_save, true)
end

T['config']['toggle_format_on_save() works'] = function()
  local df = require('dataform')
  df.config.format_on_save = false

  df.toggle_format_on_save()
  MiniTest.expect.equality(df.config.format_on_save, true)

  df.toggle_format_on_save()
  MiniTest.expect.equality(df.config.format_on_save, false)
end

T['config']['toggle_preview_style() works'] = function()
  local df = require('dataform')
  df.config.preview_style = "vsplit"

  df.toggle_preview_style()
  MiniTest.expect.equality(df.config.preview_style, "float")

  df.toggle_preview_style()
  MiniTest.expect.equality(df.config.preview_style, "vsplit")
end

T['config']['toggle_logging() works'] = function()
  local df = require('dataform')
  df.config.logging = false

  df.toggle_logging()
  MiniTest.expect.equality(df.config.logging, true)

  df.toggle_logging()
  MiniTest.expect.equality(df.config.logging, false)
end

return T
