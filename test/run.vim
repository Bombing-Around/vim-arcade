" Headless test suite:  vim -Nu NONE -es -S test/run.vim
set nocompatible
set runtimepath^=.
filetype off
let v:errors = []
let s:failed = 0

function! s:ok(cond, msg) abort
  if !a:cond
    call add(v:errors, 'FAIL: ' . a:msg)
  endif
endfunction

function! s:eq(got, want, msg) abort
  if a:got !=# a:want
    call add(v:errors, printf('FAIL: %s (got %s want %s)', a:msg, string(a:got), string(a:want)))
  endif
endfunction

" Every highlight span must sit inside its line's byte range.
function! s:check_frame(frame, msg) abort
  for l:span in get(a:frame, 'hl', [])
    let [l:lnum, l:s, l:e, l:group] = l:span
    call s:ok(l:lnum >= 0 && l:lnum < len(a:frame.lines),
          \ a:msg . ': span line out of range ' . string(l:span))
    if l:lnum < 0 || l:lnum >= len(a:frame.lines)
      continue
    endif
    let l:len = strlen(a:frame.lines[l:lnum])
    call s:ok(l:s >= 0 && l:e <= l:len && l:s <= l:e,
          \ printf('%s: span %s exceeds line length %d', a:msg, string(l:span), l:len))
    call s:ok(!empty(l:group), a:msg . ': empty highlight group')
  endfor
endfunction

" ------------------------------------------------------------------- 2048

function! s:test_collapse() abort
  call s:eq(arcade#twenty48#collapse([2, 2, 4, 0]), [[4, 4, 0, 0], 4], 'collapse pair + tail')
  call s:eq(arcade#twenty48#collapse([2, 2, 2, 2]), [[4, 4, 0, 0], 8], 'collapse two pairs')
  call s:eq(arcade#twenty48#collapse([4, 4, 8, 8]), [[8, 16, 0, 0], 24], 'collapse distinct pairs')
  call s:eq(arcade#twenty48#collapse([0, 0, 0, 2]), [[2, 0, 0, 0], 0], 'collapse slides only')
  call s:eq(arcade#twenty48#collapse([2, 4, 2, 4]), [[2, 4, 2, 4], 0], 'collapse no merge')
  call s:eq(arcade#twenty48#collapse([4, 4, 4, 0]), [[8, 4, 0, 0], 8], 'merge is leftmost-first')
  call s:eq(arcade#twenty48#collapse([0, 0, 0, 0]), [[0, 0, 0, 0], 0], 'collapse empty')
endfunction

function! s:test_move() abort
  let l:st = arcade#twenty48#new(42)
  call s:eq(len(arcade#twenty48#empty_cells(l:st)), 14, 'new board has two tiles')
  let l:st.grid = [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
  let l:st.score = 0
  call s:ok(arcade#twenty48#move(l:st, 'h'), 'left move changes board')
  call s:eq(l:st.grid[0][0], 4, 'tiles merged to the left')
  call s:eq(l:st.score, 4, 'score credited')

  let l:st2 = arcade#twenty48#new(7)
  let l:st2.grid = [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
  call s:ok(!arcade#twenty48#move(l:st2, 'k'), 'no-op move reports no change')

  let l:st3 = arcade#twenty48#new(9)
  let l:st3.grid = [[0, 0, 0, 2], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]]
  call s:ok(arcade#twenty48#move(l:st3, 'j'), 'down move changes board')
  call s:eq(l:st3.grid[3][3], 4, 'vertical merge lands at the bottom')
endfunction

function! s:test_game_over() abort
  let l:st = arcade#twenty48#new(1)
  let l:st.grid = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]]
  call s:ok(!arcade#twenty48#can_move(l:st), 'checkerboard is dead')
  let l:st.grid[3][3] = 4
  call s:ok(arcade#twenty48#can_move(l:st), 'adjacent pair is alive')
endfunction

function! s:test_undo() abort
  let l:st = arcade#twenty48#new(5)
  let l:st.grid = [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
  let l:snapshot = deepcopy(l:st.grid)
  call arcade#twenty48#move(l:st, 'h')
  call arcade#twenty48#undo(l:st)
  call s:eq(l:st.grid, l:snapshot, 'undo restores the grid')
  call s:eq(l:st.score, 0, 'undo restores the score')
  call s:ok(!arcade#twenty48#undo(l:st), 'undo on empty history is a no-op')
endfunction

function! s:test_2048_playout() abort
  let l:st = arcade#twenty48#new(1234)
  let l:dirs = ['h', 'j', 'k', 'l']
  let l:guard = 0
  while !l:st.over && l:guard < 3000
    call arcade#twenty48#move(l:st, l:dirs[arcade#util#rng_int(l:st.rng, 4)])
    let l:guard += 1
  endwhile
  call s:ok(l:st.over, 'random playout reaches game over')
  call s:ok(l:st.score > 0, 'random playout scores')
  call s:check_frame(arcade#twenty48#draw(l:st), '2048 draw')
  let l:widths = map(copy(arcade#twenty48#draw(l:st).lines), 'strdisplaywidth(v:val)')
  call s:ok(max(l:widths) < 60, '2048 board fits a narrow window')
endfunction

" ------------------------------------------------------------------ crawl

function! s:test_crawl_level() abort
  let l:st = arcade#crawl#new(99)
  call s:eq(arcade#crawl#tile(l:st, l:st.player.x, l:st.player.y), '.', 'player starts on floor')
  call s:ok(len(l:st.rooms) >= 2, 'level has rooms')
  call s:ok(!empty(l:st.monsters), 'level has monsters')
  call s:ok(l:st.visible[l:st.player.y][l:st.player.x], 'player sees own tile')
  call s:eq(arcade#crawl#tile(l:st, -1, 0), '#', 'out of bounds reads as wall')

  let l:stairs = 0
  for l:y in range(len(l:st.map))
    for l:x in range(len(l:st.map[l:y]))
      if l:st.map[l:y][l:x] ==# '>'
        let l:stairs += 1
      endif
    endfor
  endfor
  call s:eq(l:stairs, 1, 'exactly one staircase')
endfunction

function! s:test_crawl_actions() abort
  let l:st = arcade#crawl#new(3)
  call s:ok(!arcade#crawl#step(l:st, 0, 0) || 1, 'stepping nowhere is safe')

  " Walking into a wall costs no turn.
  let l:turns = l:st.turns
  let l:blocked = 0
  for l:d in [[-1, 0], [1, 0], [0, -1], [0, 1]]
    if arcade#crawl#tile(l:st, l:st.player.x + l:d[0], l:st.player.y + l:d[1]) ==# '#'
      call s:ok(!arcade#crawl#step(l:st, l:d[0], l:d[1]), 'walking into a wall is rejected')
      let l:blocked = 1
      break
    endif
  endfor
  call s:eq(l:st.turns, l:turns, 'blocked move consumes no turn')

  let l:potions = l:st.player.potions
  let l:st.player.hp = 1
  call s:ok(arcade#crawl#quaff(l:st), 'quaff succeeds with a potion in hand')
  call s:eq(l:st.player.potions, l:potions - 1, 'quaff consumes a potion')
  call s:ok(l:st.player.hp > 1, 'quaff heals')
  let l:st.player.potions = 0
  call s:ok(!arcade#crawl#quaff(l:st), 'quaff without potions fails')

  call s:ok(!arcade#crawl#descend(l:st), 'descend off-stairs fails')
  let l:depth = l:st.depth
  let l:st.map[l:st.player.y][l:st.player.x] = '>'
  call s:ok(arcade#crawl#descend(l:st), 'descend on stairs works')
  call s:eq(l:st.depth, l:depth + 1, 'depth advances')
  call s:eq(arcade#crawl#tile(l:st, l:st.player.x, l:st.player.y), '.', 'new level places player on floor')
endfunction

function! s:test_crawl_playout() abort
  let l:st = arcade#crawl#new(2024)
  let l:dirs = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [1, -1], [-1, 1]]
  let l:i = 0
  while !l:st.over && l:i < 4000
    let l:d = l:dirs[arcade#util#rng_int(l:st.rng, len(l:dirs))]
    call arcade#crawl#step(l:st, l:d[0], l:d[1])
    if arcade#crawl#tile(l:st, l:st.player.x, l:st.player.y) ==# '>'
      call arcade#crawl#descend(l:st)
    endif
    call s:ok(arcade#crawl#tile(l:st, l:st.player.x, l:st.player.y) !=# '#',
          \ 'player never stands in a wall')
    if l:st.player.hp < 5 && l:st.player.potions > 0
      call arcade#crawl#quaff(l:st)
    endif
    let l:i += 1
  endwhile
  call s:ok(l:st.turns > 0, 'playout took turns')
  call s:ok(arcade#crawl#score(l:st) >= 0, 'score is well defined')
  call s:check_frame(arcade#crawl#draw(l:st), 'crawl draw')
  let l:st.help = 1
  call s:check_frame(arcade#crawl#draw(l:st), 'crawl help draw')
endfunction

" ------------------------------------------------------------------- sort

function! s:tube_counts(st) abort
  let l:counts = {}
  for l:tube in a:st.tubes
    for l:ball in l:tube
      let l:counts[l:ball] = get(l:counts, l:ball, 0) + 1
    endfor
  endfor
  return l:counts
endfunction

" Tubes holding more than one colour. A generator bug that only shuffles
" whole colours between tubes leaves this at zero and hands out boards
" that are already all but solved.
function! s:mixed_tubes(st) abort
  let l:mixed = 0
  for l:tube in a:st.tubes
    for l:ball in l:tube
      if l:ball != l:tube[0]
        let l:mixed += 1
        break
      endif
    endfor
  endfor
  return l:mixed
endfunction

function! s:test_sort_level() abort
  let l:st = arcade#sort#new(17)
  call s:eq(l:st.level, 1, 'first level')
  call s:eq(l:st.colors, 4, 'level one has four colours')
  call s:eq(len(l:st.tubes), 6, 'colours plus two free tubes')
  call s:eq(s:tube_counts(l:st), {1: 4, 2: 4, 3: 4, 4: 4}, 'four balls of every colour')
  call s:ok(s:mixed_tubes(l:st) >= 2, 'the deal actually mixes colours together')
  call s:ok(!arcade#sort#solved(l:st), 'a fresh level is not already solved')
  call s:ok(!arcade#sort#is_stuck(l:st), 'a fresh level has a legal move')
  for l:tube in l:st.tubes
    call s:ok(len(l:tube) <= 4, 'no tube overflows')
  endfor
endfunction

function! s:test_sort_rules() abort
  let l:st = arcade#sort#new(3)
  let l:st.tubes = [[1, 1], [2], [], [1, 1, 1, 1]]
  call s:ok(arcade#sort#can_move(l:st, 0, 2), 'anything fits an empty tube')
  call s:ok(!arcade#sort#can_move(l:st, 0, 1), 'colours must match')
  call s:ok(arcade#sort#can_move(l:st, 1, 2), 'empty tube accepts any colour')
  call s:ok(!arcade#sort#can_move(l:st, 0, 3), 'a full tube takes nothing')
  call s:ok(!arcade#sort#can_move(l:st, 2, 0), 'an empty tube gives nothing')
  call s:ok(!arcade#sort#can_move(l:st, 0, 0), 'a tube cannot feed itself')
  call s:ok(!arcade#sort#can_move(l:st, 0, 9), 'out of range is not a move')

  call s:ok(arcade#sort#move(l:st, 0, 2), 'legal move applies')
  call s:eq(l:st.tubes[0], [1], 'ball left the source')
  call s:eq(l:st.tubes[2], [1], 'ball landed on the target')
  call s:eq(l:st.moves, 1, 'move counted')
  call s:ok(!arcade#sort#move(l:st, 0, 1), 'illegal move is rejected')
  call s:eq(l:st.moves, 1, 'rejected move costs nothing')

  call s:ok(arcade#sort#undo(l:st), 'undo restores the board')
  call s:eq(l:st.tubes[0], [1, 1], 'source is whole again')
  call s:eq(l:st.moves, 0, 'undo rewinds the move count')
  call s:ok(!arcade#sort#undo(l:st), 'undo with no history is a no-op')
endfunction

function! s:test_sort_hand() abort
  let l:st = arcade#sort#new(4)
  let l:st.tubes = [[1, 2], [2], [], [3, 3, 3, 3]]
  let l:st.cursor = 0

  call s:ok(arcade#sort#grab(l:st), 'space lifts the top ball')
  call s:eq(l:st.held, 2, 'the lifted ball is the top one')
  call s:eq(l:st.tubes[0], [1], 'lifted ball leaves the tube')
  call s:ok(!arcade#sort#grab(l:st), 'only one ball in hand at a time')

  let l:st.cursor = 3
  call s:ok(!arcade#sort#drop(l:st), 'cannot drop onto a full tube')
  call s:eq(l:st.held, 2, 'a refused drop keeps the ball in hand')

  let l:st.cursor = 1
  call s:ok(arcade#sort#drop(l:st), 'drop onto a matching top works')
  call s:eq(l:st.held, -1, 'hand is empty after a drop')
  call s:eq(l:st.tubes[1], [2, 2], 'ball stacked on its own colour')

  let l:st.cursor = 0
  call arcade#sort#grab(l:st)
  call s:ok(arcade#sort#drop(l:st), 'dropping a ball back where it came from works')
  call s:eq(l:st.tubes[0], [1], 'put-back leaves the tube unchanged')
  call s:eq(l:st.moves, 1, 'put-back costs no move')

  call arcade#sort#grab(l:st)
  call s:ok(arcade#sort#undo(l:st), 'undo with a full hand puts the ball back')
  call s:eq(l:st.tubes[0], [1], 'undo returned the held ball')

  let l:n = len(l:st.tubes)
  let l:st.cursor = 0
  call arcade#sort#cursor_move(l:st, -1)
  call s:eq(l:st.cursor, l:n - 1, 'cursor wraps left')
  call arcade#sort#cursor_move(l:st, 1)
  call s:eq(l:st.cursor, 0, 'cursor wraps right')
endfunction

function! s:test_sort_clear() abort
  let l:st = arcade#sort#new(8)
  let l:st.colors = 2
  let l:st.par = 8
  let l:st.tubes = [[1, 1, 1, 1], [2, 2, 2], [2], []]
  let l:st.cursor = 2
  call s:ok(!arcade#sort#solved(l:st), 'a split colour is not solved')
  call s:ok(arcade#sort#move(l:st, 2, 1), 'last ball goes home')
  call s:ok(arcade#sort#solved(l:st), 'board is solved')
  call s:ok(l:st.level_done, 'level marked clear')
  call s:ok(l:st.score > 0, 'clearing a level scores')
  call s:ok(!arcade#sort#move(l:st, 0, 3), 'a cleared board takes no more moves')

  let l:level = l:st.level
  call s:ok(arcade#sort#next_level(l:st), 'space advances')
  call s:eq(l:st.level, l:level + 1, 'level advanced')
  call s:eq(l:st.moves, 0, 'move count resets per level')
  call s:ok(!l:st.level_done, 'new level is unsolved')
  call s:ok(empty(l:st.history), 'undo history does not cross levels')
endfunction

function! s:test_sort_stuck() abort
  let l:st = arcade#sort#new(6)
  let l:st.tubes = [[1, 2, 1, 2], [2, 1, 2, 1], [1, 2, 1, 2], [2, 1, 2, 1]]
  call s:ok(arcade#sort#is_stuck(l:st), 'full mismatched tubes are stuck')
  let l:st.held = 1
  call s:ok(!arcade#sort#is_stuck(l:st), 'a ball in hand is never stuck')
endfunction

" The generator walks backwards from a solved board, so every level it
" hands out has to be complete, mixed, and open to a legal move.
function! s:test_sort_levels_are_playable() abort
  let l:st = arcade#sort#new(2718)
  for l:i in range(6)
    call s:ok(!arcade#sort#solved(l:st), printf('level %d is not pre-solved', l:st.level))
    call s:ok(!arcade#sort#is_stuck(l:st), printf('level %d opens with a legal move', l:st.level))
    call s:eq(len(l:st.tubes), l:st.colors + 2, 'two free tubes at every level')
    let l:want = {}
    for l:c in range(1, l:st.colors)
      let l:want[l:c] = 4
    endfor
    call s:eq(s:tube_counts(l:st), l:want, 'every colour is complete')
    call s:ok(s:mixed_tubes(l:st) >= l:st.colors / 2,
          \ printf('level %d is properly mixed', l:st.level))
    call s:check_frame(arcade#sort#draw(l:st), 'sort draw')
    let l:st.level += 1
    call arcade#sort#build_level(l:st)
  endfor
  call s:eq(l:st.colors, 9, 'colour count tops out')
endfunction

function! s:test_sort_draw() abort
  let l:st = arcade#sort#new(21)
  call s:check_frame(arcade#sort#draw(l:st), 'sort draw')
  let l:st.held = 1
  let l:st.held_n = 1
  let l:st.held_from = 0
  let l:st.cursor = 2
  call s:check_frame(arcade#sort#draw(l:st), 'sort draw with a ball in hand')
  let l:st.held_n = 4
  call s:check_frame(arcade#sort#draw(l:st), 'sort draw with a full hand')
  let l:st.held = -1
  let l:st.held_n = 0
  let l:st.level_done = 1
  call s:check_frame(arcade#sort#draw(l:st), 'sort clear banner')
  let l:st.level_done = 0
  let l:st.stuck = 1
  call s:check_frame(arcade#sort#draw(l:st), 'sort stuck banner')
  let l:st.stuck = 0
  let l:st.message = 'That tube is empty.'
  call s:check_frame(arcade#sort#draw(l:st), 'sort message')

  " Widest board: nine colours plus two free tubes.
  let l:wide = arcade#sort#new(5)
  let l:wide.level = 9
  call arcade#sort#build_level(l:wide)
  let l:widths = map(copy(arcade#sort#draw(l:wide).lines), 'strdisplaywidth(v:val)')
  call s:ok(max(l:widths) < 72, 'sort board fits a modest window')
  call s:check_frame(arcade#sort#draw(l:wide), 'sort wide draw')
endfunction

function! s:test_sort_run_length() abort
  call s:eq(arcade#sort#run_length([]), 0, 'empty tube has no run')
  call s:eq(arcade#sort#run_length([1]), 1, 'single ball is a run of one')
  call s:eq(arcade#sort#run_length([2, 1, 1, 1]), 3, 'run stops at a different colour')
  call s:eq(arcade#sort#run_length([1, 1, 1, 1]), 4, 'a whole tube can be one run')
  call s:eq(arcade#sort#run_length([1, 1, 2]), 1, 'only the top counts')
endfunction

function! s:test_sort_stack_grab() abort
  let l:st = arcade#sort#new(31)
  let l:st.tubes = [[2, 1, 1, 1], [1], [], [3, 3, 3, 3]]
  let l:st.cursor = 0

  call s:eq(arcade#sort#grab(l:st), 3, 'space lifts the whole run')
  call s:eq(l:st.held, 1, 'the handful is one colour')
  call s:eq(l:st.held_n, 3, 'three balls in hand')
  call s:eq(l:st.tubes[0], [2], 'the run left the tube')

  let l:st.cursor = 2
  call s:eq(arcade#sort#drop(l:st), 3, 'the whole handful lands on an empty tube')
  call s:eq(l:st.tubes[2], [1, 1, 1], 'three balls landed')
  call s:eq(l:st.held_n, 0, 'hand is empty')
  call s:eq(l:st.moves, 3, 'moves count balls, not keystrokes')

  " One undo step covers the whole handful.
  call s:ok(arcade#sort#undo(l:st), 'undo after a stack drop')
  call s:eq(l:st.tubes[0], [2, 1, 1, 1], 'the run came back whole')
  call s:eq(l:st.tubes[2], [], 'the target is empty again')
  call s:eq(l:st.moves, 0, 'move count rewound past the whole handful')
endfunction

function! s:test_sort_count_grab() abort
  let l:st = arcade#sort#new(32)
  let l:st.tubes = [[1, 1, 1], [2, 2], [], []]
  let l:st.cursor = 0

  call s:eq(arcade#sort#grab(l:st, 2), 2, '2space lifts two of three')
  call s:eq(l:st.tubes[0], [1], 'one ball stayed behind')
  let l:st.cursor = 2
  call s:eq(arcade#sort#drop(l:st), 2, 'both land')

  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st, 9), 1, 'a count past the run takes the run')
  let l:st.cursor = 3
  call s:eq(arcade#sort#drop(l:st), 1, 'and drops it')

  " A count on the drop splits the handful the other way.
  let l:st.tubes = [[1, 1, 1, 1], [], []]
  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st), 4, 'lift four')
  let l:st.cursor = 1
  call s:eq(arcade#sort#drop(l:st, 1), 1, '1space drops one of four')
  call s:eq(l:st.held_n, 3, 'three stay in hand')
  call s:eq(l:st.held_from, 0, 'the rest still belong to the source tube')
  call s:ok(arcade#sort#undo(l:st), 'undo puts the rest back first')
  call s:eq(l:st.tubes[0], [1, 1, 1], 'the held balls went home')
  call s:eq(l:st.held_n, 0, 'hand empty after the put-back')
endfunction

" The manoeuvre this is all for: three in hand, a tube with room for two,
" the last one goes somewhere else.
function! s:test_sort_partial_drop() abort
  let l:st = arcade#sort#new(33)
  let l:st.tubes = [[1, 1, 1], [2, 1], [], [4, 4, 4, 4]]
  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st), 3, 'lift the run of three')

  let l:st.cursor = 1
  call s:eq(arcade#sort#drop(l:st), 2, 'only what fits goes in')
  call s:eq(l:st.tubes[1], [2, 1, 1, 1], 'target is full')
  call s:eq(l:st.held_n, 1, 'the odd one stays in hand')
  call s:eq(l:st.held, 1, 'still the same colour')

  let l:st.cursor = 2
  call s:eq(arcade#sort#drop(l:st), 1, 'the last one goes elsewhere')
  call s:eq(l:st.tubes[2], [1], 'and lands')
  call s:eq(l:st.held_n, 0, 'hand empty')

  " Two drops, two undos, and no ball is lost in between.
  call s:ok(arcade#sort#undo(l:st), 'undo the second drop')
  call s:eq(l:st.held_n, 0, 'undo of a completed drop does not refill the hand')
  call s:ok(arcade#sort#undo(l:st), 'undo the first drop')
  call s:eq(l:st.tubes[0], [1, 1, 1], 'the whole run is back')
  call s:eq(l:st.tubes[1], [2, 1], 'the target is as it was')
  call s:eq(l:st.tubes[2], [], 'and so is the spare')
endfunction

function! s:test_sort_refused_drop_keeps_hand() abort
  let l:st = arcade#sort#new(34)
  let l:st.tubes = [[1, 1], [2, 2, 2, 2], [3]]
  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st), 2, 'lift the pair')

  let l:st.cursor = 1
  call s:eq(arcade#sort#drop(l:st), 0, 'a full tube takes nothing')
  call s:eq(l:st.held_n, 2, 'the pair is still in hand')
  let l:st.cursor = 2
  call s:eq(arcade#sort#drop(l:st), 0, 'a mismatched top takes nothing')
  call s:eq(l:st.held_n, 2, 'still in hand')
  call s:eq(l:st.tubes[0], [], 'and still out of the source tube')
  call s:eq(l:st.moves, 0, 'refused drops cost nothing')
endfunction

function! s:test_sort_move_n() abort
  let l:st = arcade#sort#new(35)
  let l:st.tubes = [[2, 1, 1, 1], [1], [], []]
  call s:eq(arcade#sort#move_n(l:st, 0, 1, 3), 3, 'three fit on a matching top')
  call s:eq(l:st.tubes[1], [1, 1, 1, 1], 'target filled')
  call s:eq(arcade#sort#move_n(l:st, 0, 1, 1), 0, 'nothing more fits')
  call s:eq(arcade#sort#move_n(l:st, 0, 2, 9), 1, 'a count past the run moves the run')
  call s:eq(arcade#sort#move_n(l:st, 2, 3, 0), 0, 'a zero move is no move')
endfunction

" A finished board announces itself however it got finished -- the clear
" is a fact about the tubes, not about which key laid the last ball.
function! s:test_sort_clear_every_path() abort
  " Put-back: lift the last ball off a finished tube and drop it straight
  " back where it came from.
  let l:st = arcade#sort#new(41)
  let l:st.colors = 2
  let l:st.par = 8
  let l:st.tubes = [[1, 1, 1, 1], [2, 2, 2, 2], [], []]
  let l:st.level_done = 0
  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st, 1), 1, 'lift a ball off a finished tube')
  call s:ok(!l:st.level_done, 'not clear while a ball is in hand')
  call s:eq(arcade#sort#drop(l:st), 1, 'put it straight back')
  call s:ok(l:st.level_done, 'a put-back that completes the board clears it')

  " Undo: walk a ball out of place and undo back into a finished board.
  let l:st2 = arcade#sort#new(42)
  let l:st2.colors = 2
  let l:st2.par = 8
  let l:st2.tubes = [[1, 1, 1, 1], [2, 2, 2, 2], [], []]
  let l:st2.level_done = 0
  call s:ok(arcade#sort#move(l:st2, 1, 2), 'move a ball out of a finished tube')
  call s:ok(!l:st2.level_done, 'board is not finished any more')
  call s:ok(arcade#sort#undo(l:st2), 'undo it back')
  call s:ok(l:st2.level_done, 'an undo that completes the board clears it')

  " And the award only lands once, however many times the board is read.
  let l:score = l:st2.score
  let l:cleared = l:st2.cleared
  call arcade#sort#refresh(l:st2)
  call arcade#sort#refresh(l:st2)
  call s:eq(l:st2.score, l:score, 'a cleared level pays out once')
  call s:eq(l:st2.cleared, l:cleared, 'and counts once')
endfunction

" Clearing a level through the hand, the way it is actually played. The
" board-level test below drives arcade#sort#move directly and so cannot
" see a hand that is still holding balls when the last one lands.
function! s:test_sort_clear_by_hand() abort
  let l:st = arcade#sort#new(36)
  let l:st.colors = 2
  let l:st.par = 8
  let l:st.tubes = [[1, 1, 1, 1], [2, 2, 2], [2], []]
  let l:st.cursor = 2
  call s:eq(arcade#sort#grab(l:st), 1, 'lift the stray ball')
  let l:st.cursor = 1
  call s:eq(arcade#sort#drop(l:st), 1, 'drop it home')
  call s:ok(arcade#sort#solved(l:st), 'board is solved')
  call s:ok(l:st.level_done, 'level clears when the last ball lands from the hand')
  call s:ok(l:st.score > 0, 'and it pays out')

  " Same thing with a handful rather than a single ball.
  let l:st2 = arcade#sort#new(37)
  let l:st2.colors = 2
  let l:st2.par = 8
  let l:st2.tubes = [[1, 1, 1, 1], [2], [2, 2, 2], []]
  let l:st2.cursor = 2
  call s:eq(arcade#sort#grab(l:st2), 3, 'lift the run')
  let l:st2.cursor = 1
  call s:eq(arcade#sort#drop(l:st2), 3, 'drop the run home')
  call s:ok(l:st2.level_done, 'a handful clears the level too')
endfunction

" Stuck is read off the board, so it has the same problem: a hand that
" still holds balls during the move hides it.
function! s:test_sort_stuck_by_hand() abort
  let l:st = arcade#sort#new(38)
  " Only tube 0 will have room once the ball in hand lands, and no other
  " tube's top matches what tube 0 is showing.
  let l:st.tubes = [[1, 2, 1, 3], [2, 1, 2, 4], [3, 4, 3, 2], [4, 4, 3]]
  let l:st.cursor = 0
  call s:eq(arcade#sort#grab(l:st), 1, 'lift the top ball')
  call s:ok(!arcade#sort#is_stuck(l:st), 'a hand with a ball in it is never stuck')
  let l:st.cursor = 3
  call s:eq(arcade#sort#drop(l:st), 1, 'land it on its colour')
  call s:ok(l:st.stuck, 'the dead end is noticed once the hand is empty')
  call s:ok(!l:st.level_done, 'a dead end is not a clear')
  call s:ok(arcade#sort#undo(l:st), 'and undo walks back out of it')
  call s:ok(!l:st.stuck, 'the flag clears with the undo')
endfunction

" Every level, played out along its own solution through grab and drop
" rather than through arcade#sort#move: the path a real game takes.
function! s:test_sort_solvable_by_hand() abort
  let l:st = arcade#sort#new(452)
  for l:level in range(2)
    let l:play = deepcopy(l:st)
    for l:mv in l:st.solution
      let l:play.cursor = l:mv[0]
      call arcade#sort#grab(l:play, 1)
      let l:play.cursor = l:mv[1]
      call arcade#sort#drop(l:play)
    endfor
    call s:ok(arcade#sort#solved(l:play), 'playing the solution by hand solves it')
    call s:ok(l:play.level_done, 'and clears the level')
    call s:eq(l:play.held_n, 0, 'with nothing left in hand')
    call s:ok(arcade#sort#next_level(l:play), 'and the next level is reachable')
    let l:st.level += 1
    call arcade#sort#build_level(l:st)
  endfor
endfunction

" The generator hands out the un-move walk it dealt from; replayed
" forwards it has to be a legal, winning line of play.
function! s:test_sort_solvable() abort
  let l:st = arcade#sort#new(451)
  for l:level in range(3)
    call s:ok(len(l:st.solution) > 0, 'level ships a solution')
    let l:play = deepcopy(l:st)
    for l:mv in l:st.solution
      call arcade#sort#move(l:play, l:mv[0], l:mv[1])
    endfor
    call s:ok(arcade#sort#solved(l:play),
          \ printf('level %d solves along its own line', l:st.level))
    call s:ok(l:play.level_done, 'solving the board clears the level')
    let l:st.level += 1
    call arcade#sort#build_level(l:st)
  endfor
endfunction

" Thousands of real moves through move/undo/solved, checking the board
" stays a legal board the whole way.
function! s:test_sort_playout() abort
  let l:st = arcade#sort#new(1009)
  let l:want = s:tube_counts(l:st)
  let l:last = [-1, -1]
  let l:i = 0
  while l:i < 600 && !l:st.level_done
    let l:legal = []
    for l:src in range(len(l:st.tubes))
      for l:dst in range(len(l:st.tubes))
        if arcade#sort#can_move(l:st, l:src, l:dst)
              \ && !(l:src == l:last[1] && l:dst == l:last[0])
          call add(l:legal, [l:src, l:dst])
        endif
      endfor
    endfor
    if empty(l:legal)
      call s:ok(arcade#sort#is_stuck(l:st) || l:st.level_done,
            \ 'no moves left means stuck or solved')
      break
    endif
    let l:pick = l:legal[arcade#util#rng_int(l:st.rng, len(l:legal))]
    call s:ok(arcade#sort#move(l:st, l:pick[0], l:pick[1]), 'legal move applies')
    let l:last = l:pick
    if arcade#util#rng_chance(l:st.rng, 15)
      call arcade#sort#undo(l:st)
      let l:last = [-1, -1]
    endif
    for l:tube in l:st.tubes
      call s:ok(len(l:tube) <= 4, 'no tube overflows mid-playout')
    endfor
    call s:eq(s:tube_counts(l:st), l:want, 'balls are conserved')
    let l:i += 1
  endwhile
  call s:ok(l:st.moves > 0, 'playout made moves')
  call s:check_frame(arcade#sort#draw(l:st), 'sort playout draw')
endfunction

function! s:test_rng_determinism() abort
  let l:a = arcade#util#rng_new(7)
  let l:b = arcade#util#rng_new(7)
  let l:seq_a = map(range(20), 'arcade#util#rng_int(l:a, 100)')
  let l:seq_b = map(range(20), 'arcade#util#rng_int(l:b, 100)')
  call s:eq(l:seq_a, l:seq_b, 'same seed gives the same sequence')
  call s:ok(max(l:seq_a) < 100 && min(l:seq_a) >= 0, 'rng stays in range')
  call s:eq(arcade#util#rng_int(l:a, 1), 0, 'rng_int(1) is always 0')
  call s:eq(strdisplaywidth(arcade#util#center('2', 7)), 7, 'center pads to width')
endfunction


" ------------------------------------------------------------------- buffer

function! s:test_surface() abort
  let g:arcade_window = 'current'
  let l:bufnr = arcade#twenty48#start(11)
  call s:eq(bufnr('%'), l:bufnr, '2048 surface is the current buffer')
  call s:eq(&l:buftype, 'nofile', 'surface is a scratch buffer')
  call s:ok(!&l:modifiable, 'surface is not modifiable')
  call s:ok(!empty(maparg('l', 'n')), 'movement key is mapped')
  let l:before = getbufline(l:bufnr, 1, '$')
  call s:ok(len(l:before) > 10, 'surface rendered the board')
  call arcade#ui#key('l')
  call arcade#ui#key('j')
  let l:after = getbufline(l:bufnr, 1, '$')
  call s:ok(l:before !=# l:after, 'keys mutate the rendered board')
  call s:ok(b:arcade.state.moves > 0, 'moves recorded')
  call arcade#ui#key('r')
  call s:eq(b:arcade.state.moves, 0, 'restart resets the run')
  silent! bwipeout!

  let l:bufnr = arcade#sort#start(13)
  call s:ok(len(getbufline(l:bufnr, 1, '$')) > 8, 'sort surface rendered')
  call s:ok(!empty(maparg('<Space>', 'n')), 'space is mapped')
  let l:cursor = b:arcade.state.cursor
  call arcade#ui#key('l')
  call s:eq(b:arcade.state.cursor, l:cursor + 1, 'l walks the cursor right')
  for l:i in range(len(b:arcade.state.tubes))
    if !empty(b:arcade.state.tubes[l:i])
      let b:arcade.state.cursor = l:i
      break
    endif
  endfor
  call arcade#ui#key('<Space>')
  call s:ok(b:arcade.state.held >= 0, 'space lifts a ball')
  call arcade#ui#key('<Space>')
  call s:eq(b:arcade.state.held, -1, 'space puts it back down')
  " A count reaches the handler through the controller dict.
  let b:arcade.state.tubes = [[1, 1, 1], [2], [], [3]]
  let b:arcade.state.cursor = 0
  call arcade#ui#key('<Space>', 2)
  call s:eq(b:arcade.state.held_n, 2, 'a count lifts that many balls')
  call arcade#ui#key('<Space>')
  call s:eq(b:arcade.state.held_n, 0, 'and space puts them back')
  let l:cursor = b:arcade.state.cursor
  call arcade#ui#key('h', 2)
  call s:eq(b:arcade.state.cursor, (l:cursor - 2 + len(b:arcade.state.tubes))
        \ % len(b:arcade.state.tubes), 'a count walks the cursor that far')
  silent! bwipeout!

  let l:bufnr = arcade#crawl#start(12)
  call s:ok(len(getbufline(l:bufnr, 1, '$')) > 20, 'crawl surface rendered')
  call arcade#ui#key('?')
  call s:ok(b:arcade.state.help, 'help toggles')
  call arcade#ui#key('?')
  call s:ok(!b:arcade.state.help, 'help toggles back')
  silent! bwipeout!
endfunction

" --------------------------------------------------------------------- run

let s:tests = [
      \ 's:test_rng_determinism', 's:test_collapse', 's:test_move', 's:test_game_over',
      \ 's:test_undo', 's:test_2048_playout', 's:test_crawl_level', 's:test_crawl_actions',
      \ 's:test_crawl_playout', 's:test_sort_level', 's:test_sort_rules',
      \ 's:test_sort_hand', 's:test_sort_clear', 's:test_sort_stuck',
      \ 's:test_sort_levels_are_playable', 's:test_sort_draw',
      \ 's:test_sort_run_length', 's:test_sort_stack_grab', 's:test_sort_count_grab',
      \ 's:test_sort_partial_drop', 's:test_sort_refused_drop_keeps_hand',
      \ 's:test_sort_move_n', 's:test_sort_clear_every_path', 's:test_sort_clear_by_hand',
      \ 's:test_sort_stuck_by_hand', 's:test_sort_solvable_by_hand',
      \ 's:test_sort_solvable', 's:test_sort_playout', 's:test_surface']

for s:name in s:tests
  try
    call call(s:name, [])
  catch
    call add(v:errors, printf('ERROR in %s: %s @ %s', s:name, v:exception, v:throwpoint))
  endtry
endfor

function! s:emit(lines) abort
  " -es swallows :echo on some builds; write straight to stdout.
  try
    call writefile(a:lines, '/dev/stdout', 'b')
  catch
    for s:line in a:lines
      echo s:line . "\n"
    endfor
  endtry
endfunction

if empty(v:errors)
  call s:emit([printf('ok - %d test functions, 0 failures', len(s:tests))])
  qall!
else
  call s:emit(v:errors + [printf('not ok - %d failure(s)', len(v:errors))])
  cquit!
endif
