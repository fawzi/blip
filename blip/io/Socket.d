/// socket implementation, non buffered, probably you want to wrap them
/// into a buffered stream
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
module blip.io.Socket;
import blip.io.BasicIO;
import blip.io.BasicStreams;
import blip.container.GrowableArray;
import blip.container.Pool;
import blip.container.Cache;
import blip.stdc.socket;
import blip.stdc.string: memset,strlen,memcpy;
import blip.stdc.errno;
import blip.util.TangoLog;
import blip.io.EventWatcher;
import blip.serialization.Serialization;
import gobo.ev.DLibev;
import gobo.ev.EventHandler;
import gobo.ev.Libev;
import tango.stdc.posix.fcntl;
import blip.parallel.smp.WorkManager;
import blip.parallel.smp.BasicTasks;
import blip.sync.Atomic;
import blip.core.sync.Semaphore;

struct TargetHost{
    char[] host;
    char[] port;
    
    static TargetHost opCall(char[] host,char[] port){
        TargetHost res;
        res.host=host;
        res.port=port;
        return res;
    }
    equals_t opEquals(TargetHost p2){
        return host==p2.host && port==p2.port;
    }
    int opCmp(TargetHost p){
        int c=cmp(host,p.host);
        return ((c==0)?cmp(port,p.port):c);
    }
    mixin(serializeSome("blip.TargetHost","host|port"));
    mixin printOut!();
}

/// basically a wrapper around a socket just to group some functions...
/// being a struct it is not possible to synchronize on this, but I realized that I did not need it
struct BasicSocket{
    socket_t sock=socket_t.init;
    enum{ eagerTries=2 }
    
    static BasicSocket opCall(socket_t s){
        BasicSocket res;
        res.sock=s;
        return res;
    }
    
    static BasicSocket opCall(char[]address,char[]service){
        BasicSocket res;
        int err;
        char buf[256];
        char * nodeName,serviceName;
        sockaddr addrName;
        addrinfo hints;
        addrinfo* addressInfo,addrAtt;

        res.sock=-1;
        auto a1=lGrowableArray(buf,0);
        dumper(&a1)(address)("\0")(service)("\0");
        auto addr0=a1.data();
        nodeName=a1.ptr;
        serviceName=a1.ptr+address.length+1;

        memset(&hints, 0, hints.sizeof);
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        err=getaddrinfo(nodeName,serviceName,&hints,&addressInfo);
        if (err!=0){
            char *errStr= gai_strerror(err);
            throw new BIOException("getaddrinfo error:"~errStr[0..strlen(errStr)],__FILE__,__LINE__);
        }

        socket_t s=-1;
        for (addrAtt=addressInfo;addrAtt;addrAtt.ai_next){
            s = socket(addrAtt.ai_family, addrAtt.ai_socktype, addrAtt.ai_protocol);
            if (s<0) continue;
            if (connect(s, addrAtt.ai_addr, addrAtt.ai_addrlen) != 0) {
                shutdown(s,SHUT_RDWR);
                s = -1;
                continue;
            }
            break;
        }
        freeaddrinfo(addressInfo);
        if (s<0){
            throw new BIOException("could not connect to "~address~" "~service,__FILE__,__LINE__);
        }
        res.sock=s;
        // set non blocking
        int oldMode;
        if ((oldMode = fcntl(res.sock, F_GETFL, 0)) != -1){
            fcntl(res.sock, F_SETFL, oldMode | O_NONBLOCK);
        }
        // receive OutOfBand data inline
        int i=1;
        setsockopt(res.sock,SOL_SOCKET,SO_OOBINLINE,&i,4); // ignore failures...
        return res;
    }
    
    static BasicSocket opCall(TargetHost t){
        return opCall(t.host,t.port);
    }
    /// writes at least one byte (unless src.length==0), but possibly less than src.length
    final size_t writeSome(void[] src){
        while(true){
            ptrdiff_t wNow;
            for (int itry=0;itry<eagerTries;++itry){
                wNow=send(sock,src.ptr,src.length,0);
                if (wNow<0){
                    if (wNow!=-1 || errno()!=EWOULDBLOCK){
                        char[] buf=new char[](256);
                        auto msg=strerror_d(errno(), buf);
                        if (msg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeData(),__FILE__,__LINE__);
                        }
                        throw new BIOException(buf[0..strlen(buf.ptr)],__FILE__,__LINE__);
                    }
                } else if (wNow>0 || src.length==0){
                    return wNow;
                }
                if (!Task.yield()) break;
            }
            if (wNow<0){
                auto tAtt=taskAtt.val;
                // implement blocking for non present or non yieldable tasks? it might be dangerous (deadlocks)
                tAtt.delay(delegate void(){// add a timeout???
                    defaultWatcher.addWatcher(GenericWatcher.ioCreate(cast(int)sock,EV_WRITE,EventHandler(tAtt)));
                });
                wNow=0;
            }
        }
    }
    
    final void writeExact(void[] src){
        size_t written=0;
        while(written<src.length){
            ptrdiff_t wNow;
            for (int itry=0;itry<eagerTries;++itry){
                wNow=send(sock,src.ptr+written,src.length-written,0);
                if (wNow<0){
                    if (wNow!=-1 || errno()!=EWOULDBLOCK){
                        char[] buf=new char[](256);
                        auto msg=strerror_d(errno(), buf);
                        if (msg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeData(),__FILE__,__LINE__);
                        }
                        throw new BIOException(buf[0..strlen(buf.ptr)],__FILE__,__LINE__);
                    }
                } else {
                    break;
                }
                if (!Task.yield()) break;
            }
            if (wNow<0){
                auto tAtt=taskAtt.val;
                // implement blocking for non present or non yieldable tasks? it might be dangeroues (deadlocks)
                tAtt.delay(delegate void(){// add a timeout???
                    defaultWatcher.addWatcher(GenericWatcher.ioCreate(cast(int)sock,EV_WRITE,EventHandler(tAtt)));
                });
                wNow=0;
            }
            written+=wNow;
        }
    }
    
    final size_t rawReadInto(void[] dst){
        ptrdiff_t res;
        while(true){
            for (int itry=0;itry<eagerTries;++itry){
                res=cast(ptrdiff_t)recv(sock,dst.ptr,dst.length,0);
                if (res==0) {
                    if (dst.length!=0) return Eof;
                    return 0;
                }
                if (res<0){
                    if (res!=-1 || errno()!=EAGAIN){
                        char[] buf=new char[](256);
                        auto errMsg=strerror_d(errno,buf);
                        if (errMsg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeData(),__FILE__,__LINE__);
                        }
                        throw new BIOException(errMsg,__FILE__,__LINE__);
                    }
                } else {
                    return res;
                }
                if (!Task.yield()) break;
            }
            if (res<0){
                auto tAtt=taskAtt.val;
                // implement blocking for non present or non yieldable tasks? it might be dangeroues (deadlocks)
                tAtt.delay(delegate void(){// add a timeout???
                    defaultWatcher.addWatcher(GenericWatcher.ioCreate(cast(int)sock,EV_READ,EventHandler(tAtt)));
                });
                res=0;
            }
        }
    }
    
    final void flush(){
    }
    
    void shutdownInput(){
        shutdown(sock,SHUT_RD);
    }

    void close(){
        shutdown(sock,SHUT_WR);
    }
    
    void desc(CharSink s){
        dumper(s)("socket@")(sock);
    }
}

class BIONoBindException:BIOException{
    this(char[] msg,char[] file,long line,Exception next=null){
        super(msg,file,line,next);
    }
}

/// a server that listens on one port
class SocketServer{
    char[]serviceName;
    size_t pos;
    socket_t[] socks;
    int[] sockfamile;
    fd_set selectSet;
    socket_t maxDesc;
    GenericWatcher[] watchers;
    size_t pendingTasks;
    size_t maxPendingTasks=size_t.max;
    CharSink log;
    
    static struct Handler{
        BasicSocket sock;
        sockaddr addrOther;
        socklen_t addrLen;
        SocketServer server;
        PoolI!(Handler*) pool;

        void doAction(){
            server.handler(*this);
            if (atomicAdd(server.pendingTasks,-1)==0)
                throw new Exception("error in pending tasks",__FILE__,__LINE__);
        }
        void giveBack(){
            if (pool!is null){
                pool.giveBack(this);
            } else {
                //tryDeleteT(this);
            }
        }
        TargetHost otherHost(char[] buf){
            TargetHost res;
            size_t lPort=buf.length/4;
            auto toC=buf.length-lPort;
            char[]addrStr=buf[0..toC];
            char[]serviceStr=buf[toC..$];
            if (getnameinfo(&addrOther,addrLen, addrStr.ptr, addrStr.length, serviceStr.ptr,serviceStr.length, 0)==0)
            {
                buf[$-1]=0;
                res.host=addrStr[0..strlen(addrStr.ptr)];
                res.port=serviceStr[0..strlen(serviceStr.ptr)];
            }
            return res;
        }
        TargetHost otherHost(){
            char[512] buf;
            auto res=otherHost(buf);
            res.host=res.host.dup;
            res.port=res.port.dup;
            return res;
        }
        static PoolI!(Handler*)gPool;
        static this(){
            gPool=cachedPool(function Handler*(PoolI!(Handler*)p){
                auto res=new Handler;
                res.pool=p;
                return res;
            });
        }
    }
    void delegate (ref Handler) handler;
    
    this(char[]serviceName,void delegate(ref Handler)handler,CharSink log){
        this.serviceName=serviceName;
        this.handler=handler;
        this.log=log;
    }
    void start(){
        addrinfo hints;
        addrinfo *res, res0;
        int isock, err;
        char nullTermAddress[80];
        memset(&hints,0,hints.sizeof);
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_flags = AI_PASSIVE;
        char[128] buf;
        auto arr=lGrowableArray(buf,0);
        arr(serviceName);
        arr('\0');
        auto serviceZ=arr.data();
        err=getaddrinfo(null,serviceZ.ptr,&hints,&res0);
        if (err){
            char *str=gai_strerror(err);
            if (str is null || strlen(str)==0){
                arr.clearData();
                arr("getaddrinfo error:");
                writeOut(&arr.appendArr,err);
                throw new BIOException(arr.takeData(),__FILE__,__LINE__);
            } else {
                throw new BIOException(str[0..strlen(str)],__FILE__,__LINE__);
            } 
        }
        for (res=res0;res;res=res.ai_next){
            //printf("will create socket(%d,%d,%d)\n",res.ai_family,res.ai_socktype,res.ai_protocol);
            socket_t s=socket(res.ai_family,res.ai_socktype,res.ai_protocol);
            if (s<0) continue;
            if (bind(s,res.ai_addr,res.ai_addrlen)!=0){
                close(s);
                s=-1;
                continue;
            }
            listen(s,5);
            // set non blocking
            int oldMode;
            if ((oldMode = fcntl(s, F_GETFL, 0)) != -1){
                fcntl(s, F_SETFL, oldMode | O_NONBLOCK);
            }
            // receive OutOfBand data inline (useful for listening socket?)
            int i=1;
            setsockopt(s,SOL_SOCKET,SO_OOBINLINE,&i,4); // ignore failures...
            socks~=s;
            sockfamile~= res . ai_family;
            watchers~=GenericWatcher.ioCreate(s,EV_READ,EventHandler(&this.callback));
        }
        freeaddrinfo(res0);
        if (socks.length==0){
            throw new BIONoBindException("no bind sucessful for "~serviceName,__FILE__,__LINE__);
        }
        defaultWatcher.watchersToAdd.append(watchers);
        defaultWatcher.notifyAdd();
    }

    bool isStarted(){
        return socks.length!=0;
    }
    
    void callback(ev_loop_t*loop,GenericWatcher w,EventHandler* h){
        version(TrackSocketServer){
            // this is in a special version, because without it one can (in the normal case) accept a socket
            // without any logging
            sinkTogether(log,delegate void(CharSink sink){
                auto s=dumper(sink);
                s("server ")(serviceName)(" received request\n");
            });
        }
        auto sock=cast(socket_t)(w.ptr!(ev_io)().fd);
        sockaddr address;
        socklen_t addrLen=cast(socklen_t)address.sizeof;
        auto newSock=blip.stdc.socket.accept(sock,&address,&addrLen);
        if (newSock<=0){ // ignore lost connections? would be safer but in development it is probably better to crash...
            char[256] buf;
            auto errMsg=strerror_d(errno,buf);
            sinkTogether(log,delegate void(CharSink sink){
                auto s=dumper(sink);
                s("error accepting socket in ")(serviceName)(":")(errMsg);
                if (errMsg.length==0){
                    s(errno);
                }
                s("\n");
            });
        }
        if (pendingTasks>= maxPendingTasks){
            sinkTogether(log,delegate void(CharSink sink){
                auto s=dumper(sink);
                s("too many pending connections, dropping connection immeditely on ")(serviceName)("\n");
            });
            BasicSocket(newSock).close();
            return;
        }
        atomicAdd(pendingTasks,1);
        auto hh=Handler.gPool.getObj;
        hh.sock=BasicSocket(newSock);
        hh.server=this;
        hh.addrOther=address;
        hh.addrLen=addrLen;
        Task("acceptedSocket",&hh.doAction).appendOnFinish(&hh.giveBack).autorelease.submit(defaultTask);
    }
    /// stops the server
    void stop(){
        if (!isStarted) return;
        auto tAtt=taskAtt.val;
        Semaphore sem;
        void stopWatchers(){
            foreach (w;watchers){
                w.stop(defaultWatcher.loop);
            }
            watchers=[];
            foreach (s;socks){
                close(s);
            }
            socks=[];
            if (sem){
                sem.notify();
            } else {
                tAtt.resubmitDelayed(tAtt.delayLevel-1);
            }
        }
        if (tAtt!is null && tAtt.mightYield()){
            tAtt.delay({
                defaultWatcher.addAction(&stopWatchers);
            });
        } else {
            sem=new Semaphore();
            defaultWatcher.addAction(&stopWatchers);
            sem.wait();
        }
    }
}
