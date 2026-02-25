" Title:        Dataform Plugin
" Description:  A plugin to provide simple dataform features. Caution: This is not a
" Dataform official product.
" Maintainer:   https://github.com/magal1337

" Use ftplugin/sqlx.lua for filetype-specific initialization
" Use plugin/dataform.lua for the unified :Dataform command

lua << EOF
  local has_cmp, cmp = pcall(require, 'cmp')
  if has_cmp then
    -- Deferred require for lazy loading
    cmp.register_source('dataform_actions', {
      complete = function(self, params, callback)
        require('dataform.completion.cmp'):complete(params, callback)
      end,
      is_available = function() return vim.bo.filetype == 'sqlx' end,
      get_trigger_characters = function() return require('dataform.completion.utils').trigger_characters() end,
    })
  end
EOF
