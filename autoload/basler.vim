" Location:     autoload/basler.vim
" Maintainer:   Mark Korondi <korondi.mark@gmail.com>

let s:bazel_base_cmd = [ 'bazel', '--output_base=' . expand('~/.vim/misc') . '/bazel-out',
      \                           '--max_idle_secs=5 ',
      \ ]->join(' ')
let s:bazel_info = {}
let s:bazel_labels = []
let s:fetched = []

function! basler#debug_info() abort
  echom 's:bazel_base_cmd = ' . s:bazel_base_cmd
  echom map(items(s:bazel_info), {_, vals -> vals[0] . ': ' . vals[1]})->join(', ')
  echom 's:bazel_labels = ' . s:bazel_labels->join(', ')
  echom 's:fetched = ' . s:fetched->join(', ')
endfunction

" Purpose:
"   
" Returns:
"   result: 
function! basler#bazel_info() abort
  function! s:out_handler(channel, msg) abort
    let [k, v] = split(a:msg, ':\s\+')
    let s:bazel_info[k] = v
  endfunction
  function! s:exit_handler(job, status) abort
    if a:status == 0
      echom 'Bazel ready'
    else
      echowindow 'Querying bazel info` failed'
    endif
  endfunction
  return job_start(s:bazel_base_cmd . ' info ', {
        \ 'mode': 'nl',
        \ 'out_cb': 's:out_handler',
        \ 'exit_cb': 's:exit_handler',
        \ })
endfunction

function! basler#workspace_root() abort
  let l:wildignore = &wildignore
  let &wildignore = ''
  let workspace = fnamemodify(findfile('WORKSPACE', '.;'), ':p:h')
  let &wildignore = l:wildignore
  return workspace
endfunction

function! s:possible_paths(fname)
  let [_, _, pkg, _, path, name] = matchlist(a:fname, '\(@\([^/]\+\)\)\?\(//\([^:]*\)\)\?:\?\(.*\)')[0:5]
  "                                          example: ...@......pkg.......//.....path....:...name..
  let possible_paths = []
  if len(pkg)
    let possible_paths += [
          \ s:bazel_info->get('execution_root', 'bazel-bin') . '/external/' . pkg . '/' . path . '/' . name,
          \ s:bazel_info->get('execution_root', 'bazel-bin') . '/external/' . pkg . '/' . path . '/BUILD.bazel',
          \ s:bazel_info->get('execution_root', 'bazel-bin') . '/external/' . pkg . '/' . path . '/BUILD',
          \ s:bazel_info->get('output_base', 'bazel-bin') . '/external/' . pkg . '/' . path . '/' . name,
          \ s:bazel_info->get('output_base', 'bazel-bin') . '/external/' . pkg . '/' . path . '/BUILD.bazel',
          \ s:bazel_info->get('output_base', 'bazel-bin') . '/external/' . pkg . '/' . path . '/BUILD',
          \ ]
  else

    let workspace = basler#workspace_root()
    let possible_paths += [
          \ (path->len() != 0) ? (path . '/') : '' . name,
          \ workspace . '/' . path . '/' . name,
          \ workspace . '/' . path . '/BUILD.bazel',
          \ workspace . '/' . path . '/BUILD',
          \ ]
  endif

  return possible_paths
endfunction

function! basler#include_expr(fname) abort
  if a:fname->match('^\(@\|//\|:\)') == -1
    return a:fname
  endif

  for attempt in [0, 1]
    " Try to find file in possible paths
    for ppath in s:possible_paths(a:fname)
      if len(findfile(ppath))
        return ppath
      endif
    endfor

    if attempt == 0 && s:fetched->index(a:fname) == -1
      try
        call system(s:bazel_base_cmd . ' fetch --remote_download_outputs=minimal ' . a:fname)
        let s:fetched += [a:fname]
      endtry
    endif
  endfor

  return a:fname
endfunction


function! basler#labels() abort
  function! s:out_handler(channel, msg) abort
    let s:bazel_labels += [a:msg]
  endfunction
  function! s:exit_handler(job, status) abort
    if a:status == 0
      echom 'Bazel query for labels successful'
    else
      echowindow 'Querying bazel labels failed'
    endif
  endfunction
  call job_start([ s:bazel_base_cmd, 'query',
        \                            '--output=label',
        \                            '--relative_locations',
        \                            '--keep_going',
        \                            '--noimplicit_deps',
        \                            '--notool_deps',
        \                            '--nodep_deps',
        \                            '"kind(\"source file\", deps(//...))"',
        \ ]->join(' '),
        \ {
        \   'mode': 'nl',
        \   'out_cb': 's:out_handler',
        \   'exit_cb': 's:exit_handler',
        \ })
endfunction

