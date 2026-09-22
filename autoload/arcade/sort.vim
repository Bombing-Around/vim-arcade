" arcade/sort.vim -- ball sort: stack every colour into its own tube.
" Logic is pure (state in, state out) so it can be tested headlessly;
" only #start and the key handlers touch a buffer.
"
" One hand, one ball: <Space> lifts the top ball of the tube under the
" cursor, <Space> again drops it wherever it fits. A ball fits an empty
" tube, or one whose top ball is the same colour and which has room.
"
" Because a legal move only ever stacks a colour on itself, a mixed tube
" can never be *built* by playing forwards -- forward play from a solved
" board just shuffles whole colours between tubes. So levels are dealt by
" walking backwards from the solved board along inverted moves (see
" s:unmoves), which both mixes the tubes and proves the level solvable.

let s:CAP = 4          " balls per tube, and balls per colour
let s:FREE = 2         " spare tubes, the whole reason the puzzle is solvable
let s:MAX_COLORS = 9
let s:UNDO_DEPTH = 32

function! s:glyphs() abort
  if get(g:, 'arcade_ascii', &encoding !=# 'utf-8')
    return {'wall': '|', 'bl': '+', 'br': '+', 'h': '-', 'caret': '^',
          \ 'balls': ['o', 'A', '#', '+', '*', 'v', '@', '=', 'x']}
  endif
  " Shape carries the colour too, so the board still reads on a monochrome
  " build and for anyone who can't tell 203 from 215.
  return {'wall': '│', 'bl': '╰', 'br': '╯', 'h': '─', 'caret': '▲',
        \ 'balls': ['●', '▲', '■', '◆', '★', '▼', '◉', '○', '◇']}
endfunction

function! s:colors_for(level) abort
  return min([3 + a:level, s:MAX_COLORS])
endfunction

" ---------------------------------------------------------------- state

function! arcade#sort#new(...) abort
  let l:seed = a:0 ? a:1 : 0
  let l:st = {
        \ 'level': 1,
        \ 'colors': 0,
        \ 'cap': s:CAP,
        \ 'tubes': [],
        \ 'cursor': 0,
        \ 'held': -1,
        \ 'held_from': -1,
        \ 'moves': 0,
        \ 'total_moves': 0,
        \ 'score': 0,
        \ 'par': 0,
        \ 'gained': 0,
        \ 'cleared': 0,
        \ 'level_done': 0,
        \ 'stuck': 0,
        \ 'recorded': 0,
        \ 'message': '',
        \ 'history': [],
        \ 'solution': [],
        \ 'best': arcade#score#best('sort'),
        \ 'rng': arcade#util#rng_new(l:seed),
        \ }
  call arcade#sort#build_level(l:st)
  return l:st
endfunction

function! arcade#sort#build_level(st) abort
  let a:st.colors = s:colors_for(a:st.level)
  let a:st.par = a:st.colors * s:CAP
  let a:st.cursor = 0
  let a:st.held = -1
  let a:st.held_from = -1
  let a:st.moves = 0
  let a:st.gained = 0
  let a:st.level_done = 0
  let a:st.stuck = 0
  let a:st.history = []
  let a:st.message = ''
  let l:tries = 0
  while 1
    let a:st.tubes = s:solved_tubes(a:st.colors)
    let a:st.solution = []
    call s:scramble(a:st)
    let l:tries += 1
    " The scramble walks backwards from the solved board along inverted
    " moves, so the walk itself is the solution and every level is
    " winnable. It can still dead-end early -- no tube left to lift a ball
    " off -- and a walk that short deals a board that is nearly solved.
    if l:tries >= 8 || (len(a:st.solution) >= s:walk_length(a:st.colors) / 2
          \ && !arcade#sort#solved(a:st) && !arcade#sort#is_stuck(a:st))
      break
    endif
  endwhile
  return a:st
endfunction

function! s:solved_tubes(colors) abort
  let l:tubes = []
  for l:c in range(1, a:colors)
    call add(l:tubes, repeat([l:c], s:CAP))
  endfor
  for l:i in range(s:FREE)
    call add(l:tubes, [])
  endfor
  return l:tubes
endfunction

function! s:walk_length(colors) abort
  return 60 + 30 * a:colors
endfunction

function! s:scramble(st) abort
  let l:steps = s:walk_length(a:st.colors)
  let l:last = [-1, -1]
  while l:steps > 0
    let l:moves = s:unmoves(a:st, l:last)
    if empty(l:moves)
      " Only the just-undone move was on offer. Better to take it than to
      " stall the walk 20 moves in and deal a board that is nearly solved.
      let l:moves = s:unmoves(a:st, [-1, -1])
    endif
    if empty(l:moves)
      break
    endif
    let l:pick = l:moves[arcade#util#rng_int(a:st.rng, len(l:moves))]
    call add(a:st.tubes[l:pick[1]], remove(a:st.tubes[l:pick[0]], -1))
    " The walk run backwards is a legal solution: keep it as the level's
    " receipt. Nothing in play reads it -- the tests use it to prove the
    " deal is winnable without having to solve the thing.
    call insert(a:st.solution, [l:pick[1], l:pick[0]], 0)
    let l:last = l:pick
    let l:steps -= 1
  endwhile
endfunction

" Every un-move [dst, src] whose forward counterpart src -> dst would be
" legal: lifting the ball off dst has to leave dst empty or showing the
" same colour, and src only needs room. Note what src does *not* need --
" a matching top -- which is the whole asymmetry the generator runs on.
function! s:unmoves(st, last) abort
  let l:out = []
  let l:n = len(a:st.tubes)
  for l:dst in range(l:n)
    let l:tube = a:st.tubes[l:dst]
    if empty(l:tube) || (len(l:tube) > 1 && l:tube[-2] != l:tube[-1])
      continue
    endif
    for l:src in range(l:n)
      if l:src != l:dst && len(a:st.tubes[l:src]) < s:CAP
            \ && !(l:dst == a:last[1] && l:src == a:last[0])
        call add(l:out, [l:dst, l:src])
      endif
    endfor
  endfor
  return l:out
endfunction

" ---------------------------------------------------------------- rules

function! arcade#sort#can_move(st, src, dst) abort
  if a:src < 0 || a:dst < 0 || a:src >= len(a:st.tubes) || a:dst >= len(a:st.tubes)
    return 0
  endif
  if a:src == a:dst || empty(a:st.tubes[a:src])
    return 0
  endif
  let l:dst = a:st.tubes[a:dst]
  if len(l:dst) >= s:CAP
    return 0
  endif
  return empty(l:dst) || l:dst[-1] == a:st.tubes[a:src][-1]
endfunction

function! s:apply(st, src, dst) abort
  call add(a:st.tubes[a:dst], remove(a:st.tubes[a:src], -1))
endfunction

" Moves one ball src -> dst. Returns 1 if the board changed.
function! arcade#sort#move(st, src, dst) abort
  if a:st.level_done || !arcade#sort#can_move(a:st, a:src, a:dst)
    return 0
  endif
  call add(a:st.history, {'tubes': deepcopy(a:st.tubes), 'moves': a:st.moves})
  if len(a:st.history) > s:UNDO_DEPTH
    call remove(a:st.history, 0)
  endif
  call s:apply(a:st, a:src, a:dst)
  let a:st.moves += 1
  let a:st.total_moves += 1
  let a:st.message = ''
  call s:after_move(a:st)
  return 1
endfunction

function! s:after_move(st) abort
  if arcade#sort#solved(a:st)
    let a:st.level_done = 1
    let a:st.stuck = 0
    let a:st.cleared += 1
    let a:st.gained = arcade#sort#award(a:st)
    let a:st.score += a:st.gained
    return
  endif
  let a:st.stuck = arcade#sort#is_stuck(a:st)
endfunction

" Points for the level just cleared: a flat purse per colour, eaten into by
" every move past par. Never worth less than a quarter of the purse, so a
" messy solve still beats giving up.
function! arcade#sort#award(st) abort
  let l:base = 100 * a:st.colors
  let l:over = max([0, a:st.moves - a:st.par])
  return max([l:base / 4, l:base - 5 * l:over])
endfunction

function! arcade#sort#solved(st) abort
  for l:tube in a:st.tubes
    if empty(l:tube)
      continue
    endif
    if len(l:tube) < s:CAP
      return 0
    endif
    for l:ball in l:tube
      if l:ball != l:tube[0]
        return 0
      endif
    endfor
  endfor
  return a:st.held < 0
endfunction

function! arcade#sort#is_stuck(st) abort
  if a:st.held >= 0
    return 0
  endif
  for l:src in range(len(a:st.tubes))
    for l:dst in range(len(a:st.tubes))
      if arcade#sort#can_move(a:st, l:src, l:dst)
        return 0
      endif
    endfor
  endfor
  return !arcade#sort#solved(a:st)
endfunction

" ---------------------------------------------------------------- hand

function! arcade#sort#cursor_move(st, delta) abort
  let l:n = len(a:st.tubes)
  let a:st.cursor = (a:st.cursor + a:delta + l:n) % l:n
  return 1
endfunction

function! arcade#sort#grab(st) abort
  if a:st.held >= 0 || a:st.level_done
    return 0
  endif
  if empty(a:st.tubes[a:st.cursor])
    let a:st.message = 'That tube is empty.'
    return 0
  endif
  let a:st.held = remove(a:st.tubes[a:st.cursor], -1)
  let a:st.held_from = a:st.cursor
  let a:st.message = ''
  return 1
endfunction

" Drops the held ball on the tube under the cursor. Dropping it back where
" it came from is always allowed and costs no move.
function! arcade#sort#drop(st) abort
  if a:st.held < 0
    return 0
  endif
  let l:src = a:st.held_from
  let l:dst = a:st.cursor
  call add(a:st.tubes[l:src], a:st.held)
  let a:st.held = -1
  let a:st.held_from = -1
  if l:src == l:dst
    let a:st.message = 'Put it back.'
    return 1
  endif
  if arcade#sort#move(a:st, l:src, l:dst)
    return 1
  endif
  " Illegal target: keep the ball in hand rather than silently dumping it.
  let a:st.held = remove(a:st.tubes[l:src], -1)
  let a:st.held_from = l:src
  let a:st.message = len(a:st.tubes[l:dst]) >= s:CAP
        \ ? 'That tube is full.'
        \ : 'Only onto its own colour, or an empty tube.'
  return 0
endfunction

function! arcade#sort#toggle(st) abort
  return a:st.held >= 0 ? arcade#sort#drop(a:st) : arcade#sort#grab(a:st)
endfunction

function! arcade#sort#undo(st) abort
  if a:st.held >= 0
    call add(a:st.tubes[a:st.held_from], a:st.held)
    let a:st.held = -1
    let a:st.held_from = -1
    let a:st.message = 'Put it back.'
    return 1
  endif
  if a:st.level_done || empty(a:st.history)
    let a:st.message = 'Nothing to undo.'
    return 0
  endif
  let l:prev = remove(a:st.history, -1)
  let a:st.tubes = l:prev.tubes
  let a:st.moves = l:prev.moves
  let a:st.stuck = 0
  let a:st.message = 'Undid one move.'
  return 1
endfunction

function! arcade#sort#next_level(st) abort
  if !a:st.level_done
    return 0
  endif
  let a:st.level += 1
  call arcade#sort#build_level(a:st)
  return 1
endfunction

function! arcade#sort#score(st) abort
  return a:st.score
endfunction

" ------------------------------------------------------------- rendering

function! s:color_group(ball) abort
  return 'ArcadeSortC' . arcade#util#clamp(a:ball, 1, s:MAX_COLORS)
endfunction

function! arcade#sort#draw(st) abort
  let l:g = s:glyphs()
  let l:margin = '  '
  let l:n = len(a:st.tubes)
  let l:lines = []
  let l:hl = []

  let l:head = l:margin . 'sort'
  call add(l:hl, [0, strlen(l:margin), strlen(l:head), 'ArcadeSortTitle'])
  call add(l:lines, l:head)
  let l:stats = printf('level %d   colours %d   moves %d   score %d   best %d',
        \ a:st.level, a:st.colors, a:st.moves, a:st.score,
        \ max([a:st.best, a:st.score]))
  call add(l:hl, [1, strlen(l:margin), strlen(l:margin . l:stats), 'ArcadeSortScore'])
  call add(l:lines, l:margin . l:stats)
  call add(l:lines, '')

  " The hand: the held ball floats over its column.
  let l:lnum = len(l:lines)
  let l:line = l:margin
  for l:i in range(l:n)
    let l:pos = strlen(l:line)
    if l:i == a:st.cursor && a:st.held >= 0
      let l:ch = l:g.balls[a:st.held - 1]
      let l:line .= ' ' . l:ch . ' '
      call add(l:hl, [l:lnum, l:pos + 1, l:pos + 1 + strlen(l:ch), s:color_group(a:st.held)])
    else
      let l:line .= '   '
    endif
    let l:line .= l:i < l:n - 1 ? ' ' : ''
  endfor
  call add(l:lines, l:line)

  " Tubes are open at the top, so there is no top border: row 0 is the
  " highest slot, row cap-1 sits on the floor of the tube.
  for l:row in range(s:CAP)
    let l:slot = s:CAP - 1 - l:row
    let l:lnum = len(l:lines)
    let l:line = l:margin
    for l:i in range(l:n)
      let l:wall = l:i == a:st.cursor ? 'ArcadeSortCursor' : 'ArcadeSortTube'
      let l:pos = strlen(l:line)
      let l:line .= l:g.wall
      call add(l:hl, [l:lnum, l:pos, strlen(l:line), l:wall])
      let l:tube = a:st.tubes[l:i]
      if l:slot < len(l:tube)
        let l:ch = l:g.balls[l:tube[l:slot] - 1]
        let l:pos = strlen(l:line)
        let l:line .= l:ch
        call add(l:hl, [l:lnum, l:pos, strlen(l:line), s:color_group(l:tube[l:slot])])
      else
        let l:line .= ' '
      endif
      let l:pos = strlen(l:line)
      let l:line .= l:g.wall
      call add(l:hl, [l:lnum, l:pos, strlen(l:line), l:wall])
      let l:line .= l:i < l:n - 1 ? ' ' : ''
    endfor
    call add(l:lines, l:line)
  endfor

  let l:lnum = len(l:lines)
  let l:line = l:margin
  for l:i in range(l:n)
    let l:pos = strlen(l:line)
    let l:line .= l:g.bl . l:g.h . l:g.br
    call add(l:hl, [l:lnum, l:pos, strlen(l:line),
          \ l:i == a:st.cursor ? 'ArcadeSortCursor' : 'ArcadeSortTube'])
    let l:line .= l:i < l:n - 1 ? ' ' : ''
  endfor
  call add(l:lines, l:line)

  let l:lnum = len(l:lines)
  let l:line = l:margin
  for l:i in range(l:n)
    let l:pos = strlen(l:line)
    if l:i == a:st.cursor
      let l:line .= ' ' . l:g.caret . ' '
      call add(l:hl, [l:lnum, l:pos + 1, l:pos + 1 + strlen(l:g.caret), 'ArcadeSortCursor'])
    else
      let l:line .= '   '
    endif
    let l:line .= l:i < l:n - 1 ? ' ' : ''
  endfor
  call add(l:lines, l:line)
  call add(l:lines, '')

  if a:st.level_done
    let l:banner = printf('LEVEL CLEAR  +%d in %d moves  --  space for the next one',
          \ a:st.gained, a:st.moves)
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:banner), 'ArcadeSortWin'])
    call add(l:lines, l:margin . l:banner)
  elseif a:st.stuck
    let l:banner = 'STUCK  --  u undoes, r reshuffles this level'
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:banner), 'ArcadeSortStuck'])
    call add(l:lines, l:margin . l:banner)
  elseif !empty(a:st.message)
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . a:st.message), 'ArcadeSortMsg'])
    call add(l:lines, l:margin . a:st.message)
  else
    call add(l:lines, '')
  endif
  let l:hint = 'hl / arrows move   space grab drop   u undo   r reshuffle   q quit'
  call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:hint), 'ArcadeSortHint'])
  call add(l:lines, l:margin . l:hint)

  return {'lines': l:lines, 'hl': l:hl}
endfunction

" --------------------------------------------------------------- session

function! s:on_cursor(ctl, key) abort
  let l:delta = index(['h', '<Left>'], a:key) >= 0 ? -1 : 1
  call arcade#sort#cursor_move(a:ctl.state, l:delta)
endfunction

function! s:on_space(ctl, key) abort
  if a:ctl.state.level_done
    call arcade#sort#next_level(a:ctl.state)
    return
  endif
  call arcade#sort#toggle(a:ctl.state)
endfunction

function! s:on_undo(ctl, key) abort
  call arcade#sort#undo(a:ctl.state)
endfunction

" Reshuffles the current level; the run's score so far is kept.
function! s:on_restart(ctl, key) abort
  call arcade#sort#build_level(a:ctl.state)
endfunction

function! s:maybe_record(st) abort
  if a:st.recorded || a:st.score <= 0
    return
  endif
  let a:st.recorded = 1
  call arcade#score#record('sort', a:st.score,
        \ {'level': a:st.level, 'cleared': a:st.cleared, 'moves': a:st.total_moves})
  let a:st.best = arcade#score#best('sort')
endfunction

function! s:on_quit(ctl, key) abort
  call s:maybe_record(a:ctl.state)
  call arcade#ui#close()
endfunction

function! arcade#sort#start(...) abort
  let l:ctl = {
        \ 'name': 'arcade://sort',
        \ 'filetype': 'arcadesort',
        \ 'state': call('arcade#sort#new', a:000),
        \ 'draw': function('arcade#sort#draw'),
        \ 'keys': {},
        \ }
  for l:key in ['h', 'l', '<Left>', '<Right>']
    let l:ctl.keys[l:key] = function('s:on_cursor')
  endfor
  for l:key in ['<Space>', '<CR>']
    let l:ctl.keys[l:key] = function('s:on_space')
  endfor
  let l:ctl.keys['u'] = function('s:on_undo')
  let l:ctl.keys['r'] = function('s:on_restart')
  let l:ctl.keys['q'] = function('s:on_quit')
  return arcade#ui#open(l:ctl)
endfunction
