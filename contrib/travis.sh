#!/bin/bash
# This file is a part of Julia. License is MIT: https://julialang.org/license
if [ $GC_ANALYZE = 0 ]; then
    contrib/download_cmake.sh;
    make -C moreutils mispipe;
    make $BUILDOPTS -C base version_git.jl.phony;
    # capture the log, but only print it if `make deps` fails
    # try to show the end of the log first, because this log might be very long (> 4MB)
    # and thus be truncated by travis
    moreutils/mispipe "make \$BUILDOPTS NO_GIT=1 -C deps 2> deps-err.log" "$BAR" > deps.log ||
        { echo "-- deps build log stderr tail 100 --------------------------------------";
          tail -n 100 deps-err.log;
          echo "-- deps build log stdout tail 100 --------------------------------------";
          tail -n 100 deps.log;
          echo "-- deps build log stderr all -------------------------------------------";
          cat deps-err.log;
          echo "-- deps build log stdout all -------------------------------------------";
          cat deps.log;
          echo "-- end of deps build log -----------------------------------------------";
          false; };
    # compile / install Julia
    make $BUILDOPTS NO_GIT=1 prefix=/tmp/julia release | moreutils/ts -s "%.s";
    make $BUILDOPTS NO_GIT=1 prefix=/tmp/julia install | moreutils/ts -s "%.s";
    make $BUILDOPTS NO_GIT=1 build-stats;
    du -sk /tmp/julia/*;
    ls -l /tmp/julia/lib;
    ls -l /tmp/julia/lib/julia;
    FILES_CHANGED=$(git diff --name-only $TRAVIS_COMMIT_RANGE -- || git ls-files);
    cd .. && mv julia julia2;
    # run tests
    /tmp/julia/bin/julia --sysimage-native-code=no -e 'true';
    # - /tmp/julia/bin/julia-debug --sysimage-native-code=no -e 'true'
    /tmp/julia/bin/julia -e 'Base.require(Main, :InteractiveUtils).versioninfo()';
    pushd /tmp/julia/share/julia/test;
    # skip tests if only files within the "doc" dir have changed
    if [ $(echo "$FILES_CHANGED" | grep -cv '^doc/') -gt 0 ]; then
        /tmp/julia/bin/julia --check-bounds=yes runtests.jl $TESTSTORUN &&
        /tmp/julia/bin/julia --check-bounds=yes runtests.jl LibGit2/online Pkg/pkg download; fi;
    popd;
    # test that the embedding code works on our installation
    mkdir /tmp/embedding-test &&
       make check -C /tmp/julia/share/julia/test/embedding \
         JULIA="/tmp/julia/bin/julia" \
         BIN=/tmp/embedding-test \
         "$(cd julia2 && make print-CC)";
    # restore initial state and prepare for travis caching
    mv julia2 julia &&
       rm -f julia/deps/scratch/libgit2-*/CMakeFiles/CMakeOutput.log;
    # run the doctests on Linux 64-bit
    if [ `uname` = "Linux" ] && [ $ARCH = "x86_64" ]; then
        pushd julia && make -C doc doctest=true && popd; fi;
else
    make -C deps install-llvm;
    make -C src analyzegc;
fi;
