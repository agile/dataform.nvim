# <img src="images/dataform-logo.png" width="120" height="120">  dataform.nvim
## Dataform Core Plugin for Neovim

⚠️ **This is not an officially supported Google product.**
<br>
<br>

[![asciicast](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG.svg)](https://asciinema.org/a/PV7XeWQqBBotCx8EhhXLVZlyG)

## 🪄 Features

- **Native LSP Integration**: Registers as a pseudo-LSP client. Supports `gd` (Go to Definition), `K` (Hover), `documentSymbol`, `formatting`, and `codeAction` using your standard LSP keybindings and plugins (like `tiny-code-action.nvim`).
- **Project Compilation**: Automatically compiles Dataform project on first open or on save.
- **Generalized Navigation**: Robust navigation and reference finding for:
    - `${ref()}` and `${resolve()}` (including multi-line calls and project variable schemas).
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
    - **JS Symbols**: Suggests constants and functions from `includes/` and local `js` blocks.
- **Advanced Code Actions**:
    - **Document Column**: One-click to add an undocumented column to your `config` block.
    - **Create Declaration**: Automatically scaffold a new declaration file for unresolved `ref()` targets.
- **Interactive Dependency Graph**: Navigable, floating window tree view. Press `<CR>` on any node to jump to its definition. Supports tag-scoped trees!
- **Enhanced Diagnostics**: Real-time warnings for unresolved project variables and JavaScript references, alongside standard compilation errors.
- **Robust Logging**: Comprehensive internal logging system for troubleshooting environment or path resolution issues.

## 📜 Requirements

- [Dataform CLI](https://cloud.google.com/dataform/docs/use-dataform-cli) (`npm i -g @dataform/cli`)
- [BigQuery CLI Tool](https://cloud.google.com/bigquery/docs/bq-command-line-tool) (`gcloud components install bq`)
- (Optional) [sqlfluff](https://sqlfluff.com/) for SQL formatting.

### Optional Enhancements

- [tiny-code-action.nvim](https://github.com/rachartier/tiny-code-action.nvim) for a beautiful code action UI.
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for smart symbol searching.
- [nvim-notify](https://github.com/rcarriga/nvim-notify) for enhanced notifications.

## 🧪 Installation & Configuration

### Simple Setup (Recommended)
For most users, simply calling `setup` is enough. This works on all Neovim versions and automatically registers the Dataform pseudo-LSP with sensible defaults.

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

          -- Use tree-sitter for block detection if available (default: true)
          use_treesitter = true,

          -- Enable internal logging (default: false)
          logging = false,

          -- Clear log file on startup (default: true)
          clear_log_on_start = true,

          -- Formatter configuration
          formatter_bin = "sqlfluff", -- (default: 'sqlfluff')
          formatter_options = { "fix", "--force", "-q" }, -- (default: as shown)
      })
    end
  }

```

### Neovim 0.11+ Setup
If you are on Neovim 0.11 or later, you can treat Dataform exactly like any other Language Server using the new native configuration system.

```lua
local df = require('dataform')

-- 1. Initialize plugin settings (optional)
df.setup({ compile_on_save = true })

-- 2. Enable the server using the new native API
vim.lsp.enable('dataform')
```

### Manual LSP Setup (Advanced / Pre-0.11)
If you want full manual control over the LSP lifecycle (e.g., custom `on_attach` or `capabilities`), you can retrieve the standard config and start it yourself.

```lua
local df = require('dataform')

local lsp_config = df.get_lsp_config({
  on_attach = function(client, bufnr)
    -- Your standard LSP keybindings here
  end,
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

-- Start the client manually
vim.lsp.start(lsp_config)
```

## 🚀 Development & Testing

This plugin uses `mini.test` for its test suite. To run the tests locally:

1. Clone the repository.
2. Install pre-commit (`brew install pre-commit` or [see installation notes](https://pre-commit.com/#installation)) and install pre-commit hooks: `pre-commit install`
3. Run `make test`. (Dependencies are automatically downloaded to `tests/.deps/`).

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
