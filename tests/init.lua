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

require('mini.test').setup({
  execute = {
    reporter = require('mini.test').gen_reporter.stdout(),
  },
})
