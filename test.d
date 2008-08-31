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

private mixin testInit!() autoInitTst2;

void main(){
    Stdout(arange(3.51))(arange(4.0))(arange(4.49)).newline;
    auto a=reverse(arange(3.5));
    auto b=ones!(double)([4]);
    a.desc(Stdout("a:")).newline;
    a.printData(Stdout).newline;
    b.desc(Stdout("b:")).newline;
    Stdout(dot(a,b)).newline;
    Stdout(rand.toString()).newline;
    SingleRTest.defaultTestController=new TextController(TextController.OnFailure.StopAllTests,
        TextController.PrintLevel.AllShort,Stdout,Stdout,1,true);
    doNArrayTests();
}
