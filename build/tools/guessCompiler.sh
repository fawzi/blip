#!/usr/bin/env bash
# tries to guess the D compiler
# tango & apache 2.0 license, © 2009 Fawzi Mohamed

return_path=
while [ $# -gt 0 ]
do
    case $1 in
        --help)
            echo "usage: guessCompiler.sh [--help] [--path] [compiler]"
            echo "tries to find out the short string for the given compiler (dmd,ldc,gdc)"
            echo "If --path is given the full path to the compiler is given"
            exit 0
            ;;
        --path)
            return_path=1
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ -n "$1" -o -n "$DC" ]; then
    comp=$1
    if [ -z "$comp" ] ; then
        comp="$DC"
    fi
    if [ -n "$return_path" ]; then
        which "$comp"
    elif ( "$comp" -v 2>&1 | grep DMD >& /dev/null ) ; then
        echo dmd
    elif ( "$comp" -v 2>&1 | grep ldc2 >& /dev/null ) ; then
        echo ldc2
    elif ( "$comp" -v 2>&1 | grep ldc >& /dev/null ) ; then
        echo ldc
    elif ( "$comp" -v 2>&1 | grep gdc >& /dev/null ) ; then
        echo gdc
    else
        echo `basename $comp`
    fi
elif (which dmd >& /dev/null); then
    if [ -n "$return_path" ]; then
        which dmd
    else
        echo dmd
    fi
elif (which gdc >& /dev/null); then
    if [ -n "$return_path" ]; then
        which gdc
    else
        echo gdc
    fi
elif (which ldc2 >& /dev/null); then
    if [ -n "$return_path" ]; then
        which ldc2
    else
        echo ldc2
    fi
elif (which ldc >& /dev/null); then
    if [ -n "$return_path" ]; then
        which ldc
    else
        echo ldc
    fi
else
    echo dmd
fi
