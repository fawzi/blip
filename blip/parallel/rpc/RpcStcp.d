/// rpc using a simple tcp based protocol
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
module blip.parallel.rpc.RpcStcp;
import blip.parallel.rpc.RpcBase;
import blip.io.Console;
import blip.serialization.Serialization;
import blip.container.GrowableArray;
import blip.BasicModels;
import blip.util.TangoConvert;
import blip.core.Array;
import blip.util.TangoLog;
import blip.sync.UniqueNumber;
import blip.io.IOArray;
import blip.parallel.smp.WorkManager;
import blip.io.BasicIO;
import blip.io.StreamConverters;
import blip.io.Console;
import blip.io.Socket;
import blip.io.BufferIn;
import blip.io.BasicStreams;
import blip.time.Time;
import blip.time.Clock;
import blip.sync.Atomic;
import blip.stdc.unistd;
import blip.serialization.Serialization;
import blip.container.HashMap;
import blip.math.random.Random;

// to do to support recoverable close:
// + guarantee increasing id in requests
// + keep last id sent out
// + restart requests that will not be answered (sent to an already closed socket)

class StcpConnection{
    enum Status{
        Setup,
        Running,
        Stopping,
        Stopped,
    }
    StcpProtocolHandler protocolHandler;
    BasicSocket sock;
    BufferedBinStream outStream;
    BufferIn!(void) readIn;
    SequentialTask serTask; /// sequential task in which sending should be performed
    TaskI requestsTask; /// reference to the task that is doing the unserialization/handling requests
    Serializer serializer;
    Unserializer unserializer;
    size_t localUsers=1;
    Time lastUse; // valid only if localUsers is 0
    TargetHost targetHost;
    Status status=Status.Setup;
    ubyte[] lastReqId;
    size_t lastReqIdCapacity;
    
    this(StcpProtocolHandler protocolHandler,TargetHost targetHost,BasicSocket sock){
        this.protocolHandler=protocolHandler;
        this.targetHost=targetHost;
        this.sock=sock;
        serTask=new SequentialTask("stcpSerTask",defaultTask,true);
        outStream=new BufferedBinStream(&sock.writeExact,2048,&sock.flush,&sock.close);
        readIn=new BufferIn!(void)(&sock.rawReadInto);
        serializer=new SBinSerializer(outStream.binSink());
        unserializer=new SBinUnserializer(readIn);
        localUsers=1;
    }
    
    this(StcpProtocolHandler protocolHandler,TargetHost targetHost){
        this(protocolHandler,targetHost,BasicSocket(targetHost));
    }
    
    bool tryAddLocalUser(){
        synchronized(this){
            if (localUsers==0) return false;
            ++localUsers;
            return true;
        }
    }

    void addLocalUser(){
        synchronized(this){
            if (atomicAdd(localUsers,1)==0){
                throw new Exception("localUsers was 0 in addLocalUser",__FILE__,__LINE__);
            }
        }
    }
    void rmLocalUser(){
        synchronized(this){
            auto oldL=atomicAdd(localUsers,-1);
            if (oldL==0){
                throw new Exception("localUsers was 0 in rmLocalUser",__FILE__,__LINE__);
            }
            if (oldL==1){
                lastUse=Clock.now;
            }
        }
    }
    
    void sendReply(ubyte[] reqId,void delegate(Serializer) serRes){
        Task("sendReply",delegate void(){
            try{
                char[128] buf2;
                size_t i=5;
                buf2[0..i]="/req#";
                auto rc=urlEncode(reqId);
                buf2[i..i+rc.length]=rc;
                version(TrakRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" sending reply for ")(buf2[0..i+rc.length])("\n");
                    });
                }
                serializer(buf2[0..i+rc.length]);
                serRes(serializer);
                outStream.flush();
            } catch(Exception o){
                sinkTogether(protocolHandler.log,delegate void(CharSink s){
                    dumper(s)("exception in sendReply sending result of #")(urlEncode(reqId))(" ")(o)("\n");
                });
            }
        }).autorelease.executeNow(serTask);
    }
    
    void sendRequest(ParsedUrl url,void delegate(Serializer)serArgs){
        Exception e;
        Task("sendRequest", delegate void(){
            try{
                char[256] buf2=void;
                version(TrakRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" sending request for ")(&url.urlWrite)("\n");
                    });
                }
                serializer(url.url(buf2));
                serArgs(serializer);
                outStream.flush();
            } catch(Exception o){
                e=new Exception(collectAppender(delegate void(CharSink s){
                    dumper(s)("exception in sending request for url")(&url.urlWriter);
                }),__FILE__,__LINE__,o);
            }
        }).autorelease.executeNow(serTask);
        if (e!is null) throw e;
    }
    
    void start(){
        synchronized(this){
            if (status!=Status.Setup){
                throw new Exception("invalid status",__FILE__,__LINE__);
            }
            status=Status.Running;
            requestsTask=Task("requestsTask",&this.handleRequests);
        }
        requestsTask.submit(defaultTask);
    }
    // should be called within requestsTask
    void handleRequests(){
        scope(exit){
            protocolHandler.lostConnection(this);
        }
        while(status<Status.Stopping){
            processRequest();
        }
        synchronized(this){
            status=Status.Stopped;
        }
    }
    
    /// handler that handles a request from connection c
    void processRequest(){
        char[512] buf;
        char[]path=buf;
        unserializer(path);
        addLocalUser();
        ParsedUrl url=ParsedUrl.parsePath(path);
        protocolHandler.handleRequest(url,unserializer,&this.sendReply);
    }
    
    // closes the connection
    void closeConnection(){
        synchronized(this){
            if (status==Status.Running){
                status=Status.Stopping;
            } else {
                status=Status.Stopped;
            }
        }
    }
}

/// handles vending (and possibly also receiving the results if using one channel for both)
class StcpProtocolHandler: ProtocolHandler{
    static char[][] selfHostnames;
    CharSink log;
    RandomSync rand;
    
    
    static StcpProtocolHandler[char[]] stcpProtocolHandlers;
    
    /// those that can actually handle the given protocol
    static ProtocolHandler findHandlerForUrl(ParsedUrl url){
        if (url.protocol.length>0 && url.protocol!="stcp"){
            throw new RpcException("unexpected protocol instead of stcp in "~url.url(),
                __FILE__,__LINE__);
        }
        char[] port=url.port;
        char[] group;
        auto gStart=find(port,'.');
        if (gStart<port.length) {
            group=port[gStart+1..$];
            port=port[0..gStart];
        }
        synchronized(StcpProtocolHandler.classinfo){
            auto pHP= group in stcpProtocolHandlers;
            if (pHP !is null){
                return *pHP;
            }
        }
        auto newH=new StcpProtocolHandler(group,port,serr.call);
        synchronized(StcpProtocolHandler.classinfo){
            auto pHP= group in stcpProtocolHandlers;
            if (pHP !is null){
                return *pHP;
            }
            stcpProtocolHandlers[group]=newH;
            return newH;
        }
    }
    
    HashMap!(TargetHost,StcpConnection) connections;
    StcpConnection[] doubleConnections;
    char[] group;
    char[] port;
    UniqueNumber!(size_t) newRequestId;
    SocketServer server;

    this(){
        super();
        log=serr.call;
        rand=new RandomSync();
        connections=new HashMap!(TargetHost,StcpConnection)();
    }
    this(char[]group,char[]port,void delegate(char[]) log=null){
        super();
        this.log=log;
        if (log is null) this.log=serr.call;
        rand=new RandomSync();
        connections=new HashMap!(TargetHost,StcpConnection)();
        this.group=group;
        this.port=port;
        char[128] buf=void;
        auto arr=lGrowableArray!(char)(buf,0,GASharing.Local);
        dumper(&arr.appendArr)("stcp://")(selfHostnames[0])(":")(port);
        if (group.length!=0){
            arr("."); arr(group);
        }
        _handlerUrl=arr.takeData();
        newRequestId=UniqueNumber!(size_t)(10);
    }
    
    void register(){
        synchronized(StcpProtocolHandler.classinfo){
            auto pHP= group in stcpProtocolHandlers;
            if (pHP !is null && (*pHP) !is this){
                log("replacing already registred protocol for group "~group~"\n");
            }
            stcpProtocolHandlers[group]=this;
        }
    }
    
    override bool localUrl(ParsedUrl pUrl){
        if (pUrl.host.length==0 || find(selfHostnames,pUrl.host)<selfHostnames.length){
            auto p=pUrl.port;
            if (p.length==0) return true;
            auto sep=find(p,'.');
            char[] group;
            if (sep<p.length)
                group=p[sep+1..$];
            auto prt=p[0..sep];
            synchronized(StcpProtocolHandler.classinfo){
                auto ph=group in stcpProtocolHandlers;
                if (ph!is null){
                    return (*ph).port==prt;
                }
            }
        }
        return false;
    }
    
    override void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,Variant addrArg){
        TargetHost tHost;
        tHost.host=url.host;
        tHost.port=url.port[0..find(url.port,'.')];
        
        TaskI tAtt=taskAtt.val;
        auto dLevel=tAtt.delayLevel;
        Exception e;
        void decodeAnswer(ParsedUrl urlAnsw,Unserializer u){
            try{
                version(TrackRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" decoding answer to ")(&url.urlWriter)(" with url ")(&urlAnsw.urlWriter)("\n");
                    });
                }
                int resKind;
                u(resKind);
                version(TrackRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" decoding answer to ")(&url.urlWriter)(" has kind ")(resKind)("\n");
                    });
                }
                switch (resKind){
                case 0:
                    return;
                case 1:
                    unserRes(u);
                    return;
                case 2:{
                    char[] errMsg;
                    u(errMsg);
                    e=new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
                }
                case 3:{
                    char[] errMsg;
                    u(errMsg);
                    e=new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
                }
                default:
                    e=new RpcException("unknown resKind "~to!(char[])(resKind)~
                        " calling "~url.url(),__FILE__,__LINE__);
                }
            } catch (Exception o){
                e=new Exception("exception decoding res for url "~url.url,__FILE__,__LINE__,o);
            }
            version(TrackRpc){
                sinkTogether(log,delegate void(CharSink s){
                    dumper(s)(taskAtt.val)(" finished decoding task for ")(&url.urlWriter);
                    if (e!is null){
                        dumper(s)(" with exception ")(e);
                    } else {
                        static if (is(typeof(writeOut(s,u)))){ // should always be true
                            s("returnVal:");
                            writeOut(s,u);
                        }
                    }
                    s("\n");
                });
            }
            tAtt.resubmitDelayed(dLevel);
        }
        
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" doRpcCall on remote url ")(&url.urlWriter)("\n");
            });
        }
        StcpConnection connection;
        synchronized(this){
            auto conn=tHost in connections;
            if (conn!is null) connection= *conn;
            if (connection is null || (! connection.tryAddLocalUser())){
                connection=new StcpConnection(this,tHost);
                connections[tHost]=connection;
            }
        }
        // connection is valid and has a LocalUser
        scope(exit){ connection.rmLocalUser(); }
        char[22] reqBuf;
        {
            size_t pos=0;
            auto res=formatInt(reqBuf[],newRequestId.next);
            url.anchor=res;
        }
        if (unserRes!is null){
            tAtt.delay({
                addPendingRequest(urlDecode(url.anchor),&decodeAnswer);
                connection.sendRequest(url,serArgs);
            });
            version(TrackRpc){
                sinkTogether(log,delegate void(CharSink sink){
                    auto s=dumper(sink);
                    s(taskAtt.val)(" ")(&url.urlWriter);
                    if (e is null){
                        s(" will return ");
                    } else {
                        s(" with exception ")(e);
                    }
                    s("\n");
                });
            }
            if (e!is null) throw e;
        } else {
            connection.sendRequest(url,serArgs);
        }
    }
    
    void handleConnection(ref SocketServer.Handler h){
        TargetHost th=h.otherHost();
        auto newC=new StcpConnection(this,th,h.sock);
        version(TrakRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" got connection to ")(th)("\n");
            });
        }
        synchronized(connections){
            auto dConn=th in connections;
            if (dConn !is null){
                doubleConnections~=*dConn;
            }
            connections[th]=newC;
        }
    }
    
    override void startServer(bool strict){
        if (server is null){
            // now uses dynamic ports as fallback, should use a narrower range or ports 24250-24320 that are unassigned (but should be registred...)
            ushort fallBackPortMin=49152;
            ushort fallBackPortMax=65535; // this is exclusive...
            char[] buf;
            char[] origPort=port;
            bool isBound=false;
            server=new SocketServer(port,&this.handleConnection,log);
            Exception bindE;
            for (int i=0;i<100;++i){
                try{
                    server.start();
                    isBound=true;
                } catch(BIONoBindException e){
                    if (strict){
                        server=null;
                        throw e;
                    }
                    bindE=e;
                }
                if (isBound) break;
                auto newP=rand.uniformR2(fallBackPortMin,fallBackPortMax);
                if (buf.length==0) buf=new char[](30);
                auto arr=lGrowableArray(buf,0,GASharing.Global);
                writeOut(&arr.appendArr,newP);
                port=arr.takeData();
                server.serviceName=port;
            }
            if (!isBound) {
                server=null;
                throw new BIONoBindException("could not bind server started with port "~origPort,__FILE__,__LINE__,bindE);
            }
        }
    }
    
    /// handles a non pending request, be very careful about sending back errors for this o avoid
    /// infinite messaging
    /// trying to skip the content of the request migth be a good idea
    override void handleNonPendingRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        Log.lookup ("blip.rpc").warn("ignoring non pending request {}",url.url());
    }
    
    override void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        version(TrakRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" handleRequest ")(&url.urlWriter)("\n");
            });
        }
        if (url.path.length>0){
            switch(url.path[0]){
            case "obj":
                publisher.handleRequest(url,u,sendRes);
                break;
            case "req":
                PendingRequest req;
                bool error=false;
                auto reqId=urlDecode(url.anchor);
                synchronized(this){
                    auto reqPtr=reqId in pendingRequests;
                    if (reqPtr is null) {
                        error=true;
                    } else {
                        req=*reqPtr;
                        pendingRequests.remove(reqId);
                    }
                }
                if (!error){
                    req.handleRequest(url,u);
                } else {
                    handleNonPendingRequest(url,u,sendRes);
                }
                break;
            case "stop":
                assert(0,"to do"); // should close down the connection, check for requests that were sent after the closing request id and restart them at the moment closig a connection means that it will never be reestablished.
            default:
                Log.lookup ("blip.rpc").error("unknown namespace {} in {}",url.path[0],url.url);
                sysError(url,"unknown namespace",sendRes,__FILE__,__LINE__);
            }
        }
    }
    
    void lostConnection(StcpConnection c){
        sinkTogether(log,delegate void(CharSink s){
            dumper(s)(port)(".")(group)(" lostConnection to")(c.targetHost)("\n");
        });
    }

    override char[] proxyObjUrl(char[] objectName){
        return handlerUrl()~"/obj/"~objectName;
    }
}

static this(){
    char[512] buf;
    if (gethostname(buf.ptr,buf.length)!=0){
        serr("Warning could not establish the hostname\n");
    } else {
        buf[$-1]=0;
        StcpProtocolHandler.selfHostnames=[buf[0..strlen(buf.ptr)].dup];
        sout("selfHostnames:")(StcpProtocolHandler.selfHostnames)("\n");
    }
    // registers the stcp protocol
    ProtocolHandler.registerProtocolHandler("stcp",&StcpProtocolHandler.findHandlerForUrl);
}

