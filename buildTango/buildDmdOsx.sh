#!/bin/bash
TANGO_HOME=../../tango
if [ $# -gt 0 ]; then
    TANGO_HOME=$1
fi
pushd $TANGO_HOME
./build/bin/osx32/bob -r=dmd -c=dmd -p=osx -l=libtango-base-dmd -o="-O -release -inline -version=SuspendOneAtTime"  .
./build/bin/osx32/bob -u -c=dmd -p=osx -l=libtango-user-dmd -o="-g -O -release -inline -version=SuspendOneAtTime"  .
./build/bin/osx32/bob -u -c=dmd -p=osx -l=libtango-user-dmd-dbg -o="-g -O -inline"  .
./build/bin/osx32/bob -u -c=dmd -p=osx -l=libtango-user-dmd-tst -o="-d -version=UnitTest -debug=UnitTest -unittest -g -debug -L-ltango-dbg"  .
rm *.o
dirDmd="`which dmd`"
dirDmd=`dirname "$dirDmd"`
mv libtango-base-dmd.a libtango-user-dmd*.a "$dirDmd/../lib"
echo built and installed libs
popd
echo creating regtest...
rm runUnittests_dmd
dmd -d -version=UnitTest -debug=UnitTest -unittest -g -debug -L-ltango-user-dmd-tst -L-lz -L-lbz2 runUnittests_dmd.d
rm *.o
./runUnittests_dmd
