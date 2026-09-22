" arcade.vim -- dispatch and scoreboard.

let s:GAMES = {
      \ '2048':  {'start': 'arcade#twenty48#start', 'label': '2048'},
      \ 'crawl': {'start': 'arcade#crawl#start',    'label': 'dungeon crawl'},
      \ 'sort':  {'start': 'arcade#sort#start',     'label': 'ball sort'},
      \ }

function! arcade#complete(lead, ...) abort
  return sort(filter(keys(s:GAMES), 'stridx(v:val, a:lead) == 0'))
endfunction

function! arcade#start(name) abort
  let l:key = tolower(substitute(a:name, '^\s*\|\s*$', '', 'g'))
  if !has_key(s:GAMES, l:key)
    echohl ErrorMsg
    echomsg 'arcade: unknown game ' . string(a:name)
          \ . ' (known: ' . join(sort(keys(s:GAMES)), ', ') . ')'
    echohl None
    return
  endif
  return call(s:GAMES[l:key].start, [])
endfunction

function! arcade#scoreboard() abort
  for l:key in sort(keys(s:GAMES))
    let l:best = arcade#score#best(l:key)
    echohl Title
    echo printf('%-8s best %d', s:GAMES[l:key].label, l:best)
    echohl None
    for l:run in arcade#score#history(l:key)[0:4]
      let l:extra = filter(copy(l:run), 'index(["score", "at"], v:key) < 0')
      echo printf('  %-16s %6d  %s', get(l:run, 'at', ''), get(l:run, 'score', 0),
            \ empty(l:extra) ? '' : string(l:extra))
    endfor
  endfor
endfunction
