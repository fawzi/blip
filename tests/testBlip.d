/*******************************************************************************
    module that creates an executable that executes all automatic tests of blip
        author:         Fawzi Mohamed
*******************************************************************************/
module testBlip;
import blip.test.BlipTests;
import blip.io.Console;
import blip.io.BasicIO;
import tango.math.random.Random;
import blip.rtest.RTest;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; import blip.util.TraceAll; }

void main(char[][] args){
    sout(rand.toString()); sout("\n");
    mainTestFun(args,blipTests!()());
}
