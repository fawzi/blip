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
import blip.time.Time;
import blip.time.Clock;
import blip.sync.Atomic;
import blip.stdc.unistd;

struct TargetHost{
    char[] host;
    char[] port;
    
    equals_t opEquals(TargetHost p2){
        return host==p2.host && port==p2.port;
    }
    int opCmp(TargetHost p){
        int c=cmp(host,p.host);
        return ((c==0)?cmp(port,p.port):c);
    }
}
// restart requests, keep last id, close at...
class StcpConnection{
    StcpProtocolHandler protocolHandler;
    BasicSocket sock;
    TaskI serTask;
    TaskI unserTask;
    Serializer serializer;
    Unserializer unserializer;
    size_t localUsers;
    Time lastUse; // valid only if localUsers is 0
    TargetHost targetHost;
    
    this(TargetHost targetHost){
        this.targetHost=targetHost;
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
                serializer(buf2[0..i+rc.length]);
                serRes(serializer);
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
                serializer(url.url(buf2));
                serArgs(serializer);
            } catch(Exception o){
                e=new Exception(collectAppender(delegate void(CharSink s){
                    dumper(s)("exception in sending request for url")(&url.urlWriter);
                }),__FILE__,__LINE__,o);
            }
        }).autorelease.executeNow(serTask);
        if (e!is null) throw e;
    }
    
    // should be called within unserTask
    void handleRequest(){
    }
    // closes the connection
    void closeConnection(){
    }
}

/// handles vending (and possibly also receiving the results if using one channel for both)
class StcpProtocolHandler: ProtocolHandler{
    static char[][] selfHostnames;
    static this(){
        char[512] buf;
        if (gethostname(buf.ptr,buf.length)!=0){
            serr("Warning could not establish the hostname\n");
        } else {
            selfHostnames=[buf[0..strlen(buf.ptr)].dup];
        }
    }
    
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
        auto newH=new StcpProtocolHandler(group,port);
        synchronized(StcpProtocolHandler.classinfo){
            auto pHP= group in stcpProtocolHandlers;
            if (pHP !is null){
                return *pHP;
            }
            stcpProtocolHandlers[group]=newH;
            return newH;
        }
    }
    /// registers the stcp protocol
    static this(){
        registerProtocolHandler("stcp",&findHandlerForUrl);
    }
    
    StcpConnection[TargetHost] connections;
    char[] group;
    char[] port;
    UniqueNumber!(size_t) newRequestId;
    SocketServer server;

    this(){ super(); }
    this(char[]group,char[]port){
        super();
        this.group=group;
        this.port=port;
        char[128] buf=void;
        auto arr=lGrowableArray!(char)(buf,0,GASharing.Local);
        dumper(&arr)("mpi-sbin://")(selfHostnames[0])(":")(port);
        if (group.length!=0){
            arr("."); arr(group);
        }
        _handlerUrl=arr.takeData();
        newRequestId=UniqueNumber!(size_t)(10);
    }
    
    override bool localUrl(ParsedUrl pUrl){
        return pUrl.host.length==0 || find(selfHostnames,pUrl.host)<selfHostnames.length;
    }
    
    override void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,Variant addrArg){
        TargetHost tHost;
        tHost.host=url.host;
        tHost.port=url.port[0..find(url.port,'.')];
        if (tHost.host.length==0 && find(selfHostnames,tHost.host)<selfHostnames.length){
            ubyte[256] buf=void;
            char[256] buf2=void;
            // local call (but with serialization/unserialization, this should not be used,
            // as localProxies avoid it)
            if (url.path.length!=3) {
                throw new RpcException("unexpected path length in url "~url.url(buf2),
                    __FILE__,__LINE__);
            }
            auto obj=publisher.objectNamed(url.path[1]);
            auto arr=lGrowableArray!(ubyte)(buf,0,GASharing.GlobalNoFree);
            auto s=new SBinSerializer(&arr.appendVoid);
            s(url.url(buf2));
            serArgs(s);
            auto arr2=new IOArray(arr.takeData);
            arr.assign(cast(ubyte[])buf2,0,GASharing.GlobalNoFree);
            auto u=new SBinUnserializer(toReaderT!(void)(arr2));
            obj.remoteMainCall(url.path[2],urlDecode(url.anchor),u,
                delegate void(ubyte[]reqId,void delegate(Serializer)sRes){
                    sRes(s);
                });
            if (unserRes!is null){
                arr2.assign(arr.takeData);
                unserRes(u);
            }
        } else {
            StcpConnection connection;
            synchronized(this){
                auto conn=tHost in connections;
                if (conn!is null) connection= *conn;
                if (connection is null || (! connection.tryAddLocalUser())){
                    connection=new StcpConnection(tHost);
                    connections[tHost]=connection;
                }
            }
            // connection is valid and has a LocalUser
            scope(exit){ connection.rmLocalUser(); }
            auto target=to!(int)(url.host);
            char[22] reqBuf;
            {
                size_t pos=0;
                auto res=formatInt(reqBuf[],newRequestId.next);
                url.anchor=res;
            }
            if (unserRes!is null){
                auto tAtt=taskAtt.val;
                Exception e;
                void decodeAnswer(ParsedUrl urlAnsw,Unserializer u){
                    try{
                        int resKind;
                        u(resKind);
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
                    tAtt.resubmitDelayed;
                }
                tAtt.delay({
                    addPendingRequest(urlDecode(url.anchor),&decodeAnswer);
                    connection.sendRequest(url,serArgs);
                });
                if (e!is null) throw e;
            } else {
                connection.sendRequest(url,serArgs);
            }
        }
    }
    
    override void startServer(bool strict){
    }
    
    /// Channel handler that handles a request
/+    void channelHandler(Channel c,int tagN){
        assert(tag==tagN,"mismatched tags");
        char[]path;
        ubyte[512] buf;
        auto u=c.recvTag(tag,buf);
        u(path);
        ParsedUrl url=ParsedUrl.parsePath(path);
        handleRequest(url,u,&sendReply);
    }+/
    
    /// handles a non pending request, be very careful about sending back errors for this o avoid
    /// infinite messaging
    /// trying to skip the content of the request migth be a good idea
    override void handleNonPendingRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        Log.lookup ("blip.rpc").warn("ignoring non pending request {}",url.url());
    }
    
    override void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
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
            case "stp":
            default:
                Log.lookup ("blip.rpc").error("unknown namespace {} in {}",url.path[0],url.url);
                sysError(url,"unknown namespace",sendRes,__FILE__,__LINE__);
            }
        }
    }

    override char[] proxyObjUrl(char[] objectName){
        return handlerUrl()~"/obj/"~objectName;
    }
}

