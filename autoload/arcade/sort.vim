" arcade/sort.vim -- ball sort: stack every colour into its own tube.
" Logic is pure (state in, state out) so it can be tested headlessly;
" only #start and the key handlers touch a buffer.
"
" <Space> lifts the run of same-coloured balls off the top of the tube
" under the cursor, <Space> again drops it wherever it fits: an empty
" tube, or one whose top ball is the same colour and which has room.
"
" A count takes a partial handful -- 2<Space> lifts two of a run of
" three, and 2<Space> over the target drops two of what is in hand. A
" drop into a tube with less room than that takes what fits and leaves
" the rest in hand, which is the same manoeuvre without the arithmetic.
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
        \ 'held_n': 0,
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
  let a:st.held_n = 0
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

" How many same-coloured balls sit on top of a tube -- one handful.
function! arcade#sort#run_length(tube) abort
  if empty(a:tube)
    return 0
  endif
  let l:n = 1
  let l:i = len(a:tube) - 2
  while l:i >= 0 && a:tube[l:i] == a:tube[-1]
    let l:n += 1
    let l:i -= 1
  endwhile
  return l:n
endfunction

function! s:apply(st, src, dst) abort
  call add(a:st.tubes[a:dst], remove(a:st.tubes[a:src], -1))
endfunction

" Moves up to n balls src -> dst, capped by the run on top of src and the
" room in dst. One undo step covers the whole handful. Returns how many
" balls actually moved. Moves are counted per ball, so par and the score
" mean the same thing whether you shift a run in one keystroke or three.
function! arcade#sort#move_n(st, src, dst, n) abort
  if a:st.level_done || a:n <= 0 || !arcade#sort#can_move(a:st, a:src, a:dst)
    return 0
  endif
  let l:n = min([a:n, arcade#sort#run_length(a:st.tubes[a:src]),
        \ s:CAP - len(a:st.tubes[a:dst])])
  if l:n <= 0
    return 0
  endif
  call add(a:st.history, {'tubes': deepcopy(a:st.tubes), 'moves': a:st.moves})
  if len(a:st.history) > s:UNDO_DEPTH
    call remove(a:st.history, 0)
  endif
  for l:i in range(l:n)
    call s:apply(a:st, a:src, a:dst)
  endfor
  let a:st.moves += l:n
  let a:st.total_moves += l:n
  let a:st.message = ''
  call s:after_move(a:st)
  return l:n
endfunction

" Moves one ball src -> dst. Returns 1 if the board changed.
function! arcade#sort#move(st, src, dst) abort
  return arcade#sort#move_n(a:st, a:src, a:dst, 1) > 0
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
  return a:st.held_n == 0
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

function! arcade#sort#cursor_move(st, delta, ...) abort
  let l:step = a:delta * max([1, a:0 ? a:1 : 0])
  let l:n = len(a:st.tubes)
  let a:st.cursor = (a:st.cursor % l:n + l:step % l:n + l:n) % l:n
  return 1
endfunction

" Lifts the run off the top of the tube under the cursor, or the top
" {count} of it. Returns how many balls came up.
function! arcade#sort#grab(st, ...) abort
  let l:want = a:0 ? a:1 : 0
  if a:st.held >= 0 || a:st.level_done
    return 0
  endif
  let l:tube = a:st.tubes[a:st.cursor]
  if empty(l:tube)
    let a:st.message = 'That tube is empty.'
    return 0
  endif
  let l:run = arcade#sort#run_length(l:tube)
  let l:n = l:want > 0 ? min([l:want, l:run]) : l:run
  let a:st.held = l:tube[-1]
  let a:st.held_n = l:n
  let a:st.held_from = a:st.cursor
  call remove(l:tube, len(l:tube) - l:n, -1)
  let a:st.message = ''
  return l:n
endfunction

" Drops the handful on the tube under the cursor, or {count} of it.
" Whatever does not fit stays in hand. Dropping back where it came from
" is always allowed and costs no move.
function! arcade#sort#drop(st, ...) abort
  let l:want = a:0 ? a:1 : 0
  if a:st.held < 0
    return 0
  endif
  let l:src = a:st.held_from
  let l:dst = a:st.cursor
  let l:n = a:st.held_n
  let l:ball = a:st.held
  " Put the whole handful back first, so the drop goes through the same
  " rules -- and lands in the same undo snapshot -- as any other move.
  " The snapshot has to hold the balls still in hand too, or undoing a
  " partial drop would lose them.
  call extend(a:st.tubes[l:src], repeat([l:ball], l:n))
  if l:src == l:dst
    call s:empty_hand(a:st)
    let a:st.message = 'Put it back.'
    return l:n
  endif
  let l:moved = arcade#sort#move_n(a:st, l:src, l:dst,
        \ l:want > 0 ? min([l:want, l:n]) : l:n)
  let l:left = l:n - l:moved
  if l:left > 0
    call remove(a:st.tubes[l:src], len(a:st.tubes[l:src]) - l:left, -1)
    let a:st.held = l:ball
    let a:st.held_n = l:left
    let a:st.held_from = l:src
  else
    call s:empty_hand(a:st)
  endif
  if l:moved > 0
    if l:left > 0
      let a:st.message = printf('%d still in hand.', l:left)
    endif
    return l:moved
  endif
  let a:st.message = len(a:st.tubes[l:dst]) >= s:CAP
        \ ? 'That tube is full.'
        \ : 'Only onto its own colour, or an empty tube.'
  return 0
endfunction

function! s:empty_hand(st) abort
  let a:st.held = -1
  let a:st.held_n = 0
  let a:st.held_from = -1
endfunction

function! arcade#sort#toggle(st, ...) abort
  let l:count = a:0 ? a:1 : 0
  return a:st.held >= 0
        \ ? arcade#sort#drop(a:st, l:count)
        \ : arcade#sort#grab(a:st, l:count)
endfunction

function! arcade#sort#undo(st) abort
  if a:st.held >= 0
    call extend(a:st.tubes[a:st.held_from], repeat([a:st.held], a:st.held_n))
    call s:empty_hand(a:st)
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

  " The hand: held balls hover over their column, stacked up from the
  " mouth of the tube. The region is always s:CAP rows tall, empty or
  " not, so picking a handful up never shifts the board under you.
  for l:row in range(s:CAP)
    let l:depth = s:CAP - l:row
    let l:lnum = len(l:lines)
    let l:line = l:margin
    for l:i in range(l:n)
      let l:pos = strlen(l:line)
      if l:i == a:st.cursor && a:st.held >= 0 && a:st.held_n >= l:depth
        let l:ch = l:g.balls[a:st.held - 1]
        let l:line .= ' ' . l:ch . ' '
        call add(l:hl, [l:lnum, l:pos + 1, l:pos + 1 + strlen(l:ch), s:color_group(a:st.held)])
      else
        let l:line .= '   '
      endif
      let l:line .= l:i < l:n - 1 ? ' ' : ''
    endfor
    call add(l:lines, l:line)
  endfor

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
  for l:hint in ['hl move   space lifts a run, space drops it   2space lifts two',
        \ 'u undo   r reshuffle   q quit']
    call add(l:hl, [len(l:lines), strlen(l:margin), strlen(l:margin . l:hint), 'ArcadeSortHint'])
    call add(l:lines, l:margin . l:hint)
  endfor

  return {'lines': l:lines, 'hl': l:hl}
endfunction

" --------------------------------------------------------------- session

function! s:on_cursor(ctl, key) abort
  let l:delta = index(['h', '<Left>'], a:key) >= 0 ? -1 : 1
  call arcade#sort#cursor_move(a:ctl.state, l:delta, get(a:ctl, 'count', 0))
endfunction

function! s:on_space(ctl, key) abort
  if a:ctl.state.level_done
    call arcade#sort#next_level(a:ctl.state)
    return
  endif
  call arcade#sort#toggle(a:ctl.state, get(a:ctl, 'count', 0))
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
