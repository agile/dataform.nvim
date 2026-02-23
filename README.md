# <img src="images/dataform-logo.png" width="120" height="120">  dataform.nvim
## Dataform Core Plugin for Neovim

⚠️ **This is not an officially supported Google product.**
<br>
<br>

[![asciicast](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG.svg)](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG)

## 🪄 Features

- **Project Compilation**: Automatically compiles Dataform project on first open or on save.
- **Enhanced Navigation**: Robust "Go to Definition" for:
    - `${ref()}` and `${resolve()}` (including multi-line calls).
    - JavaScript variables and functions in `js { ... }` blocks.
    - External JavaScript modules in the `includes/` directory.
    - SQL Common Table Expressions (CTEs) in the current file.
- **Readable Dry-Run Stats**: Preview compiled SQL with integrated BigQuery dry-run statistics (bytes processed and estimated cost).
- **Intelligent Autocompletion**:
    - Dataform Action names (Models/Declarations) within `ref()` or `resolve()`.
    - **Column Names**: Metadata-aware completion for columns documented in your project.
    - Supports both `nvim-cmp` and `blink.cmp`.
- **Metadata Hovers**: Use `:DataformHover` to see table documentation, column descriptions, and Dataform config keyword help.
- **Inline Diagnostics**: Compilation errors from `dataform compile` are mapped directly to buffers using Neovim's diagnostic API.
- **Configurable Formatting**: Format SQL blocks using `sqlfluff` or any custom formatter.
- **Action Runner**: Run specific models, tags, or the entire project directly from Neovim.
- **Dependency Finder**: Smart dependencies/dependents finder using `telescope.nvim` or `vim.ui.select`.

## 📜 Requirements

- [Dataform CLI](https://cloud.google.com/dataform/docs/use-dataform-cli) (`npm i -g @dataform/cli`)
- [BigQuery CLI Tool](https://cloud.google.com/bigquery/docs/bq-command-line-tool) (`gcloud components install bq`)
- (Optional) [sqlfluff](https://sqlfluff.com/) for SQL formatting.

### Optional Enhancements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for smart dependencies/dependents finder.
- [nvim-notify](https://github.com/rcarriga/nvim-notify) for enhanced notifications.

## 🧪 Installation & Configuration

Use your favorite plugin manager to install it.

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
        -- refresh dataform metadata on each save (default: true)
        compile_on_save = true,
        
        -- Formatter configuration (defaults shown)
        formatter_bin = "sqlfluff",
        formatter_options = { "fix", "--force", "-q" },
    })
  end
}
```

## 🚀 Completions

The plugin provides completion sources for `nvim-cmp` and `blink.cmp`. It automatically switches between Action names (inside strings) and Column names (in SQL body).

#### Example Setup for `nvim-cmp`
```lua
local cmp = require('cmp')
cmp.setup.filetype('sqlx', {
  sources = vim.fn.extend(
    { { name = 'dataform_actions' } },
    cmp.get_config().sources
  )
})
```

#### Example Setup for `blink.cmp`
```lua
blink.setup({
  sources = {
    providers = {
      dataform = {
        name = "Dataform",
        module = "dataform.completion.blink",
      },
    },
    per_filetype = {
      sqlx = { 'dataform', 'lsp', 'path', 'snippets', 'buffer' }
    },
  },
})
```

## 🌀 Commands

| Command | Action |
|---|---|
|`:DataformCompileFull` | Compile current model to SQL with syntax highlighting and dry-run stats in a vertical split. |
|`:DataformCompileIncremental` | Same as above but with the `incremental` flag enabled. |
|`:DataformGoToRef` | Jump to definition of the word under cursor (ref, JS var, CTE). |
|`:DataformHover` | Show documentation for the table, column, or config keyword under cursor. |
|`:DataformFormat` | Format the SQL block using the configured formatter. |
|`:DataformClearDiagnostics` | Clear all Dataform compilation diagnostics. |
|`:DataformRunAction` | Run the current model in BigQuery. |
|`:DataformRunTag <tag>` | Run actions associated with a specific tag. |
|`:DataformRunAll` | Run the entire Dataform project. |
|`:DataformFindDependencies`| Open a finder with all dependencies for the current model. |
|`:DataformFindDependents`| Open a finder with all dependents for the current model. |

## 🌳 Tree-sitter Support

For the best experience, it is highly recommended to use the experimental `tree-sitter-dataform` grammar included in this workspace.

### How it enhances the experience:
- **Superior Syntax Highlighting**: Precisely identifies BigQuery SQL keywords, types, and functions.
- **Multi-modal Support**: Corrects syntax highlighting for JavaScript within `js { ... }` and `config { ... }` blocks via injections.
- **Interpolation Awareness**: Properly handles `${ ... }` syntax within SQL blocks.
- **Improved Indentation**: Provides more consistent and logical indentation for complex `.sqlx` files.

### Setup with `nvim-treesitter`:

1.  Add the parser to your Tree-sitter configuration:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.dataform = {
  install_info = {
    url = "https://github.com/renzepost/tree-sitter-dataform", -- Or local path to tree-sitter-dataform
    files = { "src/parser.c" },
    branch = "main",
  },
  filetype = "sqlx",
}
```

2.  Install the parser: `:TSInstall dataform`
3.  Ensure you have the query files (`highlights.scm`, `injections.scm`, etc.) in your Neovim configuration path (usually `~/.config/nvim/queries/dataform/`).

## 🏰 How to contribute
To know more on how to contribute please check our [Contributing Guide](https://github.com/magal1337/dataform.nvim/blob/main/CONTRIBUTING.md)

## 🙏 Thanks adventurer 🧙‍♀️
Like this Plugin? Star it on [GitHub](https://github.com/magal1337/dataform.nvim)
