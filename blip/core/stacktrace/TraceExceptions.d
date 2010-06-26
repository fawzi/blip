/// include this module to get the stacktrace in the exceptions
///
/// wrapping of a tango module
module blip.core.stacktrace.TraceExceptions;
version(NewTango){
  public import tango.core.tools.TraceExceptions;
} else {
  public import tango.core.stacktrace.TraceExceptions;
}