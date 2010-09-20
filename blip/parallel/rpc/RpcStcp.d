/// rpc using a simple tcp based protocol
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
import blip.container.HashMap;
import blip.math.random.Random;
import blip.container.Pool;
import blip.container.Cache;
import blip.util.RefCount;

/// represents a request to another handler
///
/// to do to support recoverable close:
/// + restart requests that will not be answered (sent to an already closed socket)
/// (this should not be too difficult, now that we use StcpRequest, but some synchronization details will)
struct StcpRequest{
    Exception exception;
    ParsedUrl url;
    StcpConnection connection;
    void delegate(Serializer)serArgs;
    void delegate(Unserializer)unserRes;
    TaskI toResume;
    char[22] reqBuf;
    PoolI!(StcpRequest*) pool;
    static PoolI!(StcpRequest*) gPool;
    static this(){
        gPool=cachedPool(function StcpRequest*(PoolI!(StcpRequest*)p){
            auto res=new StcpRequest;
            res.pool=p;
            return res;
        });
    }
    void clear(){
        exception=null;
        url=ParsedUrl.init;
        connection=null;
        serArgs=null;
        unserRes=null;
        toResume=null;
    }
    void release0(){
        if (connection!is null){
            connection.rmLocalUser();
            connection=null;
        }
        if (pool!is null){
            refCount=1;
            pool.giveBack(this);
        } else {
            clear();
            delete this;
        }
    }
    mixin RefCountMixin!();
    /// this is the method to call to start the request
    void doRequest(){
        retain();// for sendRequest
        // always delay (even oneway) to catch at least immediate send erorrs, and to ensure that one can use on stack delegates/arguments in the serialization...
        toResume=taskAtt.val;
        toResume.delay(delegate void(){
            Task("sendReq",&this.sendRequest).autorelease.submit(connection.serTask);
        });
        if (exception!is null){
            throw exception;
        }
    }
    /// sends the request, is called from within the serialization task of the connection
    void sendRequest(){
        try{
            auto res=formatInt(reqBuf[],connection.nextRequestId);
            url.anchor=res; // makes struct non copiable!!!
            if (unserRes){
                retain(); // for decodeAnswer
                // register callback
                connection.protocolHandler.addPendingRequest(urlDecode(url.anchor),&this.decodeAnswer);
            }
            
            char[256] buf2=void;
            version(TrackRpc){
                sinkTogether(connection.log,delegate void(CharSink s){
                    dumper(s)(taskAtt.val)(" sending request for ")(&url.urlWriter)("\n");
                });
            }
            connection.serializer(url.pathAndRest(buf2));
            serArgs(connection.serializer);
            connection.outStream.flush();
        } catch(Exception o){
            exception=new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("exception in sending request for url")(&url.urlWriter);
            }),__FILE__,__LINE__,o);
        }
        if (unserRes is null) toResume.resubmitDelayed(toResume.delayLevel-1);
        release();
    }
    /// decodes the answer, this is appended to the pending requests
    void decodeAnswer(ParsedUrl urlAnsw,Unserializer u){
        assert(unserRes!is null,"called decodeAnswer of oneway method with url "~url.url());
        try{
            version(TrackRpc){
                sinkTogether(connection.log,delegate void(CharSink s){
                    dumper(s)(taskAtt.val)(" decoding answer to ")(&url.urlWriter)(" with url ")(&urlAnsw.urlWriter)("\n");
                });
            }
            int resKind;
            u(resKind);
            version(TrackRpc){
                sinkTogether(connection.log,delegate void(CharSink s){
                    dumper(s)(taskAtt.val)(" decoding answer to ")(&url.urlWriter)(" has kind ")(resKind)("\n");
                });
            }
            switch (resKind){
            case 0:
                break;
            case 1:
                unserRes(u);
                break;
            case 2:{
                char[] errMsg;
                u(errMsg);
                exception=new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
            }
                break;
            case 3:{
                char[] errMsg;
                u(errMsg);
                exception=new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
            }
                break;
            default:
                exception=new RpcException("unknown resKind "~to!(char[])(resKind)~
                    " calling "~url.url(),__FILE__,__LINE__);
            }
        } catch (Exception o){
            exception=new Exception("exception decoding res for url "~url.url(),__FILE__,__LINE__,o);
        }
        version(TrackRpc){
            sinkTogether(connection.log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" finished decoding task for ")(&url.urlWriter);
                if (exception!is null){
                    dumper(s)(" with exception ")(exception);
                }
                s("\n");
            });
        }
        toResume.resubmitDelayed(toResume.delayLevel-1);
        release();
    }
    /// creates a request and returns it
    static StcpRequest*opCall(StcpConnection connection,ParsedUrl url,void delegate(Serializer)serArgs,
        void delegate(Unserializer)unserRes){
        auto res=gPool.getObj();
        res.url=url;
        res.connection=connection;
        res.serArgs=serArgs;
        res.unserRes=unserRes;
        return res;
    }
    /// performs a request
    static void performRequest(StcpConnection connection,ParsedUrl url,void delegate(Serializer)serArgs,
        void delegate(Unserializer)unserRes)
    {
        auto res=StcpRequest(connection,url,serArgs,unserRes);
        res.doRequest();
        if (res.exception!is null)
            throw res.exception; // release? the exception might need this...
        res.release();
    }
}

/// represent a connection with an host
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
    Reader!(char) charReader;
    SequentialTask serTask; /// sequential task in which sending should be performed
    TaskI requestsTask; /// reference to the task that is doing the unserialization/handling requests, worth keeping?
    Serializer serializer;
    Unserializer unserializer;
    size_t localUsers=1;
    Time lastUse; // valid only if localUsers is 0
    TargetHost targetHost;
    Status status=Status.Setup;
    size_t lastReqId;
    CharSink log;
    size_t nextRequestId(){
        synchronized(this){
            lastReqId=protocolHandler.newRequestId.next();
            return lastReqId;
        }
    }
    
    this(StcpProtocolHandler protocolHandler,TargetHost targetHost,BasicSocket sock){
        this.protocolHandler=protocolHandler;
        this.targetHost=targetHost;
        this.sock=sock;
        version(StcpNoCache){}
        else {
            this.sock.noDelay(true); // use no delay to reduce the latency
        }
        //this.sock.keepalive(true);
        serTask=new SequentialTask("stcpSerTask",defaultTask,true);
        // should limit buffer to 1280 or 1500 or multiples of them? (jumbo frames)
        outStream=new BufferedBinStream(&this.sock.writeExact,3000,&this.sock.flush,&this.sock.close);
        readIn=new BufferIn!(void)(&this.sock.rawReadInto);
        version(StcpTextualSerialization){
            auto r=new BufferIn!(char)(cast(size_t delegate(char[]))&this.sock.rawReadInto);
            //ReinterpretReader!(void,char) r=readIn.reinterpretReader!(char)();
            charReader=r;
            serializer=new JsonSerializer!(char)(outStream.charSink());
            unserializer=new JsonUnserializer!(char)(charReader);
        } else {
            version(StcpNoCache){
                serializer=new SBinSerializer(&this.sock.writeExact);
                unserializer=new SBinUnserializer(&this.sock.rawReadExact);
            } else {
                serializer=new SBinSerializer(outStream.binSink());
                unserializer=new SBinUnserializer(readIn);
            }
        }
        localUsers=1;
        log=protocolHandler.log;
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("created new connection to ")(targetHost)(" on socket ")(this.sock)("\n");
            });
        }
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

    // stuff to keep track of the users (and allow in the future to close a unused connection)
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
    /// sends back a result on this connection
    void sendReply(ubyte[] reqId,void delegate(Serializer) serRes){
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("sendReply #")(urlEncode2(reqId))(" working in task ")(taskAtt.val)("\n");
            });
        }
        Task("sendReply",delegate void(){
            try{
                char[128] buf2;
                size_t i=5;
                buf2[0..i]="/req#";
                auto rc=urlEncode(reqId);
                buf2[i..i+rc.length]=rc;
                version(TrackRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" sending reply for ")(buf2[0..i+rc.length])(" start\n");
                    });
                }
                serializer(buf2[0..i+rc.length]);
                serRes(serializer);
                outStream.flush();
                version(TrackRpc){
                    sinkTogether(log,delegate void(CharSink s){
                        dumper(s)(taskAtt.val)(" sending reply for ")(buf2[0..i+rc.length])(" success\n");
                    });
                }
            } catch(Exception o){
                sinkTogether(log,delegate void(CharSink s){
                    dumper(s)("exception in sendReply sending result of #")(urlEncode2(reqId))(" ")(o)("\n");
                });
            }
        }).autorelease.executeNow(serTask);
    }
    
    // loop that handles incoming requests on this connection, this defines requestsTask
    void handleRequests(){
        assert(requestsTask is null);
        requestsTask=taskAtt.val;
        requestsTask.retain();
        scope(exit){requestsTask.release(); requestsTask=null;}
        try{
            synchronized(this){
                if (status!=Status.Setup){
                    throw new Exception("invalid status",__FILE__,__LINE__);
                }
                status=Status.Running;
            }
            while(status<Status.Stopping){
                processRequest();
            }
            synchronized(this){
                status=Status.Stopped;
            }
        } catch (Exception e){
            protocolHandler.lostConnection(this,e);
            return;
        }
        protocolHandler.lostConnection(this,null);
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
        outStream.close();
        readIn.shutdownInput();
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
            group=port[gStart..$];
            port=port[0..gStart];
        } else {
            group=".";
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
        version(TrackRpc){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("creating StcpProtocolHandler@")(cast(void*)this)("\n");
            });
        }
        super();
        log=serr.call;
        rand=new RandomSync();
        connections=new HashMap!(TargetHost,StcpConnection)();
    }
    this(char[]group,char[]port,void delegate(char[]) log=null){
        version(TrackRpc){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("creating StcpProtocolHandler@")(cast(void*)this)(" for group '")(group)("' and port: ")(port)("\n");
            });
        }
        super();
        this.log=log;
        if (log is null) this.log=serr.call;
        rand=new RandomSync();
        connections=new HashMap!(TargetHost,StcpConnection)();
        this.group=((group.length==0)?"."[]:group);
        assert(this.group[0]=='.',"group should start with .");
        this.port=port;
        updateUrl();
        newRequestId=UniqueNumber!(size_t)(10);
    }
    /// updates the url of this handler (to be called when the port changes)
    void updateUrl(){
        char[128] buf=void;
        auto arr=lGrowableArray!(char)(buf,0,GASharing.Local);
        dumper(&arr.appendArr)("stcp://")(selfHostnames[0])(":")(port);
        if (group.length!=1){
            arr(group);
        }
        _handlerUrl=arr.takeData();
    }
    /// registers this handler in the global registry of the handlers, there should be just one handler per
    /// group
    void register(){
        synchronized(StcpProtocolHandler.classinfo){
            auto pHP= group in stcpProtocolHandlers;
            if (pHP !is null && (*pHP) !is this){
                log("replacing already registred protocol for group "~group~"\n");
                this.newRequestId.ensure((*pHP).newRequestId.next+10_000); // try to avoid any overlap...
            }
            stcpProtocolHandlers[group]=this;
        }
    }
    /// checks if the given url is local
    override bool localUrl(ParsedUrl pUrl){
        if (pUrl.host.length==0 || find(selfHostnames,pUrl.host)<selfHostnames.length){
            auto p=pUrl.port;
            if (p.length==0) return true;
            auto sep=find(p,'.');
            char[] group;
            if (sep<p.length)
                group=p[sep..$];
            else
                group=".";
            auto prt=p[0..sep];
            synchronized(StcpProtocolHandler.classinfo){
                auto ph=group in stcpProtocolHandlers;
                if (ph!is null){
                    return (*ph).port==prt && (*ph).server !is null && (*ph).server.isStarted();
                }
            }
        }
        return false;
    }
    /// perform 
    override void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,Variant addrArg){
        version(TrackRpc){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("doRpcCall(")(&url.urlWriter)(",")(serArgs)(",")(unserRes)(",__)\n"); // don't trust variant serialization...
            });
        }
        TargetHost tHost;
        tHost.host=url.host;
        tHost.port=url.port[0..find(url.port,'.')];
        
        TaskI tAtt=taskAtt.val;
        auto dLevel=tAtt.delayLevel;
        Exception e;
        
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" doRpcCall on remote url ")(&url.urlWriter)("\n");
            });
        }
        StcpConnection connection;
        bool startHandler=false;
        synchronized(connections){
            auto conn=tHost in connections;
            if (conn!is null) connection= *conn;
            if (connection is null || (! connection.tryAddLocalUser())){
                version(TrackRpc){
                    if (connection !is null)
                        sinkTogether(log,delegate void(CharSink s){
                            dumper(s)(taskAtt.val)(" created double connection to ")(tHost)("\n");
                        });
                }
                connection=new StcpConnection(this,tHost);
                connections[tHost.dup]=connection;
                sinkTogether(log,delegate void(CharSink s){
                    auto td=tHost.dup;
                    dumper(s)(taskAtt.val)(" pippo")(tHost)(",")(td)(":")(tHost==td)(tHost<td)(tHost>td)("\n");
                });
                
                assert((tHost in connections)!is null,"host not in connections");
                startHandler=true;
            }
        }
        if (startHandler){
            Task("handleReplies",&connection.handleRequests).autorelease.submit(defaultTask);
        }
        // connection is valid and has a LocalUser
        StcpRequest.performRequest(connection,url,serArgs,unserRes);
    }
    
    void handleConnection(ref SocketServer.Handler h){
        TargetHost th=h.otherHost();
        auto newC=new StcpConnection(this,th,h.sock);
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)(" got connection to ")(th)("\n");
            });
        }
        synchronized(connections){
            auto dConn=th in connections;
            if (dConn !is null){
                sinkTogether(log,delegate void(CharSink s){
                    dumper(s)(taskAtt.val)(" has double connection to ")(th)("\n");
                });
                doubleConnections~=*dConn;
            }
            connections[th]=newC;
        }
        newC.handleRequests();
    }
    
    override void startServer(bool strict){
        if (server is null){
            // now uses the "well known" ports as fallback, should use a narrower range or ports 24250-24320 that are unassigned (but should be registred...)??
            ushort fallBackPortMin=48620;
            ushort fallBackPortMax=49151; // this is exclusive...
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
            updateUrl();
        }
    }
    
    /// handles a non pending request, be very careful about sending back errors for this to avoid
    /// infinite messaging
    /// trying to skip the content of the request migth be a good idea
    override void handleNonPendingRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        Log.lookup ("blip.rpc").warn("ignoring non pending request {}",url.url());
    }
    
    override void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        version(TrackRpc){
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
    
    void lostConnection(StcpConnection c,Exception e){
        sinkTogether(log,delegate void(CharSink s){
            dumper(s)(port)(group)(" lostConnection to")(c.targetHost);
            if (e!is null){
                dumper(s)(" with exception:")(e);
            }
            s("\n");
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

