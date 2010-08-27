/// a very simple echo server
/// to perform timings compile the NoLog version (logginh )
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

class ConnectionHandler{
    SocketServer serv;
    int status=0;
    this(){}
    void handleConnection(ref SocketServer.Handler h){
        auto s=h.sock;
        version(NoLog){} else {
            sinkTogether(sout,delegate void(CharSink sink){
                dumper(sink)("received connection ")(s.sock)(" from ")(h.otherHost)("\n");
            });
        }
        try{
            char[256] buf;
            while(true){
                auto read=s.rawReadInto(buf);
                if (read>=5 && buf[0..5]=="close"){
                    version(NoLog){} else {
                        sout("detected close, closing connection...\n");
                    }
                    s.close();
                    s.shutdownInput();
                    break;
                } else if (read>=4 && buf[0..4]=="stop"){
                    sout("detected stop, stopping server...\n");
                    bool doStop=true; // a bit of overkill :)
                    synchronized(this){
                        if (status==0){
                            status=1;
                        }
                        doStop=true;
                    }
                    if (doStop){
                        serv.stop();
                        defaultWatcher.stopLoop();
                    }
                }
                if (read==Eof) break;
                version(NoLog){} else {
                    sinkTogether(sout,delegate void(CharSink sink){
                        dumper(sink)("Connection")(cast(int)s.sock)(" received '")(buf[0..read])("'\n");
                    });
                }
                s.writeExact(buf[0..read]);
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
        }
    }
}
void main()
{
    auto c=new ConnectionHandler();
    auto port="50000";
    auto serv=new SocketServer(port,&c.handleConnection,sout.call);
    c.serv=serv;
    sinkTogether(sout,delegate void(CharSink s){
        dumper(s)("starting server on port ")(port)("\n");
    });
    serv.start();
    defaultWatcher.moveLoopHere();
    sout("main thread finished...\n");
}