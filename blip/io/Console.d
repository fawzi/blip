/// sinks to Stdout
/// author: fawzi
module blip.io.Console;
import blip.io.BasicIO;
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

static this(){
    auto stdOut=new StreamStrWriter!(char)(Cout.output);
    auto stdErr=new StreamStrWriter!(char)(Cerr.output);
    soutUnsafe=dumper(&stdOut.writeStrFlushNl);
    soutStream=new BasicStrStream!()(&stdOut.writeStrFlushNl,&stdOut.flush);
    sout=dumper(&stdOut.writeStrSyncFlushNl);
    serr=dumper(&stdErr.writeStrFlushNl);
    serrStream=new BasicStrStream!()(&stdErr.writeStrFlushNl,&stdErr.flush);
}

