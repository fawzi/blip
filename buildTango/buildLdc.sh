#!/bin/bash
TANGO_HOME=../../tango
if [ $# -gt 0 ]; then
    TANGO_HOME=$1
fi
$TANGO_HOME/build/bin/linux64/bob -r=ldc -c=ldc -p=linux -l=libtango-base-ldc -o="-O3 -release -inline"  $TANGO_HOME
$TANGO_HOME/build/bin/linux64/bob -u -c=ldc -p=linux -l=libtango-user-ldc -o="-g -O3 -release -inline"  $TANGO_HOME
$TANGO_HOME/build/bin/linux64/bob -u -c=ldc -p=linux -l=libtango-user-ldc-dbg -o="-g -O -inline"  $TANGO_HOME
$TANGO_HOME/build/bin/linux64/bob -u -c=ldc -p=linux -l=libtango-user-ldc-tst -o="-d -d-version=UnitTest -d-debug=UnitTest -unittest -g -L-ltango-dbg"  $TANGO_HOME
rm *.o
dirldc="`which ldc`"
dirldc=`dirname "$dirldc"`
mv libtango-base-ldc.a libtango-user-ldc*.a "$dirldc/../lib"
echo built and installed libs
echo creating regtest
ldc -d -d-version=UnitTest -d-debug=UnitTest -unittest -g -L-ltango-user-ldc-tst -L-lev -L-lz -L-lbz2 runUnittests_ldc.d
rm *.o
echo running regtest
./runUnittests_ldc
