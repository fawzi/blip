/// include this module to get the stacktrace in the exceptions
///
/// wrapping of a tango module
module blip.core.stacktrace.TraceExceptions;
import tango.core.Version;

static if (Tango.Major==1){
  public import tango.core.tools.TraceExceptions;
} else {
  public import tango.core.stacktrace.TraceExceptions;
}