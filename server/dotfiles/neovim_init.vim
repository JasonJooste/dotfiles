lua << EOF
vim.pack.add({
  -- Coc for npm plugins
  { src = 'https://github.com/neoclide/coc.nvim', version = 'release' },
  -- For nextflow syntax highlighting
  'https://github.com/lukegoodsell/nextflow-vim',
}, { confirm = false })
EOF
" Coc bindings
inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"
