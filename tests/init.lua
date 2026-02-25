local plugin_root = vim.fn.getcwd()
vim.opt.runtimepath:append(plugin_root)

-- Set up 'mini.test'
local deps_path = plugin_root .. '/tests/.deps'
if vim.fn.isdirectory(deps_path) == 0 then
  vim.fn.mkdir(deps_path, 'p')
end

local minipath = deps_path .. '/mini.nvim'
if vim.fn.isdirectory(minipath) == 0 then
  print('Downloading mini.nvim...')
  vim.fn.system({ 'git', 'clone', '--filter=blob:none', 'https://github.com/echasnovski/mini.nvim', minipath })
end
vim.opt.runtimepath:append(minipath)

local plenarypath = deps_path .. '/plenary.nvim'
if vim.fn.isdirectory(plenarypath) == 0 then
  print('Downloading plenary.nvim...')
  vim.fn.system({ 'git', 'clone', '--filter=blob:none', 'https://github.com/nvim-lua/plenary.nvim', plenarypath })
end
vim.opt.runtimepath:append(plenarypath)

require('mini.test').setup({
  execute = {
    reporter = require('mini.test').gen_reporter.stdout(),
  },
})

-- Reload helper
function _G.reload_dataform()
  package.loaded['dataform.project'] = nil
  package.loaded['dataform.utils'] = nil
  package.loaded['dataform.signatures'] = nil
  package.loaded['dataform.config'] = nil
  package.loaded['dataform.state'] = nil
  package.loaded['dataform.init'] = nil
  return require('dataform.project')
end
