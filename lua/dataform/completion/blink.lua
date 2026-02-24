local utils = require('dataform.completion.utils')

--- @module 'blink.cmp'
--- @class blink.cmp.Source
local source = {}

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts
  return self
end

function source:enabled()
  return vim.bo.filetype == 'sqlx'
end

function source:get_trigger_characters()
  return utils.trigger_characters()
 end

function source:get_completions(ctx, callback)
  --- @type lsp.CompletionItem[]
  local items = {}

  local line = ctx.line
  local col = ctx.cursor[2]
  local text_before = line:sub(1, col)
  local word = text_before:match("([%w_%.]+)$") or ""

  if utils.is_sqlx_js_string_syntax() then
    items = utils.action_names()
  elseif utils.is_sqlx_js_syntax() then
    items = utils.js_symbols(word)
  else
    items = utils.columns()
  end

  callback({
    items = items,
    is_incomplete_backward = false,
    is_incomplete_forward = false,
  })

  return function() end
end

return source
