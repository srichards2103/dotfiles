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

local function set_tick(buf, lineno)
  vim.api.nvim_buf_set_extmark(buf, ns, lineno, 0, {
    virt_text = { { "✓", "DiffAdd" } },
    virt_text_pos = "right_align",
    priority = 200,
  })
end

local function render_component_marks(buf, root, state)
  if not root or not root.deep_some then return false end

  root:deep_some(function(comp)
    if comp.name == "file" and comp.context and state[comp.context.path] and comp.lstart >= 0 then
      set_tick(buf, comp.lstart)
    elseif comp.name == "dir_name" and comp.parent and comp.parent.context then
      local dir = comp.parent.context
      if dir.collapsed and has_marked_child(state, dir.path) and comp.lstart >= 0 then
        set_tick(buf, comp.lstart)
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
  if vim.tbl_isempty(state) then return end

  if view.panel.components and render_component_marks(buf, view.panel.components.comp, state) then
    return
  end

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
