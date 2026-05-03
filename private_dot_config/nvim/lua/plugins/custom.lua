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
    },
    init = function()
      require("diffview_reviewed").setup()
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

  -- snacks picker: show hidden files in <leader>ff
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          files = {
            hidden = true,
          },
        },
      },
    },
  },

  -- show gitignored files in neo-tree
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      filesystem = {
        filtered_items = {
          visible = true,
          hide_gitignored = false,
        },
      },
    },
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

  -- vim motion practice game
  {
    "ThePrimeagen/vim-be-good",
    cmd = "VimBeGood",
    keys = {
      { "<leader>vg", "<cmd>VimBeGood<cr>", desc = "Vim Be Good" },
    },
  },
}
