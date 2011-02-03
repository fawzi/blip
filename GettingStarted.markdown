---
title: Getting Started
layout: Default
---

Getting Started
===============

blip has been tested only on mac and linux, some parts *should* work on windows, but 
others will probably need some porting.

To use blip you need a few things. You can install everything in the way you prefer, in 
general you might disable some parts of blip that you are not interested in by using the 
correct flags. The easiest way is to add the flags to the DFLAGS environment variable
(or to your compiler configuration file).
For example to set version=noHwloc with a bash shell you would do
{{{
export DFLAGS="$DFLAGS -version=noHwloc"
}}}
with the dmd compiler and
{{{
export DFLAGS="$DFLAGS -d-version=noHwloc"
}}}
with the ldc compiler.

How to D
--------
If you are on linux there is an example on how I did setup a complete D environment without being an administrator (root) on the machine on [howToD](http://fawzi.github.com/blip/HowToD.html), if you are root then you might install at least some package using the normal package manager.

D compiler
----------
If you are new to D you should start by installing a D compiler. You have a few choices:

 * DMD the main D compiler, developed by Walter Bright, compiles quickly and is reasonably
   competitive, but 32 bit only (work toward 64 bit support is being done)
   [dmd mac](http://www.digitalmars.com/d/1.0/dmd-osx.html) or 
   [dmd linux](http://www.digitalmars.com/d/1.0/dmd-linux.html)
 * [LDC](http://dsource.org/projects/ldc) compiler uses the LLVM machinery as backend and 
   the DMD frontend. It is actively developed and works well on linux x86_64.

 * [GDC](http://bitbucket.org/goshawk/gdc/wiki/Home) compiler uses the DMD frontend and
   the gcc backend. Is stable compiles and optimizes well, its development has been resumed
   recently, and support in tango has been only recently added back, so you might have some
   small issues. Can be used on many platforms

Tango
-----

Tango http://dsource.org/projects/tango is a standard robust library for D1.
You should use the trunk of tango to build blip (or the older frozen version 
http://github.com/fawzi/oldTango), because the current release has some low 
probability bugs with respect to threading and fibers.
The next release of tango will be supported 

There are useful scripts to build tango trunk in the buildTango directory.
If you put the tango directory at the same level of the blip directory they will
build and install tango.
They will install the basic runtime in the libtango-base-dmd.a or libtango-base-ldc.a
library, so edit your dmd.conf/ldc.cof file accordingly (-defaultlib=libtango-base-xxx.a 
-debuglib=libtango-base-xxx.a).
You should also remember to add the tango directory and tango/core/vendor to the search path of the compiler (-ItangoDir -ItangoDir/tango/core/vendor)

Hwloc
-----
to have automatic detection of your CPUs, and memory hierarchy the hwloc 1.1 library from 
http://www.open-mpi.org/projects/hwloc/ is used.

If you don't want to install and use it you should add version=noHwloc

Libev
-----
The socket, rpc, and event based infrastructure (EventManager) use the scalable event library libev 3.9 from http://software.schmorp.de/pkg/libev.html

If you don't want to install and use it you should not use any of those parts of blip and build blip using --no-libev

Blas and Lapack
---------------
blas and lapack are used by for some NArray operations.
On OSX by default the Accelerate framework is used, and on linux if MKL_ROOT is defined the MKL library is used, otherwise blas and lapack are linked.
To link other libraries put in the environment variable EXTRA_LIBS the requested flags, and possibly fix the build.sh script.

If you do not want to use those NArray operations (basic array operations are still 
defined) you should use version=no_blas and version=no_lapack when compiling

Blip
----
For blip itself, the git repository is available at
    http://github.com/fawzi/

If you have git you can
    git clone git://github.com/fawzi/blip.git
then
    cd blip
    ./build.sh --help
and you should get help with the flags and environment variables that influence the build script.

If you have all libraries
    ./build.sh --install
should build the blip library (in the libs directory, and a copy should be automatically installed), and the test programs (in the exe directory).
If you have disabled some libraries you should build with --no-tests because the automatic compilation of the tests will fail. You might still be able to build some of the tests by hand.

xfbuild
-------
[xfbuild](http://bitbucket.org/h3r3tic/xfbuild/wiki/Home) is not needed, but makes building your own d programs easier (and is fast).

If you installed it you can try to use the dbuild script (that automatically links all the needed stuff).

To compile and link your project you can also simply pass all your D files, the libraries (blip,tango-user,libev,...) to the compiler.

Mpi
----
mpi has wrappers to the open mpi routines, but that has to be activated explicitly ( the wrapper has been created and tested with openmpi).

Tests
-----
The code has a comprehensive battery of test.
By default all of them are built, which especially for testNArray might take some time, 
if you don't want to build them use pass --no-tests.
The tests in testNArray are quite stringent, and with random generation they might be 
numerically difficult.
I did not want to reduce too much the accuracy of the tests, and so in some cases they 
might fail (especially for single precision without blas, or with a very agressive blas),
it this is the case look at the error that they have, probably everything is still ok.
On windows there is a limit on the number of symbols that can be defined in a single file, 
testNArray with all tests would exceed this limit, so by default only the tests for double 
argument are performed, if you want other you have to activate them by hand.

have fun!

Fawzi
