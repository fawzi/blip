module blip.t.core.stacktrace.StackTrace;
public import tango.core.stacktrace.StackTrace;

void printTrace(void delegate(char[]) sink,char[] msg){
    auto tInfo=basicTracer();
    sink("=======\n");
    sink(msg);
    sink("\n");
    tInfo.writeOut(sink);
    sink("=======\n");
}
