/// rpc using mpi
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
module blip.parallel.rpc.RpcMpi;
import blip.parallel.rpc.RpcBase;
import blip.parallel.mpi.Mpi;
import blip.serialization.Serialization;
import blip.container.GrowableArray;
import blip.BasicModels;
import blip.util.TangoConvert;
import blip.core.Array;
import blip.util.TangoLog;import blip.sync.UniqueNumber;
import blip.io.IOArray;
import blip.parallel.smp.WorkManager;
import blip.io.BasicIO;
import blip.io.StreamConverters;

/// handles vending (and possibly also receiving the results if using one channel for both)
class MpiProtocolHandler: ProtocolHandler{
    static MpiProtocolHandler[char[]] mpiProtocolHandlers;
    
    /// those that can actually handle the given protocol
    static ProtocolHandler findHandlerForUrl(ParsedUrl url){
        if (url.protocol.length>0 && url.protocol!="mpi-sbin"){
            throw new RpcException("unexpected protocol instead of mpi-sbin in "~url.url(),
                __FILE__,__LINE__);
        }
        auto port=url.port;
        MpiProtocolHandler pH;
        synchronized(MpiProtocolHandler.classinfo){
            pH=mpiProtocolHandlers[port];
        }
        if (pH is null){
            throw new RpcException("could not find mpi handler for port '"~port~"'",
                __FILE__,__LINE__);
        }
        return pH;
    }
    /// registers the mpi-sbin protocol
    static this(){
        registerProtocolHandler("mpi-sbin",&findHandlerForUrl);
    }
    /// registers a mpi communicator handler
    static void registerMpiProtocolHandler(MpiProtocolHandler pH){
        char[128] buf;
        auto arr=lGrowableArray!(char)(buf,0,GASharing.Local);
        dumper(&arr)(pH.comm.name)("-")(pH.tag);
        char[] commName=arr.takeData();
        synchronized(MpiProtocolHandler.classinfo){
            if ((commName in mpiProtocolHandlers)is null)
                throw new RpcException("duplicate handler for communicatr named "~commName,__FILE__,__LINE__);
            mpiProtocolHandlers[commName]=pH;
        }
    }
    /// unregisters a handler for a given protocol
    static bool unregisterMpiProtocolHandler(MpiProtocolHandler pH){
        auto commName=pH.comm.name;
        synchronized(MpiProtocolHandler.classinfo){
            if ((commName in mpiProtocolHandlers)is null)
                return false;
            mpiProtocolHandlers.remove(commName);
        }
        return true;
    }
    
    LinearComm comm;
    int tag;
    UniqueNumber!(size_t) newRequestId;
    this(){ super(); }
    this(LinearComm comm,int tag){
        super();
        this.comm=comm;
        this.tag=tag;
        char[128] buf;
        auto arr=lGrowableArray!(char)(buf,0,GASharing.Local);
        dumper(&arr)("mpi-sbin://")(comm.myRank)(":")(comm.name)("-")(tag);
        _handlerUrl=arr.takeData();
        newRequestId=UniqueNumber!(size_t)(10);
    }
    
    void register(){
        registerMpiProtocolHandler(this);
    }
    void unregister(){
        unregisterMpiProtocolHandler(this);
    }
    
    void sendReply(ubyte[] reqId,void delegate(Serializer) serRes){
        ubyte[512] buf=void;
        try{
            char[128] buf2;
            auto s=comm[to!(int)(cast(char[])reqId[0..reqId.find(cast(ubyte)'-')])].sendTag(tag,buf);
            scope(exit){ s.close(); }
            size_t i=5;
            buf2[0..i]="/req#";
            auto rc=urlEncode(reqId);
            buf2[i..i+rc.length]=rc;
            s(buf2[0..i+rc.length]);
            serRes(s);
        } catch(Object o){
            Log.lookup ("blip.rpc").warn("exception in sendReply sending result of #{}: {}",cast(char[])reqId,o);
        }
    }
    
    override bool localUrl(ParsedUrl pUrl){
        return to!(int)(pUrl.host)==comm.myRank;
    }
    
    override void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,Variant addrArg){
        ubyte[256] buf=void;
        char[256] buf2=void; // ugly duplication should be removed (direct custom serialization of url)
        auto target=to!(int)(url.host);
        char[60] reqBuf;
        {
            size_t pos=url.host.length;
            reqBuf[0..pos]=url.host;
            reqBuf[pos]='-';
            ++pos;
            auto res=formatInt(reqBuf[pos..$],newRequestId.next);
            if (res.ptr !is reqBuf.ptr+pos){
                url.anchor=reqBuf[0..pos]~res;
            } else {
                url.anchor=reqBuf[0..pos+res.length];
            }
        }
        if (target!=comm.myRank){
            if (unserRes!is null){
                Unserializer u;
                auto tAtt=taskAtt.val;
                auto dLevel=tAtt.delayLevel;
                tAtt.delay({
                    addPendingRequest(urlDecode(url.anchor),delegate void(ParsedUrl url,Unserializer us){
                        u=us;
                        tAtt.resubmitDelayed(dLevel);
                    });
                    auto s=comm[target].sendTag(tag,buf);
                    s(url.url(buf2));
                    serArgs(s);
                    s.close();
                });
                scope(exit){ u.close(); }
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
                    throw new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
                }
                case 3:{
                    char[] errMsg;
                    u(errMsg);
                    throw new RpcException(errMsg~" calling "~url.url(),__FILE__,__LINE__);
                }
                default:
                    throw new RpcException("unknown resKind "~to!(char[])(resKind)~
                        " calling "~url.url(),__FILE__,__LINE__);
                }
            } else {
                auto s=comm[target].sendTag(tag,buf);
                s(url.url(buf2));
                serArgs(s);
                s.close();
            }
        } else {
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
        }
    }
    
    override void startServer(bool strict){
        comm.registerHandler(&channelHandler,tag);
    }
    
    /// Channel handler that handles a request
    void channelHandler(Channel c,int tagN){
        assert(tag==tagN,"mismatched tags");
        char[]path;
        ubyte[512] buf;
        auto u=c.recvTag(tag,buf);
        u(path);
        ParsedUrl url=ParsedUrl.parsePath(path);
        handleRequest(url,u,&sendReply);
    }
    
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

