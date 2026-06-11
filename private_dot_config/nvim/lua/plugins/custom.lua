return {
  -- markdown preview in chrome
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreview<cr>", desc = "Markdown Preview" },
    },
    init = function()
      vim.g.mkdp_browser = "Google Chrome"
      vim.g.mkdp_filetypes = { "markdown" }
    end,
  },

  -- colorscheme (matches lazyvim.org/plugins/colorscheme pattern)
  { "rebelot/kanagawa.nvim" },
  { "LazyVim/LazyVim", opts = { colorscheme = "kanagawa-wave" } },

  -- diffview
  {
    "sindrets/diffview.nvim",
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff view" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gm", "<cmd>DiffviewOpen origin/develop...HEAD<cr>", desc = "MR diff vs develop" },
      { "<leader>gmr", function() require("diffview_reviewed").reopen_mr_diff() end, desc = "Reopen MR diff" },
      { "<leader>gc", function() require("gitlab_review").comment(false) end, mode = "n", desc = "Comment on MR diff" },
      { "<leader>gc", function() require("gitlab_review").comment(false, true) end, mode = "x", desc = "Comment on MR diff" },
      { "<leader>gC", function() require("gitlab_review").comment(true) end, mode = "n", desc = "Draft MR diff comment" },
      { "<leader>gC", function() require("gitlab_review").comment(true, true) end, mode = "x", desc = "Draft MR diff comment" },
      { "<leader>gP", function() require("gitlab_review").publish_drafts() end, desc = "Publish MR draft comments" },
      { "<leader>gt", function() require("gitlab_review").toggle_threads() end, desc = "Toggle MR review threads" },
    },
    init = function()
      require("diffview_reviewed").setup()
      require("gitlab_review").setup()
    end,
    opts = {
      enhanced_diff_hl = true,
      use_icons = true,
      icons = {
        folder_closed = "",
        folder_open = "",
      },
      signs = {
        fold_closed = "",
        fold_open = "",
        done = "✓",
      },
      file_panel = {
        listing_style = "tree",
        tree_options = {
          flatten_dirs = true,
          folder_statuses = "only_folded",
        },
        win_config = {
          position = "left",
          width = 35,
        },
      },
    },
  },

  -- terminal image rendering
  {
    "3rd/image.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      window_overlap_clear_enabled = true,
      editor_only_render_when_focused = true,
      tmux_show_only_in_active_window = true,
      integrations = {
        markdown = { enabled = false },
        neorg = { enabled = false },
        html = { enabled = false },
        css = { enabled = false },
      },
    },
  },

  -- telescope: ignore noise
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        file_ignore_patterns = {
          "node_modules",
          "__pycache__",
          "%.git/",
          "%.pyc",
          "migrations/",
        },
      },
      pickers = {
        find_files = {
          hidden = true,
          no_ignore = true,
        },
      },
    },
  },

  -- claude code at bottom
  {
    "coder/claudecode.nvim",
    opts = {
      terminal = {
        split_side = "bottom",
      },
    },
  },

  -- opencode: native Neovim integration
  {
    "nickjvandyke/opencode.nvim",
    version = "*",
    dependencies = {
      {
        "folke/snacks.nvim",
        optional = true,
        opts = {
          input = {},
          picker = {
            actions = {
              opencode_send = function(...) return require("opencode").snacks_picker_send(...) end,
            },
            win = {
              input = {
                keys = {
                  ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
                },
              },
            },
          },
        },
      },
    },
    config = function()
      vim.g.opencode_opts = {}
      vim.o.autoread = true

      vim.keymap.set({ "n", "t" }, "<leader>oo", function()
        require("opencode").toggle()
      end, { desc = "Toggle opencode" })
      vim.keymap.set({ "n", "x" }, "<leader>oa", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "Ask opencode" })
      vim.keymap.set({ "n", "x" }, "<leader>os", function()
        require("opencode").select()
      end, { desc = "Select opencode action" })
      vim.keymap.set("n", "<leader>on", function()
        require("opencode").command("session.new")
      end, { desc = "New opencode session" })
      vim.keymap.set("n", "<leader>ol", function()
        require("opencode").command("session.select")
      end, { desc = "Select opencode session" })
      vim.keymap.set("n", "<leader>oq", function()
        require("opencode").command("session.interrupt")
      end, { desc = "Interrupt opencode" })
      vim.keymap.set("n", "<S-C-u>", function()
        require("opencode").command("session.half.page.up")
      end, { desc = "Scroll opencode up" })
      vim.keymap.set("n", "<S-C-d>", function()
        require("opencode").command("session.half.page.down")
      end, { desc = "Scroll opencode down" })
      vim.keymap.set({ "n", "x" }, "go", function()
        return require("opencode").operator("@this ")
      end, { desc = "Add range to opencode", expr = true })
      vim.keymap.set("n", "goo", function()
        return require("opencode").operator("@this ") .. "_"
      end, { desc = "Add line to opencode", expr = true })
    end,
  },

  -- codernvim: drive the codex/cursor CLIs headlessly for inline AI edits.
  -- Loaded from the local dev copy in the data dir.
  {
    dir = vim.fn.stdpath("data") .. "/codernvim",
    name = "codernvim",
    cmd = { "Codernvim", "CodernvimEdit", "CodernvimAsk", "CodernvimChat" },
    -- Eager keymaps (init runs at startup) so visual-range commands get the
    -- range natively; the plugin still lazy-loads on first use.
    init = function()
      vim.keymap.set("x", "<leader>ce", ":CodernvimEdit<cr>", {
        silent = true, desc = "AI edit selection (codernvim)",
      })
      vim.keymap.set("n", "<leader>cc", "<cmd>CodernvimChat<cr>", {
        silent = true, desc = "Toggle codernvim chat",
      })
      vim.keymap.set("n", "<leader>ck", "<cmd>CodernvimAsk<cr>", {
        silent = true, desc = "Ask codernvim (codebase Q&A)",
      })
    end,
    opts = {
      backend = "cursor", -- `:Codernvim config` to switch to "codex"
      backends = {
        cursor = { model = "composer-2.5" },
      },
      -- blue (new) / red (old): the blue/red axis gives real hue separation
      -- under red-green colour vision; the +/- gutter signs carry meaning too.
      colors = {
        add = { fg = "#82b1ff", bg = "#0e2240" }, -- new: blue
        delete = { bg = "#3a1518" }, -- old: red
      },
      inline = {
        keymaps = {
          -- buffer-local, active only while reviewing a proposed diff
          accept = "<leader>cy", -- accept hunk (yes)
          reject = "<leader>cn", -- reject hunk (no)
          accept_all = "<leader>cY",
          reject_all = "<leader>cN",
          next = "]c",
          prev = "[c",
        },
      },
    },
    config = function(_, opts)
      require("codernvim").setup(opts)
    end,
  },

  -- snacks: show hidden files in <leader>ff; disable smooth-scroll animation.
  -- The per-scroll repaint animation is the dominant cause of laggy scrolling
  -- inside tmux: each animation frame is a full-viewport redraw that the
  -- multiplexer must re-diff and re-emit before Ghostty ever renders it.
  {
    "folke/snacks.nvim",
    opts = {
      scroll = { enabled = false },
      picker = {
        sources = {
          files = {
            hidden = true,
          },
        },
      },
    },
  },

  -- neo-tree: show gitignored files + agent <leader>ap/<leader>aP mappings
  -- so you can hover a file and append @<path> to claude/codex input box
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = function(_, opts)
      opts.filesystem = opts.filesystem or {}
      opts.filesystem.filtered_items = vim.tbl_deep_extend(
        "force",
        opts.filesystem.filtered_items or {},
        { visible = true, hide_gitignored = false }
      )

      opts.filesystem.window = opts.filesystem.window or {}
      opts.filesystem.window.mappings = opts.filesystem.window.mappings or {}

      local function send_to(agent)
        return function(state)
          local node = state.tree:get_node()
          if node and node.type == "file" then
            require("agent").send_path(agent, node.path)
          else
            vim.notify("agent: cursor is not on a file", vim.log.levels.WARN)
          end
        end
      end

      opts.filesystem.window.mappings["<leader>ap"] = send_to("claude")
      opts.filesystem.window.mappings["<leader>aP"] = send_to("codex")
    end,
  },

  -- seamless tmux/nvim pane navigation
  {
    "christoomey/vim-tmux-navigator",
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>" },
    },
  },

  -- pyright: only type-check OPEN files, never the whole workspace.
  -- Whole-workspace mode makes pyright re-index the entire wasteos tree
  -- (multiplied across every git worktree) and pin a CPU core forever.
  -- basedpyright key is set too so the cap survives a LazyVim default flip.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = { analysis = { diagnosticMode = "openFilesOnly" } },
          },
        },
        basedpyright = {
          settings = {
            basedpyright = { analysis = { diagnosticMode = "openFilesOnly" } },
          },
        },
      },
    },
  },
}
