source plugin/basler.vim

describe 'plugin'

  before
    let s:old_dir = getcwd()
    call delete('tmp/test', 'rf')
    call mkdir('tmp/test', 'p')

    cd tmp/test
    call mkdir('dir1/dir2', 'p')
    !touch dir1/BUILD.bazel
    !echo 'def http_archive():' >> dir1/http_archive.bzl
    !echo 'http_archive_2 = my_test(' >> dir1/http_archive.bzl
    !echo 'load("//dir1:http_archive.bzl", "http_archive")' >> WORKSPACE
    !echo 'http_archive()' >> WORKSPACE
    !echo 'http_archive_2()' >> WORKSPACE
  end

  after
    exec('cd ' . s:old_dir)
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
    " go to line 2
    2
    exe "normal [\<c-d>"
    Expect fnamemodify(expand('%'), ':p') == getcwd() . '/dir1/http_archive.bzl'
    exe "normal \<c-o>"

    3
    exe "normal [\<c-d>"
    Expect fnamemodify(expand('%'), ':p') == getcwd() . '/dir1/http_archive.bzl'
    exe "normal \<c-o>"


  end

end
