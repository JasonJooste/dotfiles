lua << EOF
vim.pack.add({
  -- For liquid syntax highlighting
  'https://github.com/tpope/vim-liquid',
  -- Track file changes for nice visual replay
  'https://github.com/jasonjooste/replayvim.nvim',
}, { confirm = false })
EOF
