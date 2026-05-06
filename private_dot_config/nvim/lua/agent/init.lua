-- agent: send Neovim text into a Claude Code or Codex CLI running in a sibling
-- tmux pane in the same tmux window.
--
-- Validated send pipeline (smoke-tested):
--   tmux load-buffer        (payload via stdin)
--   tmux paste-buffer -p    (bracketed paste into target pane)
--   tmux send-keys Enter    (submit, outside the bracketed sequence)
--
-- Pane targeting uses tmux's per-pane user option `@agent`. Auto-tagging runs
-- at setup() and lazily on each send when no tagged pane is found, by scanning
-- each sibling pane's tty for a `claude-code` or `codex` process. Manual tag
-- still available via `:AgentTag claude|codex` and `:AgentRescan`.

local M = {}

local AGENTS = { claude = true, codex = true }

----------------------------------------------------------------------
-- tmux + shell helpers
----------------------------------------------------------------------
local function tmux(args, stdin)
  local r = vim.system(vim.list_extend({ "tmux" }, args), { stdin = stdin }):wait()
  if r.code ~= 0 then
    error(("tmux %s: %s"):format(table.concat(args, " "), (r.stderr or ""):gsub("%s+$", "")))
  end
  return r.stdout or ""
end

local function trim(s) return (s or ""):gsub("%s+$", "") end

local function in_tmux() return (vim.env.TMUX or "") ~= "" end

local function self_pane_id() return trim(vim.env.TMUX_PANE) end

local function current_window_id()
  return trim(tmux({ "display-message", "-p", "-t", self_pane_id(), "#{window_id}" }))
end

----------------------------------------------------------------------
-- agent detection + auto-tagging
----------------------------------------------------------------------
-- Returns "claude" | "codex" | nil for a pane.
--
-- We inspect ONLY the direct children of the pane's shell PID. Crucially we do
-- NOT recurse into grandchildren — Claude Code spawns MCP servers as children,
-- and one of those can be codex-as-MCP-server (`node /.../codex … mcp-server`).
-- A recursive walk would mistag claude panes as codex.
--
-- We also ignore `pane_current_command` for matching — Claude Code overrides
-- process.title to its version string ("2.1.129"), so tmux's foreground
-- command is not the binary name.
local function detect_pane_agent(pane_id)
  local pane_pid = trim(tmux({ "display-message", "-p", "-t", pane_id, "#{pane_pid}" }))
  if pane_pid == "" then return nil end

  local r = vim.system({ "pgrep", "-P", pane_pid }):wait()
  if r.code ~= 0 or (r.stdout or "") == "" then return nil end

  for child in r.stdout:gmatch("(%d+)") do
    local ar = vim.system({ "ps", "-o", "args=", "-p", child }):wait()
    if ar.code == 0 then
      local args = (ar.stdout or ""):gsub("%s+$", "")  -- trim trailing newline

      -- argv[0] basename: handles bare invocations like `claude` or `codex`
      local first = args:match("^%s*(%S+)") or ""
      local bin = first:match("([^/]+)$") or first
      if bin == "claude" then return "claude" end
      if bin == "codex" then return "codex" end

      -- npm package paths (claude-code installed via @anthropic-ai or @openai)
      if args:find("@anthropic") or args:find("claude%-code") then return "claude" end
      if args:find("@openai/codex") or args:find("codex%-cli") then return "codex" end

      -- node/wrapper invocations: a path-anchored binary name as any arg token
      if args:match("[%s/]claude%s*$") or args:match("[%s/]claude%s") then return "claude" end
      if args:match("[%s/]codex%s*$") or args:match("[%s/]codex%s") then return "codex" end
    end
  end

  return nil
end

-- Scan sibling panes; tag any untagged one that looks like an agent session.
-- Idempotent and safe to call repeatedly (skips already-tagged panes so manual
-- `:AgentTag` decisions aren't clobbered).
function M.auto_tag()
  if not in_tmux() then return end
  local win = current_window_id()
  local self = self_pane_id()
  local out = tmux({ "list-panes", "-t", win, "-F", "#{pane_id}|#{@agent}" })
  for line in out:gmatch("[^\n]+") do
    local id, existing = line:match("^(%S+)|(%S*)$")
    if id and id ~= self and (not existing or existing == "") then
      local detected = detect_pane_agent(id)
      if detected then
        tmux({ "set-option", "-p", "-t", id, "@agent", detected })
      end
    end
  end
end

-- Force-clear @agent on every sibling pane in this window, then re-detect.
-- Used by :AgentRescan to recover from stale or wrongly-detected tags.
function M.retag()
  if not in_tmux() then return end
  local win = current_window_id()
  local self = self_pane_id()
  local out = tmux({ "list-panes", "-t", win, "-F", "#{pane_id}" })
  for line in out:gmatch("[^\n]+") do
    local id = line:match("^(%S+)$")
    if id and id ~= self then
      pcall(tmux, { "set-option", "-pu", "-t", id, "@agent" })
    end
  end
  M.auto_tag()
end

local function list_agent_panes()
  local win = current_window_id()
  local self = self_pane_id()
  local out = tmux({ "list-panes", "-t", win, "-F", "#{pane_id}|#{@agent}" })
  local panes = {}
  for line in out:gmatch("[^\n]+") do
    local id, agent = line:match("^(%S+)|(%S*)$")
    if id and id ~= self and agent and agent ~= "" then
      table.insert(panes, { id = id, agent = agent })
    end
  end
  return panes
end

local function pick_pane(want, cb)
  local function matches_for(name)
    return vim.tbl_filter(function(p) return p.agent == name end, list_agent_panes())
  end
  local matches = matches_for(want)
  if #matches == 0 then
    pcall(M.auto_tag)  -- agent may have been launched after nvim started
    matches = matches_for(want)
  end
  if #matches == 0 then
    vim.notify(
      ("No %s pane in this tmux window. Launch %s in a sibling pane (auto-tag will pick it up) or run `:AgentTag %s`.")
        :format(want, want, want),
      vim.log.levels.ERROR
    )
    return
  end
  if #matches == 1 then cb(matches[1].id); return end
  vim.ui.select(matches, {
    prompt = ("Multiple %s panes — pick one:"):format(want),
    format_item = function(p) return ("%s (%s)"):format(p.id, p.agent) end,
  }, function(choice) if choice then cb(choice.id) end end)
end

----------------------------------------------------------------------
-- send pipeline
----------------------------------------------------------------------
-- opts.submit (default true): whether to send Enter after the paste. Use
-- {submit = false} to "append" text to the agent's input box (e.g. for @file
-- references) without triggering submission.
local function send_to_pane(pane, text, opts)
  opts = opts or {}
  local buf = "agent_send_" .. tostring(vim.uv.hrtime())
  tmux({ "load-buffer", "-b", buf, "-" }, text)
  tmux({ "paste-buffer", "-d", "-p", "-b", buf, "-t", pane })
  if opts.submit ~= false then
    tmux({ "send-keys", "-t", pane, "Enter" })
  end
end

----------------------------------------------------------------------
-- payload assembly (parameterized by source bufnr — prompt window steals focus)
----------------------------------------------------------------------
local function relpath(bufnr)
  local p = vim.api.nvim_buf_get_name(bufnr or 0)
  if p == "" then return "<unnamed>" end
  local cwd = vim.fn.getcwd()
  if p:sub(1, #cwd + 1) == cwd .. "/" then return p:sub(#cwd + 2) end
  return p
end

local function ft_of(bufnr) return vim.bo[bufnr or 0].filetype or "" end

local function fence(body, header, lang)
  return ("%s\n```%s\n%s\n```\n"):format(header, lang or "", body)
end

local function format_selection(bufnr, line1, line2)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local header = ("%s:%d-%d"):format(relpath(bufnr), line1, line2)
  return fence(table.concat(lines, "\n"), header, ft_of(bufnr)), #lines
end

local function format_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return fence(table.concat(lines, "\n"), relpath(bufnr), ft_of(bufnr)), #lines
end

----------------------------------------------------------------------
-- inline prompt window
----------------------------------------------------------------------
local function open_prompt_window(src_win, line1, on_submit)
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].buftype = "nofile"
  vim.bo[pbuf].bufhidden = "wipe"
  vim.bo[pbuf].filetype = "agent_prompt"

  local width = math.min(80, vim.api.nvim_win_get_width(src_win) - 4)
  local height = 5

  local win = vim.api.nvim_open_win(pbuf, true, {
    relative = "win",
    win = src_win,
    bufpos = { line1 - 1, 0 },  -- 0-indexed buffer position of selection start
    anchor = "SW",              -- bottom-left of float pinned there → float floats above
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " prompt — <Esc> then <CR> to send · q to cancel ",
    title_pos = "center",
  })

  vim.cmd("startinsert")

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
    local prompt = vim.trim(table.concat(lines, "\n"))
    close()
    if prompt == "" then
      vim.notify("agent: empty prompt — cancelled", vim.log.levels.WARN)
      return
    end
    on_submit(prompt)
  end

  local kopts = { buffer = pbuf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", submit, kopts)
  vim.keymap.set("n", "q", close, kopts)
end

----------------------------------------------------------------------
-- guards
----------------------------------------------------------------------
local function require_tmux()
  if in_tmux() then return true end
  vim.notify("agent: not running inside tmux", vim.log.levels.ERROR)
  return false
end

local function require_agent(name)
  if AGENTS[name] then return true end
  vim.notify(("agent: unknown agent %q (expected claude|codex)"):format(tostring(name)), vim.log.levels.ERROR)
  return false
end

----------------------------------------------------------------------
-- public actions
----------------------------------------------------------------------
function M.send_selection(agent, line1, line2, opts)
  opts = opts or {}
  if not (require_tmux() and require_agent(agent)) then return end

  -- Capture source context up front; the prompt window steals focus.
  local src_buf = vim.api.nvim_get_current_buf()
  local src_win = vim.api.nvim_get_current_win()
  local code, n = format_selection(src_buf, line1, line2)

  local function dispatch(prompt_text)
    pick_pane(agent, function(pane)
      local payload = (prompt_text and prompt_text ~= "")
        and (prompt_text .. "\n\n" .. code) or code
      send_to_pane(pane, payload)
      local suffix = prompt_text and " + prompt" or ""
      vim.notify(("→ %s (%s): %d line(s)%s"):format(agent, pane, n, suffix))
    end)
  end

  if opts.with_prompt then
    open_prompt_window(src_win, line1, dispatch)
  else
    dispatch(nil)
  end
end

function M.send_buffer(agent)
  if not (require_tmux() and require_agent(agent)) then return end
  local src_buf = vim.api.nvim_get_current_buf()
  pick_pane(agent, function(pane)
    local text, n = format_buffer(src_buf)
    send_to_pane(pane, text)
    vim.notify(("→ %s (%s): buffer (%d lines)"):format(agent, pane, n))
  end)
end

-- Append "@<relpath> " to the agent's input box without submitting. Lets the
-- user keep typing in the agent pane after the file reference. If
-- explicit_path is given (e.g. from a neo-tree mapping), it's used instead of
-- the current buffer's filename.
function M.send_path(agent, explicit_path)
  if not (require_tmux() and require_agent(agent)) then return end
  local rel
  if explicit_path and explicit_path ~= "" then
    local cwd = vim.fn.getcwd()
    if explicit_path:sub(1, #cwd + 1) == cwd .. "/" then
      rel = explicit_path:sub(#cwd + 2)
    else
      rel = explicit_path
    end
  else
    rel = relpath(vim.api.nvim_get_current_buf())
  end
  if not rel or rel == "" or rel == "<unnamed>" then
    vim.notify("agent: no file path to send", vim.log.levels.ERROR); return
  end
  pick_pane(agent, function(pane)
    send_to_pane(pane, "@" .. rel .. " ", { submit = false })
    vim.notify(("→ %s (%s): @%s"):format(agent, pane, rel))
  end)
end

function M.tag_last(agent)
  if not (require_tmux() and require_agent(agent)) then return end
  local id = trim(tmux({ "display-message", "-p", "-t", "!", "#{pane_id}" }))
  if id == "" then
    vim.notify("agent: no previous pane to tag", vim.log.levels.ERROR); return
  end
  tmux({ "set-option", "-p", "-t", id, "@agent", agent })
  vim.notify(("agent: tagged %s as %s"):format(id, agent))
end

----------------------------------------------------------------------
-- setup
----------------------------------------------------------------------
function M.setup()
  local complete = function() return { "claude", "codex" } end

  vim.api.nvim_create_user_command("AgentSend", function(opts)
    M.send_selection(opts.fargs[1], opts.line1, opts.line2)
  end, { range = true, nargs = 1, complete = complete })

  vim.api.nvim_create_user_command("AgentSendPrompt", function(opts)
    M.send_selection(opts.fargs[1], opts.line1, opts.line2, { with_prompt = true })
  end, { range = true, nargs = 1, complete = complete })

  vim.api.nvim_create_user_command("AgentSendBuffer", function(opts)
    M.send_buffer(opts.fargs[1])
  end, { nargs = 1, complete = complete })

  vim.api.nvim_create_user_command("AgentSendPath", function(opts)
    M.send_path(opts.fargs[1], opts.fargs[2])
  end, { nargs = "+", complete = complete })

  vim.api.nvim_create_user_command("AgentTag", function(opts)
    M.tag_last(opts.fargs[1])
  end, { nargs = 1, complete = complete })

  vim.api.nvim_create_user_command("AgentRescan", function() M.retag() end, {})

  -- Auto-tag at startup. pcall: don't fail setup if tmux/ps misbehaves.
  pcall(M.auto_tag)

  -- Rebuild :help tags so `:help agent` works without a manual step.
  pcall(vim.cmd, "silent! helptags " .. vim.fn.stdpath("config") .. "/doc")
end

return M
