" arcade/score.vim -- persistent high scores (best-effort; never fatal).

let s:cache = {}
let s:loaded = 0

function! s:path() abort
  return arcade#util#data_dir() . '/scores.json'
endfunction

function! s:load() abort
  if s:loaded
    return s:cache
  endif
  let s:loaded = 1
  " A corrupt score file starts fresh rather than breaking the game.
  let s:cache = arcade#util#read_json(s:path())
  return s:cache
endfunction

function! s:save() abort
  " Read-only HOME, sandbox, etc: scores stay in-memory for this session.
  call arcade#util#write_json(s:path(), s:cache)
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
  " A run that spans sessions reports itself every time it is put down.
  " Keyed by meta.run, those reports update one row instead of filling
  " the history with a row per quit.
  let l:runs = get(l:entry, 'runs', [])
  if !empty(l:runs) && !empty(get(l:meta, 'run', ''))
        \ && get(l:runs[0], 'run', '') ==# l:meta.run
    let l:runs[0] = l:run
    let l:entry.runs = l:runs
  else
    let l:entry.runs = ([l:run] + l:runs)[0:9]
  endif
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
