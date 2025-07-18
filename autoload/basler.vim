" Location:     autoload/basler.vim
" Maintainer:   Mark Korondi <korondi.mark@gmail.com>

let g:basler_output_base = g:->get('basler_output_base', expand('~/.vim/misc'))
let g:basler_log_file = g:->get('basler_log_file', '/tmp/basler.log')


let s:bazel_base_cmd = [ 'bazel', '--output_base=' . g:basler_output_base . '/bazel-out',
      \                           '--max_idle_secs=5 ', '--noblock_for_lock',
      \ ]->join(' ')
let s:bazel_query_opts = ['--keep_going', '--ui_event_filters=-ERROR,-INFO,-WARNING']->join(' ')
let s:bazel_common_opts = ['--enable_bzlmod']->join(' ')

" All these variables should be 'workspace'-dependent
let s:fname_cache = {}
let s:bazel_labels = []
let s:fetched = []
let s:workspace_to_repo = {}
let s:repo_to_workspace = {}

let s:query_channel_workspace = {}
let s:info_channel_workspace = {}

function! s:log(...) abort
    if !empty(g:basler_log_file)
        call writefile([strftime('%c') . ':' . a:000->join(' ')], g:basler_log_file, 'a')
    endif
endfunction

function! s:bazel(...) abort
  return s:bazel_base_cmd . ' ' . a:000->join(' ') . ' ' . s:bazel_common_opts
endfunction

function! s:bazel_query(...) abort
  return s:bazel('query', s:bazel_query_opts, a:000->join(' '))
endfunction

" Purpose:
"   Gather workspace knowledge, initialize variables
" Returns:
"   nothing
function! basler#bazel_info() abort
  call s:log("basler#bazel_info()")

  let workspace = basler#workspace_root()
  if workspace != ""
    call s:log(" - workspace found", workspace)
    return
  endif

  " function! s:info_out_handler(channel, msg) abort
  "   let unknown_workspace = s:info_channel_workspace[a:channel->ch_info()->get("id")]
  "   let [k, v] = split(a:msg, ':\s\+')
  "   let s:bazel_info[unknown_workspace][k] = v
  " endfunction

  " function! s:info_exit_handler(job, status) abort
  "   call s:log(" - s:info_exit_handler(<job>, ". a:status . ")")
  "   let unknown_workspace = s:info_channel_workspace[job_getchannel(a:job)->ch_info()->get("id")]
  "   if a:status == 0
  "     let actual_workspace = s:bazel_info[unknown_workspace]["workspace"]
  "     let s:bazel_info[actual_workspace] = s:bazel_info[unknown_workspace] " TODO: Error handling
  "     if actual_workspace != unknown_workspace
  "       call remove(s:bazel_info, unknown_workspace)
  "     endif

  "     call s:log('   - storing worksapce info for actual workspace:' . actual_workspace)

  "     call basler#bazel_query_all(actual_workspace)
  "     call s:log('   - bazel info done')
  "     echom 'Bazel ready'
  "   elseif a:status == 3
  "     call s:log('   - bazel info done with error code 3. Ignoring')
  "   else
  "     echowindow 'Querying bazel info` failed'
  "     call s:log('   - bazel info done with errors')
  "   endif
  " endfunction

  " let unknown_workspace = expand('%:p:h')
  " if unknown_workspace == '' || unknown_workspace[0] != '/'
  "   let unknown_workspace = getcwd()
  " endif

  " call s:log(" - unknown workspace, processing:", unknown_workspace)

  " let cmd = s:bazel('info')
  " call s:log('  - invoking:', cmd)
  " let job = job_start(cmd, {
  "       \ 'mode': 'nl',
  "       \ 'out_cb': 's:info_out_handler',
  "       \ 'exit_cb': 's:info_exit_handler',
  "       \ 'cwd': unknown_workspace,
  "       \ })
  " let s:bazel_info[unknown_workspace] = {}
  " let s:info_channel_workspace[job_getchannel(job)->ch_info()->get("id")] = unknown_workspace
endfunction

function! basler#bazel_query_all(workspace) abort
  call s:log("basler#bazel_query_all(". a:workspace .")")

  let repo = s:workspace_to_repo->get(a:workspace, '')

  if !repo
    call s:log(" - !!! Bazel not ready !!!")
    return
  endif

  call s:log('whats happening')

  function! s:query_out_handler(channel, msg) abort
    let workspace = s:query_channel_workspace[a:channel->ch_info()->get("id")]
    let file = a:msg->split(':')->get(0, '')
    let label = '//' . a:msg->split('//')->get(1, '')
    if file != '' && label != ''
      let repo = s:workspace_to_repo->get(workspace, '')
      let s:fname_cache[repo][label] = [file]
    endif
  endfunction

  function! s:query_exit_handler(job, status) abort
    call s:log(" - s:query_exit_handler(<job>, ". a:status . ")")
    if a:status == 0
      call s:log("   - bazel query all done")
    elseif a:status == 3
      call s:log("   - bazel query done with error code 3. Ignoring")
    else
      echowindow 'Bazel query all failed'
      call s:log("   - bazel query done with errors")
    endif
  endfunction

  let cmd = s:bazel_query("//...:*", "--output=location")
  call s:log('  - invoking:', cmd)
  let job = job_start(cmd, {
        \ 'mode': 'nl',
        \ 'out_cb': 's:query_out_handler',
        \ 'exit_cb': 's:query_exit_handler',
        \ 'cwd': a:workspace,
        \ })
  let s:fname_cache[repo] = {}
  let s:query_channel_workspace[job_getchannel(job)->ch_info()->get("id")] = a:workspace
endfunction


function! basler#workspace_root(...) abort
  call s:log("basler#workspace_root(". a:000->join(' ') .")")
  let possible_workspace_root = a:->get(1, '')
  if !possible_workspace_root
    let possible_workspace_root = expand("%:p:h")
    call s:log(" - no parameters received, trying with", possible_workspace_root)
  endif
  if possible_workspace_root->stridx('/') != 0
    let possible_workspace_root = getcwd()
    call s:log(" - file path isn't a real file / directory, tring with", possible_workspace_root)
  endif

  " Search upwards until either hit the root or find a workspace mapping
  while !s:is_workspace_boundary(possible_workspace_root)
    let parent = fnamemodify(possible_workspace_root, ":h")
    if parent == possible_workspace_root
      break
    else
      let possible_workspace_root = parent
    endif
  endwhile

  call s:log(" - search ended at", possible_workspace_root)
  return possible_workspace_root
endfunction

function s:is_workspace_boundary(path)
  for b in ["REPO", "WORKSPACE", "MODULE"]
    if filereadable(a:path . "/" . b) || filereadable(a:path . "/" . b . ".bazel")
      return v:true
    endif
  endfor
  return v:false
endfunction

function! s:label_of(repo, package, name)
  return '@' . a:repo . '//' . a:package . ':' . a:name
endfunction

function! s:possible_paths(workspace, fname, ...)
  call s:log("s:possible_paths(". a:workspace .", " . a:fname . ")")
  let current_repo = s:workspace_to_repo->get(a:workspace, '')

  let [_, _, repo, _, package, name] = matchlist(a:fname, '\(@\([^/]*\)\)\?\(//\([^:]*\)\)\?:\?\(.*\)')[0:5]
  "                                              example: ...@......repo.....//..package....:...name..

  " In case repo is missing, set it to the current repo
  if current_repo == '' && repo == ''
    let s:repo_to_workspace[''] = a:workspace
  endif

  if current_repo != '' && repo == ''
    let repo = current_repo
  endif

  " In case name is missing, the last segment of package is the name
  if name == '' && package != ''
    let name = package->split('/')[-1]
  endif

  call s:log(" - current repo:", current_repo)
  call s:log(" - repo:", repo)
  call s:log(" - package:", package)
  call s:log(" - name:", name)

  let cache_entry = s:fname_cache->get(repo, {})->get(a:fname, [])
  if cache_entry != []
    call s:log(" - found cache entry:", cache_entry)
    return cache_entry
  endif

  let possible_paths = []

  if s:repo_to_workspace->has_key(repo)
    call s:log(" - workspace found for repo", repo, "->", s:repo_to_workspace[repo])
    if package == ''
      call s:log(" - package is empty. search directories upwards")
      let possible_package_path = expand('%:h')
      while [s:repo_to_workspace, ".", "/"]->index(possible_package_path) == -1
        let possible_paths += [
              \ s:repo_to_workspace[repo] . '/' . possible_package_path . '/' . name,
              \ s:repo_to_workspace[repo] . '/' . possible_package_path . '/BUILD',
              \ s:repo_to_workspace[repo] . '/' . possible_package_path . '/BUILD.bazel',
              \ ]
        call s:log("   - adding", possible_package_path)
        let possible_package_path = possible_package_path->fnamemodify(":h")
      endwhile
    else
      let possible_paths += [
            \ s:repo_to_workspace[repo] . '/' . package . '/' . name,
            \ s:repo_to_workspace[repo] . '/' . package . '/BUILD',
            \ s:repo_to_workspace[repo] . '/' . package . '/BUILD.bazel',
            \ ]
  endif
  else
    call s:log(" - workspace NOT found for repo", repo)

    let cmd = "pushd " . a:workspace . " >/dev/null && " .s:bazel_query('--output=location', s:label_of(repo, package, name)) . " 2>/dev/null"
    call s:log(" - invoking:", cmd)
    let output = systemlist(cmd)
    let split = output->get(-1, '')->split(':')->get(0, '')->split('/' . package . '/' . name)
    if split == []
      return []
    endif
    call s:log(" - split", split)
    let workspace = split[0]->substitute("/" . package . ".*", "", "g")  
    call s:log(" - workspace", workspace)

    let s:workspace_to_repo[workspace] = repo
    let s:repo_to_workspace[repo] = workspace

    let possible_paths += [
          \ workspace . '/' . package . '/' . name,
          \ workspace . '/' . package . '/BUILD',
          \ workspace . '/' . package . '/BUILD.bazel',
          \ ]
  endif

  call s:log(' - possible paths found:', possible_paths)

  for ppath in possible_paths
    if filereadable(ppath)
      let s:fname_cache[repo] = s:fname_cache->get(repo, {})
      let s:fname_cache[repo][a:fname] = [ppath]
      return [ppath]
    endif
  endfor

  " " In case the package is missing
  " " if it exists under the package of the opened file
  " if package == ''
  " endif


  return []
endfunction

function! basler#include_expr(fname) abort
  if a:fname->match('^\(@\|//\|:\)') == -1
    return a:fname
  endif

  let workspace = basler#workspace_root()

  for attempt in [0, 1]
    " Try to find file in possible paths
    for ppath in s:possible_paths(workspace, a:fname)
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

