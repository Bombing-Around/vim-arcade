" arcade/ui.vim -- scratch-buffer game surface shared by every arcade game.
"
" A game supplies a controller dict:
"   {'name': 'arcade://2048', 'filetype': 'arcade2048',
"    'state': <any>, 'keys': {'h': funcref, ...},
"    'draw': funcref(state) -> {'lines': [...], 'hl': [[lnum, bcol, bend, group], ...]}}
" Key handlers get the controller dict and the pressed key, and may mutate
" controller.state. The surface redraws after every handled key.
"
" A count typed before the key ("3l") is left in controller.count, 0 when
" none was typed; it rides the dict rather than the handler signature so a
" game that does not care about counts needs no changes.

let s:ns = -1
let s:prop_types = {}

function! s:namespace() abort
  if has('nvim') && s:ns < 0
    let s:ns = nvim_create_namespace('vim_arcade')
  endif
  return s:ns
endfunction

function! s:win_for_buf(bufnr) abort
  for l:win in range(1, winnr('$'))
    if winbufnr(l:win) == a:bufnr
      return l:win
    endif
  endfor
  return -1
endfunction

function! s:make_window() abort
  let l:how = get(g:, 'arcade_window', 'tab')
  " winfixbuf is window-local: it survives the arcade buffer being wiped
  " out, and Neovim (unlike Vim) hard-errors on enew/new/vnew into a
  " fixed window instead of ignoring it. Clear it before reusing the
  " window; s:setup_buffer sets it again on the new arcade buffer.
  if l:how !=# 'tab' && exists('+winfixbuf') && &winfixbuf
    setlocal nowinfixbuf
  endif
  if l:how ==# 'current'
    enew
  elseif l:how ==# 'vsplit'
    vnew
  elseif l:how ==# 'split'
    new
  else
    tabnew
  endif
endfunction

function! s:setup_buffer(ctl) abort
  let l:bufnr = bufnr('%')
  silent! execute 'file' fnameescape(a:ctl.name)
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nomodifiable nonumber norelativenumber nowrap nolist
  setlocal nocursorline nocursorcolumn colorcolumn= foldcolumn=0
  setlocal signcolumn=no nospell scrolloff=0 sidescrolloff=0
  if exists('+winfixbuf')
    setlocal winfixbuf
  endif
  if !empty(get(a:ctl, 'filetype', ''))
    execute 'setlocal filetype=' . a:ctl.filetype
  endif
  let b:arcade = a:ctl
  let a:ctl.bufnr = l:bufnr
  call s:bind_keys(a:ctl)
  return l:bufnr
endfunction

" A mapping's {rhs}, even built via execute() and string(), still goes
" through Vim's own key-notation translation -- '<Esc>' or '<Left>' typed
" as text inside that rhs becomes the *actual* control byte the moment the
" mapping is defined, not a literal string. So embedding the key name as a
" quoted argument only round-trips correctly for plain characters; for any
" special key, arcade#ui#key() would receive that raw byte back instead of
" the name it was mapped under, and the lookup in ctl.keys would silently
" miss. Passing a plain integer index instead sidesteps the translation
" entirely: digits mean the same thing on both sides of execute().
"
" The :<C-u> is what makes counts work at all: Vim turns a count typed
" before a : mapping into a line range, which :call rejects outright
" (E481). Clearing it leaves the count readable in v:count.
function! s:bind_keys(ctl) abort
  nnoremap <buffer><silent><nowait> <Esc> :<C-u>call arcade#ui#close()<CR>
  let b:arcade_key_names = keys(a:ctl.keys)
  for l:idx in range(len(b:arcade_key_names))
    execute printf('nnoremap <buffer><silent><nowait> %s :<C-u>call arcade#ui#dispatch(%d, v:count)<CR>',
          \ b:arcade_key_names[l:idx], l:idx)
  endfor
  " Swallow keys that would otherwise move the cursor or edit the board.
  for l:key in ['i', 'I', 'a', 'A', 'o', 'O', 'c', 'C', 'd', 'D', 's', 'S',
        \ 'x', 'X', 'p', 'P', 'v', 'V', 'R', '<C-v>']
    if !has_key(a:ctl.keys, l:key)
      execute printf('nnoremap <buffer><silent><nowait> %s <Nop>', l:key)
    endif
  endfor
endfunction

" Opens (or re-focuses) the surface for a controller and draws it.
function! arcade#ui#open(ctl) abort
  let l:existing = bufnr(a:ctl.name)
  if l:existing > 0 && bufloaded(l:existing)
    let l:win = s:win_for_buf(l:existing)
    if l:win > 0
      execute l:win . 'wincmd w'
    else
      execute 'buffer' l:existing
    endif
    silent! execute 'bwipeout!' l:existing
  endif
  call s:make_window()
  let l:bufnr = s:setup_buffer(a:ctl)
  call arcade#ui#redraw(a:ctl)
  return l:bufnr
endfunction

" Entry point actually wired to keypresses; see the comment on s:bind_keys
" for why the mapping passes an index here rather than the key name.
function! arcade#ui#dispatch(idx, ...) abort
  if !exists('b:arcade_key_names') || a:idx >= len(b:arcade_key_names)
    return
  endif
  call arcade#ui#key(b:arcade_key_names[a:idx], a:0 ? a:1 : 0)
endfunction

" Entry point for direct calls (tests, other mappings) that already have
" the real key name in hand.
function! arcade#ui#key(key, ...) abort
  if !exists('b:arcade')
    return
  endif
  let l:ctl = b:arcade
  let l:Handler = get(l:ctl.keys, a:key, 0)
  if type(l:Handler) != v:t_func
    return
  endif
  let l:ctl.count = a:0 ? a:1 : 0
  call call(l:Handler, [l:ctl, a:key])
  if bufexists(get(l:ctl, 'bufnr', -1))
    call arcade#ui#redraw(l:ctl)
  endif
endfunction

function! arcade#ui#close() abort
  if !exists('b:arcade')
    return
  endif
  let l:bufnr = b:arcade.bufnr
  if winnr('$') == 1 && tabpagenr('$') > 1
    silent! tabclose
  else
    silent! execute 'bwipeout!' l:bufnr
  endif
endfunction

function! s:clear_highlights(bufnr) abort
  if has('nvim')
    call nvim_buf_clear_namespace(a:bufnr, s:namespace(), 0, -1)
  elseif has('textprop')
    let l:last = max([1, len(getbufline(a:bufnr, 1, '$'))])
    silent! call prop_clear(1, l:last, {'bufnr': a:bufnr})
  endif
endfunction

function! s:prop_type(group) abort
  if !has_key(s:prop_types, a:group)
    let l:name = 'arcade_' . a:group
    silent! call prop_type_add(l:name, {'highlight': a:group, 'priority': 10})
    let s:prop_types[a:group] = l:name
  endif
  return s:prop_types[a:group]
endfunction

" spans: [[lnum (0-based), byte_start, byte_end, hl_group], ...]
function! arcade#ui#highlight(bufnr, spans) abort
  if has('nvim')
    let l:ns = s:namespace()
    if exists('*nvim_buf_set_extmark')
      for l:s in a:spans
        call nvim_buf_set_extmark(a:bufnr, l:ns, l:s[0], l:s[1],
              \ {'end_col': l:s[2], 'hl_group': l:s[3]})
      endfor
    else
      for l:s in a:spans
        call nvim_buf_add_highlight(a:bufnr, l:ns, l:s[3], l:s[0], l:s[1], l:s[2])
      endfor
    endif
  elseif has('textprop')
    for l:s in a:spans
      silent! call prop_add(l:s[0] + 1, l:s[1] + 1, {
            \ 'length': l:s[2] - l:s[1],
            \ 'type': s:prop_type(l:s[3]),
            \ 'bufnr': a:bufnr})
    endfor
  endif
endfunction

function! arcade#ui#redraw(ctl) abort
  let l:bufnr = get(a:ctl, 'bufnr', -1)
  if l:bufnr < 0 || !bufexists(l:bufnr)
    return
  endif
  let l:frame = call(a:ctl.draw, [a:ctl.state])
  let l:win = s:win_for_buf(l:bufnr)
  let l:cur = winnr()
  if l:win > 0 && l:win != l:cur
    execute l:win . 'wincmd w'
  endif
  try
    setlocal modifiable
    call s:clear_highlights(l:bufnr)
    silent! call deletebufline(l:bufnr, 1, '$')
    call setbufline(l:bufnr, 1, l:frame.lines)
    setlocal nomodifiable nomodified
    call arcade#ui#highlight(l:bufnr, get(l:frame, 'hl', []))
    call cursor(1, 1)
  finally
    if l:win > 0 && l:win != l:cur && winnr() != l:cur && l:cur <= winnr('$')
      execute l:cur . 'wincmd w'
    endif
  endtry
  redraw
endfunction

" Convenience for games: append a highlight span while building a line.
function! arcade#ui#span(lnum, text, prefix, group) abort
  let l:start = strlen(a:prefix)
  return [a:lnum, l:start, l:start + strlen(a:text), a:group]
endfunction
