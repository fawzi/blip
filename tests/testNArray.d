/*******************************************************************************
    module that creates an executable that extensively tests NArray
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module testNArray;
import blip.test.narray.NArrayTests;
import blip.io.Console;
import blip.io.BasicIO;
import tango.math.random.Random;
import blip.rtest.RTest;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; import blip.util.TraceAll; }

void main(char[][] args){
    sout(rand.toString()); sout("\n");
    mainTestFun(args,narrayTests!()());
}
