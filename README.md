# <img src="images/dataform-logo.png" width="120" height="120">  dataform.nvim
## Dataform Core Plugin for Neovim

⚠️ **This is not an officially supported Google product.**
<br>
<br>

[![asciicast](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG.svg)](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG)

## 🪄 Features

- **Project Compilation**: Automatically compiles Dataform project on first open or on save.
- **Generalized Navigation**: Robust "Go to Definition" and "Find References" for:
    - `${ref()}` and `${resolve()}` (including multi-line calls).
    - JavaScript variables and functions in `js { ... }` blocks.
    - External JavaScript modules in the `includes/` directory.
    - Project Variables defined in `workflow_settings.yaml`.
    - SQL Common Table Expressions (CTEs) in the current file.
- **Signature Hints**: Proactive parameter help while typing `ref(`, `resolve(`, or `config {`. Supports dynamic signature extraction for your custom JavaScript functions!
- **Inline Virtual Text**: Automatically displays BigQuery dry-run cost and bytes at the top of your file after every successful save.
- **Floating Window Previews**: View compiled SQL in a vertical split or a centered floating window for a non-disruptive workflow.
- **Intelligent Autocompletion**:
    - Dataform Action names (Models/Declarations) within `ref()` or `resolve()`.
    - **Column Names**: Metadata-aware completion for columns documented in your project.
    - Supports both `nvim-cmp` and `blink.cmp`.
- **Metadata Hovers**: See table documentation, column descriptions, and Dataform config keyword help. Now includes signature information for JavaScript functions.
- **Inline Diagnostics**: Compilation errors from `dataform compile` are mapped directly to buffers.
- **Configurable Formatting**: Format SQL blocks using `sqlfluff` on command or automatically on save.
- **Action Runner**: Run specific models, tags, or the entire project directly from Neovim.
- **Dependency Finder**: Smart dependencies/dependents finder and navigable dependency trees.

## 📜 Requirements

- [Dataform CLI](https://cloud.google.com/dataform/docs/use-dataform-cli) (`npm i -g @dataform/cli`)
- [BigQuery CLI Tool](https://cloud.google.com/bigquery/docs/bq-command-line-tool) (`gcloud components install bq`)
- (Optional) [sqlfluff](https://sqlfluff.com/) for SQL formatting.

### Optional Enhancements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for smart dependencies/dependents finder.
- [nvim-notify](https://github.com/rcarriga/nvim-notify) for enhanced notifications.

## 🧪 Installation & Configuration

```lua
-- Example with lazy.nvim
{
  'magal1337/dataform.nvim',
  dependencies = {
    'rcarriga/nvim-notify',
    'nvim-telescope/telescope.nvim'
  },
  config = function ()
    require('dataform').setup({
        -- Automatically compile on save (default: true)
        compile_on_save = true,

        -- Automatically format SQL blocks on save (default: false)
        format_on_save = false,

        -- Layout for compiled SQL previews: 'vsplit' or 'float' (default: 'vsplit')
        preview_style = "vsplit",

        -- Formatter configuration
        formatter_bin = "sqlfluff",
        formatter_options = { "fix", "--force", "-q" },
    })
  end
}
```

## 🌀 Commands

| Command | Action |
|---|---|
|`:DataformCompileFull` | Preview compiled SQL with dry-run stats (respects `preview_style`). |
|`:DataformGoToRef` | Jump to definition of symbol under cursor (Table, JS var, Project Var, CTE). |
|`:DataformHover` | Show documentation/metadata for symbol under cursor. |
|`:DataformFindReferences`| Find all usages of the table, variable, or function under cursor. |
|`:DataformSignatureHelp`| Manually trigger the signature hint window. |
|`:DataformShowDryRun`| Refresh the inline dry-run virtual text. |
|`:DataformToggleCompileOnSave`| Toggle automatic compilation. |
|`:DataformToggleFormatOnSave`| Toggle automatic formatting. |
|`:DataformTogglePreviewStyle`| Switch between 'vsplit' and 'float' for previews. |
|`:DataformFormat` | Manually format the SQL block. |
|`:DataformShowDependencyTree`| Open a buffer showing the full dependency tree. |
|`:DataformRunAction` | Run the current model in BigQuery. |
|`:DataformRunTag <tag>` | Run actions associated with a specific tag. |
|`:DataformRunAll` | Run the entire Dataform project. |

## 🚀 Development & Testing

This plugin uses `mini.test` for its test suite. To run the tests locally:

1. Clone the repository.
2. Install pre-commit (`brew install pre-commit` or [see installation notes](https://pre-commit.com/#installation)) and install pre-commit hooks: `pre-commit install`
3. Run `make test`. (The test runner will automatically download dependencies to `tests/.deps/`).


## 🌳 Tree-sitter Support

For the best experience, use the experimental `tree-sitter-dataform` grammar included in this workspace.

### Setup with `nvim-treesitter`:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.dataform = {
  install_info = {
    url = "https://github.com/renzepost/tree-sitter-dataform",
    files = { "src/parser.c" },
    branch = "main",
  },
  filetype = "sqlx",
}
```

## 🏰 How to contribute
Check our [Contributing Guide](https://github.com/magal1337/dataform.nvim/blob/main/CONTRIBUTING.md)

## 🙏 Thanks adventurer 🧙‍♀️
Like this Plugin? Star it on [GitHub](https://github.com/magal1337/dataform.nvim)
