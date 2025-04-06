" chat.vim - OpenRouter API integration for Vim

if exists('g:loaded_chat_vim')
  finish
endif
let g:loaded_chat_vim = 1

" Get API Key from settings
function! s:GetApiKey()
  " Try VSCode settings first
  if exists('g:vscode_settings') && has_key(g:vscode_settings, 'chatVim') 
    \ && has_key(g:vscode_settings.chatVim, 'openRouterApiKey')
    return g:vscode_settings.chatVim.openRouterApiKey
  endif

  " Fall back to Vim variable
  if exists('g:chat_vim_api_key')
    return g:chat_vim_api_key
  endif

  return ''
endfunction

" Basic API call function
function! chat#SendMessage(message)
  let api_key = s:GetApiKey()
  if empty(api_key)
    echoerr "OpenRouter API Key not configured"
    return
  endif

  let model = get(g:, 'chat_vim_model', 'google/gemini-2.5-pro-exp-03-25:free')
  let cmd = 'curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" ' .
        \ '-H "Authorization: Bearer ' . api_key . '" ' .
        \ '-H "Content-Type: application/json" ' .
        \ '-d ''{"model": "' . model . '", ' .
        \ '"messages": [{"role": "user", "content": "' . a:message . '"}]}'''

  let response = system(cmd)
  let json = json_decode(response)
  if type(json) == v:t_dict
    call chat#ShowResponse(json)
  else
    echoerr "Failed to decode API response"
  endif
  return json
endfunction

" Tab completion
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"

" Get selected text in Visual mode
function! s:GetVisualSelection()
  try
    let [lnum1, col1] = getpos("'<")[1:2]
    let [lnum2, col2] = getpos("'>")[1:2]
    let lines = getline(lnum1, lnum2)
    if len(lines) == 0
      return ''
    endif
    let lines[-1] = lines[-1][:col2 - 1]
    let lines[0] = lines[0][col1 - 1:]
    return join(lines, "\n")
  catch /E20:/ " Mark not set
    return ''
  endtry
endfunction

" Send selected text to API
function! chat#SendSelection() range
  let selected_text = s:GetVisualSelection()
  if empty(selected_text)
    echoerr "No text selected"
    return
  endif
  call chat#SendMessage(selected_text)
endfunction

" Chat command (Normal mode)
command! -nargs=1 Chat call chat#SendMessage(<q-args>)

" Chat command (Visual mode)
vnoremap <silent> <Plug>(ChatSelection) :<C-u>call chat#SendSelection()<CR>
" Default mapping for Visual mode (e.g., <leader>c)
" You can change this mapping in your .vimrc
vmap <Leader>c <Plug>(ChatSelection)

" Display response in preview window
function! chat#ShowResponse(response)
  if type(a:response) != v:t_dict || !has_key(a:response, 'choices')
    echoerr "Invalid API response"
    return
  endif

  let content = a:response.choices[0].message.content
  silent! pedit ChatResponse
  wincmd P
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
  call setline(1, split(content, '\n'))
  wincmd p
endfunction
