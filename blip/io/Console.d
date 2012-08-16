/// sinks to Stdout
/// author: fawzi
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.io.Console;
import blip.io.BasicIO;
import blip.io.BasicStreams;
import tango.io.Console;
import blip.io.StreamConverters;
import blip.Comp;

/// a threadsafe sink to Stdout
__gshared Dumper!(void delegate(cstring)) sout;
/// non threadsafe sink to Stdout
__gshared Dumper!(void delegate(cstring)) soutUnsafe;
/// sink to Stderr
__gshared Dumper!(void delegate(cstring)) serr;
/// stdout stream
__gshared OutStreamI soutStream;
/// stderr stream
__gshared OutStreamI serrStream;
/// in a parallel setting this is a log local to the current process
__gshared Dumper!(void delegate(cstring)) localLog;
/// in a parallel setting this log is active only in the master process
__gshared Dumper!(void delegate(cstring)) globalLog;
/// true is the global log is active
__gshared bool hasGlobalLog;

shared static this(){
    auto stdOut=new StreamStrWriter!(char)(Cout.output);
    auto stdErr=new StreamStrWriter!(char)(Cerr.output);
    soutUnsafe=dumper(&stdOut.writeStrFlushNl);
    soutStream=new BasicStrStream!()(&stdOut.desc,&stdOut.writeStrFlushNl,&stdOut.flush);
    sout=dumper(&stdOut.writeStrSyncFlushNl);
    serr=dumper(&stdErr.writeStrFlushNl);
    serrStream=new BasicStrStream!()(&stdErr.desc,&stdErr.writeStrFlushNl,&stdErr.flush);
    localLog=sout;
    globalLog=sout;
    hasGlobalLog=true;
}

