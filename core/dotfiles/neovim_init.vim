" Adapt to filetype. Required for NERD commenter
filetype plugin on
call plug#begin()
" The default plugin directory is '~/.vim/plugged'
source ~/.config/nvim/neovim_plug_init.vim
" Allow project-level settings overrides
set exrc
call plug#end()
" Coc bindings
inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"
" Leap remapping of s S and gs
lua require('leap').create_default_mappings()
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
