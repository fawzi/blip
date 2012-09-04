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
import blip.Comp;

void printTrace(scope void delegate(in cstring) sink,in cstring msg){
    auto tInfo=basicTracer();
    sink("=======\n");
    sink(msg);
    sink("\n");
    sink(tInfo.toString());
    sink("=======\n");
}
