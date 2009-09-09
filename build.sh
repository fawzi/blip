#!/usr/bin/env bash
version=opt
clean=1
relink=
out=
compiler=
silent="-s"
tests=1
if [ -z "$TANGO_HOME" ] ; then
    TANGO_HOME=$HOME/tango
fi
if [ -z "$BLIP_HOME" ] ; then
    BLIP_HOME=$HOME/blip
fi
while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: build [--dbg] [--opt] [--quick] [--tango-home tangoHome] "
            echo "           [--verbose]"
            echo ""
            echo "  builds mainDFile.d linking tango, blip and all needed libs (lapack, bz2,...)"
            echo "  --debug         builds the debug version"
            echo "  --opt           builds the optimized version"
            echo "  --quick         no clean before rebuilding"
            echo "  --verbose       verbose building"
            echo "  --tango-home x  uses x as tango home (default is $TANGO_HOME )"
            echo ""
            echo "  useful xfbuild options:"
            echo "  -ox       can be used to give the name x to the executable"
            echo "  --        separates xfbuild options from compiler options"
            exit 0
            ;;
        --dbg)
            version=dbg
            ;;
        --opt)
            version=opt
            ;;
        --quick)
            clean=
            ;;
        --verbose)
            silent=
            ;;
        --tango-home)
            shift
            TANGO_HOME=$1
            ;;
        --no-tests)
            tests=0
            ;;
        *)
            die "unexpected argument $1"
            break
            ;;
    esac
    shift
done

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
    linkLib="-L-l"
    linkPath="-L-L"
    extra_libs_opt="-L-ltango-user-dmd -defaultlib=tango-base-dmd -L-framework -LAccelerate -L-lz -L-lbz2"
    extra_libs_dbg="-L-ltango-user-dmd-dbg -defaultlib=tango-base-dmd -L-framework -LAccelerate -L-lz -L-lbz2"
    extra_libs="-L-ltango-user-dmd$libExt -defaultlib=tango-base-dmd -L-framework -LAccelerate -L-lz -L-lbz2"
    ;;
    ldc)
    linkLib="-L=-l"
    linkPath="-L=-L"
    extra_libs_opt="-L=-ltango-user-dmd -defaultlib=tango-base-dmd -L=-framework -L=Accelerate -L=-lz -L=-lbz2"
    extra_libs_dbg="-L=-ltango-user-dmd-dbg -defaultlib=tango-base-dmd -L=-framework -L=Accelerate -L=-lz -L=-lbz2"
    extra_libs="-L=-ltango-user-dmd$libExt -defaultlib=tango-base-dmd -L=-framework -L=Accelerate -L=-lz -L=-lbz2"
    ;;
    *)
    die "unsupported compiler"
esac
case $version in
    opt)
    flags="-release -O"
    ;;
    dbg)
    flags="-g"
    ;;
    *)
    die "unknown version"
esac
if [ -z "$out_name" ]; then
    out_name=${main_d%%d}$version
fi

if [ -n "$clean" ]; then
    make $silent distclean
fi
rm libblip-*
make $silent EXTRA_LIBS="$extra_libs_opt" VERSION=opt lib
make $silent EXTRA_LIBS="$extra_libs_dbg" VERSION=dbg lib
if [ -n "$tests" ] ; then
    make $silent EXTRA_LIBS="$extra_libs" VERSION=$version
fi
installDir=`dirname $compiler`/../lib
echo "cp libblip-* $installDir"
cp libblip-* $installDir