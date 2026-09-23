" Adapt to filetype. Required for NERD commenter
filetype plugin on
" Plugins, via neovim's built-in manager (needs nvim 0.12+). Missing ones are installed on startup.
" Later tiers append their own vim.pack.add() calls to this file.
lua << EOF
vim.pack.add({
  -- Leap
  'https://codeberg.org/andyg/leap.nvim',
  -- Improve commenting
  'https://github.com/preservim/nerdcommenter',
  -- Airline status bar for a bit more info
  'https://github.com/vim-airline/vim-airline',
  -- Git integration
  'https://github.com/tpope/vim-fugitive',
  -- jiangmiao/auto-pairs - could be interesting later for bracket pairs
  -- For vim/tmux integration
  'https://github.com/preservim/vimux',
}, { confirm = false })
EOF
" Allow project-level settings overrides
set exrc
" Leap remapping of s S gs and text objects (this fork has no
" create_default_mappings() - it lazy-loads itself, so these are just keymaps)
lua vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(leap)')
lua vim.keymap.set('n', 'S', '<Plug>(leap-from-window)')
lua vim.keymap.set({ 'n', 'x', 'o' }, 'gs', '<Plug>(leap-visit)')
lua vim.keymap.set({ 'x', 'o' }, 'ar', '<Plug>(leap-visit-text-object)')
lua vim.keymap.set({ 'x', 'o' }, 'ir', '<Plug>(leap-visit-inner-text-object)')
" copy line to clipboard
nnoremap <C-y> "+yy
vnoremap <C-y> "+y
" vimux run commands
nnoremap <C-p> :VimuxPromptCommand<CR>
nnoremap <C-l> :VimuxRunLastCommand<CR>
nnoremap <C-w> :call VimuxZoomRunner()<CR>
" Remap jinja python templates to just have the python filetype
autocmd BufNewFile,BufRead *.py.j2 set filetype=python
" Set the spellchecker
autocmd FileType markdown,text setlocal spell spelllang=en_au
