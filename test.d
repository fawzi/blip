/*******************************************************************************
    module that creates a test executable.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module test;
import frm.narray.BasicTypes;
import tango.io.Stdout;
import frm.rtest.RTest;
import frm.narray.NArray;
import frm.narray.Test;
import frm.random.Random: rand;
import frm.narray.Convolve;

private mixin testInit!() autoInitTst2;

void main(){
    version(NoTests){}
    else {
        // change this to true to track bugs that crash or stop the program without throwing an exception
        bool trace=false;
        Stdout(rand.toString()).newline;
        SingleRTest.defaultTestController=new TextController(//TextController.OnFailure.StopAllTests,
            TextController.OnFailure.StopTest,
            TextController.PrintLevel.AllShort,Stdout,Stdout,1,trace);
        doNArrayTests(10);
    }
}
