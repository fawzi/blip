/// a programm stressing an echo server
/// to perform timings compile the NoLog version (logging slows down very much)
///
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
module StressEchoServer;
import blip.io.Console;
import blip.container.GrowableArray;
import blip.io.Socket;
import blip.core.sync.Semaphore;
import blip.io.BasicIO;
import blip.bindings.ev.DLibev;
import blip.io.EventWatcher;
import blip.io.BasicStreams;
import blip.io.BufferIn;
import Integer=tango.text.convert.Integer;
import Float=tango.text.convert.Float;
import blip.rtest.BasicGenerators;
import blip.math.random.Random;
import blip.parallel.smp.WorkManager;
import blip.stdc.stdlib:exit;
//import blip.util.IgnoreSigpipe;
import blip.Comp;

class StressGenerator{
    Random rand;
    BasicSocket connection;
    TargetHost target;
    bool cached;
    uint stressIter;
    double maxWait;
    BufferedBinStream outStream;
    BufferIn!(void) readIn;
    this(TargetHost target,uint stressIter,double maxWait,bool cached=true,Random rand=null){
        this.target=target;
        this.stressIter=stressIter;
        this.maxWait=maxWait;
        this.cached=cached;
        this.rand=rand;
        if (rand is null){
            rand=new Random();
        }
    }
    void makeStress(){
        connection=BasicSocket(target);
        version(NoLog){} else {
            sinkTogether(sout,delegate void(CharSink sink){
                dumper(sink)("created connection ")(connection.sock)(" to ")(target)("\n");
            });
        }
        try{
            char[3000] bufIn;
            char[3000] bufOut;
            if (cached){
                outStream=new BufferedBinStream(&this.connection.desc,&this.connection.writeExact,2048,&this.connection.flush,&this.connection.close);
                readIn=new BufferIn!(void)(&connection.desc,&this.connection.rawReadInto);
            }
            for(uint iter=0;iter<stressIter;++iter){
                size_t toSend=rand.uniformR(bufOut.length);
                bool acceptable;
                mkRandomArray(rand,bufOut[0..toSend],acceptable);
                version(NoLog){} else {
                    sinkTogether(sout,delegate void(CharSink sink){
                        dumper(sink)("Connection")(cast(int)connection.sock)(" sending '")(bufOut[0..toSend])("'\n");
                    });
                }
                if (cached){
                    outStream.rawWrite(bufOut[0..toSend]);
                    outStream.flush();
                } else {
                    connection.writeExact(bufOut[0..toSend]);
                }
                ptrdiff_t read;
                if (cached){
                    readExact(&readIn.readSome,bufIn[0..toSend]);
                } else {
                    connection.rawReadExact(bufIn[0..toSend]);
                }
                if (bufOut[0..toSend]!=bufIn[0..toSend]){
                    throw new Exception("unexpected difference in echo '"~bufOut[0..toSend]~"' vs '"~
                        bufIn[0..toSend]~"'");
                }
                version(NoLog){} else {
                    sinkTogether(sout,delegate void(CharSink sink){
                        dumper(sink)("Connection")(cast(int)connection.sock)(" echoed\n");
                    });
                }
                EventWatcher.sleepTask(rand.uniformR(maxWait));
            }
        } catch (Exception e){
            version(NoLog){} else {
                sinkTogether(sout,delegate void(CharSink sink){
                    dumper(sink)("Exception in connection")(cast(int)connection.sock)(":")(e)("\n");
                });
            }
        }
        try{
            version(NoLog){} else {
                if (cached){
                    outStream.close();
                    readIn.shutdownInput();
                } else {
                    connection.close();
                    connection.shutdownInput();
                }
                sinkTogether(sout,delegate void(CharSink sink){
                    dumper(sink)("\nConnection")(cast(int)connection.sock)(" closed\n");
                });
            }
        } catch (Exception e){
            version(NoLog){} else {
                sinkTogether(sout,delegate void(CharSink sink){
                    dumper(sink)("Exception closing connection")(cast(int)connection.sock)(":")(e)("\n");
                });
            }
        }
    }
}

class StressManager{
    Random rand;
    TargetHost target;
    uint connections=30;
    uint iterations=100;
    double maxWait=0.1;
    bool cached=true;
    this(Random r=null){
        rand=r;
        if (r is null){
            rand=new Random();
        }
    }
    void makeStress(){
        for(uint iConn=0;iConn<connections;++iConn){
            auto sg=new StressGenerator(target,iterations,maxWait,cached,rand.spawn());
            Task("genStress",&sg.makeStress).autorelease.submit();
            EventWatcher.sleepTask(rand.uniformR(maxWait));
        }
    }
}
void main(string [] argv)
{
    if (argv.length<3 ||argv.length>6){
        sout("usage:")(argv[0])(" host port [connections [iterations [maxWait]]]\n");
        exit(1);
    }
    auto target=TargetHost(argv[1],argv[2]);
    auto sm=new StressManager();
    sout("randomSeed: ")(sm.rand.toString())("\n");
    sm.target=target;
    version(NoCache){
        sm.cached=false;
    }
    if (argv.length>3){
        sm.connections=cast(uint)Integer.toLong(argv[3]);
        if (argv.length>4){
            sm.iterations=cast(uint)Integer.toLong(argv[4]);
            if (argv.length>5){
                sm.maxWait=Float.toFloat(argv[5]);
            }
        }
    }
    Task("stress",&sm.makeStress).autorelease.executeNow();
    sout("main thread finished...\n");
    exit(0);
}