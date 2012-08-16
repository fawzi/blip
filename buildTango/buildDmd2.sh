#!/bin/bash
TANGO_HOME=../../Tango-D2
if [ "$1" != "--test-only" ] ; then
if [ $# -gt 0 ]; then
    TANGO_HOME=$1
fi
$TANGO_HOME/build/bin/linux64/bob -v -u -c=dmd -p=linux -l=libtango-user-dmd -o="-O -release"  $TANGO_HOME
$TANGO_HOME/build/bin/linux64/bob -v -u -c=dmd -p=linux -l=libtango-user-dmd-dbg -o="-gc"  $TANGO_HOME
$TANGO_HOME/build/bin/linux64/bob -v -u -c=dmd -p=linux -l=libtango-user-dmd-tst -o="-d -version=UnitTest -debug=UnitTest -unittest -g -L-ltango-dbg"  $TANGO_HOME
rm *.o
dirdmd="`which dmd`"
dirdmd=`dirname "$dirdmd"`
libdir="$dirdmd/../lib"
if [ ! -e "$libdir" ] ; then
    libdir="$dirdmd/../lib64"
fi
mv libtango-user-dmd*.a "$libdir"
echo built and installed libs
fi
echo creating regtest
./gen_runUnittests.sh
dmd -d -version=UnitTest -debug=UnitTest -unittest -gc -I$TANGO_HOME -L-ltango-user-dmd-tst -L-lz -L-lbz2 -L-ldl runUnittests.d
rm *.o
echo running regtest
./runUnittests
