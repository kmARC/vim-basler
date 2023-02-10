let s:cpo_save = &cpoptions
set cpoptions&vim

augroup basler
  autocmd!

  autocmd FileType starlark,bzl 
    \   call basler#bazel_info()
    \ | setlocal includeexpr=basler#include_expr(v:fname)
    \            isfname+=:,@-@
    \ | let &l:include='\(load(\s*"\zs[^"]\+\ze"\|\s*"\zs[^"]\+\.bzl\ze",\)'
    \ | let &l:define='^\(\s*\(def\|class\)\|\ze[^ ]\+\s*=\s*\)'
augroup END

set wildignore+=*/bazel-*/*                   " Bazel

command! BaslerDebugInfo :call basler#debug_info()

let &cpoptions = s:cpo_save
unlet s:cpo_save
