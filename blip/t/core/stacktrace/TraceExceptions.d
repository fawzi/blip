module blip.t.core.stacktrace.TraceExceptions;
version(NewTango){
  public import tango.core.tools.TraceExceptions;
} else {
  public import tango.core.stacktrace.TraceExceptions;
}