---
title: How to D
layout: Default
---

How to D, setting up a D environment on linux x86_64
====================================================

Here there used to be how I did a full setup of my basic D environment and tested it well.
In january 2011 I began full rewrite with support for more compilers, and nicer setup, it is still work in progress, but it should become an easy way to set up a complete D environment from scratch as non root.

Basic setups
------------

    # setting up a D environment from scratch
    # you might want to change the following variables

    # the place where D and D related stuff should live
    export D_HOME=$HOME/d
    # the directory to use for the packages & building (not needed once installed)
    export BuildDir=/tmp/$USER
    # the place where to build D stuff
    # for performace reasons you want this to be local
    export D_BUILD_DIR=/tmp/$USER/d_build

    # preparing a setup file in $D_HOME/bin that sets up the environment
    # so that D is used
    mkdir -p $D_HOME/bin
    cat > $D_HOME/bin/setup.sh <<EOF
    # source this file to setup the D environment

    . $D_HOME/env/base.sh
    # by default adds the ldc compiler, change it if you want
    . $D_HOME/env/ldc.sh
    EOF

    # create setup files for the various compilers
    mkdir $D_HOME/env
    # base
    cat > $D_HOME/env/base.sh <<EOF
    # source this file for the basic setup of the d environment

    export D_HOME=$D_HOME
    export D_BUILD_DIR=$D_BUILD_DIR
    mkdir -p $D_BUILD_DIR
    export PATH=\$D_HOME/bin:\$PATH
    export LD_LIBRARY_PATH=\$D_HOME/lib:\$LD_LIBRARY_PATH
    export LD_RUN_PATH=\$D_HOME/lib:\$LD_RUN_PATH
    export LDPATH=\$D_HOME/lib:\$LDPATH
    export LDFLAGS="-L\$D_HOME/lib \$LDFLAGS"
    export ACLOCAL_PATH=/home/b/becfawzi/d/share/aclocal
    EOF

Setup (environment) files for various compilers
-----------------------------------------------

    # dmd
    cat > $D_HOME/env/dmd.sh <<EOF
    # source this file to setup the dmd compiler

    export PATH=$D_HOME/dmd/linux/bin:$PATH
    export LDPATH=$D_HOME/dmd/linux/lib64:$D_HOME/dmd/linux/lib:$LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=$D_HOME/dmd/linux/lib64:$D_HOME/dmd/linux/lib:$LD_LIBRARY_PATH
    export LD_RUN_PATH=$D_HOME/dmd/linux/lib:$D_HOME/dmd/linux/lib64:$LD_RUN_PATH
    EOF
    # ldc
    cat > $D_HOME/env/ldc.sh <<EOF
    # source this file to setup the ldc compiler

    export PATH=$D_HOME/ldc/bin:$D_HOME/llvm/bin:$PATH
    export LDPATH=$D_HOME/ldc/lib:$D_HOME/llvm/lib:$LDPATH
    export LD_LIBRARY_PATH=$D_HOME/ldc/lib:$D_HOME/llvm/lib:$LD_LIBRARY_PATH
    export LD_RUN_PATH=$D_HOME/ldc/lib:$D_HOME/dmd/llvm/lib:$LD_RUN_PATH
    EOF
    # gdc
    cat > $D_HOME/env/gdc.sh <<EOF
    # source this file to setup the gdc compiler

    export PATH=$D_HOME/gdc/bin:$PATH
    export LDPATH=$D_HOME/gdc/lib:$LDPATH
    export LD_LIBRARY_PATH=$D_HOME/gdc/lib:$LD_LIBRARY_PATH
    export LD_RUN_PATH=$D_HOME/gdc/lib:$LD_RUN_PATH
    EOF

load the d environment, and move to the build directory

    . $D_HOME/bin/setup.sh
    mkdir -p $BuildDir
    cd $BuildDir

Common libs/software
--------------------
You might skip something if you have it already, but the following will assume that you install it.
You will need hg http://mercurial.selenic.com/ , which is not installed as part of this.

    # libbz2
    # 
    # if you are missing libbz2 get it from http://www.bzip.org/downloads.html

    wget http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
    tar xzf bzip2-1.0.6.tar.gz
    cd bzip2-1.0.6
    make
    make install PREFIX=$D_HOME
    cd ..
    rm -rf bzip2-1.0.6*

    # zlib
    #
    # if you are missing libz downoad the tar from http://www.zlib.net/
    wget http://zlib.net/zlib-1.2.5.tar.gz
    tar xzf zlib-1.2.5.tar.gz
    cd zlib-1.2.5
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf zlib-1.2.5*

    # m4 (needed by autoconf)
    #
    wget http://ftp.gnu.org/gnu/m4/m4-1.4.15.tar.bz2
    wget http://ftp.gnu.org/gnu/m4/m4-1.4.15.tar.bz2.sig
    #verify.sh m4-1.4.15.tar.bz2
    tar xjf m4-1.4.15.tar.bz2
    cd m4-1.4.15
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf m4-1.4.15*

    # Autoconf tools 
    # 
    # if you don't have automake (needed by hwloc and gcc)
    wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.68.tar.bz2
    tar xjf autoconf-2.68.tar.bz2
    cd autoconf-2.68
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf autoconf-2.68*

    wget http://ftp.gnu.org/gnu/automake/automake-1.11.tar.bz2
    wget http://ftp.gnu.org/gnu/automake/automake-1.11.tar.bz2.sig
    #verify.sh m4-1.4.15.tar.bz2
    tar xjf automake-1.11.tar.bz2
    cd automake-1.11
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf automake-1.11*

    wget http://ftp.gnu.org/gnu/libtool/libtool-2.2.10.tar.gz
    wget http://ftp.gnu.org/gnu/libtool/libtool-2.2.10.tar.gz.sig
    #verify.sh libtool-2.2.10.tar.gz
    tar xzf libtool-2.2.10.tar.gz
    cd libtool-2.2.10
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf libtool-2.2.10*

    # git
    # if you don't have it
    wget http://kernel.org/pub/software/scm/git/git-1.7.3.5.tar.bz2
    tar xjf git-1.7.3.5.tar.bz2
    cd git-1.7.3.5
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf git-1.7.3.5*

Ldc
----

    # cmake (for ldc)
    # needs also the package, so build it in $D_HOME/pkgs
    mkdir -p $D_HOME/pkgs
    cd $D_HOME/pkgs
    wget http://www.cmake.org/files/v2.8/cmake-2.8.3.tar.gz
    tar xzf cmake-2.8.3.tar.gz
    cd cmake-2.8.3
    ./configure --prefix=$D_HOME
    make
    make install
    cd $BuildDir

    # libconfig (for ldc)
    wget http://www.hyperrealm.com/libconfig/libconfig-1.3.2.tar.gz
    tar xzf libconfig-1.3.2.tar.gz
    cd libconfig-1.3.2
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf libconfig-1.3.2*

    # LLVM
    #
    # if you use ldc you need llvm 2.8, probably you can use the clang package
    # that contains a complete llvm and you can install in $D_HOME/llvm.
    # compiling from source allows one to activate the assertions, a good idea if
    # you plan to track ldc development.
    # Should you prefer a compilation from source:
    # llvm is installed in a separated directory for more flexibility
    svn co http://llvm.org/svn/llvm-project/llvm/branches/release_28 llvm28
    mkdir llvm-build
    cd llvm-build
    ../llvm28/configure --prefix=$D_HOME/llvm --enable-optimized \
       --enable-assertions
    make
    make install
    cd ..
    rm -rf llvm28 llvm-build

    # LDC
    #
    #follow the [build instruction for ldc](http://dsource.org/projects/ldc/wiki/BuildInstructions), i.e.
    mkdir -p $D_HOME/pkgs
    cd $D_HOME/pkgs
    hg clone http://bitbucket.org/lindquist/ldc ldc
    cd ldc
    # the following times you can
    # hg pull
    # hg update
    cmake ./ -DCMAKE_INSTALL_PREFIX=$D_HOME/ldc \
       -DLIBCONFIG_CXXFLAGS=-I$D_HOME/include \
       -DLIBCONFIG_LDFLAGS="-L$D_HOME/lib -lconfig++" \
       -DLLVM_CONFIG=$D_HOME/llvm/bin/llvm-config \
       -DLLVM_CONFIG_FILE_PATH=$D_HOME/llvm/include/llvm/Config \
       -DLLVM_INSTDIR=$D_HOME/llvm \
       -DRUNTIME_DIR=$D_HOME/tango \
       -DRUNTIME_AIO=tango-base-ldc
    # at the moment one should remove the leading / to "set(CONF_INST_DIR /etc)"
    # in CMakeLists.txt
    make
    make install
    # we compile the runtime separately from the user lib, so we rename the default lib to link
    mv $D_HOME/etc/ldc.conf $D_HOME/etc/ldc.conf.orig
    sed -e 's/tango-user-ldc/tango-base-ldc/g'  \
        $D_HOME/etc/ldc.conf.orig > $D_HOME/etc/ldc.conf
    cd $BuildDir

Tango
-----
the [tango library](http://dsource.org/projects/tango)

    # tango
    #
    # at the moment (until the next release) you need the trunk version of tango,
    # or the older (and slighlty better tested) oldTango. Using the tango trunk
    cd $D_HOME
    svn co http://svn.dsource.org/projects/tango/trunk tango
    # if you haven't downloaded blip yet
    git clone git://github.com/fawzi/blip
    #
    cd blip/buildTango
    ./buildLdc.sh
    cd ../..

Blip/dchem libs
---------------
libraries either needed or suggested for blip and dchem

    # libxml2 needed by the xml hwloc backend
    wget ftp://xmlsoft.org/libxml2/libxml2-sources-2.7.8.tar.gz
    tar xzf libxml2-sources-2.7.8.tar.gz
    cd libxml2-2.7.8
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf libxml2-sources-2.7.8.tar.gz libxml2-2.7.8

    # hwloc
    # hardware locality, gives a more efficeint blip.parallel.smp
    cd $D_HOME/pkgs
    svn co http://svn.open-mpi.org/svn/hwloc/branches/v1.1 hwloc1_1
    cd hwloc1_1
    ./autogen.sh
    cd ..
    mkdir hwloc-build
    cd hwloc-build
    ../hwloc1_1/configure --prefix=$D_HOME --enable-static=yes --disable-cairo
    make
    make install
    cd ..
    rm -rf hwloc-build
    cd $BuildDir

    # libev
    #
    cd $D_HOME/pkgs
    #cvs -z3 -d :pserver:anonymous@cvs.schmorp.de/schmorpforge co -r rel-4_03 libev
    cvs -z3 -d :pserver:anonymous@cvs.schmorp.de/schmorpforge co -r rel-3_9 libev
    cd libev
    autoreconf -ivf
    ./configure --prefix=$D_HOME
    make
    make install
    cd $BuildDir

    # Open mpi (optional)
    #
    # if you want to build mpi parallelized programs and don't have open mpi
    # installed (otherwise as long as mpicc is in the path it is ok).
    # it is installed to another subdirectory, because you might want to use
    # another mpi version...
    wget http://www.open-mpi.org/software/ompi/v1.4/downloads/openmpi-1.4.2.tar.bz2
    tar xjf openmpi-1.4.2.tar.bz2
    cd openmpi-1.4.2
    ./configure --prefix=$D_HOME/ompi
    make
    make install
    cd ..
    rm -rf openmpi-1.4.2*

    # FFTW (optional)
    #
    # if you don't have fftw and you want to use it
    wget http://www.fftw.org/fftw-3.2.2.tar.gz
    tar xzf fftw-3.2.2.tar.gz
    cd fftw-3.2.2
    ./configure --prefix=$D_HOME
    make
    make install
    cd ..
    rm -rf fftw-3.2.2*

xfbuild
-------
xfbuild lets you build d files easily, blip dbuild script uses it

    hg clone http://bitbucket.org/h3r3tic/xfbuild build
    cd build
    ./ldcBuild.sh
    cp xfbuild $D_HOME/bin
    cd ..

blip
----

    # you should have done
    # git clone git://github.com/fawzi/blip
    # while installing tango, otherwise do it now
    cd blip
    # later you can just git pull
    ./build.sh --install
    # add a simple script to build d programs
    ln -s $D_HOME/blip/dbuild $D_HOME/bin

dbuild
------
dbuild is installed with blip.
use dbuild [--version dbg|opt] [--full]  file.d to create the executable file.opt (or file.dbg)
use --help to get more information on all the flags

Dmd
----
The Dmd compiler. On 64 bit one should still test the beta (should change soonish)

    # dmd
    #
    # the new dmd compiler with beta support for 64 bit, installed in the dmd
    # subdirectory of $D_HOME
    wget http://ftp.digitalmars.com/dmd1beta.zip
    unzip dmd1beta.zip -d $D_HOME

Gdc
----
Gdc development has been recovered and proceeds very quickly. The support for tango is being reestablished.
We start installing gdc with phobos.

    ### gdc stuff
    cd $BuildDir
    wget ftp://ftp.fu-berlin.de/unix/languages/gcc/infrastructure/gmp-4.3.2.tar.bz2
    tar xjf gmp-4.3.2.tar.bz2
    cd gmp-4.3.2
    ./configure --prefix=$D_HOME/gdc
    make
    make check
    make install
    cd ..
    rm -rf gmp-4.3.2 gmp-4.3.2.tar.bz2

    cd $BuildDir
    wget ftp://ftp.fu-berlin.de/unix/languages/gcc/infrastructure/mpfr-2.4.2.tar.bz2
    tar xjf mpfr-2.4.2.tar.bz2
    cd mpfr-2.4.2
    ./configure --prefix=$D_HOME/gdc --with-gmp=$D_HOME/gdc
    make
    make install
    cd ..
    rm -rf mpfr-2.4.2*

    cd $BuildDir
    wget ftp://ftp.fu-berlin.de/unix/languages/gcc/infrastructure/mpc-0.8.1.tar.gz
    tar xzf mpc-0.8.1.tar.gz
    cd mpc-0.8.1
    ./configure --prefix=$D_HOME/gdc --with-gmp=$D_HOME/gdc --with-mpfr=$D_HOME/gdc
    make
    make install
    cd ..
    rm -rf mpc-0.8.1*

    cd $D_HOME/pkgs
    hg clone https://goshawk@bitbucket.org/goshawk/gdc
    mkdir gdc/dev
    cd gdc/dev
    wget ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-4.5.2/gcc-4.5.2.tar.bz2
    #wget ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-4.5.2/gcc-core-4.5.2.tar.bz2
    tar xjf gcc-4.5.2.tar.bz2
    cd gcc-4.5.2
    ln -s ../../../d gcc/d
    cd ..
    ./gcc/d/setup-gcc.sh
    mkdir $D_BUILD_DIR/gcc
    cd $D_BUILD_DIR/gcc
    $D_HOME/pkgs/gdc/dev/gcc-4.5.2/configure --enable-languages=d --enable-checking=release \
        --disable-shared --prefix=$D_HOME/gdc  --with-gmp=$D_HOME/gdc --with-mpfr=$D_HOME/gdc \
        --with-mpc=$D_HOME/gdc CPPFLAGS="-I$D_HOME/gdc/include -I$D_HOME/include $CPPFLAGS" \
        LDFLAGS="-L$D_HOME/gdc/lib -L$D_HOME/lib $LDFLAGS"
    make
    make install
    cd ..
    rm -rf gcc-4.5.2*

now if we want to use tango we have to deactivate phobos, and activate tango, and build it.
At the moment it is a bit ugly.

    mkdir $D_HOME/gdc/include/d/4.5.2/phobos
    mv $D_HOME/gdc/include/d/4.5.2/std $D_HOME/gdc/include/d/4.5.2/object.d $D_HOME/gdc/include/d/4.5.2/phobos
    ln -s $D_HOME/gdc/tango/tango $D_HOME/gdc/tango/object.di $D_HOME/gdc/include/d/4.5.2
    mv $D_HOME/gdc/lib/libgphobos.a $D_HOME/gdc/lib/libgphobos-orig.a
    ln -s $D_HOME/gdc/lib/libtango-base-gdc.a $D_HOME/gdc/lib/libgphobos.a
    cd $D_HOME/blip/buildTango
    ./buildGdc.sh

Old stuff
=========
Old tango
---------
If you want to use the older tango version (might have issues with newer compilers)

    cd $D_HOME
    git clone git://github.com/fawzi/oldTango.git tango
    cd tango/build
    ./build.sh

    ./build.sh --version tst
    ./unittest-ldc.sh
    ./runUnittests_ldc
    ./build.sh --clean
    cd ..

dchem
-----

    git clone git@github.com:fawzi/dchem.git
    cd dchem
    # later you can just
    git pull
