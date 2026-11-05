lua << EOF
vim.pack.add({
  -- Coc for npm plugins
  { src = 'https://github.com/neoclide/coc.nvim', version = 'release' },
  -- For nextflow syntax highlighting
  'https://github.com/lukegoodsell/nextflow-vim',
  -- :Glow for a rendered markdown preview (needs the glow binary)
  'https://github.com/ellisonleao/glow.nvim',
}, { confirm = false })
-- Full screen: the default 100x100 caps would otherwise limit the window size
require('glow').setup({ border = 'none', width_ratio = 1.0, height_ratio = 1.0, width = 10000, height = 10000 })
EOF
" Coc bindings
inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"
