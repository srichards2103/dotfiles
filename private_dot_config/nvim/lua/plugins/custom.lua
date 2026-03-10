return {
  -- colorscheme (matches lazyvim.org/plugins/colorscheme pattern)
  { "navarasu/onedark.nvim", opts = { style = "dark" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "onedark" } },

  -- diffview
  {
    "sindrets/diffview.nvim",
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diff view" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
    },
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
}
