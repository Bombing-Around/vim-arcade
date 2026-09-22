# vim-arcade

Three small games that run inside a Vim or Neovim buffer: **2048**, a
turn-based **dungeon crawler**, and a **ball sort** puzzle. One
legacy-VimScript implementation serves both editors — no Lua, no Vim9, no
external process, no dependencies.

```
:Arcade2048    :ArcadeCrawl    :ArcadeSort    :ArcadeScores
```

## Install

Any plugin manager, or just drop the directory on your `runtimepath`.

```vim
" vim-plug
Plug 'Bombing-Around/vim-arcade'

" lazy.nvim
{ 'Bombing-Around/vim-arcade', cmd = { 'Arcade', 'Arcade2048', 'ArcadeCrawl', 'ArcadeSort' } }
```

Requires Vim 8.0+ or Neovim. Colour uses text properties (Vim) or extmarks
(Neovim) and degrades to monochrome on builds with neither.

## 2048

`hjkl` or the arrow keys slide, `u` undoes (8 deep), `r` restarts, `q` quits.
Scores persist between sessions.

## Crawl

`hjkl` + `yubn` move, `.` waits, `p` drinks a potion, `>` takes the stairs,
`?` shows help. Walking into a monster attacks it. Levels are generated per
descent, field of view is recursive shadowcasting, monsters only act when they
can see you. Reach depth 8, grab the Amulet of Yendor (`"`), and the run is a
win.

## Sort

Tubes of coloured balls; stack every colour into a tube of its own. `h`/`l` or
the arrows walk the hand between tubes, `<Space>` lifts the whole run of
matching balls off a tube and `<Space>` drops it again, `u` undoes, `r`
reshuffles, `q` quits. Balls only drop onto an empty tube or onto their own
colour, and each colour is a distinct shape as well, so the board still reads
without colour.

Counts work the way they do everywhere else in vim: `2<Space>` lifts two of a
run of three, `2l` walks two tubes over, and `1<Space>` over the target drops
one of what you are holding. Dropping into a tube with less room than you are
carrying puts in what fits and keeps the rest in hand — the same manoeuvre
without the arithmetic. One `u` puts back a whole handful.

`<Esc>` is disabled: it is muscle memory in normal mode and a run can be many
levels deep, so it stays put and points at `q` instead. The run is written down
whenever the game closes — `q`, a wiped buffer, a closed tab or Vim quitting —
and the next `:ArcadeSort` picks it up where you left it. `R` abandons it and
deals a fresh run.

```
            ●
            ●            <- three in hand, hovering
            ●
│ │ │◆│ │ │ │ │ │ │ │◆│
│ │ │▲│ │■│ │ │ │ │ │▲│
│ │ │▲│ │■│ │ │ │●│ │■│
│ │ │▲│ │■│ │ │ │●│ │◆│
╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯ ╰─╯
            ▲
```

Levels run from four colours to nine, two spare tubes throughout. Each one is
dealt by walking backwards from a solved board along inverted moves, so every
level is winnable — though a careless line still strands the board, which is
what `u` is for.

## Options

| option | default | meaning |
| --- | --- | --- |
| `g:arcade_window` | `'tab'` | `tab`, `split`, `vsplit` or `current` |
| `g:arcade_ascii` | auto | force ASCII box drawing |
| `g:arcade_crawl_depth` | `8` | depth holding the amulet |
| `g:arcade_data_dir` | XDG data dir | where `scores.json` lives |

Every highlight group is defined with `highlight default`, so your colorscheme
wins. See `:help vim-arcade`.

## How it works

- `autoload/arcade/ui.vim` owns the scratch buffer: `nofile`, `nomodifiable`,
  buffer-local mappings per key, full redraw after every handled key, and a
  highlight-span abstraction over `prop_add()` / `nvim_buf_add_highlight()`.
- Game modules are pure state machines — `#new()`, the action functions and
  `#draw(state) -> {lines, hl}` never touch a buffer, so the whole thing is
  testable headlessly.
- Games share a deterministic LCG (`arcade#util#rng_*`), so a seed reproduces a
  run exactly; the tests rely on that.

Adding a game means supplying a controller dict to `arcade#ui#open()`; see
`:help arcade-extending`.

## Tests

```sh
make test          # vim -Nu NONE -es -S test/run.vim
```

Covers merge/slide rules, game-over detection, undo, level generation, FOV,
combat and item effects, a few thousand turns of random playout in both games,
the invariant that every highlight span lies inside its line, and a buffer-level
smoke test of the surface itself.
