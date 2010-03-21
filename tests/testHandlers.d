module testHandlers;
import blip.serialization.Handlers;
import blip.container.GrowableArray;
import blip.io.Console;
import blip.io.BasicIO;

void main(){
    char[14] buf;
    auto arr=new GrowableArray!(char)(buf,0);
    auto f=new FormattedWriteHandlers!()(&arr.appendArr);
    int i=10;
    char[] s="bla";
    f(i);
    f(s);
    f(cast(void[])"bla2");
    sout(cast(char[])arr.takeData)("\n");
    soutStream.flush;
    ssout(outWriter("sep\n"));
    auto arr2=new GrowableArray!(ubyte)();
    auto f2=new BinaryWriteHandlers!()(&arr2.appendVoid);
    f2(i);
    f2(s);
    f2(cast(void[])"bla2");
    writeOut(sout,arr2.takeData,"x");
    soutStream.flush;
}