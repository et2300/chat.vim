" chat.vim - OpenRouter API integration for Vim (Plugin entry point)

if exists('g:loaded_chat_vim')
  finish
endif
let g:loaded_chat_vim = 1

" Chat command (Normal mode)
" Calls autoloaded function chat#SendMessage
command! -nargs=1 Chat call chat#SendMessage(<q-args>)

" Chat command (Visual mode)
" Calls autoloaded function chat#SendSelection
vnoremap <silent> <Plug>(ChatSelection) :<C-u>call chat#SendSelection()<CR>
" Default mapping for Visual mode (e.g., <leader>c)
" You can change this mapping in your .vimrc
if !hasmapto('<Plug>(ChatSelection)', 'v')
  vmap <Leader>c <Plug>(ChatSelection)
endif

" Command to open the TUI interface
command! ChatTUI call chat#tui#Open()

" Tab completion mapping
" If popup menu is visible, cycle through it (<C-n>)
" Otherwise, call the API completion function chat#CompleteCode()
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : chat#CompleteCode()
