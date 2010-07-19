/// stacktrace
///
/// wrapping of a tango module
module blip.core.stacktrace.StackTrace;
import tango.core.Version;
static if (Tango.Major==1) {
    public import tango.core.tools.StackTrace;
} else {
    public import tango.core.stacktrace.StackTrace;
}

void printTrace(void delegate(char[]) sink,char[] msg){
    auto tInfo=basicTracer();
    sink("=======\n");
    sink(msg);
    sink("\n");
    tInfo.writeOut(sink);
    sink("=======\n");
}
