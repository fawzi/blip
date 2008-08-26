/*******************************************************************************
    module that creates a test executable.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module test;
import frm.rtest.RTest;
import tango.io.Stdout;
import frm.narray.NArray;
import frm.narray.Test;
import frm.random.Random: rand;

private mixin testInit!() autoInitTst2;

void main(){
    Stdout(rand.toString()).newline;
    SingleRTest.defaultTestController=new TextController(TextController.OnFailure.StopAllTests,
        TextController.PrintLevel.AllShort,Stdout,Stdout,1,true);
    doNArrayTests();
}
