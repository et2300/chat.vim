" autoload/chat/tui.vim - TUI functions for chat.vim
" Copyright (C) 2025 et2300
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <https://www.gnu.org/licenses/>.

" Store window and buffer IDs globally for TUI management
let g:chat_tui_output_winid = -1
let g:chat_tui_input_winid = -1
let g:chat_tui_output_bufnr = -1
let g:chat_tui_input_bufnr = -1

" Function to open the TUI interface
function! chat#tui#Open() abort
  " Prevent opening multiple TUIs
  if g:chat_tui_output_winid != -1 && win_gotoid(g:chat_tui_output_winid)
    echo "Chat TUI is already open."
    return
  endif

  " --- Create Windows ---
  " 1. Create Output Window (Top/Left)
  if winnr('$') > 1
      vsplit __ChatTUI_Output__ " Use vsplit if already split
  else
      new __ChatTUI_Output__    " Use new if it's the only window
  endif
  let g:chat_tui_output_winid = win_getid() " Store output window ID

  " 2. Create Input Window (Split below the output window)
  10split __ChatTUI_Input__ " Create the split for input
  let g:chat_tui_input_winid = win_getid() " Store input window ID

  " --- Configure Output Window ---
  call win_gotoid(g:chat_tui_output_winid) " Go to output window
  let g:chat_tui_output_bufnr = bufnr('%') " Store buffer number
  " Set options for the output buffer
  setlocal buftype=nofile bufhidden=hide noswapfile nomodifiable
  setlocal wrap                    " Wrap long lines
  setlocal nonumber norelativenumber " Hide line numbers
  setlocal winfixheight            " Keep height fixed if possible
  " Add initial text
  call setline(1, ["--- Chat History ---", ""])
  " Map 'q' in normal mode to close the TUI
  nnoremap <buffer> <silent> q :call chat#tui#Close()<CR>

  " --- Configure Input Window ---
  call win_gotoid(g:chat_tui_input_winid) " Go to input window
  " Create a new unnamed buffer for input
  enew
  let g:chat_tui_input_bufnr = bufnr('%') " Store buffer number
  " Rename the buffer (optional but good practice)
  silent! file __ChatTUI_Input__
  " Set options for the input buffer
  setlocal buftype=prompt bufhidden=hide noswapfile modifiable
  setlocal nonumber norelativenumber " Hide line numbers
  setlocal wrap                    " Wrap long lines
  " Optional: Set prompt-like behavior (requires Vim 8+)
  if exists('*prompt_setprompt')
      call prompt_setprompt(g:chat_tui_input_bufnr, 'You: ')
  endif
  " Map Enter key in insert mode to send the message
  inoremap <buffer> <silent> <CR> <Cmd>call chat#tui#SendMessage()<CR>
  " Map 'q' in normal mode to close the TUI
  nnoremap <buffer> <silent> q :call chat#tui#Close()<CR>

  " --- Final Steps ---
  " Focus the input window initially
  call win_gotoid(g:chat_tui_input_winid)
  startinsert " Enter insert mode

  echo "Chat TUI opened. Type your message and press Enter."
endfunction

" Function to close the TUI interface
function! chat#tui#Close() abort
  let closed_output = 0
  let closed_input = 0

  " Close Output Window if it exists and buffer exists
  if g:chat_tui_output_winid != -1 && win_gotoid(g:chat_tui_output_winid)
    if bufexists(g:chat_tui_output_bufnr)
        execute 'bwipeout! ' . g:chat_tui_output_bufnr
    else
        close! " Force close window if buffer is somehow gone
    endif
    let closed_output = 1
  endif
  " Reset ID regardless
  let g:chat_tui_output_winid = -1
  let g:chat_tui_output_bufnr = -1

  " Close Input Window if it exists and buffer exists
  if g:chat_tui_input_winid != -1 && win_gotoid(g:chat_tui_input_winid)
    if bufexists(g:chat_tui_input_bufnr)
        execute 'bwipeout! ' . g:chat_tui_input_bufnr
    else
        close! " Force close window if buffer is somehow gone
    endif
    let closed_input = 1
  endif
  " Reset ID regardless
  let g:chat_tui_input_winid = -1
  let g:chat_tui_input_bufnr = -1

  if closed_output || closed_input
    echo "Chat TUI closed."
  endif
  " No message if windows were already closed to avoid confusion
endfunction

" Function to send message from input buffer
function! chat#tui#SendMessage() abort
  " Ensure input window is valid
  if g:chat_tui_input_winid == -1 || !win_gotoid(g:chat_tui_input_winid)
    echoerr "Chat TUI input window not found!"
    return
  endif

  " Get message from the first line of the input buffer
  let user_message = getline(1)

  " If message is empty, do nothing (or maybe just clear the line?)
  if empty(trim(user_message))
    " Optionally clear the line even if it was just whitespace
    call setline(1, '')
    return
  endif

  " Clear the input line
  call setline(1, '')
  " Ensure cursor stays on the first line (important for buftype=prompt)
  call cursor(1, 1)

  " Append user message to output
  call chat#tui#_AppendMessage('You', user_message)

  " Append thinking message and get its line number
  call chat#tui#_AppendMessage('AI', 'Thinking...')
  let thinking_line_nr = line('$') " Get the line number of the thinking message

  " Prepare payload for API call
  let payload = {'messages': [{'role': 'user', 'content': user_message}]}

  " Make the API call (using the function from autoload/chat.vim)
  let response = chat#_MakeApiCall(payload)

  " --- Process Response ---
  " Go back to output window to modify it
  if g:chat_tui_output_winid == -1 || !win_gotoid(g:chat_tui_output_winid)
    echoerr "Chat TUI output window lost!"
    " Attempt to refocus input window anyway
    if g:chat_tui_input_winid != -1 && win_gotoid(g:chat_tui_input_winid)
      startinsert
    endif
    return
  endif

  " Make output buffer modifiable to remove 'Thinking...' and add response
  setlocal modifiable

  " Delete the 'Thinking...' line
  execute thinking_line_nr . 'delete _'

  " Append the actual response or error
  if has_key(response, 'error')
    call chat#tui#_AppendMessage('Error', response.error)
  elseif has_key(response, 'choices') && !empty(response.choices) && has_key(response.choices[0], 'message') && has_key(response.choices[0].message, 'content')
    call chat#tui#_AppendMessage('AI', response.choices[0].message.content)
  else
    call chat#tui#_AppendMessage('Error', 'Invalid or empty response received from API.')
  endif

  " Make output buffer non-modifiable again (already done by _AppendMessage)
  " setlocal nomodifiable (handled by the last _AppendMessage call)

  " --- Final Steps ---
  " Return focus to the input window and enter insert mode
  if g:chat_tui_input_winid != -1 && win_gotoid(g:chat_tui_input_winid)
    startinsert
  endif
endfunction

" Helper to append message to the output buffer
function! chat#tui#_AppendMessage(role, message) abort
  if g:chat_tui_output_winid == -1 || !win_gotoid(g:chat_tui_output_winid)
    echoerr "Chat TUI output window not found!"
    return
  endif

  " Temporarily make the buffer modifiable
  setlocal modifiable

  " Format the message
  let formatted_message = a:role . ': ' . a:message

  " Append the message lines
  for line in split(formatted_message, '\n')
    call append('$', line)
  endfor

  " Scroll to the bottom
  normal! G
  " Make the buffer non-modifiable again
  setlocal nomodifiable

  " Return focus to the input window if it's still valid
  if g:chat_tui_input_winid != -1 && win_gotoid(g:chat_tui_input_winid)
    " No action needed, already there or switched back implicitly by win_gotoid check
  else
    " If input window is gone, maybe focus output? Or do nothing.
    " For now, just stay in the output window.
  endif
endfunction
