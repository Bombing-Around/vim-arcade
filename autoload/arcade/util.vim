" arcade/util.vim -- shared helpers (deterministic RNG, formatting)
" Deterministic LCG so games are reproducible under a fixed seed (tests).

function! arcade#util#rng_new(...) abort
  let l:seed = a:0 && a:1 > 0 ? a:1 : localtime() * 1000 + reltime()[1] % 1000
  return {'s': l:seed % 2147483648}
endfunction

" Returns an integer in [0, n).
function! arcade#util#rng_int(rng, n) abort
  if a:n <= 1
    return 0
  endif
  let a:rng.s = (1103515245 * a:rng.s + 12345) % 2147483648
  return (a:rng.s / 65536) % a:n
endfunction

" Returns 1 with probability pct/100.
function! arcade#util#rng_chance(rng, pct) abort
  return arcade#util#rng_int(a:rng, 100) < a:pct
endfunction

function! arcade#util#rng_range(rng, lo, hi) abort
  return a:lo + arcade#util#rng_int(a:rng, a:hi - a:lo + 1)
endfunction

function! arcade#util#shuffle(rng, list) abort
  let l:i = len(a:list) - 1
  while l:i > 0
    let l:j = arcade#util#rng_int(a:rng, l:i + 1)
    let l:tmp = a:list[l:i]
    let a:list[l:i] = a:list[l:j]
    let a:list[l:j] = l:tmp
    let l:i -= 1
  endwhile
  return a:list
endfunction

function! arcade#util#center(text, width) abort
  let l:len = strdisplaywidth(a:text)
  if l:len >= a:width
    return a:text
  endif
  let l:left = (a:width - l:len) / 2
  return repeat(' ', l:left) . a:text . repeat(' ', a:width - l:len - l:left)
endfunction

function! arcade#util#rpad(text, width) abort
  let l:len = strdisplaywidth(a:text)
  return l:len >= a:width ? a:text : a:text . repeat(' ', a:width - l:len)
endfunction

function! arcade#util#lpad(text, width) abort
  let l:len = strdisplaywidth(a:text)
  return l:len >= a:width ? a:text : repeat(' ', a:width - l:len) . a:text
endfunction

function! arcade#util#clamp(v, lo, hi) abort
  return a:v < a:lo ? a:lo : (a:v > a:hi ? a:hi : a:v)
endfunction
