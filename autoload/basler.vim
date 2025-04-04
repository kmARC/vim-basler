" Location:     autoload/basler.vim
" Maintainer:   Mark Korondi <korondi.mark@gmail.com>

let g:basler_output_base = g:->get('basler_output_base', expand('~/.vim/misc'))
let g:basler_log_file = g:->get('basler_log_file', '/tmp/basler.log')

let g:basler_bazel_info = {}
let s:bazel_base_cmd = [ 'bazel', '--output_base=' . g:basler_output_base . '/bazel-out',
      \                           '--max_idle_secs=5 ',
      \ ]->join(' ')
let s:bazel_labels = []
let s:fetched = []
let s:bazel_query_opts = ['--ui_event_filters=-ERROR,-INFO,-WARNING']->join(' ')

let g:basler_fname_cache = {}

function! basler#debug_info() abort
  echom 's:bazel_base_cmd = ' . s:bazel_base_cmd
  echom map(items(g:basler_bazel_info->get(getcwd())), {_, vals -> vals[0] . ': ' . vals[1]})->join(', ')
  echom 's:bazel_labels = ' . s:bazel_labels->join(', ')
  echom 's:fetched = ' . s:fetched->join(', ')
endfunction

function! basler#log(...) abort
    if !empty(g:basler_log_file)
        call writefile([strftime('%c') . ':' . a:000->join(' ')], g:basler_log_file, 'a')
    endif
endfunction

function! s:bazel(...) abort
  let working_directory = expand('%:p:h')
  if working_directory == ''
    let working_directory = getcwd()
  endif
  let bazel_cmd = "cd " . working_directory . " && " . s:bazel_base_cmd . ' ' . a:000->join(' ') . " 2>/dev/null"
  call basler#log("invoking", bazel_cmd)

  return systemlist(bazel_cmd)
endfunction

function! s:bazel_query(...) abort
  return s:bazel('query', s:bazel_query_opts, a:000->join(' '))
endfunction

" Purpose:
"   
" Returns:
"   result: 

function! basler#bazel_info() abort
  if basler#workspace_root() != ""
    return
  endif
  let s:bazel_info = {}
  function! s:out_handler(channel, msg) abort
    let [k, v] = split(a:msg, ':\s\+')
    let s:bazel_info[k] = v
  endfunction
  function! s:exit_handler(job, status) abort
    if a:status == 0
      let g:basler_bazel_info[s:bazel_info["workspace"]] = s:bazel_info
      let g:basler_fname_cache[s:bazel_info["workspace"]] = {}
      echom 'Bazel ready'
    else
      echowindow 'Querying bazel info` failed'
    endif
  endfunction
  let working_directory = expand('%:p:h')
  if working_directory == ''
    let working_directory = getcwd()
  endif
  return job_start(s:bazel_base_cmd . ' info ', {
        \ 'mode': 'nl',
        \ 'out_cb': 's:out_handler',
        \ 'exit_cb': 's:exit_handler',
        \ 'cwd': working_directory,
        \ })
endfunction

function! basler#workspace_root() abort
  let possible_workspace_root = expand("%:p:h")
  while !has_key(g:basler_bazel_info, possible_workspace_root)
    let parent = fnamemodify(possible_workspace_root, ":h")
    if parent == possible_workspace_root
      break
    else
      let possible_workspace_root = parent
    endif
  endwhile
  return g:basler_bazel_info->get(possible_workspace_root, {})->get("workspace", "")
endfunction

function! s:possible_paths(fname)
  if g:basler_fname_cache->get(basler#workspace_root(), {})->has_key(a:fname)
    return g:basler_fname_cache[basler#workspace_root()][a:fname]
  endif
  let [_, _, pkg, _, path, name] = matchlist(a:fname, '\(@\([^/]\+\)\)\?\(//\([^:]*\)\)\?:\?\(.*\)')[0:5]
  "                                          example: ...@......pkg.......//.....path....:...name..

  let possible_paths = []

  " In case this is a relative name (starts with a ':'), then try to check
  " if it exists under the path of the opened file
  if a:fname->stridx(':') == 0
    let path = expand('%:h')
  endif

  let build_file = s:bazel_query('--output=location', '@'.pkg.'//'.path.':'.name)
                   \ ->get(-1, '')->split(':')->get(0, '')
  if build_file != ''
    let possible_paths += [build_file]
  else 
    " No BUILD file found for the given name.

    " In case "name" is a file that is not exported (e.g. in load statements),
    " try to find the package root
    let package_location = s:bazel_query('--output=location', '@'.pkg.'//'.path.':*')
                           \ ->get(-1, '')->split(':')->get(0, '')->fnamemodify(':h')
    let possible_paths += [package_location . '/' . name]
  endif

  call basler#log('Found possible paths', possible_paths)

  let g:basler_fname_cache[basler#workspace_root()][a:fname] = possible_paths
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

