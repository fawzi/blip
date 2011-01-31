#!/usr/bin/env bash
version=dbg
clean=1
relink=
out=
compiler=
silent="-s"
tests=1
build_dir=
noopt=
nodbg=
noTangoUser=
BLIP_HOME=$PWD
mpi=

die() {
    echo "$1"
    exit $2
}

if [ -z "$D_HOME" ] ; then
    D_HOME=$HOME
fi
if [ -n "`which gmake`" ] ; then
    make="gmake"
elif [ -n "`which gnumake`" ] ; then
    make="gnumake"
else
    make="make"
fi
while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: build [--version x] [--quick] [--d-home dHome] "
            echo "           [--verbose] [--build-dir buildDir]"
            echo ""
            echo "  builds mainDFile.d linking blip and all needed libs (lapack, bz2,...)"
            echo "  --version x     builds version x (typically opt or dbg)"
            echo "  --quick         no clean before rebuilding"
            echo "  --verbose       verbose building"
            echo "  --d-home x      uses x as d home (default $D_HOME )"
            echo "  --blip-home x   uses x as blip home (defaults to $PWD )"
            echo "  --mpi           compiles the mpi version"
            echo "  --no-tango-user does not link the tango-user library"
            echo "  --no-tests      does not compile the tests"
            echo "  --no-opt        does not compile the opt version"
            echo "  --no-dbg        does not compile the dbg version"
            echo "  --build-dir X   uses X as build dir (you *really* want to use a local"
            echo "                  filesystem like /tmp/$USER/build for building if possible"
            if [ -n "$D_BUILD_DIR" ] ; then
                echo "                  defaults to $D_BUILD_DIR )"
            else
                echo "                  defaults to $D_HOME/build )"
            fi
            echo ""
            echo "The script uses '$'DC as compiler if set"
            echo "or the first compiler found if not set."
            echo "important environment variables are:"
            echo " D_HOME: the default --d-home value"
            echo " D_BUILD_DIR: the default build dir (you should use a local filesystem)"
            echo " DFLAGS_ADD: adds the given D flags"
            echo " CFLAGS_ADD: adds the given C flags"
            echo " DFLAGS: as environment variable is not changed"
            echo " CFLAGS: adds the given C flags"
            echo " EXTRA_LIBS: add the given link flags (to link lapack for example)"
            echo " MKLROOT: if sets links the mkl library on linux x86_64"
            exit 0
            ;;
        --version)
          shift
          version=$1
            ;;
        --quick)
            clean=
            ;;
        --verbose)
            silent=
            ;;
        --d-home)
            shift
            D_HOME=$1
            ;;
        --make)
            shift
            make="$1"
            ;;
        --build-dir)
            shift
            build_dir="OBJDIRBASE=$1"
            ;;
        --blip-home)
            shift
            BLIP_HOME=$1
            ;;
        --mpi)
            mpi=1
            ;;
        --no-tango-user)
            noTangoUser=1
            ;;
        --no-tests)
            tests=0
            ;;
        --no-dbg)
            nodbg=1
            ;;
        --no-opt)
            noopt=1
            ;;
        *)
            die "unexpected argument $1"
            break
            ;;
    esac
    shift
done
if [ -z "$build_dir" ] ; then
    if [ -n "$D_BUILD_DIR" ] ; then
        build_dir=OBJDIRBASE="$D_BUILD_DIR"
    fi
fi
if [ -z "$compiler" ]; then
    compiler=`$BLIP_HOME/build/tools/guessCompiler.sh --path $DC`
fi
compShort=`$BLIP_HOME/build/tools/guessCompiler.sh $compiler`
if [ "$version" == "opt" ]; then
    libExt=
else
    libExt="-$version"
fi
case $compShort in
    dmd)
    linkFlag="-L"
    versionFlag="-version="
    extra_libs_comp=""
    ;;
    ldc)
    linkFlag="-L="
    versionFlag="-d-version="
    extra_libs_comp=
    ;;
    *)
    die "unsupported compiler"
esac
mpiVersion=
mpiFlags=
if [ -n "$mpi" ] ; then
    mpiFlags=
    for f in `mpicc --showme:link` ; do
        mpiFlags="$mpiFlags ${linkFlag}$f"
    done
    mpiFlags="$mpiFlags ${versionFlag}mpi"
    mpiVersion="_mpi"
fi
case `uname` in
  Darwin)
  extra_libs_os="${linkFlag}-lhwloc ${linkFlag}-lev ${linkFlag}-framework ${linkFlag}Accelerate ${linkFlag}-lz ${linkFlag}-lbz2"
  ;;
  Linux)
    if [ -n "$MKLROOT" ] ; then
      extra_libs_os="${linkFlag}-lhwloc ${linkFlag}-lev ${linkFlag}-L$MKLROOT/lib/em64t ${linkFlag}-lmkl_lapack ${linkFlag}--start-group ${linkFlag}-lmkl_intel_lp64 ${linkFlag}-lmkl_core ${linkFlag}-lmkl_sequential ${linkFlag}--end-group ${linkFlag}-ldl ${linkFlag}-lz ${linkFlag}-lbz2"
    else
      extra_libs_os="${linkFlag}-lhwloc ${linkFlag}-lev ${linkFlag}-lgoto2 ${linkFlag}-ldl ${linkFlag}-lz ${linkFlag}-lbz2"
    fi
  ;;
  *)
  die "unknown platform, you need to set extra_libs_os"
esac
if [ -z "$noTangoUser" ]; then
    tangoUserOpt="${linkFlag}-ltango-user-${compShort}"
    tangoUserDbg="${linkFlag}-ltango-user-${compShort}-dbg"
fi
extra_libs_opt="${linkFlag}-L${D_HOME}/lib $tangoUserOpt $extra_libs_os $extra_libs_comp $mpiFlags"
extra_libs_dbg="${linkFlag}-L${D_HOME}/lib $tangoUserDbg $extra_libs_os $extra_libs_comp $mpiFlags"
case $version in
    opt)
    extra_libs="$extra_libs_opt"
    ;;
    dbg)
    extra_libs="$extra_libs_dbg"
    ;;
    *)
    echo "unknown version, guessing extra_libs"
    extra_libs="${linkFlag}-L${D_HOME}/lib $tangoUserDbg $extra_libs_os $extra_libs_comp $mpiFlags"
esac
makeFlags="$silent $build_dir"
if [ -n "$clean" ]; then
    $make $makeFlags distclean
    rm -f libs/libblip-*
fi
if [ -z "$noopt" ]; then
    $make $makeFlags EXTRA_LIBS="$EXTRA_LIBS $extra_libs_opt" VERSION=opt${mpiVersion} lib || die "error building the opt version"
fi
if [ -z "$nodbg" ]; then
    $make $makeFlags EXTRA_LIBS="$EXTRA_LIBS $extra_libs_dbg" VERSION=dbg${mpiVersion} lib || die "error building the dbg version"
fi
if [ -n "$tests" ] ; then
    $make $makeFlags EXTRA_LIBS="$EXTRA_LIBS $extra_libs" VERSION=$version${mpiVersion} || die "error building the tests"
fi
installDir=`dirname $compiler`/../lib
for l in libs/libblip-* ; do
    if [ -e "$l" ] ; then
      echo "$l -> $installDir"
      cp $l $installDir
    fi
done
