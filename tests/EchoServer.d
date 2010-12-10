/// a very simple echo server
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
module EchoServer;
import blip.io.Console;
import blip.container.GrowableArray;
import blip.io.Socket;
import blip.core.sync.Semaphore;
import blip.io.BasicIO;
import blip.bindings.ev.DLibev;
import blip.io.EventWatcher;
import blip.io.BasicStreams;
import blip.io.BufferIn;
import blip.core.Thread; //pippo
import blip.stdc.stdlib:exit;
import blip.util.IgnoreSigpipe;
import blip.Comp;

class ConnectionHandler{
    SocketServer serv;
    int status=0;
    bool cached=true;
    bool timeout=false;
    this(){}
    void handleConnection(ref SocketServer.Handler h){
        auto s=h.sock;
        version(NoLog){} else {
            sinkTogether(sout,delegate void(CharSink sink){
                dumper(sink)("received connection ")(s.sock)(" from ")(h.otherHost)("\n");
            });
        }
        char[256] buf;
        BufferedBinStream outStream;
        BufferIn!(void) readIn;
        try{
            if (cached){
                outStream=new BufferedBinStream(&h.sock.writeExact,2048,&h.sock.flush,&h.sock.close);
                readIn=new BufferIn!(void)(&h.sock.rawReadInto);
            }
            while(true){
                size_t read;
                if (cached){
                    read=readIn.readSome(buf);
                } else {
                    if (timeout){
                        read=s.rawReadIntoTout(buf,sToutWatcher);
                    } else {
                        read=s.rawReadInto(buf);
                    }
                }
                if (read>=5 && buf[0..5]=="close"){
                    version(NoLog){} else {
                        sout("detected close, closing connection...\n");
                    }
                    if (cached){
                        outStream.close();
                        readIn.shutdownInput();
                    } else {
                        s.close();
                        s.shutdownInput();
                    }
                    break;
                } else if (read>=4 && buf[0..4]=="stop"){
                    sout("detected stop, stopping server...\n");
                    bool doStop=false; // a bit of overkill :)
                    synchronized(this){
                        if (status==0){
                            status=1;
                            doStop=true;
                        }
                    }
                    if (doStop){
                        serv.stop();
                        noToutWatcher.stopLoop();
                    }
                }
                if (read==Eof) break;
                version(NoLog){} else {
                    sinkTogether(sout,delegate void(CharSink sink){
                        dumper(sink)("Connection")(cast(int)s.sock)(" received '")(buf[0..read])("'\n");
                    });
                }
                if (cached){
                    outStream.rawWrite(buf[0..read]);
                    outStream.flush();
                } else {
                    s.writeExact(buf[0..read]);
                }
            }
            version(NoLog){} else {
                sinkTogether(sout,delegate void(CharSink sink){
                    dumper(sink)("\nConnection")(cast(int)s.sock)(" closed\n");
                });
            }
        } catch (Exception e){
            version(NoLog){} else {
                sinkTogether(sout,delegate void(CharSink sink){
                    dumper(sink)("Exception in connection")(cast(int)s.sock)(":")(e)("\n");
                });
            }
            if (cached){
                if (outStream) outStream.close();
                if (readIn) readIn.shutdownInput();
            } else {
                s.close();
                s.shutdownInput();
            }
        }
    }
}
void main(string [] argv)
{
    auto c=new ConnectionHandler();
    string port="50000";
    if (argv.length>1){
        port=argv[1];
    }
    if (argv.length>2){
        if (argv[2].length>0 && argv[2][0]!='c'){
            sout("no cache\n");
            c.cached=false;
            if (argv[2].length>0 && argv[2][0]=='t'){
                sout("timeout on read\n");
                c.timeout=true;
            }
        }
    }
    auto serv=new SocketServer(port,&c.handleConnection,sout.call);
    c.serv=serv;
    sinkTogether(sout,delegate void(CharSink s){
        dumper(s)("starting server on port ")(port)("\n");
    });
    serv.start();
    noToutWatcher.moveLoopHere(); // avoids having a thread blocked just waiting...
    sout("main thread finished...\n");
    Thread.sleep(0.1);
    exit(0); // just to be sure (in case there are still listening sockets in other threads)
}
