-- Unified :Dataform command dispatcher

local function subcommand_dispatcher(opts)
  local fargs = opts.fargs
  local subcommand = fargs[1]
  local args = table.move(fargs, 2, #fargs, 1, {})

  local df = require('dataform')

  local commands = {
    compile = function() df.get_compiled_sql_job() end,
    compile_incremental = function() df.get_compiled_sql_job(true) end,
    preview = function() df.get_compiled_sql_job() end,
    run = function() df.run_action_job() end,
    run_full = function() df.run_action_job(true) end,
    run_all = function() df.run_all() end,
    run_tag = function(a) df.run_tag(a[1]) end,
    run_assertions = function() df.run_assertions_job() end,
    estimate_tag_cost = function(a) df.estimate_tag_cost(a[1]) end,
    hover = function() df.hover() end,
    code_action = function() df.code_action() end,
    go_to_ref = function() df.go_to_ref() end,
    format = function() df.format() end,
    lint = function() df.lint() end,
    show_tree = function() df.show_dependency_tree() end,
    show_dry_run = function() df.show_dry_run_virtual_text() end,
    find_dependencies = function() df.find_model_dependencies() end,
    find_dependents = function() df.find_model_dependents() end,
    find_references = function() df.find_references() end,
    clear_diagnostics = function() df.clear_diagnostics() end,
    diagnostics = function() df.set_diagnostics(require('dataform.state').compiled_project_table) end,
    show_log = function() df.open_log() end,
    clear_log = function() df.clear_log() end,
    signature_help = function() df.show_signature_help() end,
    toggle_compile_on_save = function() df.toggle_compile_on_save() end,
    toggle_format_on_save = function() df.toggle_format_on_save() end,
    toggle_lint_on_save = function() df.toggle_lint_on_save() end,
    toggle_preview_style = function() df.toggle_preview_style() end,
    toggle_treesitter = function() df.toggle_treesitter() end,
    toggle_logging = function() df.toggle_logging() end,
  }

  if commands[subcommand] then
    commands[subcommand](args)
  else
    vim.notify("Dataform: Unknown subcommand '" .. tostring(subcommand) .. "'", vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_user_command("Dataform", subcommand_dispatcher, {
  nargs = "+",
  desc = "Dataform plugin commands",
  complete = function(ArgLead, CmdLine, CursorPos)
    local commands = {
      "compile", "compile_incremental", "preview", "run", "run_full", "run_all",
      "run_tag", "run_assertions", "estimate_tag_cost", "hover", "code_action",
      "go_to_ref", "format", "lint", "show_tree", "show_dry_run",
      "find_dependencies", "find_dependents", "find_references",
      "clear_diagnostics", "diagnostics", "show_log", "clear_log", "signature_help",
      "toggle_compile_on_save", "toggle_format_on_save", "toggle_lint_on_save",
      "toggle_preview_style", "toggle_treesitter", "toggle_logging"
    }
    return vim.tbl_filter(function(cmd)
      return cmd:match("^" .. ArgLead)
    end, commands)
  end,
})
