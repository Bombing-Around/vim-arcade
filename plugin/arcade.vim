" vim-arcade -- little games inside vim/nvim.
" Maintainer: https://github.com/ephbaum
" License: same as Vim.

if exists('g:loaded_arcade') || &compatible || v:version < 800
  finish
endif
let g:loaded_arcade = 1

command! -nargs=0 Arcade2048    call arcade#twenty48#start()
command! -nargs=0 ArcadeCrawl   call arcade#crawl#start()
command! -nargs=0 ArcadeSort    call arcade#sort#start()
command! -nargs=0 ArcadeScores  call arcade#scoreboard()
command! -nargs=1 -complete=customlist,arcade#complete Arcade call arcade#start(<q-args>)

function! s:hl(group, attrs) abort
  execute 'highlight default' a:group a:attrs
endfunction

function! s:define_highlights() abort
  " 2048 -- classic tile palette.
  call s:hl('Arcade2048Title', 'cterm=bold gui=bold ctermfg=214 guifg=#edc22e')
  call s:hl('Arcade2048Score', 'ctermfg=246 guifg=#9a9186')
  call s:hl('Arcade2048Hint',  'ctermfg=240 guifg=#6c6660')
  call s:hl('Arcade2048Win',   'cterm=bold gui=bold ctermfg=220 guifg=#edc53f')
  call s:hl('Arcade2048Over',  'cterm=bold gui=bold ctermfg=203 guifg=#f65e3b')
  " No fill on empty cells: they take the editor's own background instead
  " of a light tan. The classic tan/cream/cream progression (empty -> 2 ->
  " 4) reads fine on the original's flat canvas, but in a terminal, over a
  " dark colorscheme, those three sit within a few percent of each other in
  " luminance and the early board looks like a wash of nothing.  Leaving
  " empty cells unfilled means populated tiles read as distinct light
  " blocks against whatever background is already there.
  call s:hl('Arcade2048Empty', 'ctermfg=239 guifg=#3c3a32')
  call s:hl('Arcade2048T2',    'ctermfg=238 ctermbg=255 guifg=#776e65 guibg=#eee4da')
  call s:hl('Arcade2048T4',    'ctermfg=238 ctermbg=253 guifg=#776e65 guibg=#ede0c8')
  call s:hl('Arcade2048T8',    'ctermfg=255 ctermbg=216 guifg=#f9f6f2 guibg=#f2b179')
  call s:hl('Arcade2048T16',   'ctermfg=255 ctermbg=209 guifg=#f9f6f2 guibg=#f59563')
  call s:hl('Arcade2048T32',   'ctermfg=255 ctermbg=203 guifg=#f9f6f2 guibg=#f67c5f')
  call s:hl('Arcade2048T64',   'ctermfg=255 ctermbg=196 guifg=#f9f6f2 guibg=#f65e3b')
  call s:hl('Arcade2048T128',  'ctermfg=238 ctermbg=222 guifg=#776e65 guibg=#edcf72')
  call s:hl('Arcade2048T256',  'ctermfg=238 ctermbg=221 guifg=#776e65 guibg=#edcc61')
  call s:hl('Arcade2048T512',  'ctermfg=238 ctermbg=220 guifg=#776e65 guibg=#edc850')
  call s:hl('Arcade2048T1024', 'cterm=bold gui=bold ctermfg=238 ctermbg=214 guifg=#776e65 guibg=#edc53f')
  call s:hl('Arcade2048T2048', 'cterm=bold gui=bold ctermfg=255 ctermbg=208 guifg=#f9f6f2 guibg=#edc22e')
  call s:hl('Arcade2048T4096', 'cterm=bold gui=bold ctermfg=255 ctermbg=236 guifg=#f9f6f2 guibg=#3c3a32')

  " crawl
  call s:hl('ArcadeCrawlStatus',  'cterm=bold gui=bold ctermfg=250 guifg=#d0d0d0')
  call s:hl('ArcadeCrawlWall',    'ctermfg=245 guifg=#8a8a8a')
  call s:hl('ArcadeCrawlFloor',   'ctermfg=239 guifg=#4e4e4e')
  call s:hl('ArcadeCrawlDim',     'ctermfg=236 guifg=#303030')
  call s:hl('ArcadeCrawlPlayer',  'cterm=bold gui=bold ctermfg=226 guifg=#ffff5f')
  call s:hl('ArcadeCrawlMonster', 'cterm=bold gui=bold ctermfg=203 guifg=#ff5f5f')
  call s:hl('ArcadeCrawlStairs',  'cterm=bold gui=bold ctermfg=81  guifg=#5fd7ff')
  call s:hl('ArcadeCrawlGold',    'ctermfg=220 guifg=#ffd700')
  call s:hl('ArcadeCrawlPotion',  'ctermfg=170 guifg=#d75fd7')
  call s:hl('ArcadeCrawlGear',    'ctermfg=44  guifg=#00d7d7')
  call s:hl('ArcadeCrawlAmulet',  'cterm=bold gui=bold ctermfg=213 guifg=#ff87ff')
  call s:hl('ArcadeCrawlLog',     'ctermfg=243 guifg=#767676')
  call s:hl('ArcadeCrawlLogNew',  'ctermfg=252 guifg=#d0d0d0')
  call s:hl('ArcadeCrawlHint',    'ctermfg=240 guifg=#585858')
  call s:hl('ArcadeCrawlWin',     'cterm=bold gui=bold ctermfg=220 guifg=#ffd700')
  call s:hl('ArcadeCrawlDead',    'cterm=bold gui=bold ctermfg=196 guifg=#ff0000')

  " sort -- ball colours are also distinguished by shape, so the palette
  " only has to be pleasant, not carry the whole board on its own.
  call s:hl('ArcadeSortTitle',  'cterm=bold gui=bold ctermfg=80  guifg=#5fd7d7')
  call s:hl('ArcadeSortScore',  'ctermfg=246 guifg=#949494')
  call s:hl('ArcadeSortHint',   'ctermfg=240 guifg=#585858')
  call s:hl('ArcadeSortTube',   'ctermfg=240 guifg=#585858')
  call s:hl('ArcadeSortCursor', 'cterm=bold gui=bold ctermfg=252 guifg=#d0d0d0')
  call s:hl('ArcadeSortMsg',    'ctermfg=246 guifg=#949494')
  call s:hl('ArcadeSortWin',    'cterm=bold gui=bold ctermfg=220 guifg=#ffd700')
  call s:hl('ArcadeSortStuck',  'cterm=bold gui=bold ctermfg=203 guifg=#ff5f5f')
  call s:hl('ArcadeSortAssist', 'cterm=bold gui=bold ctermfg=220 guifg=#ffd700')
  call s:hl('ArcadeSortC1',     'cterm=bold gui=bold ctermfg=203 guifg=#ff5f5f')
  call s:hl('ArcadeSortC2',     'cterm=bold gui=bold ctermfg=114 guifg=#87d787')
  call s:hl('ArcadeSortC3',     'cterm=bold gui=bold ctermfg=221 guifg=#ffd75f')
  call s:hl('ArcadeSortC4',     'cterm=bold gui=bold ctermfg=75  guifg=#5fafff')
  call s:hl('ArcadeSortC5',     'cterm=bold gui=bold ctermfg=176 guifg=#d787d7')
  call s:hl('ArcadeSortC6',     'cterm=bold gui=bold ctermfg=80  guifg=#5fd7d7')
  call s:hl('ArcadeSortC7',     'cterm=bold gui=bold ctermfg=215 guifg=#ffaf5f')
  call s:hl('ArcadeSortC8',     'cterm=bold gui=bold ctermfg=253 guifg=#dadada')
  call s:hl('ArcadeSortC9',     'cterm=bold gui=bold ctermfg=141 guifg=#af87ff')
endfunction

call s:define_highlights()

augroup vim_arcade
  autocmd!
  autocmd ColorScheme * call s:define_highlights()
augroup END
