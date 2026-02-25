local plugin_root = vim.fn.getcwd()
vim.opt.runtimepath:append(plugin_root)

-- Add dependencies to runtimepath
local deps_path = plugin_root .. '/tests/.deps'
vim.opt.runtimepath:append(deps_path .. '/mini.nvim')
vim.opt.runtimepath:append(deps_path .. '/plenary.nvim')

-- Set up 'mini.test'
require('mini.test').setup({
  execute = {
    reporter = require('mini.test').gen_reporter.stdout(),
  },
})

-- Reload helper
function _G.reload_dataform()
  package.loaded['dataform.project'] = nil
  package.loaded['dataform.parser'] = nil
  package.loaded['dataform.diagnostics'] = nil
  package.loaded['dataform.actions'] = nil
  package.loaded['dataform.lsp'] = nil
  package.loaded['dataform.utils'] = nil
  package.loaded['dataform.signatures'] = nil
  package.loaded['dataform.config'] = nil
  package.loaded['dataform.state'] = nil
  package.loaded['dataform.init'] = nil
  package.loaded['dataform'] = nil
  return require('dataform')
end
