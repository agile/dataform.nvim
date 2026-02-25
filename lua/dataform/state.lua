local M = {}

---@class DataformState
---@field compiled_project_table table The last compiled Dataform project table.
---@field lsp_client_id integer|nil The active pseudo-LSP client ID.
---@field current_compile_job table|nil The active plenary Job for compilation.
---@field current_dry_run_job table|nil The active plenary Job for dry-run analysis.
---@field structural_hashes table<integer, string> Mapping of buffer numbers to their last structural hash.

---@type table The last compiled Dataform project table.
M.compiled_project_table = {}
---@type integer|nil The active pseudo-LSP client ID.
M.lsp_client_id = nil
---@type table|nil The active plenary Job for compilation.
M.current_compile_job = nil
---@type table|nil The active plenary Job for dry-run analysis.
M.current_dry_run_job = nil
---@type table<string, string> Mapping of file paths to their last structural hash.
M.structural_hashes = {}

return M
