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

" Internal function to make the API call
function! chat#_MakeApiCall(payload)
  let api_key = chat#_GetApiKey()
  if empty(api_key)
    echoerr "OpenRouter API Key not configured"
    return {'error': 'API Key not configured'}
  endif

  let model = get(g:, 'chat_vim_model', 'google/gemini-2.5-pro-exp-03-25:free')
  let payload_dict = a:payload
  let payload_dict['model'] = model " Add model to the payload

  let cmd = 'curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" ' .
        \ '-H "Authorization: Bearer ' . api_key . '" ' .
        \ '-H "Content-Type: application/json" ' .
        \ '-d ''' . json_encode(payload_dict) . ''''

  let response_str = system(cmd)
  let json = json_decode(response_str)

  if type(json) != v:t_dict
    return {'error': 'Failed to decode API response: ' . response_str}
  endif
  if has_key(json, 'error')
     return {'error': 'API Error: ' . json.error.message}
  endif
   if !has_key(json, 'choices') || empty(json.choices) || !has_key(json.choices[0], 'message') || !has_key(json.choices[0].message, 'content')
     return {'error': 'Invalid API response content: ' . string(json)}
  endif

  return json " Return the full parsed JSON response
endfunction


" Basic API call function for Chat command
function! chat#SendMessage(message)
  let payload = {'messages': [{'role': 'user', 'content': a:message}]}
  let json = chat#_MakeApiCall(payload)

  if has_key(json, 'error')
    echoerr json.error
  else
    call chat#ShowResponse(json) " Show response only for chat
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

" Send selected text to API (for Visual mode command)
function! chat#SendSelection() range
  let selected_text = chat#_GetVisualSelection()
  if empty(selected_text)
    echoerr "No text selected"
    return
  endif
  call chat#SendMessage(selected_text) " Use SendMessage to show response
endfunction

" Display response in preview window
function! chat#ShowResponse(response)
  " Error checking already done in _MakeApiCall or SendMessage
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

" --- Code Completion ---

" Function called by Tab mapping to get API completion
function! chat#CompleteCode()
  " Get context: line before cursor
  let col = col('.') - 1
  let line = getline('.')
  let line_before_cursor = (col > 0) ? line[: col - 1] : ''

  " Basic check: Don't trigger completion on empty space after space
  if line_before_cursor =~ '\s$' || empty(line_before_cursor)
      return "\<Tab>" " Insert regular tab
  endif

  " Construct prompt for completion
  let prompt = "Complete the following code snippet:\n```\n" . line_before_cursor . "\n```"
  let payload = {'messages': [{'role': 'user', 'content': prompt}], 'max_tokens': 50, 'stop': ["\n"]} " Limit tokens and stop at newline for completion

  " Make the synchronous API call
  echom "Requesting API completion..." 
  " Give user feedback
  let json_response = chat#_MakeApiCall(payload)
  echom "" 
  " Clear message

  " Handle response
  if has_key(json_response, 'error')
    echoerr json_response.error
    return "\<Tab>" " Fallback to regular Tab on error
  endif

  let completion_text = json_response.choices[0].message.content
  " Basic cleanup: remove leading/trailing whitespace, potentially remove the input part if the model repeats it
  let completion_text = trim(completion_text)

  " Avoid inserting empty completion
  if empty(completion_text)
      return "\<Tab>"
  endif

  " Return the completion text to be inserted by the mapping
  return completion_text
endfunction
