" arcade/score.vim -- persistent high scores (best-effort; never fatal).

let s:cache = {}
let s:loaded = 0

function! s:data_dir() abort
  if exists('g:arcade_data_dir')
    return expand(g:arcade_data_dir)
  endif
  if has('nvim')
    return stdpath('data') . '/vim-arcade'
  endif
  let l:base = empty($XDG_DATA_HOME) ? expand('~/.local/share') : $XDG_DATA_HOME
  return l:base . '/vim-arcade'
endfunction

function! s:path() abort
  return s:data_dir() . '/scores.json'
endfunction

function! s:load() abort
  if s:loaded
    return s:cache
  endif
  let s:loaded = 1
  let s:cache = {}
  let l:path = s:path()
  if !filereadable(l:path)
    return s:cache
  endif
  try
    let l:raw = join(readfile(l:path), "\n")
    let l:data = json_decode(l:raw)
    if type(l:data) == v:t_dict
      let s:cache = l:data
    endif
  catch
    " Corrupt score file: start fresh rather than breaking the game.
    let s:cache = {}
  endtry
  return s:cache
endfunction

function! s:save() abort
  let l:dir = s:data_dir()
  try
    if !isdirectory(l:dir)
      call mkdir(l:dir, 'p', 0700)
    endif
    let l:tmp = s:path() . '.tmp'
    call writefile([json_encode(s:cache)], l:tmp)
    call rename(l:tmp, s:path())
  catch
    " Read-only HOME, sandbox, etc. Scores stay in-memory for this session.
  endtry
endfunction

function! arcade#score#best(game) abort
  let l:data = s:load()
  let l:entry = get(l:data, a:game, {})
  return get(l:entry, 'best', 0)
endfunction

function! arcade#score#history(game) abort
  let l:data = s:load()
  return get(get(l:data, a:game, {}), 'runs', [])
endfunction

" Records a finished run; returns 1 if it is a new personal best.
function! arcade#score#record(game, score, ...) abort
  let l:meta = a:0 ? a:1 : {}
  let l:data = s:load()
  let l:entry = get(l:data, a:game, {'best': 0, 'runs': []})
  let l:is_best = a:score > get(l:entry, 'best', 0)
  if l:is_best
    let l:entry.best = a:score
  endif
  let l:run = extend({'score': a:score, 'at': strftime('%Y-%m-%d %H:%M')}, l:meta)
  let l:entry.runs = ([l:run] + get(l:entry, 'runs', []))[0:9]
  let l:data[a:game] = l:entry
  let s:cache = l:data
  call s:save()
  return l:is_best
endfunction

function! arcade#score#reset(...) abort
  call s:load()
  if a:0
    if has_key(s:cache, a:1)
      call remove(s:cache, a:1)
    endif
  else
    let s:cache = {}
  endif
  call s:save()
endfunction
