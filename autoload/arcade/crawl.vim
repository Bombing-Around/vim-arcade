" arcade/crawl.vim -- a small turn-based dungeon crawler.
" Pure state machine: #new, #act and #descend never touch a buffer.

let s:W = 64
let s:H = 21
let s:FOV = 8
let s:LOG_LINES = 3

let s:MONSTERS = [
      \ {'glyph': 'r', 'name': 'rat',      'hp': 4,  'atk': 2, 'def': 0, 'xp': 2,  'min': 1, 'max': 3},
      \ {'glyph': 'k', 'name': 'kobold',   'hp': 7,  'atk': 3, 'def': 0, 'xp': 4,  'min': 1, 'max': 4},
      \ {'glyph': 'g', 'name': 'goblin',   'hp': 10, 'atk': 4, 'def': 1, 'xp': 7,  'min': 2, 'max': 6},
      \ {'glyph': 'o', 'name': 'orc',      'hp': 15, 'atk': 6, 'def': 2, 'xp': 12, 'min': 3, 'max': 8},
      \ {'glyph': 'W', 'name': 'wraith',   'hp': 18, 'atk': 8, 'def': 2, 'xp': 18, 'min': 5, 'max': 99},
      \ {'glyph': 'T', 'name': 'troll',    'hp': 26, 'atk': 9, 'def': 3, 'xp': 25, 'min': 6, 'max': 99},
      \ {'glyph': 'D', 'name': 'dragon',   'hp': 40, 'atk': 13,'def': 5, 'xp': 60, 'min': 8, 'max': 99},
      \ ]

function! s:max_depth() abort
  return get(g:, 'arcade_crawl_depth', 8)
endfunction

" ------------------------------------------------------------------- state

function! arcade#crawl#new(...) abort
  let l:seed = a:0 ? a:1 : 0
  let l:st = {
        \ 'rng': arcade#util#rng_new(l:seed),
        \ 'depth': 1,
        \ 'turns': 0,
        \ 'over': 0,
        \ 'won': 0,
        \ 'recorded': 0,
        \ 'help': 0,
        \ 'log': [],
        \ 'best': arcade#score#best('crawl'),
        \ 'player': {'x': 0, 'y': 0, 'hp': 24, 'maxhp': 24, 'atk': 4, 'def': 1,
        \            'xp': 0, 'level': 1, 'gold': 0, 'potions': 2, 'amulet': 0},
        \ }
  call arcade#crawl#build_level(l:st)
  call arcade#crawl#log(l:st, 'You descend into the dungeon. Find the stairs (>).')
  return l:st
endfunction

function! arcade#crawl#log(st, msg) abort
  call add(a:st.log, a:msg)
  if len(a:st.log) > 40
    call remove(a:st.log, 0, len(a:st.log) - 40)
  endif
endfunction

function! s:blank_grid(fill) abort
  return map(range(s:H), {_, __ -> repeat([a:fill], s:W)})
endfunction

function! arcade#crawl#tile(st, x, y) abort
  if a:x < 0 || a:y < 0 || a:x >= s:W || a:y >= s:H
    return '#'
  endif
  return a:st.map[a:y][a:x]
endfunction

function! s:walkable(st, x, y) abort
  return arcade#crawl#tile(a:st, a:x, a:y) !=# '#'
endfunction

function! arcade#crawl#monster_at(st, x, y) abort
  for l:m in a:st.monsters
    if l:m.x == a:x && l:m.y == a:y
      return l:m
    endif
  endfor
  return {}
endfunction

" ------------------------------------------------------------- generation

function! s:carve_room(st, room) abort
  for l:y in range(a:room.y, a:room.y + a:room.h - 1)
    for l:x in range(a:room.x, a:room.x + a:room.w - 1)
      let a:st.map[l:y][l:x] = '.'
    endfor
  endfor
endfunction

function! s:carve_h(st, x1, x2, y) abort
  for l:x in range(min([a:x1, a:x2]), max([a:x1, a:x2]))
    let a:st.map[a:y][l:x] = '.'
  endfor
endfunction

function! s:carve_v(st, y1, y2, x) abort
  for l:y in range(min([a:y1, a:y2]), max([a:y1, a:y2]))
    let a:st.map[l:y][a:x] = '.'
  endfor
endfunction

function! s:overlaps(a, b) abort
  return a:a.x <= a:b.x + a:b.w && a:b.x <= a:a.x + a:a.w
        \ && a:a.y <= a:b.y + a:b.h && a:b.y <= a:a.y + a:a.h
endfunction

function! arcade#crawl#build_level(st) abort
  let a:st.map = s:blank_grid('#')
  let a:st.seen = s:blank_grid(0)
  let a:st.visible = s:blank_grid(0)
  let a:st.monsters = []
  let a:st.items = []

  let l:rooms = []
  for l:try in range(80)
    if len(l:rooms) >= 9
      break
    endif
    let l:w = arcade#util#rng_range(a:st.rng, 5, 11)
    let l:h = arcade#util#rng_range(a:st.rng, 3, 6)
    let l:room = {
          \ 'w': l:w, 'h': l:h,
          \ 'x': arcade#util#rng_range(a:st.rng, 1, s:W - l:w - 2),
          \ 'y': arcade#util#rng_range(a:st.rng, 1, s:H - l:h - 2)}
    let l:clash = 0
    for l:other in l:rooms
      if s:overlaps(l:room, l:other)
        let l:clash = 1
        break
      endif
    endfor
    if l:clash
      continue
    endif
    call s:carve_room(a:st, l:room)
    if !empty(l:rooms)
      let l:prev = l:rooms[-1]
      let [l:px, l:py] = [l:prev.x + l:prev.w / 2, l:prev.y + l:prev.h / 2]
      let [l:cx, l:cy] = [l:room.x + l:room.w / 2, l:room.y + l:room.h / 2]
      if arcade#util#rng_chance(a:st.rng, 50)
        call s:carve_h(a:st, l:px, l:cx, l:py)
        call s:carve_v(a:st, l:py, l:cy, l:cx)
      else
        call s:carve_v(a:st, l:py, l:cy, l:px)
        call s:carve_h(a:st, l:px, l:cx, l:cy)
      endif
    endif
    call add(l:rooms, l:room)
  endfor

  let a:st.rooms = l:rooms
  let l:first = l:rooms[0]
  let a:st.player.x = l:first.x + l:first.w / 2
  let a:st.player.y = l:first.y + l:first.h / 2

  let l:last = l:rooms[-1]
  let a:st.map[l:last.y + l:last.h / 2][l:last.x + l:last.w / 2] = '>'

  call s:populate(a:st, l:rooms)
  call arcade#crawl#update_fov(a:st)
endfunction

function! s:free_spot(st, room) abort
  for l:try in range(20)
    let l:x = arcade#util#rng_range(a:st.rng, a:room.x, a:room.x + a:room.w - 1)
    let l:y = arcade#util#rng_range(a:st.rng, a:room.y, a:room.y + a:room.h - 1)
    if arcade#crawl#tile(a:st, l:x, l:y) !=# '.'
      continue
    endif
    if l:x == a:st.player.x && l:y == a:st.player.y
      continue
    endif
    if !empty(arcade#crawl#monster_at(a:st, l:x, l:y))
      continue
    endif
    return [l:x, l:y]
  endfor
  return []
endfunction

function! s:populate(st, rooms) abort
  let l:depth = a:st.depth
  let l:pool = filter(copy(s:MONSTERS), 'l:depth >= v:val.min && l:depth <= v:val.max')
  if empty(l:pool)
    let l:pool = [s:MONSTERS[-1]]
  endif
  for l:room in a:rooms[1:]
    let l:count = arcade#util#rng_range(a:st.rng, 0, 1 + l:depth / 2)
    for l:i in range(l:count)
      let l:spot = s:free_spot(a:st, l:room)
      if empty(l:spot)
        continue
      endif
      let l:proto = l:pool[arcade#util#rng_int(a:st.rng, len(l:pool))]
      let l:boost = (l:depth - l:proto.min) / 2
      call add(a:st.monsters, {
            \ 'x': l:spot[0], 'y': l:spot[1], 'glyph': l:proto.glyph, 'name': l:proto.name,
            \ 'hp': l:proto.hp + l:boost * 2, 'maxhp': l:proto.hp + l:boost * 2,
            \ 'atk': l:proto.atk + l:boost, 'def': l:proto.def, 'xp': l:proto.xp + l:boost})
    endfor

    if arcade#util#rng_chance(a:st.rng, 55)
      let l:spot = s:free_spot(a:st, l:room)
      if !empty(l:spot)
        call add(a:st.items, {'x': l:spot[0], 'y': l:spot[1], 'kind': 'gold', 'glyph': '$',
              \ 'amount': arcade#util#rng_range(a:st.rng, 5, 12 + l:depth * 4)})
      endif
    endif
    if arcade#util#rng_chance(a:st.rng, 35)
      let l:spot = s:free_spot(a:st, l:room)
      if !empty(l:spot)
        call add(a:st.items, {'x': l:spot[0], 'y': l:spot[1], 'kind': 'potion', 'glyph': '!'})
      endif
    endif
    if arcade#util#rng_chance(a:st.rng, 18)
      let l:spot = s:free_spot(a:st, l:room)
      if !empty(l:spot)
        let l:weapon = arcade#util#rng_chance(a:st.rng, 50)
        call add(a:st.items, {'x': l:spot[0], 'y': l:spot[1],
              \ 'kind': l:weapon ? 'weapon' : 'armor', 'glyph': l:weapon ? '/' : '['})
      endif
    endif
  endfor

  if a:st.depth >= s:max_depth()
    let l:room = a:rooms[-1]
    let l:spot = s:free_spot(a:st, l:room)
    if empty(l:spot)
      let l:spot = [l:room.x, l:room.y]
    endif
    call add(a:st.items, {'x': l:spot[0], 'y': l:spot[1], 'kind': 'amulet', 'glyph': '"'})
  endif
endfunction

" -------------------------------------------------------------------- fov
" Recursive shadowcasting over the eight octants: symmetric, no gaps, and it
" lights the wall faces that bound a lit floor.

let s:OCTANTS = [
      \ [ 1,  0,  0,  1], [ 0,  1,  1,  0], [ 0, -1,  1,  0], [-1,  0,  0,  1],
      \ [-1,  0,  0, -1], [ 0, -1, -1,  0], [ 0,  1, -1,  0], [ 1,  0,  0, -1]]

function! s:reveal(st, x, y) abort
  if a:x < 0 || a:y < 0 || a:x >= s:W || a:y >= s:H
    return
  endif
  let a:st.visible[a:y][a:x] = 1
  let a:st.seen[a:y][a:x] = 1
endfunction

function! s:cast_light(st, row, start, end, xx, xy, yx, yy) abort
  let l:start = a:start
  if l:start < a:end
    return
  endif
  let l:cx = a:st.player.x
  let l:cy = a:st.player.y
  let l:radius = s:FOV
  let l:new_start = 0.0
  let l:blocked = 0
  let l:j = a:row
  while l:j <= l:radius && !l:blocked
    let l:dy = -l:j
    let l:dx = -l:j
    while l:dx <= 0
      let l:x = l:cx + l:dx * a:xx + l:dy * a:xy
      let l:y = l:cy + l:dx * a:yx + l:dy * a:yy
      let l:l_slope = (l:dx - 0.5) / (l:dy + 0.5)
      let l:r_slope = (l:dx + 0.5) / (l:dy - 0.5)
      if l:start < l:r_slope
        let l:dx += 1
        continue
      elseif a:end > l:l_slope
        break
      endif
      if l:dx * l:dx + l:dy * l:dy <= l:radius * l:radius
        call s:reveal(a:st, l:x, l:y)
      endif
      let l:wall = arcade#crawl#tile(a:st, l:x, l:y) ==# '#'
      if l:blocked
        if l:wall
          let l:new_start = l:r_slope
        else
          let l:blocked = 0
          let l:start = l:new_start
        endif
      elseif l:wall && l:j < l:radius
        let l:blocked = 1
        call s:cast_light(a:st, l:j + 1, l:start, l:l_slope, a:xx, a:xy, a:yx, a:yy)
        let l:new_start = l:r_slope
      endif
      let l:dx += 1
    endwhile
    let l:j += 1
  endwhile
endfunction

function! arcade#crawl#update_fov(st) abort
  let a:st.visible = s:blank_grid(0)
  call s:reveal(a:st, a:st.player.x, a:st.player.y)
  for l:oct in s:OCTANTS
    call s:cast_light(a:st, 1, 1.0, 0.0, l:oct[0], l:oct[1], l:oct[2], l:oct[3])
  endfor
endfunction

" ------------------------------------------------------------------ combat

function! s:damage(rng, atk, def) abort
  return max([1, a:atk + arcade#util#rng_int(a:rng, 3) - a:def])
endfunction

function! s:xp_needed(level) abort
  return a:level * 20
endfunction

function! s:gain_xp(st, amount) abort
  let l:p = a:st.player
  let l:p.xp += a:amount
  while l:p.xp >= s:xp_needed(l:p.level)
    let l:p.xp -= s:xp_needed(l:p.level)
    let l:p.level += 1
    let l:p.maxhp += 4
    let l:p.hp = min([l:p.maxhp, l:p.hp + l:p.maxhp * 2 / 5])
    let l:p.atk += 1
    if l:p.level % 3 == 0
      let l:p.def += 1
    endif
    call arcade#crawl#log(a:st, printf('You reach level %d!', l:p.level))
  endwhile
endfunction

function! s:attack(st, monster) abort
  let l:dmg = s:damage(a:st.rng, a:st.player.atk, a:monster.def)
  let a:monster.hp -= l:dmg
  if a:monster.hp <= 0
    call filter(a:st.monsters, 'v:val isnot a:monster')
    call arcade#crawl#log(a:st, printf('You kill the %s. (+%d xp)', a:monster.name, a:monster.xp))
    call s:gain_xp(a:st, a:monster.xp)
  else
    call arcade#crawl#log(a:st, printf('You hit the %s for %d. (%d/%d)',
          \ a:monster.name, l:dmg, a:monster.hp, a:monster.maxhp))
  endif
endfunction

function! s:monster_turn(st) abort
  for l:m in copy(a:st.monsters)
    if a:st.over
      return
    endif
    if !a:st.visible[l:m.y][l:m.x]
      continue
    endif
    let l:dx = a:st.player.x - l:m.x
    let l:dy = a:st.player.y - l:m.y
    if abs(l:dx) <= 1 && abs(l:dy) <= 1
      let l:dmg = s:damage(a:st.rng, l:m.atk, a:st.player.def)
      let a:st.player.hp -= l:dmg
      call arcade#crawl#log(a:st, printf('The %s hits you for %d.', l:m.name, l:dmg))
      if a:st.player.hp <= 0
        let a:st.player.hp = 0
        let a:st.over = 1
        call arcade#crawl#log(a:st, printf('The %s kills you. You died on depth %d.',
              \ l:m.name, a:st.depth))
      endif
      continue
    endif
    let l:steps = []
    if l:dx != 0
      call add(l:steps, [l:dx > 0 ? 1 : -1, 0])
    endif
    if l:dy != 0
      call add(l:steps, [0, l:dy > 0 ? 1 : -1])
    endif
    if abs(l:dy) > abs(l:dx)
      call reverse(l:steps)
    endif
    for l:step in l:steps
      let l:nx = l:m.x + l:step[0]
      let l:ny = l:m.y + l:step[1]
      if !s:walkable(a:st, l:nx, l:ny)
        continue
      endif
      if l:nx == a:st.player.x && l:ny == a:st.player.y
        continue
      endif
      if !empty(arcade#crawl#monster_at(a:st, l:nx, l:ny))
        continue
      endif
      let l:m.x = l:nx
      let l:m.y = l:ny
      break
    endfor
  endfor
endfunction

" ------------------------------------------------------------------ actions

function! s:pickup(st) abort
  let l:p = a:st.player
  for l:item in copy(a:st.items)
    if l:item.x != l:p.x || l:item.y != l:p.y
      continue
    endif
    call filter(a:st.items, 'v:val isnot l:item')
    if l:item.kind ==# 'gold'
      let l:p.gold += l:item.amount
      call arcade#crawl#log(a:st, printf('You pick up %d gold.', l:item.amount))
    elseif l:item.kind ==# 'potion'
      let l:p.potions += 1
      call arcade#crawl#log(a:st, 'You pick up a potion. (p to drink)')
    elseif l:item.kind ==# 'weapon'
      let l:p.atk += 1
      call arcade#crawl#log(a:st, 'A sharper blade. Attack +1.')
    elseif l:item.kind ==# 'armor'
      let l:p.def += 1
      call arcade#crawl#log(a:st, 'Sturdier mail. Defense +1.')
    elseif l:item.kind ==# 'amulet'
      let l:p.amulet = 1
      let a:st.won = 1
      let a:st.over = 1
      call arcade#crawl#log(a:st, 'You seize the Amulet of Yendor. You win!')
    endif
  endfor
endfunction

" dir: [dx, dy]. Returns 1 if a turn was consumed.
function! arcade#crawl#step(st, dx, dy) abort
  if a:st.over
    return 0
  endif
  let l:nx = a:st.player.x + a:dx
  let l:ny = a:st.player.y + a:dy
  let l:monster = arcade#crawl#monster_at(a:st, l:nx, l:ny)
  if !empty(l:monster)
    call s:attack(a:st, l:monster)
  elseif s:walkable(a:st, l:nx, l:ny)
    let a:st.player.x = l:nx
    let a:st.player.y = l:ny
    call s:pickup(a:st)
  else
    return 0
  endif
  call arcade#crawl#end_turn(a:st)
  return 1
endfunction

function! arcade#crawl#end_turn(st) abort
  let a:st.turns += 1
  if !a:st.over
    call s:monster_turn(a:st)
  endif
  " Slow natural regeneration, rogue style.
  if !a:st.over && a:st.turns % 20 == 0 && a:st.player.hp < a:st.player.maxhp
    let a:st.player.hp += 1
  endif
  call arcade#crawl#update_fov(a:st)
endfunction

function! arcade#crawl#quaff(st) abort
  if a:st.over
    return 0
  endif
  let l:p = a:st.player
  if l:p.potions <= 0
    call arcade#crawl#log(a:st, 'You have no potions.')
    return 0
  endif
  let l:p.potions -= 1
  let l:heal = arcade#util#rng_range(a:st.rng, 8, 14)
  let l:p.hp = min([l:p.maxhp, l:p.hp + l:heal])
  call arcade#crawl#log(a:st, printf('You drink a potion. (+%d hp)', l:heal))
  call arcade#crawl#end_turn(a:st)
  return 1
endfunction

function! arcade#crawl#descend(st) abort
  if a:st.over
    return 0
  endif
  if arcade#crawl#tile(a:st, a:st.player.x, a:st.player.y) !=# '>'
    call arcade#crawl#log(a:st, 'There are no stairs here.')
    return 0
  endif
  let a:st.depth += 1
  call arcade#crawl#build_level(a:st)
  call arcade#crawl#log(a:st, printf('You descend to depth %d.', a:st.depth))
  return 1
endfunction

function! arcade#crawl#score(st) abort
  let l:p = a:st.player
  return l:p.gold + l:p.level * 25 + (a:st.depth - 1) * 50 + (l:p.amulet ? 500 : 0)
endfunction

" ---------------------------------------------------------------- rendering

let s:GLYPH_HL = {
      \ '@': 'ArcadeCrawlPlayer', '#': 'ArcadeCrawlWall', '.': 'ArcadeCrawlFloor',
      \ '>': 'ArcadeCrawlStairs', '$': 'ArcadeCrawlGold', '!': 'ArcadeCrawlPotion',
      \ '/': 'ArcadeCrawlGear', '[': 'ArcadeCrawlGear', '"': 'ArcadeCrawlAmulet'}

function! s:glyph_group(ch, visible) abort
  if !a:visible
    return 'ArcadeCrawlDim'
  endif
  return get(s:GLYPH_HL, a:ch, 'ArcadeCrawlMonster')
endfunction

function! s:hp_bar(p, width) abort
  let l:filled = a:p.maxhp > 0 ? (a:p.hp * a:width) / a:p.maxhp : 0
  let l:filled = arcade#util#clamp(l:filled, a:p.hp > 0 ? 1 : 0, a:width)
  let l:on = get(g:, 'arcade_ascii', &encoding !=# 'utf-8') ? '#' : '█'
  let l:off = get(g:, 'arcade_ascii', &encoding !=# 'utf-8') ? '.' : '░'
  return repeat(l:on, l:filled) . repeat(l:off, a:width - l:filled)
endfunction

function! arcade#crawl#draw(st) abort
  let l:lines = []
  let l:hl = []
  let l:p = a:st.player

  if a:st.help
    return s:draw_help(a:st)
  endif

  let l:bar = s:hp_bar(l:p, 16)
  let l:head = printf('depth %-3d hp [%s] %3d/%-3d  lvl %-2d xp %-3d atk %-2d def %-2d  $%-5d  !%d',
        \ a:st.depth, l:bar, l:p.hp, l:p.maxhp, l:p.level, l:p.xp, l:p.atk, l:p.def,
        \ l:p.gold, l:p.potions)
  call add(l:lines, l:head)
  call add(l:hl, [0, 0, strlen(l:head), 'ArcadeCrawlStatus'])
  call add(l:lines, '')

  " Composite layer: map, then items, then monsters, then the player.
  let l:grid = map(range(s:H), {y, _ -> copy(a:st.map[y])})
  for l:item in a:st.items
    let l:grid[l:item.y][l:item.x] = l:item.glyph
  endfor
  for l:m in a:st.monsters
    if a:st.visible[l:m.y][l:m.x]
      let l:grid[l:m.y][l:m.x] = l:m.glyph
    endif
  endfor
  let l:grid[l:p.y][l:p.x] = '@'

  for l:y in range(s:H)
    let l:lnum = len(l:lines)
    let l:line = ''
    let l:run_start = 0
    let l:run_group = ''
    for l:x in range(s:W)
      let l:vis = a:st.visible[l:y][l:x]
      let l:seen = a:st.seen[l:y][l:x]
      if !l:vis && !l:seen
        let l:ch = ' '
        let l:group = 'ArcadeCrawlDim'
      else
        " Remembered tiles show terrain only; entities need line of sight.
        let l:ch = l:vis ? l:grid[l:y][l:x] : a:st.map[l:y][l:x]
        let l:group = s:glyph_group(l:ch, l:vis)
      endif
      if l:group !=# l:run_group
        if !empty(l:run_group) && strlen(l:line) > l:run_start
          call add(l:hl, [l:lnum, l:run_start, strlen(l:line), l:run_group])
        endif
        let l:run_start = strlen(l:line)
        let l:run_group = l:group
      endif
      let l:line .= l:ch
    endfor
    if !empty(l:run_group) && strlen(l:line) > l:run_start
      call add(l:hl, [l:lnum, l:run_start, strlen(l:line), l:run_group])
    endif
    call add(l:lines, l:line)
  endfor

  call add(l:lines, '')
  let l:recent = a:st.log[max([0, len(a:st.log) - s:LOG_LINES]):]
  for l:i in range(s:LOG_LINES)
    let l:msg = l:i < len(l:recent) ? l:recent[l:i] : ''
    if !empty(l:msg)
      call add(l:hl, [len(l:lines), 0, strlen(l:msg),
            \ l:i == len(l:recent) - 1 ? 'ArcadeCrawlLogNew' : 'ArcadeCrawlLog'])
    endif
    call add(l:lines, l:msg)
  endfor

  call add(l:lines, '')
  if a:st.over
    let l:banner = a:st.won
          \ ? printf('*** YOU WIN *** score %d  --  r restarts, q quits', arcade#crawl#score(a:st))
          \ : printf('*** YOU DIED *** score %d  --  r restarts, q quits', arcade#crawl#score(a:st))
    call add(l:hl, [len(l:lines), 0, strlen(l:banner),
          \ a:st.won ? 'ArcadeCrawlWin' : 'ArcadeCrawlDead'])
    call add(l:lines, l:banner)
  else
    let l:hint = 'hjkl/yubn move  . wait  p potion  > stairs  ? help  r restart  q quit'
    call add(l:hl, [len(l:lines), 0, strlen(l:hint), 'ArcadeCrawlHint'])
    call add(l:lines, l:hint)
  endif

  return {'lines': l:lines, 'hl': l:hl}
endfunction

function! s:draw_help(st) abort
  let l:lines = [
        \ '  vim-arcade :: crawl',
        \ '',
        \ '  movement    h j k l      west south north east',
        \ '              y u b n      diagonals',
        \ '              arrows       west south north east',
        \ '              .            wait a turn',
        \ '',
        \ '  actions     p            drink a potion',
        \ '              >            descend the stairs you stand on',
        \ '              r            restart from depth 1',
        \ '              q / <Esc>    quit',
        \ '',
        \ '  glyphs      @ you        > stairs down    $ gold',
        \ '              ! potion     / weapon         [ armor',
        \ '              " Amulet of Yendor (depth ' . s:max_depth() . ')',
        \ '              r k g o W T D  monsters, nastier down the list',
        \ '',
        \ '  Walking into a monster attacks it. Monsters only act when they',
        \ '  can see you. Score = gold + 25/level + 50/depth + 500 for the amulet.',
        \ '',
        \ '  press ? to return',
        \ ]
  let l:hl = [[0, 2, strlen(l:lines[0]), 'ArcadeCrawlStatus']]
  return {'lines': l:lines, 'hl': l:hl}
endfunction

" ------------------------------------------------------------------ session

let s:DIRS = {
      \ 'h': [-1, 0], 'j': [0, 1], 'k': [0, -1], 'l': [1, 0],
      \ 'y': [-1, -1], 'u': [1, -1], 'b': [-1, 1], 'n': [1, 1],
      \ '<Left>': [-1, 0], '<Down>': [0, 1], '<Up>': [0, -1], '<Right>': [1, 0]}

function! s:maybe_record(st) abort
  if a:st.over && !a:st.recorded
    let a:st.recorded = 1
    call arcade#score#record('crawl', arcade#crawl#score(a:st),
          \ {'depth': a:st.depth, 'level': a:st.player.level, 'won': a:st.won})
    let a:st.best = arcade#score#best('crawl')
  endif
endfunction

function! s:on_move(ctl, key) abort
  let l:d = s:DIRS[a:key]
  call arcade#crawl#step(a:ctl.state, l:d[0], l:d[1])
  call s:maybe_record(a:ctl.state)
endfunction

function! s:on_wait(ctl, key) abort
  if !a:ctl.state.over
    call arcade#crawl#end_turn(a:ctl.state)
  endif
  call s:maybe_record(a:ctl.state)
endfunction

function! s:on_potion(ctl, key) abort
  call arcade#crawl#quaff(a:ctl.state)
  call s:maybe_record(a:ctl.state)
endfunction

function! s:on_descend(ctl, key) abort
  call arcade#crawl#descend(a:ctl.state)
endfunction

function! s:on_help(ctl, key) abort
  let a:ctl.state.help = !a:ctl.state.help
endfunction

function! s:on_restart(ctl, key) abort
  let a:ctl.state = arcade#crawl#new()
endfunction

function! s:on_quit(ctl, key) abort
  call s:maybe_record(a:ctl.state)
  call arcade#ui#close()
endfunction

function! arcade#crawl#start(...) abort
  let l:ctl = {
        \ 'name': 'arcade://crawl',
        \ 'filetype': 'arcadecrawl',
        \ 'state': call('arcade#crawl#new', a:000),
        \ 'draw': function('arcade#crawl#draw'),
        \ 'keys': {},
        \ }
  for l:key in keys(s:DIRS)
    let l:ctl.keys[l:key] = function('s:on_move')
  endfor
  let l:ctl.keys['.'] = function('s:on_wait')
  let l:ctl.keys['p'] = function('s:on_potion')
  let l:ctl.keys['>'] = function('s:on_descend')
  let l:ctl.keys['?'] = function('s:on_help')
  let l:ctl.keys['r'] = function('s:on_restart')
  let l:ctl.keys['q'] = function('s:on_quit')
  return arcade#ui#open(l:ctl)
endfunction
