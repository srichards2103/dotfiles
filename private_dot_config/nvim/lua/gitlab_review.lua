local M = {}

local defaults = {
  context_lines = 8,
  draft = false,
  image_height = 78,
  image_width = 280,
  remote = "origin",
}

local opts = vim.deepcopy(defaults)
local current_view
local open_comment_popup
local panel_ns = vim.api.nvim_create_namespace("gitlab_review_panel")
local panel = {
  buf = nil,
  win = nil,
  context = nil,
  discussions = {},
  image_rows = {},
  image_preview = nil,
  rows = {},
  thread_rows = {},
  show_resolved = false,
}

local function setup_highlights()
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewHeader", { link = "Title", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewHelp", { link = "Comment", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewOpen", { link = "DiagnosticWarn", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewResolved", { link = "DiagnosticOk", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewPath", { link = "Directory", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewAuthor", { link = "Identifier", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewCodeTarget", { link = "DiffText", default = true })
  pcall(vim.api.nvim_set_hl, 0, "GitLabReviewImage", { link = "Underlined", default = true })
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "GitLab Review" })
end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function system(args, input, cwd)
  if cwd and vim.system then
    local result = vim.system(args, { text = true, stdin = input, cwd = cwd }):wait()
    local output = trim((result.stdout or "") .. (result.stderr or ""))
    if result.code ~= 0 then
      return nil, output
    end
    return trim(result.stdout or ""), nil
  end

  local output = vim.fn.system(args, input)
  if vim.v.shell_error ~= 0 then
    return nil, trim(output)
  end
  return trim(output), nil
end

local function system_async(args, input, cwd, callback)
  if vim.system then
    vim.system(args, { text = true, stdin = input, cwd = cwd }, function(result)
      vim.schedule(function()
        local output = trim((result.stdout or "") .. (result.stderr or ""))
        if result.code ~= 0 then
          callback(nil, output)
          return
        end

        callback(trim(result.stdout or ""), nil)
      end)
    end)
    return
  end

  vim.schedule(function()
    local output, err = system(args, input, cwd)
    callback(output, err)
  end)
end

local function system_binary_async(args, cwd, callback)
  if vim.system then
    vim.system(args, { cwd = cwd }, function(result)
      vim.schedule(function()
        local stderr = trim(result.stderr or "")
        if result.code ~= 0 then
          callback(nil, stderr)
          return
        end

        callback(result.stdout or "", nil)
      end)
    end)
    return
  end

  vim.schedule(function()
    callback(nil, "Binary downloads require Neovim with vim.system support")
  end)
end

local function url_encode(value)
  return (value:gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function parse_project_path(remote_url)
  local path = remote_url:match("^[%w+.-]+://[^/]+/(.+)$") or remote_url:match("^[^@]+@[^:]+:(.+)$")
  if not path then
    return nil
  end
  return (path:gsub("%.git$", ""))
end

local function current_project_id(cwd)
  local remote_url, remote_err = system({ "git", "remote", "get-url", opts.remote }, nil, cwd)
  if not remote_url then
    return nil, remote_err
  end

  local project_path = parse_project_path(remote_url)
  if not project_path then
    return nil, "Could not parse GitLab project from " .. remote_url
  end

  return url_encode(project_path), nil
end

local function current_project_id_async(cwd, callback)
  system_async({ "git", "remote", "get-url", opts.remote }, nil, cwd, function(remote_url, remote_err)
    if not remote_url then
      callback(nil, remote_err)
      return
    end

    local project_path = parse_project_path(remote_url)
    if not project_path then
      callback(nil, "Could not parse GitLab project from " .. remote_url)
      return
    end

    callback(url_encode(project_path), nil)
  end)
end

local function glab_json(args, cwd)
  local output, err = system(args, nil, cwd)
  if not output then
    return nil, err
  end

  local ok, data = pcall(vim.json.decode, output)
  if not ok then
    return nil, "GitLab returned invalid JSON"
  end

  return data, nil
end

local function glab_json_async(args, cwd, callback)
  system_async(args, nil, cwd, function(output, err)
    if not output then
      callback(nil, err)
      return
    end

    local ok, data = pcall(vim.json.decode, output)
    if not ok then
      callback(nil, "GitLab returned invalid JSON")
      return
    end

    callback(data, nil)
  end)
end

local function current_branch(cwd)
  return system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, nil, cwd)
end

local function current_branch_async(cwd, callback)
  system_async({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, nil, cwd, callback)
end

local function current_merge_request(project_id, cwd)
  local branch, branch_err = current_branch(cwd)
  if not branch then
    return nil, branch_err
  end

  local merge_requests, err = glab_json({
    "glab",
    "api",
    "projects/" .. project_id .. "/merge_requests?state=opened&source_branch=" .. url_encode(branch),
  }, cwd)
  if not merge_requests then
    return nil, err
  end
  if not merge_requests[1] then
    return nil, "No open merge request found for " .. branch
  end

  return merge_requests[1].iid, nil
end

local function current_merge_request_async(project_id, cwd, callback)
  current_branch_async(cwd, function(branch, branch_err)
    if not branch then
      callback(nil, branch_err)
      return
    end

    glab_json_async({
      "glab",
      "api",
      "projects/" .. project_id .. "/merge_requests?state=opened&source_branch=" .. url_encode(branch),
    }, cwd, function(merge_requests, err)
      if not merge_requests then
        callback(nil, err)
        return
      end
      if not merge_requests[1] then
        callback(nil, "No open merge request found for " .. branch)
        return
      end

      callback(merge_requests[1].iid, nil)
    end)
  end)
end

local function latest_version(project_id, mr_iid, cwd)
  local versions, err = glab_json({
    "glab",
    "api",
    "projects/" .. project_id .. "/merge_requests/" .. mr_iid .. "/versions",
  }, cwd)
  if not versions then
    return nil, err
  end
  if not versions[1] then
    return nil, "No collected merge request diff versions found"
  end

  return versions[1], nil
end

local function current_repo_cwd()
  local view = current_view()
  if view and view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel then
    return view.adapter.ctx.toplevel
  end

  local root = system({ "git", "rev-parse", "--show-toplevel" })
  return root
end

local function mr_context()
  local cwd = current_repo_cwd()
  local project_id, project_err = current_project_id(cwd)
  if not project_id then
    return nil, project_err
  end

  local mr_iid, mr_err = current_merge_request(project_id, cwd)
  if not mr_iid then
    return nil, mr_err
  end

  return {
    cwd = cwd,
    project_id = project_id,
    mr_iid = tostring(mr_iid),
  }, nil
end

local function mr_context_async(callback)
  local cwd = current_repo_cwd()

  current_project_id_async(cwd, function(project_id, project_err)
    if not project_id then
      callback(nil, project_err)
      return
    end

    current_merge_request_async(project_id, cwd, function(mr_iid, mr_err)
      if not mr_iid then
        callback(nil, mr_err)
        return
      end

      callback({
        cwd = cwd,
        project_id = project_id,
        mr_iid = tostring(mr_iid),
      }, nil)
    end)
  end)
end

current_view = function()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return nil
  end
  return lib.get_current_view()
end

local function current_entry()
  local view = current_view()
  if not view or not view.cur_entry then
    return nil
  end
  return view.cur_entry
end

local function current_side(entry)
  local bufnr = vim.api.nvim_get_current_buf()
  local layout = entry.layout

  if layout.a and layout.a.file and layout.a.file.bufnr == bufnr then
    return "old"
  end
  if layout.b and layout.b.file and layout.b.file.bufnr == bufnr then
    return "new"
  end

  return nil
end

local function selection_range(visual)
  if visual then
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    return start_line, end_line
  end

  return vim.fn.line("."), vim.fn.line(".")
end

local function line_code(path, old_line, new_line)
  local digest, err = system({ "shasum", "-a", "1" }, path)
  if not digest then
    return nil, err
  end

  return ("%s_%s_%s"):format(digest:match("^(%x+)"), old_line or 0, new_line or 0)
end

local function line_range(path, side, start_line, end_line)
  if start_line == end_line then
    return nil, nil
  end

  local start_old = side == "old" and start_line or nil
  local start_new = side == "new" and start_line or nil
  local end_old = side == "old" and end_line or nil
  local end_new = side == "new" and end_line or nil

  local start_code, start_err = line_code(path, start_old, start_new)
  if not start_code then
    return nil, start_err
  end

  local end_code, end_err = line_code(path, end_old, end_new)
  if not end_code then
    return nil, end_err
  end

  return {
    start = {
      type = side,
      old_line = start_old,
      new_line = start_new,
      line_code = start_code,
    },
    ["end"] = {
      type = side,
      old_line = end_old,
      new_line = end_new,
      line_code = end_code,
    },
  }, nil
end

local function build_position(visual)
  local entry = current_entry()
  if not entry then
    return nil, "Open a file in Diffview first"
  end

  local side = current_side(entry)
  if not side then
    return nil, "Place the cursor in a Diffview file pane"
  end

  local start_line, end_line = selection_range(visual)
  local cwd = entry.adapter and entry.adapter.ctx and entry.adapter.ctx.toplevel or nil
  local project_id, project_err = current_project_id(cwd)
  if not project_id then
    return nil, project_err
  end

  local mr_iid, mr_err = current_merge_request(project_id, cwd)
  if not mr_iid then
    return nil, mr_err
  end

  local version, version_err = latest_version(project_id, mr_iid, cwd)
  if not version then
    return nil, version_err
  end

  local old_path = entry.oldpath or entry.path
  local new_path = entry.path
  local range_path = side == "old" and old_path or new_path
  local range, range_err = line_range(range_path, side, start_line, end_line)
  if range_err then
    return nil, range_err
  end

  local position = {
    position_type = "text",
    base_sha = version.base_commit_sha,
    head_sha = version.head_commit_sha,
    start_sha = version.start_commit_sha,
    old_path = old_path,
    new_path = new_path,
    line_range = range,
  }

  if side == "old" then
    position.old_line = end_line
  else
    position.new_line = end_line
  end

  return {
    project_id = project_id,
    mr_iid = tostring(mr_iid),
    position = position,
    cwd = cwd,
  }, nil
end

local function discussion_endpoint(context, suffix)
  local endpoint = "projects/"
    .. context.project_id
    .. "/merge_requests/"
    .. context.mr_iid
    .. "/discussions"

  if suffix then
    endpoint = endpoint .. "/" .. suffix
  end

  return endpoint
end

local function fetch_discussions(context)
  return glab_json({ "glab", "api", discussion_endpoint(context), "--paginate" }, context.cwd)
end

local function fetch_discussions_async(context, callback)
  glab_json_async({ "glab", "api", discussion_endpoint(context), "--paginate" }, context.cwd, callback)
end

local function first_note(discussion)
  return discussion.notes and discussion.notes[1] or nil
end

local function first_positioned_note(discussion)
  for _, note in ipairs(discussion.notes or {}) do
    if note.position then
      return note
    end
  end

  return first_note(discussion)
end

local function is_resolved(discussion)
  for _, note in ipairs(discussion.notes or {}) do
    if note.resolvable then
      return note.resolved == true
    end
  end

  return false
end

local function is_resolvable(discussion)
  for _, note in ipairs(discussion.notes or {}) do
    if note.resolvable then
      return true
    end
  end

  return false
end

local function is_review_thread(discussion)
  return is_resolvable(discussion)
end

local function note_position(note)
  local position = note and note.position or nil
  if not position then
    return nil
  end

  local path = position.new_path or position.old_path
  local line = position.new_line or position.old_line
  if not path then
    return nil
  end

  if line then
    return path .. ":" .. line
  end

  return path
end

local function discussion_title(discussion)
  local note = first_positioned_note(discussion)
  local state = is_resolved(discussion) and "resolved" or "open"
  local target = note_position(note) or "MR"
  local count = #(discussion.notes or {})

  return ("[%s] %s (%d)"):format(state, target, count)
end

local function note_author(note)
  return note.author and note.author.username or "unknown"
end

local function wrapped_line(line, width)
  if #line <= width then
    return { line }
  end

  local lines = {}
  local remaining = line
  while #remaining > width do
    lines[#lines + 1] = remaining:sub(1, width)
    remaining = remaining:sub(width + 1)
  end
  if remaining ~= "" then
    lines[#lines + 1] = remaining
  end

  return lines
end

local function note_body_lines(body)
  local lines = {}
  for line in ((body or "") .. "\n"):gmatch("(.-)\n") do
    local text = trim(line:gsub("!%[[^%]]*%]%([^%)]+%)", ""))
    if text ~= "" then
      for _, wrapped in ipairs(wrapped_line(text, 110)) do
        lines[#lines + 1] = wrapped
      end
    end
  end

  return lines
end

local function image_links(body)
  local links = {}
  for alt, url in (body or ""):gmatch("!%[([^%]]*)%]%(([^%)]+)%)") do
    links[#links + 1] = {
      label = alt ~= "" and alt or "image",
      url = url,
    }
  end

  return links
end

local function image_filename(url)
  local path = url:gsub("%?.*$", "")
  local filename = path:match("([^/%s]+)$")
  return filename or url
end

local function upload_parts(url)
  local path = (url or ""):gsub("%?.*$", "")
  local secret, filename = path:match("/uploads/([%w]+)/(.*)$")
  if secret and filename and #secret == 32 then
    return secret, filename
  end

  secret, filename = path:match("/%-/project/%d+/uploads/([%w]+)/(.*)$")
  if secret and filename and #secret == 32 then
    return secret, filename
  end

  return nil, nil
end

local function cache_path_for_upload(secret, filename)
  local clean_filename = image_filename(filename):gsub("[^%w%._%-]", "_")
  return vim.fn.stdpath("cache") .. "/gitlab-review-images/" .. secret .. "-" .. clean_filename
end

local function download_upload_image(image, callback)
  if not panel.context then
    callback(nil, "No GitLab MR context available")
    return
  end

  local secret, filename = upload_parts(image.url)
  if not secret then
    callback(nil, "Image is not a GitLab markdown upload")
    return
  end

  local cache_path = cache_path_for_upload(secret, filename)
  if vim.fn.filereadable(cache_path) == 1 then
    callback(cache_path, nil)
    return
  end

  vim.fn.mkdir(vim.fn.fnamemodify(cache_path, ":h"), "p")
  local endpoint = "projects/" .. panel.context.project_id .. "/uploads/" .. secret .. "/" .. url_encode(filename)
  system_binary_async({ "glab", "api", endpoint }, panel.context.cwd, function(data, err)
    if not data then
      callback(nil, err)
      return
    end

    vim.fn.writefile(data, cache_path, "b")
    callback(cache_path, nil)
  end)
end

local function file_language(path)
  local ext = path and path:match("%.([%w_%-]+)$") or nil
  return ({
    js = "javascript",
    jsx = "jsx",
    ts = "typescript",
    tsx = "tsx",
    py = "python",
    lua = "lua",
    rb = "ruby",
    go = "go",
    rs = "rust",
    java = "java",
    kt = "kotlin",
    html = "html",
    css = "css",
    scss = "scss",
    json = "json",
    yml = "yaml",
    yaml = "yaml",
    md = "markdown",
    sh = "bash",
  })[ext] or ""
end

local function code_context(note)
  local position = note and note.position or nil
  if not position or not panel.context or not panel.context.cwd then
    return {}
  end

  local path = position.new_path or position.old_path
  local line = position.new_line or position.old_line
  if not path or not line then
    return {}
  end

  local absolute_path = panel.context.cwd .. "/" .. path
  if vim.fn.filereadable(absolute_path) ~= 1 then
    return {
      "```" .. file_language(path),
      "code context unavailable locally: " .. path,
      "```",
    }
  end

  local file_lines = vim.fn.readfile(absolute_path)
  local first_line = math.max(1, line - opts.context_lines)
  local last_line = math.min(#file_lines, line + opts.context_lines)
  local width = #tostring(last_line)
  local lines = { "```" .. file_language(path) }

  for lineno = first_line, last_line do
    local marker = lineno == line and ">" or " "
    lines[#lines + 1] = (("%s %" .. width .. "d | %s"):format(marker, lineno, file_lines[lineno]))
  end

  lines[#lines + 1] = "```"
  return lines
end

local function add_highlight(highlights, line, group)
  highlights[#highlights + 1] = { line = line, group = group }
end

local function panel_thread()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return panel.rows[row]
end

local function panel_image()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return panel.image_rows[row]
end

local function clear_terminal_images()
  local image_api_ok, image_api = pcall(require, "image")
  if image_api_ok then
    pcall(image_api.clear)
  end

  local helpers_ok, helpers = pcall(require, "image/backends/kitty/helpers")
  local codes_ok, codes = pcall(require, "image/backends/kitty/codes")
  if helpers_ok and codes_ok then
    pcall(helpers.write_graphics, {
      action = codes.control.action.delete,
      quiet = 2,
    })
    pcall(helpers.write_graphics, {
      action = codes.control.action.delete,
      display_delete = "a",
      quiet = 2,
    })
    pcall(helpers.write_graphics, {
      action = codes.control.action.delete,
      display_delete = "A",
      quiet = 2,
    })
    pcall(helpers.write_graphics, {
      action = codes.control.action.delete,
      display_delete = "Z",
      display_zindex = -1,
      quiet = 2,
    })
  end

  vim.cmd("redraw!")
end

local function close_image_preview()
  local preview = panel.image_preview
  panel.image_preview = nil
  if not preview then
    return
  end

  if preview.image then
    pcall(preview.image.clear, preview.image)
  end
  clear_terminal_images()
  if preview.win and vim.api.nvim_win_is_valid(preview.win) then
    pcall(vim.api.nvim_win_close, preview.win, true)
  end
  if preview.buf and vim.api.nvim_buf_is_valid(preview.buf) then
    pcall(vim.api.nvim_buf_delete, preview.buf, { force = true })
  end
  vim.defer_fn(function()
    clear_terminal_images()
  end, 30)
end

local function jump_to_thread(direction)
  if #panel.thread_rows == 0 then
    return
  end

  local current_row = vim.api.nvim_win_get_cursor(0)[1]
  local target = panel.thread_rows[1]

  if direction == "first" then
    target = panel.thread_rows[1]
  elseif direction == "last" then
    target = panel.thread_rows[#panel.thread_rows]
  elseif direction == "next" then
    for _, row in ipairs(panel.thread_rows) do
      if row > current_row then
        target = row
        break
      end
    end
  elseif direction == "previous" then
    target = panel.thread_rows[#panel.thread_rows]
    for index = #panel.thread_rows, 1, -1 do
      if panel.thread_rows[index] < current_row then
        target = panel.thread_rows[index]
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

local function set_panel_lines(lines)
  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(panel.buf, panel_ns, 0, -1)
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false
end

local function render_panel()
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    return
  end

  panel.rows = {}
  panel.image_rows = {}
  panel.thread_rows = {}
  close_image_preview()
  vim.api.nvim_buf_clear_namespace(panel.buf, panel_ns, 0, -1)

  local lines = {
    "GitLab MR !" .. panel.context.mr_iid .. " review threads",
    "]t next  [t prev  gt first  G last  r resolve  R reopen  a reply  o open  i preview image  O browser  f refresh  u all  q close",
    "",
  }
  local highlights = {
    { line = 1, group = "GitLabReviewHeader" },
    { line = 2, group = "GitLabReviewHelp" },
  }
  local visible_count = 0
  local total_review_count = 0
  local unresolved_count = 0

  for _, discussion in ipairs(panel.discussions) do
    if is_review_thread(discussion) then
      total_review_count = total_review_count + 1
    end

    local resolved = is_resolved(discussion)
    if is_review_thread(discussion) and not resolved then
      unresolved_count = unresolved_count + 1
    end

    if is_review_thread(discussion) and (panel.show_resolved or not resolved) then
      visible_count = visible_count + 1
      local note = first_positioned_note(discussion)
      local title_row = #lines + 1
      lines[#lines + 1] = discussion_title(discussion)
      panel.rows[title_row] = discussion
      panel.thread_rows[#panel.thread_rows + 1] = title_row
      add_highlight(highlights, title_row, resolved and "GitLabReviewResolved" or "GitLabReviewOpen")

      local location = note_position(note)
      if location then
        local path_row = #lines + 1
        lines[#lines + 1] = "  " .. location
        panel.rows[path_row] = discussion
        add_highlight(highlights, path_row, "GitLabReviewPath")
      end

      for _, context_line in ipairs(code_context(note)) do
        local code_row = #lines + 1
        lines[#lines + 1] = "  " .. context_line
        panel.rows[code_row] = discussion
        if context_line:match("^>") then
          add_highlight(highlights, code_row, "GitLabReviewCodeTarget")
        end
      end

      for _, note in ipairs(discussion.notes or {}) do
        if not note.system then
          local note_row = #lines + 1
          lines[#lines + 1] = ("  %s:"):format(note_author(note))
          panel.rows[note_row] = discussion
          add_highlight(highlights, note_row, "GitLabReviewAuthor")

          for _, body_line in ipairs(note_body_lines(note.body)) do
            local body_row = #lines + 1
            lines[#lines + 1] = ("    %s"):format(body_line)
            panel.rows[body_row] = discussion
          end

          for _, image in ipairs(image_links(note.body)) do
            local image_row = #lines + 1
            lines[#lines + 1] = ("    image: %s <%s>"):format(image_filename(image.url), image.url)
            panel.rows[image_row] = discussion
            panel.image_rows[image_row] = image
            add_highlight(highlights, image_row, "GitLabReviewImage")
          end
        end
      end

      lines[#lines + 1] = ""
    end
  end

  lines[1] = ("GitLab MR !%s review threads - %d unresolved, %d total"):format(
    panel.context.mr_iid,
    unresolved_count,
    total_review_count
  )

  if visible_count == 0 then
    lines[#lines + 1] = panel.show_resolved and "No review threads found." or "No unresolved review threads found."
  end

  set_panel_lines(lines)
  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(panel.buf, panel_ns, highlight.line - 1, 0, {
      end_line = highlight.line,
      hl_group = highlight.group,
      priority = 200,
    })
  end
end

local function refresh_panel()
  if not panel.context then
    return
  end

  set_panel_lines({
    "GitLab MR !" .. panel.context.mr_iid .. " review threads",
    "Loading review threads...",
  })

  fetch_discussions_async(panel.context, function(discussions, err)
    if not discussions then
      notify(err, vim.log.levels.ERROR)
      set_panel_lines({ "Failed to load GitLab review threads.", err or "" })
      return
    end

    panel.discussions = discussions
    render_panel()
  end)
end

local function close_panel()
  close_image_preview()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win = nil
end

local function update_discussion_resolved(discussion, resolved)
  if not is_resolvable(discussion) then
    notify("Thread is not resolvable", vim.log.levels.WARN)
    return
  end

  local endpoint = discussion_endpoint(panel.context, discussion.id)
  local payload = vim.json.encode({ resolved = resolved })
  notify(resolved and "Resolving thread..." or "Reopening thread...")
  system_async(
    { "glab", "api", endpoint, "-X", "PUT", "-H", "Content-Type: application/json", "--input", "-" },
    payload,
    panel.context.cwd,
    function(_, err)
      if err then
        notify(err, vim.log.levels.ERROR)
        return
      end

      notify(resolved and "Thread resolved" or "Thread reopened")
      refresh_panel()
    end
  )
end

local function reply_to_discussion(discussion, body)
  local endpoint = discussion_endpoint(panel.context, discussion.id .. "/notes")
  local payload = vim.json.encode({ body = body })
  notify("Adding reply...")
  system_async(
    { "glab", "api", endpoint, "-X", "POST", "-H", "Content-Type: application/json", "--input", "-" },
    payload,
    panel.context.cwd,
    function(_, err)
      if err then
        notify(err, vim.log.levels.ERROR)
        return
      end

      notify("Reply added")
      refresh_panel()
    end
  )
end

local function open_reply_popup(discussion)
  open_comment_popup({
    submit_title = " GitLab thread reply ",
    submit = function(body)
      reply_to_discussion(discussion, body)
    end,
  })
end

local function open_thread_location(discussion)
  local note = first_positioned_note(discussion)
  local position = note and note.position or nil
  if not position then
    notify("Thread has no diff position", vim.log.levels.WARN)
    return
  end

  local path = position.new_path or position.old_path
  local line = position.new_line or position.old_line
  if not path then
    notify("Thread has no file path", vim.log.levels.WARN)
    return
  end

  local absolute_path = panel.context and panel.context.cwd and (panel.context.cwd .. "/" .. path) or path
  if vim.fn.filereadable(absolute_path) ~= 1 then
    notify("File is not available locally: " .. path, vim.log.levels.WARN)
    return
  end

  close_panel()
  vim.cmd("edit " .. vim.fn.fnameescape(absolute_path))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
    vim.cmd("normal! zz")
  end
end

local function open_image_preview_window(title)
  close_image_preview()

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local width = math.max(40, math.min(opts.image_width, editor_width - 6))
  local height = math.max(16, math.min(opts.image_height, editor_height - 6))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((editor_width - width) / 2),
    row = math.floor((editor_height - height) / 2),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "gitlab-review-image"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({ "" }, height))
  vim.bo[buf].modifiable = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].signcolumn = "no"

  panel.image_preview = { buf = buf, win = win, image = nil }

  vim.keymap.set("n", "q", close_image_preview, { buffer = buf, desc = "Close GitLab review image preview" })
  vim.keymap.set("n", "<Esc>", close_image_preview, { buffer = buf, desc = "Close GitLab review image preview" })

  local group = vim.api.nvim_create_augroup("GitLabReviewImagePreview", { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    group = group,
    buffer = buf,
    callback = close_image_preview,
  })
  vim.api.nvim_create_autocmd({ "FocusLost", "TabLeave" }, {
    group = group,
    callback = function()
      if panel.image_preview and panel.image_preview.buf == buf then
        close_image_preview()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = close_image_preview,
  })

  return buf, win, width, height
end

local function open_image(image)
  if not image then
    notify("No image on this row", vim.log.levels.WARN)
    return
  end

  local ok, image_api = pcall(require, "image")
  if not ok then
    notify("image.nvim is not available yet. Run :Lazy sync, then restart Neovim.", vim.log.levels.WARN)
    return
  end

  clear_terminal_images()
  local buf, win, width, height = open_image_preview_window(" GitLab image ")
  local function preview_is_open()
    return panel.image_preview
      and panel.image_preview.buf == buf
      and vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_win_is_valid(win)
  end

  local function render_file(path)
    if not preview_is_open() then
      return
    end

    local rendered = image_api.from_file(path, {
      buffer = buf,
      window = win,
      x = 0,
      y = 0,
      width = width,
      height = height,
    })

    if not rendered then
      close_image_preview()
      notify("Could not render image. Use O to open it externally.", vim.log.levels.ERROR)
      return
    end

    if panel.image_preview and panel.image_preview.buf == buf then
      panel.image_preview.image = rendered
      rendered:render()
    end
  end

  local function render_url()
    image_api.from_url(image.url, {
      buffer = buf,
      window = win,
      x = 0,
      y = 0,
      width = width,
      height = height,
    }, function(rendered)
      vim.schedule(function()
        if not rendered then
          close_image_preview()
          notify("Could not render image. Use O to open it externally.", vim.log.levels.ERROR)
          return
        end

        if preview_is_open() then
          panel.image_preview.image = rendered
          rendered:render()
        else
          pcall(rendered.clear, rendered)
        end
      end)
    end)
  end

  if upload_parts(image.url) then
    download_upload_image(image, function(path, err)
      if not path then
        notify(err or "Could not download GitLab upload. Trying direct URL...", vim.log.levels.WARN)
        render_url()
        return
      end

      render_file(path)
    end)
    return
  end

  render_url()
end

local function open_image_external(image)
  if not image then
    notify("No image on this row", vim.log.levels.WARN)
    return
  end

  local opener = vim.fn.has("mac") == 1 and "open" or "xdg-open"
  system_async({ opener, image.url }, nil, nil, function(_, err)
    if err then
      notify(err, vim.log.levels.ERROR)
    end
  end)
end

local function set_panel_keymaps()
  vim.keymap.set("n", "q", close_panel, { buffer = panel.buf, desc = "Close GitLab review threads" })
  vim.keymap.set("n", "f", refresh_panel, { buffer = panel.buf, desc = "Refresh GitLab review threads" })
  vim.keymap.set("n", "u", function()
    panel.show_resolved = not panel.show_resolved
    render_panel()
  end, { buffer = panel.buf, desc = "Toggle resolved GitLab review threads" })
  vim.keymap.set("n", "r", function()
    local discussion = panel_thread()
    if discussion then
      update_discussion_resolved(discussion, true)
    end
  end, { buffer = panel.buf, desc = "Resolve GitLab review thread" })
  vim.keymap.set("n", "R", function()
    local discussion = panel_thread()
    if discussion then
      update_discussion_resolved(discussion, false)
    end
  end, { buffer = panel.buf, desc = "Reopen GitLab review thread" })
  vim.keymap.set("n", "a", function()
    local discussion = panel_thread()
    if discussion then
      open_reply_popup(discussion)
    end
  end, { buffer = panel.buf, desc = "Reply to GitLab review thread" })
  vim.keymap.set("n", "o", function()
    local discussion = panel_thread()
    if discussion then
      open_thread_location(discussion)
    end
  end, { buffer = panel.buf, desc = "Open GitLab review thread location" })
  vim.keymap.set("n", "i", function()
    open_image(panel_image())
  end, { buffer = panel.buf, desc = "Render GitLab review image" })
  vim.keymap.set("n", "O", function()
    open_image_external(panel_image())
  end, { buffer = panel.buf, desc = "Open GitLab review image externally" })
  vim.keymap.set("n", "]t", function()
    jump_to_thread("next")
  end, { buffer = panel.buf, desc = "Next GitLab review thread" })
  vim.keymap.set("n", "[t", function()
    jump_to_thread("previous")
  end, { buffer = panel.buf, desc = "Previous GitLab review thread" })
  vim.keymap.set("n", "gt", function()
    jump_to_thread("first")
  end, { buffer = panel.buf, desc = "First GitLab review thread" })
  vim.keymap.set("n", "G", function()
    jump_to_thread("last")
  end, { buffer = panel.buf, desc = "Last GitLab review thread" })
end

local function ensure_panel()
  if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then
    return
  end

  panel.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[panel.buf].buftype = "nofile"
  vim.bo[panel.buf].bufhidden = "hide"
  vim.bo[panel.buf].filetype = "markdown"
  set_panel_keymaps()

  local group = vim.api.nvim_create_augroup("GitLabReviewPanelImages", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = panel.buf,
    callback = close_image_preview,
  })
end

local function open_panel_window()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_set_current_win(panel.win)
    return
  end

  vim.cmd("botright 18split")
  panel.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(panel.win, panel.buf)
  vim.wo[panel.win].wrap = false
end

local function post_comment(context, body, draft)
  local endpoint = "projects/" .. context.project_id .. "/merge_requests/" .. context.mr_iid

  if draft then
    endpoint = endpoint .. "/draft_notes"
  else
    endpoint = endpoint .. "/discussions"
  end

  local args = { "glab", "api", endpoint, "-X", "POST", "-H", "Content-Type: application/json", "--input", "-" }
  local payload = {
    position = context.position,
  }

  if draft then
    payload.note = body
  else
    payload.body = body
  end

  notify(draft and "Creating draft note..." or "Posting MR comment...")
  system_async(args, vim.json.encode(payload), context.cwd, function(_, err)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end

    notify(draft and "Draft note created" or "MR comment posted")
  end)
end

open_comment_popup = function(context, draft)
  local width = math.min(88, math.floor(vim.o.columns * 0.8))
  local height = math.min(14, math.floor(vim.o.lines * 0.35))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = context.submit_title or (draft and " GitLab draft note " or " GitLab MR comment "),
    title_pos = "center",
  })

  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[win].wrap = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

  local function close()
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local body = trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    if body == "" then
      notify("Comment is empty", vim.log.levels.WARN)
      return
    end

    close()
    if context.submit then
      context.submit(body)
    else
      post_comment(context, body, draft)
    end
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "Submit GitLab comment" })
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close GitLab comment" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close GitLab comment" })
  vim.cmd("startinsert")
end

function M.comment(draft, visual)
  local context, err = build_position(visual)
  if not context then
    notify(err, vim.log.levels.ERROR)
    return
  end

  open_comment_popup(context, draft == nil and opts.draft or draft)
end

function M.publish_drafts()
  local view = current_view()
  local cwd = view and view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel or nil
  local project_id, project_err = current_project_id(cwd)
  if not project_id then
    notify(project_err, vim.log.levels.ERROR)
    return
  end

  local mr_iid, mr_err = current_merge_request(project_id, cwd)
  if not mr_iid then
    notify(mr_err, vim.log.levels.ERROR)
    return
  end

  local endpoint = "projects/" .. project_id .. "/merge_requests/" .. mr_iid .. "/draft_notes/bulk_publish"
  notify("Publishing GitLab draft notes...")
  system_async({ "glab", "api", endpoint, "-X", "POST" }, nil, cwd, function(_, err)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end

    notify("Published GitLab draft notes")
  end)
end

function M.toggle_threads()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    close_panel()
    return
  end

  ensure_panel()
  open_panel_window()
  set_panel_lines({ "GitLab MR review threads", "Finding current merge request..." })

  mr_context_async(function(context, err)
    if not context then
      notify(err, vim.log.levels.ERROR)
      set_panel_lines({ "Failed to find current merge request.", err or "" })
      return
    end

    panel.context = context
    refresh_panel()
  end)
end

function M.setup(config)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), config or {})
  setup_highlights()

  vim.api.nvim_create_user_command("GitLabReviewComment", function(command)
    M.comment(false, command.range > 0)
  end, { range = true, force = true })

  vim.api.nvim_create_user_command("GitLabReviewDraft", function(command)
    M.comment(true, command.range > 0)
  end, { range = true, force = true })

  vim.api.nvim_create_user_command("GitLabReviewPublishDrafts", M.publish_drafts, { force = true })
  vim.api.nvim_create_user_command("GitLabReviewThreads", M.toggle_threads, { force = true })
end

return M
