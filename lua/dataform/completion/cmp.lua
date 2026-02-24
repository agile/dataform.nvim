local utils = require('dataform.completion.utils')

local source = {}

function source:is_available()
  return vim.bo.filetype == 'sqlx'
end

function source:complete(params, callback)
  local items = {}

  if utils.is_sqlx_js_string_syntax() then
    items = utils.action_names()
  elseif utils.is_sqlx_js_syntax() then
    items = utils.js_symbols()
  else
    items = utils.columns()
  end

  callback(items)
end

function source:get_trigger_characters()
  return utils.trigger_characters()
end

return source
