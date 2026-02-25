" Title:        Dataform Plugin
" Description:  A plugin to provide simple dataform features. Caution: This is not a
" Dataform official product.
" Maintainer:   https://github.com/magal1337

" Use ftplugin/sqlx.lua for filetype-specific initialization

lua << EOF
  local has_cmp, cmp = pcall(require, 'cmp')
  if has_cmp then
    cmp.register_source('dataform_actions', require('dataform').completion_cmp_source)
  end
EOF

command! -nargs=0 DataformSignatureHelp lua require('dataform').show_signature_help()
command! -nargs=0 DataformTogglePreviewStyle lua require('dataform').toggle_preview_style()
command! -nargs=0 DataformToggleTreesitter lua require('dataform').toggle_treesitter()
command! -nargs=0 DataformToggleLogging lua require('dataform').toggle_logging()
command! -nargs=0 DataformToggleLintOnSave lua require('dataform').toggle_lint_on_save()
command! -nargs=0 DataformLint lua require('dataform').lint()
command! -nargs=0 DataformClearLog lua require('dataform').clear_log()
command! -nargs=0 DataformShowLog lua require('dataform').open_log()
command! -nargs=0 DataformToggleFormatOnSave lua require('dataform').toggle_format_on_save()
command! -nargs=0 DataformToggleCompileOnSave lua require('dataform').toggle_compile_on_save()
command! -nargs=0 DataformCompileFull lua require('dataform').get_compiled_sql_job()
command! -nargs=0 DataformPreview lua require('dataform').get_compiled_sql_job()
command! -nargs=0 DataformClearDiagnostics lua require('dataform').clear_diagnostics()
command! -nargs=0 DataformDiagnostics lua require('dataform').set_diagnostics(require('dataform').compiled_project_table)
command! -nargs=0 DataformCompileIncremental lua require('dataform').get_compiled_sql_job(true)
command! -nargs=0 DataformGoToRef lua require('dataform').go_to_ref()
command! -nargs=0 DataformHover lua require('dataform').hover()
command! -nargs=0 DataformCodeAction lua require('dataform').code_action()
command! -nargs=0 DataformFormat lua require('dataform').format()
command! -nargs=0 DataformRunActionIncremental lua require('dataform').run_action_job()
command! -nargs=0 DataformRunAction lua require('dataform').run_action_job(true)
command! -nargs=0 DataformRunAll lua require('dataform').run_all()
command! -nargs=0 DataformRunAssertions lua require('dataform').run_assertions_job()
command! -nargs=1 DataformEstimateTagCost lua require('dataform').estimate_tag_cost(<f-args>)
command! -nargs=1 DataformRunTag lua require('dataform').run_tag(<f-args>)
command! -nargs=0 DataformShowDryRun lua require('dataform').show_dry_run_virtual_text()
command! -nargs=0 DataformFindDependencies lua require('dataform').find_model_dependencies()
command! -nargs=0 DataformFindDependents lua require('dataform').find_model_dependents()
command! -nargs=0 DataformShowDependencyTree lua require('dataform').show_dependency_tree()
command! -nargs=0 DataformFindVariableReferences lua require('dataform').find_variable_references()
command! -nargs=0 DataformFindReferences lua require('dataform').find_references()
