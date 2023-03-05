source plugin/basler.vim

describe 'plugin'

  before
    let s:old_dir = getcwd()
    call delete('tmp/test', 'rf')
    call mkdir('tmp/test', 'p')

    cd tmp/test
    call mkdir('dir1/dir2', 'p')
    !touch dir1/BUILD.bazel
    !echo 'load("//dir1:test", "http_archive")' > WORKSPACE
  end

  it 'should set up gf'
    edit WORKSPACE
    set ft=starlark
    normal f/
    normal gf
    Expect expand('%') == getcwd() . '/dir1/BUILD.bazel'
  end

  after
    exec('cd ' . s:old_dir)
    call delete('tmp/test', 'rf')
  end
end
