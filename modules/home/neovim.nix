{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # None of the plugins above need a Ruby/Python3 host -- avoid pulling
    # those in as a Neovim wrapper dependency.
    withRuby = false;
    withPython3 = false;

    # Deliberately no extraPackages for language LSPs/toolchains here --
    # those come from each project's own devShell (see the flake
    # `templates` output and modules/home/dev.nix), so a project only
    # pulls in exactly the languages it actually uses.
    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      blink-cmp
      (nvim-treesitter.withPlugins (p: [
        p.c
        p.rust
        p.python
        p.sql
        p.javascript
        p.typescript
        p.tsx
        p.bash
        p.lua
        p.vim
        p.vimdoc
        p.markdown
      ]))
      telescope-nvim
      telescope-fzf-native-nvim
      gitsigns-nvim
      lualine-nvim
      nvim-web-devicons
      tokyonight-nvim
    ];

    initLua = ''
      vim.g.mapleader = " "
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.smartindent = true
      vim.opt.termguicolors = true
      vim.opt.signcolumn = "yes"
      vim.opt.updatetime = 250
      vim.opt.ignorecase = true
      vim.opt.smartcase = true

      vim.cmd.colorscheme("tokyonight")

      -- Treesitter highlighting/folding/indent: nvim-treesitter's "main"
      -- branch (what this repo's pinned nixpkgs ships) dropped the old
      -- configs.setup{highlight={enable=true}} API entirely. Parsers
      -- themselves are baked in via `withPlugins` above (no :TSInstall
      -- needed, ever) -- this just turns on the Neovim-builtin treesitter
      -- features for the filetypes we actually work in.
      local ts_filetypes = {
        "c", "rust", "python", "sql",
        "javascript", "typescript", "typescriptreact",
        "bash", "lua", "vim", "help", "markdown",
      }
      vim.api.nvim_create_autocmd("FileType", {
        pattern = ts_filetypes,
        callback = function()
          vim.treesitter.start()
          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo[0][0].foldmethod = "expr"
          vim.wo[0][0].foldenable = false
        end,
      })

      -- Completion (blink.cmp). Works out of the box; this just wires its
      -- capabilities into every LSP client below.
      require("blink.cmp").setup({
        keymap = { preset = "default" },
        appearance = { nerd_font_variant = "mono" },
        completion = { documentation = { auto_show = true } },
      })

      -- LSP servers. Binaries are intentionally referenced by name only
      -- (never a nix store path) -- they resolve via PATH from whichever
      -- per-project devShell direnv has activated (see flake `templates`
      -- output). If no devShell is active for a given language, that one
      -- LSP just won't start; everything else in this config still works.
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      vim.lsp.enable({
        "rust_analyzer",   -- rust
        "basedpyright",    -- python
        "ruff",            -- python (lint/format via LSP actions)
        "clangd",          -- c
        "sqls",            -- sql
        "ts_ls",           -- javascript/typescript
        "eslint",          -- javascript/typescript
      })

      vim.diagnostic.config({ virtual_text = true, severity_sort = true })

      -- Telescope
      require("telescope").setup({})
      require("telescope").load_extension("fzf")
      local tb = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", tb.find_files, {})
      vim.keymap.set("n", "<leader>fg", tb.live_grep, {})
      vim.keymap.set("n", "<leader>fb", tb.buffers, {})
      vim.keymap.set("n", "gd", tb.lsp_definitions, {})
      vim.keymap.set("n", "gr", tb.lsp_references, {})

      -- Gitsigns, lualine
      require("gitsigns").setup({})
      require("lualine").setup({ options = { theme = "tokyonight" } })

      -- LSP keymaps
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufnr = args.buf
          local opts = { buffer = bufnr }
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "<leader>f", function()
            vim.lsp.buf.format({ async = true })
          end, opts)
        end,
      })
    '';
  };
}
