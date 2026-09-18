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
      \ 's:test_crawl_playout', 's:test_surface']

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
