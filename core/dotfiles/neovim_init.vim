" Adapt to filetype. Required for NERD commenter
filetype plugin on
call plug#begin()
" The default plugin directory is '~/.vim/plugged'
source ~/.config/nvim/neovim_plug_init.vim
" Allow project-level settings overrides
set exrc
call plug#end()
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
