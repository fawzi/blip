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
import frm.narray.Test: doNArrayTests;
import frm.Stringify;
import tango.math.Math: abs;

void main(){
    
    SingleRTest.defaultTestController=new TextController(TextController.OnFailure.StopAllTests,
        TextController.PrintLevel.AllShort);
    
    doNArrayTests();
}
