/*******************************************************************************
    module that creates a test executable.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module test;
import blip.narray.BasicTypes;
import tango.io.Stdout;
import blip.rtest.RTest;
import blip.narray.NArray;
import blip.narray.Test;
import blip.random.Random: rand;
import blip.narray.Convolve;
import blip.TemplateFu;
import blip.parallel.WorkManager;
import tango.util.log.Config;

private mixin testInit!() autoInitTst2;

void main(char[][] args){
    debug(UnitTest){
        Stdout(rand.toString()).newline;
        doNArrayFixTests();
        mainTestFun(args,rtestNArray());
    } else {
        Stdout("You need -debug=UnitTest to perform the tests").newline;
    }
}
