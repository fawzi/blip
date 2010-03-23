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
            echo "usage: build [--version x] [--quick] [--d-home dHome] [--tango-home tangoHome] "
            echo "           [--verbose] [--build-dir buildDir]"
            echo ""
            echo "  builds mainDFile.d linking tango, blip and all needed libs (lapack, bz2,...)"
            echo "  --version x     builds version x (typically opt or dbg)"
            echo "  --quick         no clean before rebuilding"
            echo "  --verbose       verbose building"
            echo "  --d-home x      uses x as d home (default $D_HOME )"
            echo "  --tango-home x  uses x as tango home"
            echo "  --no-tests      does not compile the tests"
            echo "  --no-opt      does not compile the opt version"
            echo "  --build-dir X   uses X as build dir (you *really* want to use a local"
            echo "                  filesystem like /tmp/$USER/build for building if possible)"
            echo ""
            echo "The script uses '$'DC as compiler if set"
            echo "or the first compiler found if not set."
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
        --tango-home)
            shift
            TANGO_HOME=$1
            ;;
        --no-tests)
            tests=0
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
if [ -z "$TANGO_HOME" ] ; then
    TANGO_HOME=$D_HOME/tango
fi
if [ -z "$build_dir" ] ; then
    if [ -n "$D_BUILD_DIR" ] ; then
        build_dir=OBJDIRBASE="$D_BUILD_DIR"
    fi
fi
if [ -z "$compiler" ]; then
    compiler=`$TANGO_HOME/build/tools/guessCompiler.sh --path $DC`
fi
compShort=`$TANGO_HOME/build/tools/guessCompiler.sh $compiler`
if [ "$version" == "opt" ]; then
    libExt=
else
    libExt="-$version"
fi
case $compShort in
    dmd)
    linkFlag="-L"
    extra_libs_comp="-defaultlib=tango-base-${compShort}"
    ;;
    ldc)
    linkFlag="-L="
    extra_libs_comp=
    ;;
    *)
    die "unsupported compiler"
esac
case `uname` in
  Darwin)
  extra_libs_os="${linkFlag}-lhwloc ${linkFlag}-framework ${linkFlag}Accelerate ${linkFlag}-lz ${linkFlag}-lbz2"
  ;;
  Linux)
  extra_libs_os="${linkFlag}-lhwloc ${linkFlag}-lgoto2 ${linkFlag}-ldl ${linkFlag}-lz ${linkFlag}-lbz2 ${linkFlag}-lg2c"
  ;;
  *)
  die "unknown platform, you need to set extra_libs_os"
esac
extra_libs_opt="${linkFlag}-L${D_HOME}/lib ${linkFlag}-ltango-user-${compShort} $extra_libs_os $extra_libs_comp"
extra_libs_dbg="${linkFlag}-L${D_HOME}/lib ${linkFlag}-ltango-user-${compShort}-dbg $extra_libs_os $extra_libs_comp"
case $version in
    opt)
    extra_libs="$extra_libs_opt"
    ;;
    dbg)
    extra_libs="$extra_libs_dbg"
    ;;
    *)
    echo "unknown version, guessing extra_libs"
    extra_libs="${linkFlag}-L${D_HOME}/lib ${linkFlag}-ltango-user-${compShort}-${version} $extra_libs_os $extra_libs_comp"
esac
makeFlags="$silent TANGO_HOME=$TANGO_HOME $build_dir"
if [ -n "$clean" ]; then
    $make $makeFlags distclean
    rm -f libs/libblip-*
fi
if [ -z "$noopt" ]; then
    $make $makeFlags EXTRA_LIBS="$extra_libs_opt" VERSION=opt lib || die "error building the opt version"
fi
$make $makeFlags EXTRA_LIBS="$extra_libs_dbg" VERSION=dbg lib || die "error building the dbg version"
if [ -n "$tests" ] ; then
    $make $makeFlags EXTRA_LIBS="$extra_libs" VERSION=$version || die "error building the tests"
fi
installDir=`dirname $compiler`/../lib
for l in libs/libblip-* ; do
    echo "$l -> $installDir"
    cp $l $installDir
done
