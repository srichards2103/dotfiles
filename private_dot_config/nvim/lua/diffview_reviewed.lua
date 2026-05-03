local M = {}

local data_file = vim.fn.stdpath("data") .. "/diffview-reviewed.json"
local ns = vim.api.nvim_create_namespace("diffview_reviewed")
local redraw_patched = false

local function load_state()
  local f = io.open(data_file, "r")
  if not f then return {} end
  local content = f:read("*a") or ""
  f:close()
  if content == "" then return {} end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

local function save_state(state)
  vim.fn.mkdir(vim.fn.fnamemodify(data_file, ":h"), "p")
  local f = io.open(data_file, "w")
  if not f then return end
  f:write(vim.json.encode(state))
  f:close()
end

local function branch_key()
  local out = vim.fn.system("git rev-parse --abbrev-ref HEAD"):gsub("%s+$", "")
  return out ~= "" and out or "unknown"
end

local function get_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then return nil end
  return lib.get_current_view()
end

local function file_at_cursor()
  local view = get_view()
  if not view or not view.panel then return nil end

  if view.infer_cur_file then
    local ok, file = pcall(view.infer_cur_file, view)
    if ok and file and file.path then return file.path end
  end

  if view.panel.get_item_at_cursor then
    local ok, item = pcall(view.panel.get_item_at_cursor, view.panel)
    if ok and item and item.path then return item.path end
  end

  if view.panel.cur_file and view.panel.cur_file.path then return view.panel.cur_file.path end

  return nil
end

local function has_marked_child(state, dir_path)
  local prefix = dir_path .. "/"
  for path, _ in pairs(state) do
    if path:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function file_stats(file)
  if not file or not file.stats then return nil end
  if not file.stats.additions and not file.stats.deletions then return nil end

  return {
    additions = file.stats.additions or 0,
    deletions = file.stats.deletions or 0,
  }
end

local function add_stats(total, stats)
  if not stats then return total end
  total.additions = total.additions + stats.additions
  total.deletions = total.deletions + stats.deletions
  return total
end

local function dir_stats(root, dir_path)
  local total = { additions = 0, deletions = 0 }
  local prefix = dir_path .. "/"

  root:deep_some(function(comp)
    if comp.name == "file" and comp.context and comp.context.path:sub(1, #prefix) == prefix then
      add_stats(total, file_stats(comp.context))
    end
  end)

  if total.additions == 0 and total.deletions == 0 then return nil end
  return total
end

local function set_row_summary(buf, lineno, stats, is_viewed)
  if not stats and not is_viewed then return end

  local text = {}
  if stats then
    text[#text + 1] = { "+" .. stats.additions, "DiffviewFilePanelInsertions" }
    text[#text + 1] = { " -" .. stats.deletions, "DiffviewFilePanelDeletions" }
  end
  if is_viewed then
    text[#text + 1] = { " ✓", "DiffAdd" }
  end

  vim.api.nvim_buf_set_extmark(buf, ns, lineno, 0, {
    virt_text = text,
    virt_text_pos = "right_align",
    priority = 200,
  })
end

local function render_component_marks(buf, root, state)
  if not root or not root.deep_some then return false end

  root:deep_some(function(comp)
    if comp.name == "file" and comp.context and comp.lstart >= 0 then
      set_row_summary(buf, comp.lstart, file_stats(comp.context), state[comp.context.path])
    elseif comp.name == "dir_name" and comp.parent and comp.parent.context then
      local dir = comp.parent.context
      if dir.collapsed and comp.lstart >= 0 then
        set_row_summary(buf, comp.lstart, dir_stats(root, dir.path), has_marked_child(state, dir.path))
      end
    end
  end)

  return true
end

local function patch_diffview_redraw()
  if redraw_patched then return end

  local ok, panel_mod = pcall(require, "diffview.ui.panel")
  if not ok or not panel_mod.Panel then return end

  local panel = panel_mod.Panel
  local original_redraw = panel.redraw
  panel.redraw = function(self, ...)
    local result = { original_redraw(self, ...) }
    if self.bufid and vim.api.nvim_buf_is_valid(self.bufid) then
      vim.schedule(M.render)
    end
    return unpack(result)
  end

  redraw_patched = true
end

function M.render()
  local view = get_view()
  if not view or not view.panel then return end
  local buf = view.panel.bufid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local state = load_state()[branch_key()] or {}

  if view.panel.components and render_component_marks(buf, view.panel.components.comp, state) then
    return
  end

  if vim.tbl_isempty(state) then return end

  local marked_basenames = {}
  for path, _ in pairs(state) do
    local basename = path:match("([^/]+)$")
    if basename then marked_basenames[basename] = true end
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for lineno, line_text in ipairs(lines) do
    for basename, _ in pairs(marked_basenames) do
      if line_text:find(vim.pesc(basename)) then
        vim.api.nvim_buf_set_extmark(buf, ns, lineno - 1, 0, {
          virt_text = { { " ✓", "DiffAdd" } },
          virt_text_pos = "eol",
        })
        break
      end
    end
  end
end

function M.toggle()
  local path = file_at_cursor()
  if not path then
    vim.notify("No file under cursor", vim.log.levels.WARN)
    return
  end
  local state = load_state()
  local key = branch_key()
  state[key] = state[key] or {}
  if state[key][path] then
    state[key][path] = nil
    vim.notify("Unmarked: " .. path)
  else
    state[key][path] = true
    vim.notify("Viewed: " .. path)
  end
  save_state(state)
  M.render()
end

function M.clear()
  local state = load_state()
  state[branch_key()] = nil
  save_state(state)
  M.render()
  vim.notify("Cleared viewed marks for " .. branch_key())
end

function M.list()
  local state = load_state()[branch_key()] or {}
  local paths = vim.tbl_keys(state)
  if #paths == 0 then
    vim.notify("No viewed files for " .. branch_key())
    return
  end
  table.sort(paths)
  vim.notify("Viewed (" .. branch_key() .. "):\n  " .. table.concat(paths, "\n  "))
end

function M.reopen_mr_diff()
  vim.cmd("DiffviewClose")
  vim.schedule(function()
    vim.cmd("DiffviewOpen origin/develop...HEAD")
  end)
end

function M.setup()
  patch_diffview_redraw()

  local group = vim.api.nvim_create_augroup("DiffviewReviewed", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "DiffviewFiles",
    callback = function(args)
      patch_diffview_redraw()
      vim.keymap.set("n", "<leader>v", M.toggle, {
        buffer = args.buf,
        desc = "Toggle viewed",
      })
      vim.keymap.set("n", "<leader>V", M.clear, {
        buffer = args.buf,
        desc = "Clear viewed marks",
      })
      vim.schedule(M.render)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function()
      if vim.bo.filetype == "DiffviewFiles" then
        vim.schedule(M.render)
      end
    end,
  })

  vim.api.nvim_create_user_command("DiffviewReviewedList", M.list, {})
  vim.api.nvim_create_user_command("DiffviewReviewedClear", M.clear, {})
end

return M
