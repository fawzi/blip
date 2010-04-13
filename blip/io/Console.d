/// sinks to Stdout
/// author: fawzi
module blip.io.Console;
import blip.io.BasicIO;
import blip.io.BasicStreams;
import tango.io.Console;
import blip.io.StreamConverters;

/// a threadsafe sink to Stdout
Dumper!(void delegate(char[])) sout;
/// non threadsafe sink to Stdout
Dumper!(void delegate(char[])) soutUnsafe;
/// sink to Stderr
Dumper!(void delegate(char[])) serr;
/// stdout stream
OutStreamI soutStream;
/// stderr stream
OutStreamI serrStream;
/// in a parallel setting this is a log local to the current process
Dumper!(void delegate(char[])) localLog;
/// in a parallel setting this log is active only in the master process
Dumper!(void delegate(char[])) globalLog;
/// true is the global log is active
bool hasGlobalLog;

static this(){
    auto stdOut=new StreamStrWriter!(char)(Cout.output);
    auto stdErr=new StreamStrWriter!(char)(Cerr.output);
    soutUnsafe=dumper(&stdOut.writeStrFlushNl);
    soutStream=new BasicStrStream!()(&stdOut.writeStrFlushNl,&stdOut.flush);
    sout=dumper(&stdOut.writeStrSyncFlushNl);
    serr=dumper(&stdErr.writeStrFlushNl);
    serrStream=new BasicStrStream!()(&stdErr.writeStrFlushNl,&stdErr.flush);
    localLog=sout;
    globalLog=sout;
    hasGlobalLog=true;
}

