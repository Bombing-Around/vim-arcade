" arcade/save.vim -- suspended games (best-effort; never fatal).
"
" A game that can be picked up again stores whatever it needs to resume
" here, keyed by game name. Nothing in here is precious: a missing,
" unreadable, corrupt or stale-format file just means the game starts
" fresh, which is exactly what happened before any of this existed.

let s:VERSION = 1
let s:cache = {}
let s:loaded = 0

function! s:path() abort
  return arcade#util#data_dir() . '/sessions.json'
endfunction

function! s:load() abort
  if s:loaded
    return s:cache
  endif
  let s:loaded = 1
  let s:cache = arcade#util#read_json(s:path())
  return s:cache
endfunction

" Stores a game's resume data. Anything json_encode cannot represent --
" a funcref that crept into the state, say -- drops the save rather than
" throwing in the player's face on the way out.
function! arcade#save#put(game, data) abort
  let l:store = s:load()
  let l:store[a:game] = {'version': s:VERSION, 'at': strftime('%Y-%m-%d %H:%M'),
        \ 'data': a:data}
  let s:cache = l:store
  return arcade#util#write_json(s:path(), s:cache)
endfunction

" Returns the stored data, or {} when there is nothing usable.
function! arcade#save#get(game) abort
  let l:entry = get(s:load(), a:game, {})
  if type(l:entry) != v:t_dict || get(l:entry, 'version', 0) != s:VERSION
    return {}
  endif
  let l:data = get(l:entry, 'data', {})
  return type(l:data) == v:t_dict ? l:data : {}
endfunction

function! arcade#save#when(game) abort
  return get(get(s:load(), a:game, {}), 'at', '')
endfunction

function! arcade#save#clear(game) abort
  call s:load()
  if has_key(s:cache, a:game)
    call remove(s:cache, a:game)
    call arcade#util#write_json(s:path(), s:cache)
  endif
endfunction
