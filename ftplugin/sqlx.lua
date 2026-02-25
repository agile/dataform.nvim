-- Dataform filetype plugin

-- 1. One-time setup: change workdir and run initial compile
-- This mimics the original behavior in plugin/dataform.vim
if vim.g.loaded_dataform == nil or vim.g.loaded_dataform == 0 then
  require('dataform').set_dataform_workdir_project_path()
  require('dataform').compile()
  vim.g.loaded_dataform = 1
end

local bufnr = vim.api.nvim_get_current_buf()

-- 2. Buffer-local Autocmds

-- Format on save
vim.api.nvim_create_autocmd("BufWritePre", {
  buffer = bufnr,
  callback = function()
    require('dataform').format_on_save()
  end,
  desc = "Dataform: Format SQL block on save"
})

-- Compile on save
vim.api.nvim_create_autocmd("BufWritePost", {
  buffer = bufnr,
  callback = function()
    require('dataform').compile_on_save()
  end,
  desc = "Dataform: Compile project on save"
})

-- Signature help
vim.api.nvim_create_autocmd("CursorMovedI", {
  buffer = bufnr,
  callback = function()
    require('dataform').show_signature_help()
  end,
  desc = "Dataform: Show signature help"
})

-- 3. LSP Attachment
-- If a client is already running, attach it to this buffer
local state = require('dataform.state')
if state.lsp_client_id and vim.lsp.get_client_by_id(state.lsp_client_id) then
  vim.lsp.buf_attach_client(bufnr, state.lsp_client_id)
end
