runtime autoload/basler.vim

describe 'basler#workspace_root'

  before
    let s:old_dir = getcwd()
    call delete('tmp/test', 'rf')
    call mkdir('tmp/test', 'p')

    cd tmp/test
    call mkdir('dir1/dir2', 'p')
    !touch WORKSPACE
  end

  it 'should find workspace root'
    cd dir1
    Expect basler#workspace_root() == fnamemodify(expand(getcwd() . '/..'), ':p:h')
    cd dir2
    Expect basler#workspace_root() == fnamemodify(expand(getcwd() . '/../..'), ':p:h')
  end

  after
    exec('cd ' . s:old_dir)
    call delete('tmp/test', 'rf')
  end
end

describe 'basler#include_expr'

  before
    call delete('tmp/test', 'rf')
    call mkdir('tmp/test', 'p')
    cd tmp/test
    call mkdir('dir1/dir2', 'p')
    !touch dir1/test.txt
    !touch dir1/BUILD.bazel
    !touch dir1/dir2/test.txt
    !touch dir1/dir2/BUILD
  end

  after
    cd -
    call delete('tmp/test', 'rf')
  end

  it 'returns passed value if nothing found'
    Expect basler#include_expr('//tmp:NONEXISTENT') == '//tmp:NONEXISTENT'
  end

  it 'returns filename if not a basel label'
    Expect basler#include_expr('/tmp/test.txt') == '/tmp/test.txt'
  end

  it 'finds file in the current workspace'
    Expect basler#include_expr('//dir1:test.txt') == getcwd() . '/dir1/test.txt'
    Expect basler#include_expr('//dir1/dir2:test.txt') == getcwd() . '/dir1/dir2/test.txt'
  end

  it 'finds BUILD file in the current workspace'
    Expect basler#include_expr('//dir1:rule-name') == getcwd() . '/dir1/BUILD.bazel'
    Expect basler#include_expr('//dir1/dir2:rule-name') == getcwd() . '/dir1/dir2/BUILD'
  end

  context 'with querying bazel'
    before
      !echo 'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")' > WORKSPACE

      let l:job = basler#bazel_info()
      let l:tries = 0
      while l:tries < 5
        let l:tries += 1
        if job_status(l:job) != 'run'
          break
        endif
        sleep 1
      endwhile
      Expect job_status(l:job) == 'dead'
      Expect job_info(l:job)->get('exitval') == 0
    end

    it 'finds external package'
      Expect basler#include_expr('@bazel_tools//tools/build_defs/repo:http.bzl')->matchstrpos('bazel_tools/tools/build_defs/repo/http.bzl') != -1
    end

  end

end
