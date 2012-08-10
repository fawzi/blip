#!/usr/bin/env bash
clean=
BLIP_HOME=$PWD
mpi=

die() {
    echo "$1"
    exit $2
}

if [ -z "$D_HOME" ] ; then
    D_HOME=$HOME
fi
while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: install [options]"
            echo ""
            echo "  installs the blip libraries build"
            echo "  --clean         removes already installed libs"
            echo "  --blip-home x   uses x as blip home (defaults to $PWD )"
            if [ -n "$D_BUILD_DIR" ] ; then
                echo "                  defaults to $D_BUILD_DIR )"
            else
                echo "                  defaults to $D_HOME/build )"
            fi
            echo ""
            echo "The script uses '$'DC as compiler if set"
            echo "or the first compiler found if not set."
            echo "important environment variables are:"
            exit 0
            ;;
	--clean)
	    clean=1
	    ;;
        --blip-home)
            shift
            BLIP_HOME=$1
            ;;
        *)
            die "unexpected argument $1"
            break
            ;;
    esac
    shift
done
if [ -z "$compiler" ]; then
    compiler=`$BLIP_HOME/build/tools/guessCompiler.sh --path $DC`
fi
installDir=`dirname $compiler`/../lib
if [ -n "$clean" ] ; then
    echo "cleaning installed libs"
    rm -f "$installDir/libblip-*";
fi
for l in libs/libblip-* ; do
    if [ -e "$l" ] ; then
      echo "$l -> $installDir"
      cp $l $installDir
    fi
done
