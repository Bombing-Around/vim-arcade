" arcade/twenty48.vim -- 2048.
" Logic is pure (state in, state out) so it can be tested headlessly;
" only #start and the key handlers touch a buffer.

let s:SIZE = 4
let s:UNDO_DEPTH = 8

function! s:glyphs() abort
  if get(g:, 'arcade_ascii', &encoding !=# 'utf-8')
    return {'tl': '+', 'tr': '+', 'bl': '+', 'br': '+', 'h': '-', 'v': '|',
          \ 'lt': '+', 'rt': '+', 'tt': '+', 'bt': '+', 'x': '+'}
  endif
  return {'tl': '╭', 'tr': '╮', 'bl': '╰', 'br': '╯', 'h': '─', 'v': '│',
        \ 'lt': '├', 'rt': '┤', 'tt': '┬', 'bt': '┴', 'x': '┼'}
endfunction

function! arcade#twenty48#new(...) abort
  let l:seed = a:0 ? a:1 : 0
  let l:st = {
        \ 'grid': map(range(s:SIZE), {_, __ -> repeat([0], s:SIZE)}),
        \ 'score': 0,
        \ 'moves': 0,
        \ 'won': 0,
        \ 'over': 0,
        \ 'recorded': 0,
        \ 'message': '',
        \ 'history': [],
        \ 'best': arcade#score#best('2048'),
        \ 'rng': arcade#util#rng_new(l:seed),
        \ }
  call arcade#twenty48#spawn(l:st)
  call arcade#twenty48#spawn(l:st)
  return l:st
endfunction

function! arcade#twenty48#empty_cells(st) abort
  let l:cells = []
  for l:r in range(s:SIZE)
    for l:c in range(s:SIZE)
      if a:st.grid[l:r][l:c] == 0
        call add(l:cells, [l:r, l:c])
      endif
    endfor
  endfor
  return l:cells
endfunction

" Places a 2 (90%) or 4 (10%) on a random empty cell. Returns 0 if full.
function! arcade#twenty48#spawn(st) abort
  let l:cells = arcade#twenty48#empty_cells(a:st)
  if empty(l:cells)
    return 0
  endif
  let l:pick = l:cells[arcade#util#rng_int(a:st.rng, len(l:cells))]
  let a:st.grid[l:pick[0]][l:pick[1]] = arcade#util#rng_chance(a:st.rng, 10) ? 4 : 2
  return 1
endfunction

" Collapses one line toward index 0. Returns [new_line, gained_score].
function! arcade#twenty48#collapse(line) abort
  let l:vals = filter(copy(a:line), 'v:val != 0')
  let l:out = []
  let l:gain = 0
  let l:i = 0
  while l:i < len(l:vals)
    if l:i + 1 < len(l:vals) && l:vals[l:i] == l:vals[l:i + 1]
      let l:merged = l:vals[l:i] * 2
      call add(l:out, l:merged)
      let l:gain += l:merged
      let l:i += 2
    else
      call add(l:out, l:vals[l:i])
      let l:i += 1
    endif
  endwhile
  return [l:out + repeat([0], s:SIZE - len(l:out)), l:gain]
endfunction

function! s:line_of(grid, dir, idx) abort
  " Returns the line to collapse, already oriented toward index 0.
  if a:dir ==# 'h'
    return copy(a:grid[a:idx])
  elseif a:dir ==# 'l'
    return reverse(copy(a:grid[a:idx]))
  endif
  let l:col = map(range(s:SIZE), {i, _ -> a:grid[i][a:idx]})
  return a:dir ==# 'k' ? l:col : reverse(l:col)
endfunction

function! s:write_line(grid, dir, idx, line) abort
  if a:dir ==# 'h'
    let a:grid[a:idx] = copy(a:line)
  elseif a:dir ==# 'l'
    let a:grid[a:idx] = reverse(copy(a:line))
  else
    let l:vals = a:dir ==# 'k' ? copy(a:line) : reverse(copy(a:line))
    for l:i in range(s:SIZE)
      let a:grid[l:i][a:idx] = l:vals[l:i]
    endfor
  endif
endfunction

" Applies a move in direction h/j/k/l. Returns 1 if the board changed.
function! arcade#twenty48#move(st, dir) abort
  if a:st.over
    return 0
  endif
  let l:before = deepcopy(a:st.grid)
  let l:gain = 0
  for l:idx in range(s:SIZE)
    let [l:line, l:got] = arcade#twenty48#collapse(s:line_of(a:st.grid, a:dir, l:idx))
    let l:gain += l:got
    call s:write_line(a:st.grid, a:dir, l:idx, l:line)
  endfor
  if a:st.grid ==# l:before
    return 0
  endif
  call add(a:st.history, {'grid': l:before, 'score': a:st.score, 'won': a:st.won})
  if len(a:st.history) > s:UNDO_DEPTH
    call remove(a:st.history, 0)
  endif
  let a:st.score += l:gain
  let a:st.moves += 1
  let a:st.message = ''
  call arcade#twenty48#spawn(a:st)
  if !a:st.won && arcade#twenty48#max_tile(a:st) >= 2048
    let a:st.won = 1
    let a:st.message = 'You made 2048! Keep going for a higher score.'
  endif
  if !arcade#twenty48#can_move(a:st)
    let a:st.over = 1
  endif
  return 1
endfunction

function! arcade#twenty48#max_tile(st) abort
  let l:max = 0
  for l:row in a:st.grid
    let l:max = max([l:max] + l:row)
  endfor
  return l:max
endfunction

function! arcade#twenty48#can_move(st) abort
  if !empty(arcade#twenty48#empty_cells(a:st))
    return 1
  endif
  for l:r in range(s:SIZE)
    for l:c in range(s:SIZE)
      let l:v = a:st.grid[l:r][l:c]
      if (l:c + 1 < s:SIZE && a:st.grid[l:r][l:c + 1] == l:v)
            \ || (l:r + 1 < s:SIZE && a:st.grid[l:r + 1][l:c] == l:v)
        return 1
      endif
    endfor
  endfor
  return 0
endfunction

function! arcade#twenty48#undo(st) abort
  if empty(a:st.history)
    let a:st.message = 'Nothing to undo.'
    return 0
  endif
  let l:prev = remove(a:st.history, -1)
  let a:st.grid = l:prev.grid
  let a:st.score = l:prev.score
  let a:st.won = l:prev.won
  let a:st.over = 0
  let a:st.recorded = 0
  let a:st.moves = max([0, a:st.moves - 1])
  let a:st.message = 'Undid one move.'
  return 1
endfunction

" ---------------------------------------------------------------- rendering

function! s:tile_group(value) abort
  if a:value == 0
    return 'Arcade2048Empty'
  endif
  return 'Arcade2048T' . min([a:value, 4096])
endfunction

function! arcade#twenty48#draw(st) abort
  let l:g = s:glyphs()
  let l:cw = 7
  let l:margin = '  '
  let l:lines = []
  let l:hl = []

  let l:head = l:margin . '2048'
  let l:stats = printf('score %d    best %d    moves %d',
        \ a:st.score, max([a:st.best, a:st.score]), a:st.moves)
  call add(l:lines, l:head)
  call add(l:hl, [0, strlen(l:margin), strlen(l:head), 'Arcade2048Title'])
  call add(l:lines, l:margin . l:stats)
  call add(l:hl, [1, strlen(l:margin), strlen(l:margin . l:stats), 'Arcade2048Score'])
  call add(l:lines, '')

  let l:seg = repeat(l:g.h, l:cw)
  let l:top = l:margin . l:g.tl . join(repeat([l:seg], s:SIZE), l:g.tt) . l:g.tr
  let l:mid = l:margin . l:g.lt . join(repeat([l:seg], s:SIZE), l:g.x) . l:g.rt
  let l:bot = l:margin . l:g.bl . join(repeat([l:seg], s:SIZE), l:g.bt) . l:g.br

  call add(l:lines, l:top)
  for l:r in range(s:SIZE)
    for l:sub in range(3)
      let l:line = l:margin . l:g.v
      let l:lnum = len(l:lines)
      for l:c in range(s:SIZE)
        let l:value = a:st.grid[l:r][l:c]
        let l:text = l:sub == 1 && l:value > 0
              \ ? arcade#util#center(string(l:value), l:cw)
              \ : repeat(' ', l:cw)
        let l:start = strlen(l:line)
        let l:line .= l:text . l:g.v
        call add(l:hl, [l:lnum, l:start, l:start + strlen(l:text), s:tile_group(l:value)])
      endfor
      call add(l:lines, l:line)
    endfor
    call add(l:lines, l:r == s:SIZE - 1 ? l:bot : l:mid)
  endfor

  call add(l:lines, '')
  if a:st.over
    let l:banner = 'GAME OVER  --  r restarts, u undoes, q quits'
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:banner), 'Arcade2048Over'])
    call add(l:lines, l:margin . l:banner)
  elseif !empty(a:st.message)
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . a:st.message), 'Arcade2048Win'])
    call add(l:lines, l:margin . a:st.message)
  else
    call add(l:lines, '')
  endif
  let l:hint = 'hjkl / arrows move    u undo    r restart    q quit'
  call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:hint), 'Arcade2048Hint'])
  call add(l:lines, l:margin . l:hint)

  return {'lines': l:lines, 'hl': l:hl}
endfunction

" ------------------------------------------------------------------ session

function! s:on_move(ctl, key) abort
  let l:dir = get({'<Left>': 'h', '<Down>': 'j', '<Up>': 'k', '<Right>': 'l'}, a:key, a:key)
  call arcade#twenty48#move(a:ctl.state, l:dir)
  call s:maybe_record(a:ctl.state)
endfunction

function! s:maybe_record(st) abort
  if a:st.over && !a:st.recorded
    let a:st.recorded = 1
    call arcade#score#record('2048', a:st.score,
          \ {'max_tile': arcade#twenty48#max_tile(a:st), 'moves': a:st.moves})
    let a:st.best = arcade#score#best('2048')
  endif
endfunction

function! s:on_undo(ctl, key) abort
  call arcade#twenty48#undo(a:ctl.state)
endfunction

function! s:on_restart(ctl, key) abort
  let a:ctl.state = arcade#twenty48#new()
endfunction

function! s:on_quit(ctl, key) abort
  call s:maybe_record(a:ctl.state)
  call arcade#ui#close()
endfunction

function! arcade#twenty48#start(...) abort
  let l:ctl = {
        \ 'name': 'arcade://2048',
        \ 'filetype': 'arcade2048',
        \ 'state': call('arcade#twenty48#new', a:000),
        \ 'draw': function('arcade#twenty48#draw'),
        \ 'keys': {},
        \ }
  for l:key in ['h', 'j', 'k', 'l', '<Left>', '<Down>', '<Up>', '<Right>']
    let l:ctl.keys[l:key] = function('s:on_move')
  endfor
  let l:ctl.keys['u'] = function('s:on_undo')
  let l:ctl.keys['r'] = function('s:on_restart')
  let l:ctl.keys['q'] = function('s:on_quit')
  return arcade#ui#open(l:ctl)
endfunction
