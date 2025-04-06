" Autoload functions for chat.vim

" Get API Key from settings (Internal function)
function! chat#_GetApiKey()
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
  let api_key = chat#_GetApiKey()
  if empty(api_key)
    echoerr "OpenRouter API Key not configured"
    return
  endif

  let model = get(g:, 'chat_vim_model', 'google/gemini-2.5-pro-exp-03-25:free')
  let cmd = 'curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" ' .
        \ '-H "Authorization: Bearer ' . api_key . '" ' .
        \ '-H "Content-Type: application/json" ' .
        \ '-d ''{"model": "' . model . '", ' .
        \ '"messages": [{"role": "user", "content": "' . escape(a:message, '"') . '"}]}''' " Escape message content

  let response = system(cmd)
  let json = json_decode(response)
  if type(json) == v:t_dict
    call chat#ShowResponse(json)
  else
    echoerr "Failed to decode API response: " . response
  endif
  return json
endfunction

" Get selected text in Visual mode (Internal function)
function! chat#_GetVisualSelection()
  try
    let [lnum1, col1] = getpos("'<")[1:2]
    let [lnum2, col2] = getpos("'>")[1:2]
    let lines = getline(lnum1, lnum2)
    if len(lines) == 0
      return ''
    endif
    " Handle visual line selection correctly
    if col1 == 1 && col2 ==# 'max'
        " Visual line selection, keep full lines
    else
        let lines[-1] = lines[-1][:col2 - 1]
        let lines[0] = lines[0][col1 - 1:]
    endif
    return join(lines, "\n")
  catch /E20:/ " Mark not set
    return ''
  endtry
endfunction

" Send selected text to API
function! chat#SendSelection() range
  let selected_text = chat#_GetVisualSelection()
  if empty(selected_text)
    echoerr "No text selected"
    return
  endif
  call chat#SendMessage(selected_text)
endfunction

" Display response in preview window
function! chat#ShowResponse(response)
  if type(a:response) != v:t_dict
    echoerr "Invalid API response structure: " . string(a:response)
    return
  endif
  if !has_key(a:response, 'choices') || empty(a:response.choices) || !has_key(a:response.choices[0], 'message') || !has_key(a:response.choices[0].message, 'content')
     echoerr "Invalid API response content: " . string(a:response)
     return
  endif


  let content = a:response.choices[0].message.content
  " Ensure preview window exists or create it
  if !exists('g:chat_preview_winid') || !win_gotoid(g:chat_preview_winid)
      silent! pedit ChatResponse
      let g:chat_preview_winid = win_getid()
  endif
  " Switch to preview window
  call win_gotoid(g:chat_preview_winid)
  setlocal modifiable           " Allow modification
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
  %delete _                     " Clear buffer content
  call setline(1, split(content, '\n'))
  setlocal nomodifiable         " Prevent accidental modification
  normal! gg                    " Go to the top
  wincmd p                      " Return to previous window
endfunction
