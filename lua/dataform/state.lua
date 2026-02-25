local M = {}

---@class DataformState
---@field compiled_project_table table The last compiled Dataform project table.
---@field lsp_client_id integer|nil The active pseudo-LSP client ID.
---@field current_compile_job table|nil The active plenary Job for compilation.
---@field current_dry_run_job table|nil The active plenary Job for dry-run analysis.
---@field structural_hashes table<integer, string> Mapping of buffer numbers to their last structural hash.

M.compiled_project_table = {}
M.lsp_client_id = nil
M.current_compile_job = nil
M.current_dry_run_job = nil
M.structural_hashes = {}

return M
