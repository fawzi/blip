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
import blip.bindings.ev.DLibev;
import blip.bindings.ev.EventHandler;
import blip.bindings.ev.Libev;
import tango.stdc.posix.fcntl;
import blip.parallel.smp.WorkManager;
import blip.parallel.smp.BasicTasks;
import blip.sync.Atomic;
import blip.core.sync.Semaphore;
import blip.io.Console;
import blip.Comp;

version(linux) {
    enum { IPV6_V6ONLY=26 }
}
version(solarix) {
    enum { IPV6_V6ONLY=27 }
}

struct TargetHost{
    string host;
    string port;
    
    static TargetHost opCall(string host,string port){
        TargetHost res;
        res.host=host;
        res.port=port;
        return res;
    }
    equals_t opEquals(TargetHost p2){
        return host==p2.host && port==p2.port;
    }
    int opCmp(TargetHost p){
        int c=((host<p.host)?-1:((host==p.host)?0:1));
        return ((c==0)?((port<p.port)?-1:((port==p.port)?0:1)):c);
    }
    mixin(serializeSome("blip.TargetHost","a host/post to connect to or connected to (identifes one end of a tpc socket)",
        "host|port"));
    mixin printOut!();
    TargetHost dup(){
        TargetHost res;
        res.host=host.idup;
        res.port=port.idup;
        return res;
    }
    hash_t toHash(){
        return rt_hash_combine(getHash(host),getHash(port));
    }
}

/// basically a wrapper around a socket just to group some functions...
/// being a struct it is not possible to synchronize on this, but I realized that I did not need it
struct BasicSocket{
    socket_t sock=socket_tInit;
    enum{ eagerTries=2 }
    
    static BasicSocket opCall(socket_t s){
        BasicSocket res;
        res.sock=s;
        // set non blocking
        int oldMode;
        if ((oldMode = fcntl(res.sock, F_GETFL, 0)) == -1 ||
            fcntl(res.sock, F_SETFL, oldMode | O_NONBLOCK)==-1){
            throw new BIOException(collectIAppender(delegate void(scope CharSink s){
                        dumper(s)("could not set non blocking mode for socket ")(s);
                    }),__FILE__,__LINE__);
        }
        // receive OutOfBand data inline
        int i=1;
        setsockopt(res.sock,SOL_SOCKET,SO_OOBINLINE,&i,4); // ignore failures...
        return res;
    }
    /// creates a socket
    static BasicSocket opCall(string address,string service){
        BasicSocket res;
        int err;
        char[256] buf;
        char * nodeName,serviceName;
        sockaddr_storage addrName;
        addrinfo hints;
        addrinfo* addressInfo,addrAtt;

        res.sock=-1;
        auto a1=lGrowableArray(buf,0,GASharing.GlobalNoFree);
	scope(exit){
	    a1.deallocData();
	}
        dumper(&a1.appendArr)(address)("\0")(service)("\0");
        auto addr0=a1.data();
        nodeName=a1.ptr;
        serviceName=a1.ptr+address.length+1;

        memset(&hints, 0, hints.sizeof);
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        err=getaddrinfo(nodeName,serviceName,&hints,&addressInfo);
        if (err!=0){
            char *errStr= gai_strerror(err);
	    char[256] errBuf;
	    auto errA=lGrowableArray(errBuf,0);
	    dumper(&errA.appendArr)("getaddrinfo error:")(errStr[0..strlen(errStr)])
		(" with address:")(address)(" and service:")(service);
            throw new BIOException(errA.takeIData(),__FILE__,__LINE__);
        }

        socket_t s=-1;
        for (addrAtt=addressInfo;addrAtt;addrAtt=addrAtt.ai_next){
            s = socket(addrAtt.ai_family, addrAtt.ai_socktype, addrAtt.ai_protocol);
            if (s<0) continue;
            version(TrackSocketServer){
                sinkTogether(serr,delegate void(scope CharSink s){
                    dumper(s)("trying to connect to ");
                    char[256] buf;
                    auto res=inet_ntop(addrAtt.ai_family, addrAtt.ai_addr,
                           buf.ptr,buf.length);
                    buf[$-1]=0;
                    s(res[0..strlen(res)]);
                    s("\n");
                });
            }
            if (connect(s, addrAtt.ai_addr, addrAtt.ai_addrlen) != 0) {
                version(TrackSocketServer){
                    sinkTogether(serr,delegate void(scope CharSink s){
                        dumper(s)("connection to ");
                        char[256] buf;
                        auto res=inet_ntop(addrAtt.ai_family, addrAtt.ai_addr,
                               buf.ptr,buf.length);
                        buf[$-1]=0;
                        s(res[0..strlen(res)]);
                        s(" failed\n");
                    });
                }
                shutdown(s,SHUT_RDWR);
                s = -1;
                continue;
            }
            version(TrackSocketServer){
                sinkTogether(serr,delegate void(scope CharSink s){
                    dumper(s)("connection to ");
                    char[256] buf;
                    auto res=inet_ntop(addrAtt.ai_family, addrAtt.ai_addr,
                           buf.ptr,buf.length);
                    buf[$-1]=0;
                    s(res[0..strlen(res)]);
                    s(" success\n");
                });
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
        if ((oldMode = fcntl(res.sock, F_GETFL, 0)) == -1 ||
            fcntl(res.sock, F_SETFL, oldMode | O_NONBLOCK)==-1){
            throw new BIOException("could not set non blocking mode "~address~" "~service,__FILE__,__LINE__);
        }
        // receive OutOfBand data inline
        int i=1;
        setsockopt(res.sock,SOL_SOCKET,SO_OOBINLINE,&i,4); // ignore failures...
        return res;
    }
    /// sets the value of noDelay, if you do your own buffering using TCP setting it to noDelay gives smaller latency
    void noDelay(bool val){
        int i=(val?1:0);
        if (setsockopt(sock,SOL_TCP,TCP_NODELAY,&i,4)!=0){
            throw new Exception(collectIAppender(delegate void(scope CharSink s){
                dumper(s)("setsockopt SOL_TCP,TCP_NODELAY failed on socket ")(sock);
                char[256] buf;
                s(strerror_d(errno(),buf));
            }),__FILE__,__LINE__);
        }
    }
    /// returns the value of noDelay, if you do your own buffering using TCP setting it to noDelay gives smaller latency
    bool noDelay(){
        int i;
        socklen_t len=4;
        if (getsockopt(sock,SOL_TCP,TCP_NODELAY,&i,&len)){
            throw new Exception(collectIAppender(delegate void(scope CharSink s){
                dumper(s)("getsockopt SOL_TCP,TCP_NODELAY failed on socket ")(sock);
                char[256] buf;
                s(strerror_d(errno(),buf));
            }),__FILE__,__LINE__);
        }
        assert(len==4,"unexpected return length in getsockopt");
        return i!=0;
    }
    /// sets keepalive
    void keepalive(bool k){
        int i=cast(int)k;
        if (setsockopt(sock,SOL_SOCKET,SO_KEEPALIVE,&i,4)!=0){
            throw new Exception(collectIAppender(delegate void(scope CharSink s){
                dumper(s)("setsockopt SOL_SOCKET,SO_KEEPALIVE failed on socket ")(sock);
                char[256] buf;
                s(strerror_d(errno(),buf));
            }),__FILE__,__LINE__);
        }
    }
    bool keepalive(){
        int i;
        socklen_t len=4;
        if (getsockopt(sock,SOL_SOCKET,SO_KEEPALIVE,&i,&len)){
            throw new Exception(collectIAppender(delegate void(scope CharSink s){
                dumper(s)("getsockopt SOL_SOCKET,SO_KEEPALIVE failed on socket ")(sock);
                char[256] buf;
                if (strerror_d(errno(),buf)){
                    s(",");
                    buf[$-1]=0;
                    s(buf[0..strlen(buf.ptr)]);
                }
            }),__FILE__,__LINE__);
        }
        assert(len==4,"unexpected return length in getsockopt");
        return i!=0;
    }
    
    static BasicSocket opCall(TargetHost t){
        return opCall(t.host,t.port);
    }
    /// writes at least one byte (unless src.length==0), but possibly less than src.length
    final size_t writeSomeTout(in void[] src,LoopHandlerI loop){
        while(true){
            ptrdiff_t wNow;
            for (int itry=0;itry<eagerTries;++itry){
                wNow=send(sock,src.ptr,src.length,0);
                if (wNow<0){
                    if (errno()==EINTR) continue;
                    if (wNow!=-1 || errno()!=EWOULDBLOCK){
                        char[] buf=new char[](256);
                        auto msg=strerror_d(errno(), buf);
                        if (msg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeIData(),__FILE__,__LINE__);
                        }
                        throw new BIOException(buf[0..strlen(buf.ptr)],__FILE__,__LINE__);
                    }
                } else if (wNow>0 || src.length==0){
                    version(SocketEcho){
                        sinkTogether(sout,delegate void(scope CharSink s){
                            dumper(s)("socket ")(sock)(" writing '")(src[0..wNow])("'\n");
                        });
                    }
                    return wNow;
                }
                if (!Task.yield()) break;
            }
            if (wNow<0){
                auto tAtt=taskAtt.val;
                auto watcher=GenericWatcher.ioCreate(cast(int)sock,EV_WRITE);
                // implement blocking for non present or non yieldable tasks? it might be dangerous (deadlocks)
                if (!loop.waitForEvent(watcher)){
                    throw new Exception("timeout while writing",__FILE__,__LINE__);
                }
                wNow=0;
            }
        }
    }
    /// ditto
    final size_t writeSome(in void[] src){
        return writeSomeTout(src,noToutWatcher);
    }
    
    final void writeExactTout(in void[] src,LoopHandlerI loop){
        size_t written=0;
        while(written<src.length){
            ptrdiff_t wNow;
            for (int itry=0;itry<eagerTries;++itry){
                wNow=send(sock,src.ptr+written,src.length-written,0);
                if (wNow<0){
                    if (errno()==EINTR) continue;
                    if (wNow!=-1 || errno()!=EWOULDBLOCK){
                        char[] buf=new char[](256);
                        auto msg=strerror_d(errno(), buf);
                        if (msg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeIData(),__FILE__,__LINE__);
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
                auto watcher=GenericWatcher.ioCreate(cast(int)sock,EV_WRITE);
                // implement blocking for non present or non yieldable tasks? it might be dangeroues (deadlocks)
                if (!loop.waitForEvent(watcher)){
                    throw new Exception("timeout while writing",__FILE__,__LINE__);
                }
                wNow=0;
            }
            version(SocketEcho){
                sinkTogether(sout,delegate void(scope CharSink s){
                    dumper(s)("socket ")(sock)(" writing '")(src[0..wNow])("'\n");
                });
            }
            written+=wNow;
        }
    }
    final void writeExact(in void[] src){
        writeExactTout(src,noToutWatcher);
    }
    
    final size_t rawReadIntoTout(void[] dst,LoopHandlerI loop){
        assert(loop!is null);
        ptrdiff_t res;
        while(true){
            for (int itry=0;itry<eagerTries;++itry){
                res=cast(ptrdiff_t)recv(sock,dst.ptr,dst.length,0);
                if (res==0) {
                    if (dst.length!=0) return Eof;
                    return 0;
                }
                if (res<0){
                    if (errno()==EINTR) continue;
                    if (res!=-1 || errno()!=EAGAIN){
                        char[] buf=new char[](256);
                        auto errMsg=strerror_d(errno,buf);
                        if (errMsg.length==0){
                            auto a=lGrowableArray(buf,0);
                            a("IO error:");
                            writeOut(&a.appendArr,errno());
                            throw new BIOException(a.takeIData(),__FILE__,__LINE__);
                        }
                        throw new BIOException(errMsg,__FILE__,__LINE__);
                    }
                } else {
                    version(SocketEcho){
                        sinkTogether(sout,delegate void(scope CharSink s){
                            dumper(s)("socket ")(sock)(" got '")(dst[0..res])("'\n");
                        });
                    }
                    return res;
                }
                if (!Task.yield()) break;
            }
            if (res<0){
                auto tAtt=taskAtt.val;
                auto watcher=GenericWatcher.ioCreate(cast(int)sock,EV_READ);
                // implement blocking for non present or non yieldable tasks? it might be dangeroues (deadlocks)
                version(LogReadWaits){
                    sinkTogether(sout,delegate void(scope CharSink s){
                        dumper(s)("socket ")(sock)(" start waiting in read with event@")(cast(void*)watcher.ptr_)("\n");
                    });
                }
                if (!loop.waitForEvent(watcher)){
                    throw new Exception("timeout in read",__FILE__,__LINE__);
                }
                res=0;
                version(LogReadWaits){
                    sinkTogether(sout,delegate void(scope CharSink s){
                        dumper(s)("socket ")(sock)(" did waiting in read\n");
                    });
                }
            }
        }
    }
    final size_t rawReadInto(void[] dst){
        return rawReadIntoTout(dst,noToutWatcher);
    }
    
    void rawReadExact(void[] buf){
        readExact(&this.rawReadInto,buf);
    }
    
    final void flush(){
    }
    
    void shutdownInput(){
        version(SocketEcho){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("socket ")(sock)(" shutdownInput\n");
            });
        }
        shutdown(sock,SHUT_RD);
    }

    void close(){
        version(SocketEcho){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("socket ")(sock)(" close\n");
            });
        }
        shutdown(sock,SHUT_WR);
    }
    
    void desc(scope CharSink s){
        dumper(s)("socket@")(sock);
    }
}

class BIONoBindException:BIOException{
    this(string msg,string file,long line,Exception next=null){
        super(msg,file,line,next);
    }
}

/// a server that listens on one port
class SocketServer{
    string serviceName;
    size_t pos;
    socket_t[] socks;
    int[] sockfamile;
    fd_set selectSet;
    socket_t maxDesc;
    GenericWatcher[] watchers;
    size_t pendingTasks;
    size_t maxPendingTasks=size_t.max;
    scope CharSink log;
    bool requireFirst;
    
    static struct Handler{
        BasicSocket sock;
        sockaddr_storage addrOther;
        socklen_t addrLen;
        SocketServer server;
        PoolI!(Handler*) pool;

        void doAction(){
            server.handler(this);
            if (atomicAdd(server.pendingTasks,-1)==0)
                throw new Exception("error in pending tasks",__FILE__,__LINE__);
        }
        void giveBack(){
            if (pool!is null){
                pool.giveBack(&this);
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
            if (getnameinfo(cast(sockaddr*)&addrOther,addrLen, addrStr.ptr, cast(socklen_t)addrStr.length, serviceStr.ptr,cast(socklen_t)serviceStr.length, 0)==0)
            {
                buf[$-1]=0;
                res.host=cast(string)(addrStr[0..strlen(addrStr.ptr)]);
                res.port=cast(string)(serviceStr[0..strlen(serviceStr.ptr)]);
            }
            return res;
        }
        TargetHost otherHost(){
            char[512] buf;
            auto res=otherHost(buf);
            res.host=Idup(res.host);
            res.port=Idup(res.port);
            return res;
        }
        __gshared static PoolI!(Handler*)gPool;
        shared static this(){
            gPool=cachedPool(function Handler*(PoolI!(Handler*)p){
                auto res=new Handler;
                res.pool=p;
                return res;
            });
        }
    }
    void delegate (ref Handler) handler;
    
    this(string serviceName,void delegate(ref Handler)handler,scope CharSink log){
        this.serviceName=serviceName;
        this.handler=handler;
        this.log=log;
    }
    /// starts the server
    ///
    /// it seems that restaring a server might make it bind to only some of the socket/families/interfaces
    /// it should, which might bring *large* slowdowns in creating the connections.
    /// At the moment as long as one socket can be bound, the start is considered a success.
    /// maybe this should be tightened up
    void start(){
        addrinfo hints;
        addrinfo *res, res0;
        int isock, err;
        char nullTermAddress[80];
        memset(&hints,0,addrinfo.sizeof);
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
	    static if (is(typeof(IPV6_V6ONLY))) {
		{
		    static if (!is(typeof(SOL_IPV6))) {
			enum { SOL_IPV6 = IPPROTO_IPV6 }
		    }
		    // avoid skipping IPv6 if IPv4 is bound first on linux
		    int tmp = 1;
		    if (res.ai_family == AF_INET6
			&& setsockopt (s, SOL_IPV6, IPV6_V6ONLY, cast(char *) &tmp,
				       cast(socklen_t) tmp.sizeof) != 0)
			{
			    sinkTogether(log,delegate void(scope CharSink s){
				    char[256] buf;
				    dumper(s)(strerror_d(errno(), buf))
					(", in setsockopt(s, SOL_IPV6, IPV6_V6ONLY,[1],4)\n");
				});
			}
		}
	    }
            version(TrackSocketServer){
                sinkTogether(log,delegate void(scope CharSink s){
                    dumper(s)("trying bind to ");
                    char[256] buf;
                    auto res=inet_ntop(res.ai_family, res.ai_addr,
                           buf.ptr,buf.length);
                    buf[$-1]=0;
                    dumper(s)(res[0..strlen(res)])(" on port ")(serviceName)("\n");
                });
            }
            if (bind(s,res.ai_addr,res.ai_addrlen)!=0){
                sinkTogether(log,delegate void(scope CharSink s){
                    dumper(s)("bind to ");
                    char[256] buf;
                    auto res=inet_ntop(res.ai_family, res.ai_addr,
                           buf.ptr,buf.length);
                    buf[$-1]=0;
                    dumper(s)(res[0..strlen(res)])(" on port ")(serviceName)(" failed\n");
                });
                close(s);
                s=-1;
                continue;
            }
            version(TrackSocketServer){
                sinkTogether(log,delegate void(scope CharSink s){
                    dumper(s)("bind to ");
                    char[256] buf;
                    auto res=inet_ntop(res.ai_family, res.ai_addr,
                           buf.ptr,buf.length);
                    buf[$-1]=0;
                    dumper(s)(res[0..strlen(res)])(" on port ")(serviceName)(" succeded\n");
                });
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
        noToutWatcher.watchersToAdd.append(watchers);
        noToutWatcher.notifyAdd();
    }

    bool isStarted(){
        return socks.length!=0;
    }
    
    void callback(ev_loop_t*loop,GenericWatcher w,EventHandler* h){
        version(TrackSocketServer){
            // this is in a special version, because without it one can (in the normal case) accept a socket
            // without any logging
            sinkTogether(log,delegate void(scope CharSink sink){
                auto s=dumper(sink);
                s("server ")(serviceName)(" received request\n");
            });
        }
        sockaddr_storage addrOther;
        socklen_t addrLen=cast(socklen_t)addrOther.sizeof;
        auto sock=cast(socket_t)(w.ptr!(ev_io)().fd);
        auto newSock=blip.stdc.socket.accept(sock,cast(sockaddr*)&addrOther,&addrLen);
        assert(addrLen<=addrOther.sizeof,"sockaddr overflow");
        if (newSock<=0){ // ignore lost connections? would be safer but in development it is probably better to crash...
            char[256] buf;
            auto errMsg=strerror_d(errno,buf);
            sinkTogether(log,delegate void(scope CharSink sink){
                auto s=dumper(sink);
                s("error accepting socket in ")(serviceName)(":")(errMsg);
                if (errMsg.length==0){
                    s(errno);
                }
                s(", ")(__FILE__)(":")(__LINE__)("\n");
            });
        }
        if (pendingTasks>= maxPendingTasks){
            sinkTogether(log,delegate void(scope CharSink sink){
                auto s=dumper(sink);
                s("too many pending connections, dropping connection immeditely on ")(serviceName)("\n");
            });
            BasicSocket(newSock).close();
            BasicSocket(newSock).shutdownInput();
            return;
        }
        atomicAdd(pendingTasks,1);
        auto hh=Handler.gPool.getObj;
        hh.addrOther=addrOther;
        hh.addrLen=addrLen;
        hh.sock=BasicSocket(newSock);
        hh.server=this;
        Task("acceptedSocket",&hh.doAction).appendOnFinish(&hh.giveBack).autorelease.submit(defaultTask);
    }
    /// stops the server
    void stop(){
        if (!isStarted) return;
        void stopWatchers(){
            foreach (w;watchers){
                w.stop(noToutWatcher.loop);
            }
            watchers=[];
            foreach (s;socks){
                close(s);
            }
            socks=[];
        }
        waitLoopOp(&stopWatchers,&noToutWatcher.addAction);
    }
}
