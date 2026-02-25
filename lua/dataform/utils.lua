local utils = {}

function utils.get_current_file_path()
  local Path = require('plenary.path')
  return Path:new(vim.fn.expand('%:p')):absolute()
end

function utils.open_file(file_path)
  vim.cmd("edit " .. file_path)
end

--- Execute a job using plenary
---@param cmd string
---@param args string[]
---@param opts table? { json: boolean, quiet: boolean, callback: function }
---@return any JobObj
function utils.execute_job(cmd, args, opts)
  local Job = require('plenary.job')
  opts = opts or {}

  utils.log("JOB EXEC: " .. cmd .. " " .. table.concat(args, " "))

  local job = Job:new({
    command = cmd,
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        local stdout = table.concat(j:result(), "\n")
        local stderr = table.concat(j:stderr_result(), "\n")

        utils.log("JOB EXIT CODE: " .. tostring(return_val))

        if return_val ~= 0 then
          utils.log("JOB ERROR OUTPUT: " .. (stderr or "(empty)"))
          if not opts.quiet then
            utils.notify("Job failed: " .. cmd .. "\n" .. stderr, vim.log.levels.ERROR)
          end
        else
          if not opts.json then
            utils.log("JOB OUTPUT: " .. (stdout or "(empty)"))
          end
        end

        if opts.callback then
          opts.callback(return_val, stdout, stderr)
        end
      end)
    end,
  })

  job:start()
  return job
end

function utils.os_execute_with_status(command, json_output, quiet)
  local is_json = json_output or false
  local handle_stdout = is_json and " 2>/dev/null" or " 2>&1"

  utils.log("EXEC (Sync): " .. command)

  local n = os.tmpname()
  local status = os.execute(command .. " > " .. n .. handle_stdout)
  local f = io.open(n, "r")
  local content = f:read("*all")
  f:close()
  os.remove(n)

  utils.log("EXIT CODE: " .. tostring(status))
  if status ~= 0 then
    utils.log("ERROR OUTPUT: " .. (content or "(empty)"))
  elseif not is_json then
    -- Log success output for non-json commands (like version checks)
    utils.log("OUTPUT: " .. (content or "(empty)"))
  end

  if status ~= 0 and not quiet then
    utils.notify("Command failed: " .. command .. "\n" .. content, vim.log.levels.ERROR)
  end

  return status, content
end

--- Asynchronous execution using vim.system
---@param cmd string[] | string
---@param opts table? { json: boolean, quiet: boolean, callback: function }
---@return any SystemObj
function utils.system_async(cmd, opts)
  opts = opts or {}
  local command_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
  utils.log("EXEC (Async): " .. command_str)

  return vim.system(type(cmd) == "string" and { "bash", "-c", cmd } or cmd, {
    text = true,
  }, function(obj)
    vim.schedule(function()
      utils.log("EXIT CODE (Async): " .. tostring(obj.code))

      if obj.code ~= 0 then
        utils.log("ERROR OUTPUT (Async): " .. (obj.stderr or "(empty)"))
        if not opts.quiet then
          utils.notify("Async command failed: " .. command_str .. "\n" .. (obj.stderr or ""), vim.log.levels.ERROR)
        end
      else
        if not opts.json then
          utils.log("OUTPUT (Async): " .. (obj.stdout or "(empty)"))
        end
      end

      if opts.callback then
        opts.callback(obj.code, obj.stdout, obj.stderr)
      end
    end)
  end)
end
function utils.open_buffer_with_content(content, filetype, title)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, vim.split(content, "\n"))

  if filetype then
    vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
  end

  if title then
    vim.api.nvim_buf_set_name(bufnr, title)
  end

  vim.api.nvim_command("vsplit")
  vim.api.nvim_win_set_buf(0, bufnr)
end

function utils.open_floating_window(content, filetype, title)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, vim.split(content, "\n"))

  if filetype then
    vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title or "Dataform Preview",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Close on 'q'
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':close<CR>', { noremap = true, silent = true })

  return win, bufnr
end

function utils.open_interactive_buffer(content, filetype, title, keymaps)
  local win, bufnr = utils.open_floating_window(content, filetype, title)

  if keymaps then
    for key, action in pairs(keymaps) do
      vim.keymap.set('n', key, action, { buffer = bufnr, noremap = true, silent = true })
    end
  end

  return win, bufnr
end

function utils.custom_picker(prompt_name, custom_file_paths)
  if not custom_file_paths or #custom_file_paths == 0 then return end

  local has_telescope, telescope = pcall(require, "telescope")
  if has_telescope then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local conf = require("telescope.config").values

    pickers.new({}, {
      prompt_title = prompt_name,
      finder = finders.new_table {
        results = custom_file_paths,
      },
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          return { "cat", entry.value }
        end,
      }),
      sorter = conf.generic_sorter({}),
    }):find()
  else
    vim.ui.select(
      custom_file_paths,
      { prompt = prompt_name },
      function(choice)
        if choice then
          vim.cmd.edit(choice)
        end
      end
    )
  end
end

function utils.notify(msg, level)
  utils.log({ event = "notify", message = msg, level = level })
  local notify_fn = vim.notify
  local has_notify_plugin, notify_plugin_fn = pcall(require, 'notify')
  if has_notify_plugin then
    notify_fn = notify_plugin_fn
  end
  notify_fn(msg, level)
end

function utils.format_bytes(bytes)
  if not bytes or bytes == 0 then return "0 B" end
  local units = {"B", "KiB", "MiB", "GiB", "TiB", "PiB"}
  local k = 1024
  local i = math.floor(math.log(bytes) / math.log(k))
  return string.format("%.2f %s", bytes / (k^i), units[i+1])
end

function utils.parse_dry_run_stats(bq_output)
  -- bq query --dry_run usually outputs something like:
  -- "Query successfully validated. Assuming the transaction succeeds, this query will process 12345 bytes."
  local bytes = bq_output:match("process%s+(%d+)%s+bytes")
  if bytes then
    bytes = tonumber(bytes)
    local formatted = utils.format_bytes(bytes)
    -- Estimate cost: $5 per TiB (1024^4 bytes)
    local cost = (bytes / (1024^4)) * 5
    return string.format("Dry run: %s (~$%.5f)", formatted, cost)
  end
  return nil
end

function utils.get_dataform_definitions_file_path()
  local file = utils.get_current_file_path()
  utils.log("get_dataform_definitions_file_path: current file=" .. file)
  if file:find("/definitions/") then
    return file
  end
  utils.log("get_dataform_definitions_file_path: FAILED, file not in /definitions/")
  return utils.notify(
    "Error: File does not exist inside dataform definitions folder.",
    vim.log.levels.ERROR
  )
end

function utils.log(msg)
  local ok, config = pcall(require, "dataform.config")
  if not ok or not config.options or not config.options.logging then return end

  local log_path = vim.fn.stdpath('cache') .. '/dataform.log'
  local f = io.open(log_path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [DEBUG] " .. (type(msg) == "table" and vim.inspect(msg) or tostring(msg)) .. "\n")
    f:close()
  end
end

function utils.open_log()
  local log_path = vim.fn.stdpath('cache') .. '/dataform.log'
  if vim.fn.filereadable(log_path) == 1 then
    vim.cmd("edit " .. log_path)
  else
    utils.notify("Log file not found.", vim.log.levels.WARN)
  end
end

function utils.clear_log()
  local log_path = vim.fn.stdpath('cache') .. '/dataform.log'
  local f = io.open(log_path, "w")
  if f then
    f:write("")
    f:close()
    utils.notify("Dataform log cleared.", vim.log.levels.INFO)
  end
end

return utils
