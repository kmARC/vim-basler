runtime autoload/basler.vim

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

describe 'autoload/basler.vim'

  before
    call s:setup_workspace()
    call s:wait_for_bazel()
  end

  after
    exec('cd ' . s:old_dir)
    call delete(s:tmp_dir, "rf")
  end

  context "g:basler_bazel_info"

    it 'finds workspace root'
      cd dir1
      Expect basler#workspace_root() == fnamemodify(expand(getcwd() . '/..'), ':p:h')
      cd dir2
      Expect basler#workspace_root() == fnamemodify(expand(getcwd() . '/../..'), ':p:h')
    end

  end

  context 'basler#include_expr'

    it 'returns passed value if nothing found'
      Expect basler#include_expr('//:NONEXISTENT') == '//:NONEXISTENT'
    end

    it 'returns filename if not a bazel label'
      Expect basler#include_expr('/tmp/test.txt') == '/tmp/test.txt'
    end

    it 'finds file in the current workspace'
      Expect basler#include_expr('//dir1:first.bzl') == getcwd()
                              \ . '/dir1/first.bzl'
      Expect basler#include_expr('//dir1/dir2:second.bzl') == getcwd() 
                              \ . '/dir1/dir2/second.bzl'
      Expect basler#include_expr('//:dir3/dir4/fourth.bzl') == getcwd() 
                              \ . '/dir3/dir4/fourth.bzl'
    end

    it 'finds BUILD file where rule is defined in the current workspace'
      Expect basler#include_expr('//:existing-rule') == getcwd() . '/BUILD.bazel'
    end

    it 'finds target in external package'
      Expect basler#include_expr('@bazel_tools//tools/build_defs/repo:http.bzl')
             \ == g:basler_bazel_info->get(getcwd())->get("output_base") . "/external/" .
             \                    'bazel_tools/tools/build_defs/repo/http.bzl'
    end

    it 'finds relative target'
      edit dir1/test.txt
      let relative_test = basler#include_expr(':relative-test')
      Expect relative_test == getcwd() . '/dir1/BUILD.bazel'
      bd dir1/test.txt
    end

  end

end

" describe 'basler#include_expr'


"   context 'with querying bazel'
"     before
"       !echo 'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")' > WORKSPACE

"       let l:job = basler#bazel_info()
"       let l:tries = 0
"       while l:tries < 5
"         let l:tries += 1
"         if job_status(l:job) != 'run'
"           break
"         endif
"         sleep 1
"       endwhile
"       Expect job_status(l:job) == 'dead'
"       Expect job_info(l:job)->get('exitval') == 0
"     end

"     it 'finds external package'
"       Expect basler#include_expr('@bazel_tools//tools/build_defs/repo:http.bzl')->matchstrpos('bazel_tools/tools/build_defs/repo/http.bzl') != -1
"     end

"   end

" end
