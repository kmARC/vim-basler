source plugin/basler.vim

let g:basler_output_base = environ()->get("BAZEL_OUTPUT_BASE", v:none)

fun s:setup_workspace()
    let s:old_dir = getcwd()
    let s:tmp_dir = "tmp"
    call system("cp -r --no-target-directory test/workspace_example " . s:tmp_dir)
    exec('cd ' . s:tmp_dir)
endf

fun s:wait_for_bazel()
    call basler#bazel_info()
    let ctr = 25
    while basler#workspace_root() == '' && ctr > 0
      sleep 200ms
      let ctr = ctr - 1
    endw
    Expect ctr != 0
endf

describe 'plugin/basler.vim'

  before
    call s:setup_workspace()
    call s:wait_for_bazel()
  end

  after
    exec('cd ' . s:old_dir)
    call delete(s:tmp_dir, "rf")
  end

  it 'should set up gf'
    edit WORKSPACE
    set ft=starlark
    normal gg
    " jump to the first slash of //dir1
    normal f/
    normal gf
    Expect fnamemodify(expand('%'), ':p') == getcwd() . '/dir1/http_archive.bzl'
  end

  it 'should set up [_CTRL-d'
    edit WORKSPACE
    set ft=starlark
    " go to line 3 where a call to http_archive is
    3
    exe "normal [\<c-d>"
    Expect fnamemodify(expand('%'), ':p') == getcwd() . '/dir1/http_archive.bzl'
    exe "normal \<c-o>"
  end

end
