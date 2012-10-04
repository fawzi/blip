/// basic types for remote procedure call
///
/// localProxies are kind of hacked in... should probably be improved:
/// - subtask handling (in mixins) slightly different from normal call
/// - targetObj has to be available, and a single lookup is done at creation time
///   (does not update if the vended object is changed)
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
module blip.parallel.rpc.RpcBase;
import blip.parallel.smp.SmpModels;
import blip.serialization.StringSerialize;
import blip.serialization.Serialization;
import blip.util.TangoLog;
import blip.sync.UniqueNumber;
import blip.time.Clock;
import blip.time.Time;
import blip.util.TangoConvert;
import blip.container.GrowableArray;
import blip.container.HashMap;
import blip.BasicModels;
import blip.core.sync.Mutex;
import blip.io.BasicIO;
import blip.core.Variant;
import blip.io.Console;
import blip.container.Pool;
import blip.container.Cache;
import blip.parallel.smp.WorkManager;
import blip.container.RedBlack;
import blip.container.Deque;
import blip.core.Traits: cmp;
import blip.Comp;

alias void delegate(in ubyte[] reqId,void delegate(Serializer) sRes) SendResHandler;

class RpcException:Exception{
    this(string msg,string file,long line){
        super(msg,file,line);
    }
    this(void delegate(scope void delegate(in cstring))msg,string file,long line){
        super(collectIAppender(msg),file,line);
    }
}

/// urls have the following form: protocol://host:port/namespace/object/function#requestId?query
/// paths skip the protocol://host:port part
/// represent an url parsed in its components
/// protocol:[//]host:port/path/path?query&query#anchor
struct ParsedUrl{
    string protocol;
    string host;
    string port;
    string [4] pathBuf; // this is a hack for efficient appending to small paths
    string * pathPtr;   // and still be able to copy the structure...
    size_t pathLen;    //
    string [] query;
    string anchor;
    void fullPathWriter(scope void delegate(in cstring)sink){
        foreach (p;path){
            sink("/");
            sink(p);
        }
    }
    string [] path(){
        if (pathPtr is null){
            return pathBuf[0..pathLen];
        }
        return pathPtr[0..pathLen];
    }
    void path(string []p){
        pathPtr=p.ptr;
        pathLen=p.length;
    }
    static void dumpHost(scope void delegate(in cstring)sink, string host) {
	bool ipv6ip=false;
	foreach (c;host)
	    if (c == ':') ipv6ip=true;
	if (ipv6ip) sink("[");
        sink(host);
	if (ipv6ip) sink("]");
    }
    void urlWriter(scope void delegate(in cstring)sink){
        sink(protocol);
        sink("://");
	dumpHost(sink,host);
        if (port.length!=0){
            sink(":");
            sink(port);
        }
        foreach (p;path){
            sink("/");
            sink(p);
        }
        if (query.length){
            sink("?");
            sink(query[0]);
            foreach (q;query[1..$]){
                sink("&");
                sink(q);
            }
        }
        if (anchor.length){
            sink("#");
            sink(anchor);
        }
    }
    void desc(scope void delegate(in cstring)sink){
        urlWriter(sink);
    }
    
    void pathAndRestWriter(scope void delegate(in cstring)sink){
        foreach (p;path){
            sink("/");
            sink(p);
        }
        if (query.length){
            sink("?");
            sink(query[0]);
            foreach (q;query[1..$]){
                sink("&");
                sink(q);
            }
        }
        if (anchor.length){
            sink("#");
            sink(anchor);
        }
    }
    string url(char[]buf=null){
        return collectIAppender(&this.urlWriter,buf);
    }
    string fullPath(char[]buf=null){
        return collectIAppender(&this.fullPathWriter,buf);
    }
    string pathAndRest(char[]buf=null){
        return collectIAppender(&this.pathAndRestWriter,buf);
    }
    void clearPath(){
        pathBuf[]=null;
        pathLen=0;
        pathPtr=null;
        query=null;
        anchor=null;
    }
    void clearHost(){
        protocol=null;
        host=null;
        port=null;
    }
    void appendToPath(string segment){
        if (pathLen<pathBuf.length){
            if (pathLen!=0 && pathPtr !is null){
                foreach (i,p;path){
                    pathBuf[i]=p;
                }
            }
            pathBuf[pathLen]=segment;
            pathPtr=null;
            ++pathLen;
        } else {
            if (pathPtr is null){
                path=path~segment;
            } else {
                auto nPath=path;
                nPath~=segment;
                pathPtr=nPath.ptr;
                pathLen=nPath.length;
            }
        }
    }
    void clear(){
        clearHost();
        clearPath();
    }
    static ParsedUrl parseUrl(string url){
        ParsedUrl res;
        auto len=res.parseUrlInternal(url);
        if (len!=url.length){
            throw new RpcException(collectIAppender(delegate void(scope CharSink s){
                dumper(s)("url parsing failed:")(len)("vs")(url.length)(", '")(&res.urlWriter)("' vs '")(url)("'");
            }),__FILE__,__LINE__);
        }
        return res;
    }
    static ParsedUrl parsePath(string path){
        ParsedUrl res;
        if (res.parsePathInternal(path)!=path.length){
            throw new RpcException("path parsing failed",__FILE__,__LINE__);
        }
        return res;
    }
    size_t parseUrlInternal(string url){
        clearHost();
        size_t i=0;
        while (i<url.length){
            if (url[i]=='/'||url[i]==':') break;
            ++i;
        }
        protocol=url[0..i];
        if (i==url.length || url[i]!=':') return i;
        ++i;
        if (i==url.length) return i;
        if (url[i]=='/'){
            ++i;
            if (i==url.length || url[i]!='/') return i;
            ++i;
        }
        size_t j;
	if (url[i]=='[') {
	    for (j=++i;j<url.length;++j){
		if (url[j]==']') break;
	    }
	    if (j==url.length) return j;
	    host=url[i..j];
	    ++j;
	    if (j==url.length) return j;
	    if (url[j]!='/' && url[j]!=':') return j;
	} else {
	    for (j=i;j<url.length;++j){
		if (url[j]=='/'||url[j]==':') break;
	    }
	    host=url[i..j];
	    if (j==url.length) return j;
	}
	i=j+1;
        if (url[j]==':'){
            for (j=i;j<url.length;++j){
                if (url[j]=='/') break;
            }
            port=url[i..j];
        }
        if (j==url.length) return j;
        i=j;
        return j+parsePathInternal(url[j..$]);
    }
    
    size_t parsePathInternal(string fPath){
        clearPath();
        if (fPath.length==0) return 0;
        size_t i=0;
        if (fPath[0]=='/') i=1;
        size_t j;
        while(1){
            for (j=i; j<fPath.length;++j){
                if (fPath[j]=='/'|| fPath[j]=='#'|| fPath[j]=='?') break;
            }
            appendToPath(fPath[i..j]);
            if (j==fPath.length) return j;
            i=j+1;
            if (fPath[j]!='/') break;
        }
        if (i==fPath.length) return i;
        if (fPath[i-1]=='?'){
            while(1){
                for (j=i; j<fPath.length;++j){
                    if (fPath[j]=='&'||fPath[j]=='#') break;
                }
                query~=fPath[i..j];
                if (j==fPath.length) return j;
                i=j+1;
                if (fPath[j]=='#') break;
            }
        }
        anchor=fPath[i..$];
        return fPath.length;
    }
}

/// at the moment just checks that no encoding is needed
/// actually reallocate and do the encoding?
inout(char)[] urlEncode(inout(ubyte)[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=cast(char)str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_' && c!='[' && c!=']'){
            throw new Exception("only clean (not needing decoding) strings are supported, not '"~(cast(string )str)~"' (more efficient)",
                __FILE__,__LINE__);
        }
    }
    return cast(inout(char)[])str;
}
/// safe encoding, never raises (switches to '' delimited hex encoding)
cstring urlEncode2(in ubyte[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        auto c=cast(char)str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_' && c!='[' && c!=']'){
            return collectAppender(delegate void(scope CharSink s){
                dumper(s)("'")(str)("'");
            });
        }
    }
    return cast(cstring )str;
}

/// ditto
inout(ubyte)[] urlDecode(inout(char)[] str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_' && c!='[' && c!=']'){
            throw new Exception("only clean (not needing decoding) strings are supported (more efficient)",
                __FILE__,__LINE__);
        }
    }
    return (cast(inout(ubyte*))str.ptr)[0..str.length];
}

/// an objects that can be published (typically publishes another object)
interface ObjVendorI{
    Object targetObj();
    void proxyDescDumper(scope void delegate(in cstring));
    string proxyDesc();
    string proxyName();
    string objName();
    void objName(string newVal);
    string proxyObjUrl();
    Publisher publisher();
    void publisher(Publisher newP);
    TaskI objTask();
    void objTask(TaskI task);
    void remoteMainCall(string functionName,in ubyte[] requestId, Unserializer u, SendResHandler sendRes);
}

class BasicVendor:ObjVendorI{
    string _proxyName;
    string _objName;
    Publisher _publisher;
    TaskI _objTask;
    
    this(string pName=""){
        _proxyName=pName;
        _objTask=defaultTask;
    }
    
    Object targetObj(){
        return this;
    }
    void proxyDescDumper(scope void delegate(in cstring)s){
        s("string proxyDesc()\nstring proxyName()\nstring proxyObjUrl()\n");
    }
    string proxyDesc(){
        return collectIAppender(&proxyDescDumper);
    }
    string proxyName(){
        return _proxyName;
    }
    string proxyObjUrl(){
        return publisher.proxyObjUrl(_objName);
    }
    string objName(){
        return _objName;
    }
    void objName(string newVal){
        _objName=newVal;
    }
    Publisher publisher(){
        return _publisher;
    }
    void publisher(Publisher newP){
        _publisher=newP;
    }
    TaskI objTask(){
        return _objTask;
    }
    void objTask(TaskI t){
        _objTask=t;
    }
    
    /// returns res, this should *not* be executed in the unserialization task
    void simpleReply()(SendResHandler sendRes,in ubyte[] reqId)
    {
        sendRes(reqId,delegate void(Serializer s){
            s(0);
        });
    }
    /// returns res, this should *not* be executed in the unserialization task
    void simpleReply(T)(SendResHandler sendRes,in ubyte[] reqId,T res)
    {
        sendRes(reqId,delegate void(Serializer s){
            static if (is(T==void)){
                s(0);
            } else {
                s(1);
                s(res);
            }
        });
    }
    /// returns an exception, this should *not* be executed in the unserialization task
    void exceptionReply(T)(SendResHandler sendRes,in ubyte[] reqId,T exception)
    {
        sendRes(reqId,delegate void(Serializer s){
            s(2);
            s(collectAppender(outWriter(exception)));
        });
    }
    /// helper to create closures of simpleReply
    static struct SimpleReplyClosure(T){
        ubyte[64] reqIdBuf;
        BasicVendor obj;
        SendResHandler sendRes;
        ubyte* reqIdPtr;
        size_t reqIdLen;
        T res;
        PoolI!(SimpleReplyClosure*) pool;
        static __gshared PoolI!(SimpleReplyClosure*) gPool;
        @property ubyte[] reqId(){
            if (reqIdPtr is null){
                return reqIdBuf[0..reqIdLen];
            }
            return reqIdPtr[0..reqIdLen];
        }
        @property void reqId(in ubyte[]v){
            if (v.length<reqIdBuf.length){
                reqIdBuf[0..v.length]=v;
                reqIdPtr=null;
                reqIdLen=v.length;
            } else {
                auto nV=v.dup;
                reqIdPtr=nV.ptr;
                reqIdLen=nV.length;
            }
        }
        shared static this(){
            gPool=cachedPool(function SimpleReplyClosure*(PoolI!(SimpleReplyClosure*)p){
                auto res=new SimpleReplyClosure;
                res.pool=p;
                return res;
            });
        }
        void doOp(){
            obj.simpleReply(sendRes,reqId,res);
        }
        void doOpExcept(){
            obj.exceptionReply(sendRes,reqId,res);
        }
        void giveBack(){
            if (pool!is null){
                pool.giveBack(&this);
            } else {
                // delete(this); // cannot be done anymore
            }
        }
    }
    /// helper to more easily create closures of simpleReply
    SimpleReplyClosure!(T) *simpleReplyClosure(T)(SendResHandler sendRes,in ubyte[] reqId,T res){
        auto r=SimpleReplyClosure!(T).gPool.getObj();
        r.sendRes=sendRes;
        r.reqId=reqId;
        r.res=res;
        r.obj=this;
        return r;
    }
    /// performs simpleReply in another task (detached)
    void simpleReplyBg(T)(SendResHandler sendRes,in ubyte[] reqId,T res){
        auto cl=simpleReplyClosure(sendRes,reqId,res);
        Task("simpleReplyBg",&cl.doOp).appendOnFinish(&cl.giveBack).autorelease.submit(defaultTask);
    }
    /// performs exceptionReply in another task (detached)
    void exceptionReplyBg(T)(SendResHandler sendRes,in ubyte[] reqId,T res){
        auto cl=simpleReplyClosure(sendRes,reqId,res);
        Task("exceptionReplyBg",&cl.doOpExcept).appendOnFinish(&cl.giveBack).autorelease.submit(defaultTask);
    }
    
    void remoteMainCall(string fName,in ubyte[] reqId, Unserializer u, SendResHandler sendRes)
    {
        switch(fName){
        case "proxyDesc":
            simpleReplyBg(sendRes,reqId,&proxyDescDumper);
            break;
        case "proxyName":
            simpleReplyBg(sendRes,reqId,proxyName());
            break;
        case "proxyObjUrl":
            simpleReplyBg(sendRes,reqId,proxyObjUrl());
            break;
        default:
            char[256] buf;
            auto appender=lGrowableArray!(char)(buf,0,GASharing.Local);
            dumper(&appender.appendArr)("unknown function ")(fName)(" ")(__FILE__)(" ");
            writeOut(&appender.appendArr,__LINE__);
            exceptionReplyBg(sendRes,reqId,appender.takeData());
        }
    }
}
/// utility method to call an rpc method returning void
void rpcManualVoidCallPUrl(T...)(ParsedUrl pUrl,T args){
    version(TrackRpc){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("will do rpcManualVoidCallPUrl with url ")(pUrl)("\n");
        });
    }
    Variant firstArg;
    static if (is(typeof(Variant(args[0])))){
        firstArg=Variant(args[0]);
    }
    void serialArgs(Serializer s){ s(args); }
    void unserialRes(Unserializer u){ };
    auto handler=ProtocolHandler.protocolForUrl(pUrl);
    if (handler.localUrl(pUrl)) {
        version(TrackRpc){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("will local call for url ")(pUrl)("\n");
            });
        }
        handler.doRpcCallLocal(pUrl,&serialArgs,&unserialRes,firstArg);
    } else {
        version(TrackRpc){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("will do remote call for url ")(pUrl)("\n");
            });
        }
        handler.doRpcCall(pUrl,&serialArgs,&unserialRes,firstArg);
    }
    version(TrackRpc){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("finished url ")(pUrl)("\n");
        });
    }
}
/// ditto
void rpcManualVoidCall(T...)(string url,T args){
    auto pUrl=ParsedUrl.parseUrl(url);
    rpcManualVoidCallPUrl(pUrl,args);
}
/// utility method to call a oneway method
void rpcManualOnewayCallPUrl(T...)(ParsedUrl pUrl,T args){
    Variant firstArg;
    static if (is(typeof(Variant(args[0])))){
        firstArg=Variant(args[0]);
    }
    void serialArgs(Serializer s){ s(args); }
    auto handler=ProtocolHandler.protocolForUrl(pUrl);
    handler.doRpcCall(pUrl,&serialArgs,cast(void delegate(Unserializer))null,firstArg);
    if (handler.localUrl(pUrl)) {
        handler.doRpcCallLocal(pUrl,&serialArgs,cast(void delegate(Unserializer))null,firstArg);
    } else {
        handler.doRpcCall(pUrl,&serialArgs,cast(void delegate(Unserializer))null,firstArg);
    }
}
/// ditto
void rpcManualOnewayCall(T...)(string url,T args){
    auto pUrl=ParsedUrl.parseUrl(url);
    rpcManualOnewayCallPUrl(pUrl,args);
}
/// utility method to call an rpc method that returns a value
void rpcManualResCallPUrl(U,T...)(out U res,ParsedUrl pUrl,T args){
    version(TrackRpc){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("will do rpcManualResCallPUrl with url ")(pUrl)("\n");
        });
    }
    Variant firstArg;
    static if (is(typeof(Variant(args[0])))){
        firstArg=Variant(args[0]);
    }
    void serialArgs(Serializer s){ s(args); }
    void unserialRes(Unserializer u){ u(res); };
    auto handler=ProtocolHandler.protocolForUrl(pUrl);
    if (handler.localUrl(pUrl)) {
        version(TrackRpc){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("will do local call for url ")(&pUrl.urlWriter)("\n");
            });
        }
        handler.doRpcCallLocal(pUrl,&serialArgs,&unserialRes,firstArg);
    } else {
        version(TrackRpc){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("will do remote call for url ")(&pUrl.urlWriter)("\n");
            });
        }
        handler.doRpcCall(pUrl,&serialArgs,&unserialRes,firstArg);
    }
    version(TrackRpc){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("did rpcManualResCallPUrl with url ")(&pUrl.urlWriter)("\n");
        });
    }
}
/// ditto
void rpcManualResCall(U,T...)(out U res,string url,T args){
    auto pUrl=ParsedUrl.parseUrl(url);
    rpcManualResCallPUrl(res,pUrl,args);
}
/// ditto
U rpcManualResCall1(U,T...)(string url,T args){
    U res;
    auto pUrl=ParsedUrl.parseUrl(url);
    rpcManualResCallPUrl(res,pUrl,args);
    return res;
}

/// handler that performs an Rpc call
alias void delegate(ParsedUrl url,void delegate(Serializer) serArgs,
    void delegate(Unserializer) unserRes,Variant firstArg) RpcCallHandler;

/// one can get a proxy for that object
interface Proxiable{
    /// returns the url to use to get a proxy to this object
    string proxyObjUrl();
}

/// a proxy of an object, exposes a partial interface, and communicate with the real
/// object behind the scenes
interface Proxy: Proxiable,Serializable{
    /// returns the call handler used by this proxy
    RpcCallHandler rpcCallHandler();
    //// sets the call handler
    void rpcCallHandler(RpcCallHandler);
    /// name (class) of the proxy
    string proxyName();
    /// sets the url of the object this proxy connects to
    void proxyObjUrl(string );
    /// returns the url of the object this proxy connects to
    /// (repeating it because it seems that overloading between interfaces doesn't work)
    string proxyObjUrl();
    /// parsed version of proxyObjUrl
    ParsedUrl proxyObjPUrl();
    /// if the target object is local
    bool proxyIsLocal();
    /// cast helper, casts the proxy to Object
    Object proxyObj();
    /// equality check (of proxies!!!)
    equals_t opEqual(Object);
    /// comparison check (of proxies!!!)
    int opCmp(Object);
}

interface LocalProxy {
    Object targetObj();
    void targetObj(Object);
    TaskI objTask();
    void objTask(TaskI);
}

/// basic implementation of a proxy
class BasicProxy: Proxy {
    string _proxyObjUrl;
    ParsedUrl _proxyObjPUrl;
    string _proxyName;
    RpcCallHandler _rpcCallHandler;

    string proxyName(){
        return _proxyName;
    }
    string proxyObjUrl(){
        return _proxyObjUrl;
    }
    void proxyObjUrl(string u){
        _proxyObjUrl=u;
        _proxyObjPUrl=ParsedUrl.parseUrl(u);
    }
    ParsedUrl proxyObjPUrl(){
        return _proxyObjPUrl;
    }
    bool proxyIsLocal(){
        return false;
    }
    RpcCallHandler rpcCallHandler(){
        return _rpcCallHandler;
    }
    void rpcCallHandler(RpcCallHandler c){
        _rpcCallHandler=c;
    }
    equals_t opEqual(Object o){
        if (auto p=cast(BasicProxy)o){
            if (p.proxyObjUrl == proxyObjUrl){
                return true;
            }
        }
        return false;
    }
    int opCmp(Object o){
        if (auto p=cast(BasicProxy)o){
            if (proxyObjUrl < p.proxyObjUrl){
                return -1;
            } else if (proxyObjUrl==p.proxyObjUrl){
                return 0;
            } else {
                return 1;
            }
        }
        return -2;
    }
    Object proxyObj(){
        return this;
    }
    this(){ }
    this(string name,string url){
        proxyObjUrl=url;
        _proxyName=name;
    }
    static __gshared ClassMetaInfo metaI;
    shared static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("blip.parallel.rpc.BasicProxy","a proxy base class");
        metaI.addFieldOfType!(string )("proxyObjUrl","url identifying the proxied object");
        metaI.addFieldOfType!(string )("proxyName","name identifying the class of the proxy object");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        s.field(metaI[0],_proxyObjUrl);
        string pName=proxyName();
        s.field(metaI[1],_proxyName);
    }
    void unserialize(Unserializer u){
        u.field(metaI[0],_proxyObjUrl);
        string pName;
        u.field(metaI[1],_proxyName);
    }
    Serializable preUnserialize(Unserializer s){
        return this;
    }
    Serializable postUnserialize(Unserializer s){
        return ProtocolHandler.proxyForUrl(_proxyObjUrl,_proxyName);
    }
    
    mixin printOut!();
}

/// object that publishes other objects
class Publisher{
    enum Flags{
        None=0,
        Public,
    }
    struct PublishedObject{
        int flags;
        ObjVendorI obj;
    }

    HashMap!(string ,PublishedObject) objects;
    UniqueNumber!(int) idNr;
    ProtocolHandler protocol;
    scope CharSink log;
    string namespace;
    
    this(ProtocolHandler pH,string namespace="obj"){
        this.protocol=pH;
        this.log=pH.log;
        this.namespace=namespace;
        this.objects=new HashMap!(string ,PublishedObject)();
        this.idNr=UniqueNumber!(int)(3);
        if (log==null){
            this.log=serr.call;
        }
    }
    
    PublishedObject publishedObjectNamed(string name){
        PublishedObject po;
        synchronized(this){
            auto o=name in objects;
            if (o !is null){
                po=*o;
            }
        }
        return po;
    }
    ObjVendorI objectNamed(string name){
        PublishedObject po=publishedObjectNamed(name);
        return po.obj;
    }
    string proxyObjUrl(string objName){
        return collectIAppender(delegate void(scope CharSink s){
            dumper(s)(protocol.handlerUrl())("/")(namespace)("/")(objName);
        });
    }
    void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes)
    {
        char[256] buf;
        if (url.path.length<3){
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Warning: ignoring invalid request ")(url)("\n");
            });
            protocol.sysError(url,"invalid request",sendRes,__FILE__,__LINE__);
            return;
        }
        string objName=url.path[1];
        string fName=url.path[2];
        immutable(ubyte)[]requestId=urlDecode(url.anchor);
        auto o=objectNamed(objName);
        if (o is null){
            Log.lookup ("blip.rpc").warn("missing {}",url.url(buf));
            protocol.sysError(url,"missing object "~url.url(buf),sendRes,
                __FILE__,__LINE__);
            return;
        }
        o.remoteMainCall(fName,requestId,u,sendRes);
    }
    
    string publishObject(ObjVendorI obj, string name,bool makeUnique=false,Flags flags=Flags.Public){
        string myName=name;
        PublishedObject pObj;
        pObj.obj=obj;
        pObj.flags=flags;
        obj.publisher(this);
        while(1){
            synchronized(this){
                auto o=myName in objects;
                if (o) {
                    if (!makeUnique){
                        throw new RpcException("an object with name '"~name~"' is already published",
                            __FILE__,__LINE__);
                    }
                    myName=name~to!(string )(idNr.next());
                } else {
                    obj.objName(myName);
                    objects[myName]=pObj;
                    return myName;
                }
            }
        }
    }
    
    bool unpublishObject(string name){
        synchronized(this){
            bool res= (name in objects) !is null;
            objects.removeKey(name);
            return res;
        }
    }
}

/// handles failures of remote hosts
class FailureManager{
    alias RedBlack!(string ,void delegate(in cstring)) Node;
    Node* failureCallbacks;
    alias void delegate(in cstring baseUrl,bool delegate(in cstring)realFail) FailureHandler;
    Deque!(FailureHandler) failureHandlers;
    this(){
        failureHandlers=new Deque!(FailureHandler)();
    }
    /// register a url to be watched for failures
    void addFailureCallback(string url,void delegate(in cstring)failureOp){
        synchronized(this){
            if (failureCallbacks is null){
                failureCallbacks=new Node;
                failureCallbacks.value=url;
                failureCallbacks.attribute=failureOp;
            } else {
                auto t = failureCallbacks;
                auto newEl=new Node;
                newEl.value=url;
                newEl.attribute=failureOp;
                for (;;) {
                    int diff = cmp(url, t.value);
                    if (diff <= 0) {
                        if (t.left){
                            t = t.left;
                        } else {
                            t.insertLeft(newEl,failureCallbacks);
                            break;
                        }
                    } else {
                        if (t.right){
                            t = t.right;
                        } else {
                            failureCallbacks = t.insertRight (newEl, failureCallbacks);
                            break;
                        }
                    }
                }
            }
        }
    }
    void rmFailureCallback(string url,void delegate(in cstring)failureOp){
        synchronized(this){
            if (failureCallbacks is null){
                return;
            } else {
                auto t=failureCallbacks.find(url,function int(ref string a,ref string b){ return cmp(a,b); });
                if (t!is null){
                    if (t.attribute is failureOp){ // should use the callback to order same url?
                        auto tPrev=t.predecessor;
                        auto tNext=t.successor;
                        t.remove(failureCallbacks);
                        t=tPrev;
                        while(t!is null && t.value==url){ // should be empty
                            tPrev=t.predecessor;
                            if (t.attribute is failureOp){
                                t.remove(failureCallbacks);
                            }
                            t=tPrev;
                        }
                        t=tNext;
                        while(t!is null && t.value==url){
                            tNext=t.successor;
                            if (t.attribute is failureOp){
                                t.remove(failureCallbacks);
                            }
                            t=tNext;
                        }
                    }
                }
            }
        }
    }
    /// adds a failureHandler
    void addFailureHandler(FailureHandler fh){
        failureHandlers.pushBack(fh);
    }
    /// removes a failureHandler
    void rmFailureHandler(FailureHandler fh){
        failureHandlers.filterInPlace(delegate bool(FailureHandler f){ return f!is fh; });
    }
    /// notifies a failure of some url
    void notifyFailure(string baseUrl,bool delegate(in cstring)realFail){
        synchronized(this){
            if (failureCallbacks!is null){
                auto iter=failureCallbacks.findFirst(baseUrl,function int(ref string a,ref string b){ return cmp(a,b); },true);
                while(iter!is null){
                    string newK=iter.value;
                    if (newK.length>baseUrl.length) newK=newK[0..baseUrl.length];
                    if (newK>baseUrl) break;
                    auto next=iter.successor;
                    if (realFail(iter.value)){
                        iter.attribute(iter.value); // spawn this in a subtask?
                        iter.remove(failureCallbacks);
                    }
                    iter=next;
                }
            }
        }
        foreach(f;failureHandlers){
            f(baseUrl,realFail);
        }
    }
}

/// handles vending (and possibly also receiving the results if using one channel for both)
class ProtocolHandler{
    /// the default protocol handler (to vend objects)
    /// this defaults to StcpProtocol handler if included
    static __gshared ProtocolHandler defaultProtocol;
    scope CharSink log;
    // static part (move to a singleton?)
    
    alias ProtocolHandler function(ParsedUrl url) ProtocolGetter;
    /// those that can actually handle the given protocol
    static __gshared ProtocolGetter[string ] protocolHandlers;
    /// registers a handler for a given protocol
    static void registerProtocolHandler(string protocol,ProtocolGetter pH){
        assert((protocol in protocolHandlers)is null,"duplicate handler for protocol "~protocol);
        protocolHandlers[protocol]=pH;
    }
    /// returns the protocol handler for the given url
    static ProtocolHandler protocolForUrl(ParsedUrl url){
        if ((url.protocol in protocolHandlers) is null){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("no handler for protocol ")(url.protocol)("\n");
            });
        }
        auto pH=protocolHandlers[url.protocol];
        return pH(url);
    }
    
    /// internal proxy creators
    struct ProxyCreators{
        Proxy function(string name,string url) proxyCreator;
        Proxy function(string name,string url) localProxyCreator;
    }
    static __gshared ProxyCreators[string ] proxyCreators;
    static __gshared Mutex proxyCreatorsLock;
    FailureManager failureManager;
    
    shared static this(){
        proxyCreatorsLock=new Mutex();
        ProtocolHandler.registerProxy("blip.BasicProxy",function Proxy(string name,string url){ return new BasicProxy(name,url); });
    }
    /// registers an internal proxy creator
    static void registerProxy(string name,Proxy function(string name,string url) generate,
        Proxy function(string name,string url) generateLocal=null)
    {
        ProxyCreators pc;
        pc.proxyCreator=generate;
        pc.localProxyCreator=generateLocal;
        synchronized(proxyCreatorsLock){
            auto creator=name in proxyCreators;
            if (creator){
                throw new Exception("duplicate proxy registration for "~name,__FILE__,__LINE__);
            }
            proxyCreators[name]=pc;
        }
    }
    /// public method to get a proxy
    static Proxy proxyForUrl(string objectUrl,string proxyName=null){
        auto pUrl=ParsedUrl.parseUrl(objectUrl);
        auto handler=protocolForUrl(pUrl);
        assert(handler!is null,"unhandled protocol for url "~objectUrl);
        return handler.proxyForPUrl(pUrl,proxyName);
    }
    /// nicer to use method to get a prxy of the given type
    static T proxyForUrlT(T)(string objectUrl,string proxyName=null){
        auto p=proxyForUrl(objectUrl,proxyName);
        auto res=cast(T)cast(Object)p;
        if (res is null){
            throw new Exception("proxy "~objectUrl~" cannot be casted to "~T.stringof);
        }
        return res;
    }
    // dynamic part
    Publisher publisher;
    Publisher servPublisher;
    string _handlerUrl;
    
    this(scope CharSink log=null){
        this.log=log;
        if (log is null)
            this.log=serr.call;
        publisher=new Publisher(this);
        servPublisher=new Publisher(this,"serv");
        failureManager=new FailureManager();
    }
    
    // a function with no arguments returning a string 
    string simpleCall(ParsedUrl url){
        string res;
        doRpcCall(url,delegate void(Serializer){},
            delegate void(Unserializer u){ u(res); },Variant.init);
        return res;
    }
    
    string handlerUrl(){
        return _handlerUrl;
    }
    
    bool localUrl(ParsedUrl pUrl){
        return false;
    }    
    Proxy proxyForPUrl(ParsedUrl pUrl,string proxyName=null){
        if (proxyName.length==0){
            ParsedUrl pUrl2=pUrl;
            pUrl2.appendToPath("proxyName");
            proxyName=simpleCall(pUrl2);
        }
        ProxyCreators creator;
        synchronized(proxyCreatorsLock){
            auto creatorPtr=proxyName in ProtocolHandler.proxyCreators;
            if (creatorPtr is null){
                throw new RpcException("does not know how to create proxy '"~proxyName~"'",
                    __FILE__,__LINE__);
            }
            creator=*creatorPtr;
        }
        Proxy nP;
        char[256] buf;
        string objectUrl=pUrl.url(buf).idup; // avoidable?
        if (localUrl(pUrl) && creator.localProxyCreator !is null){
            nP=creator.localProxyCreator(proxyName,objectUrl);
            string objName=pUrl.path[1]; // kind of ugly
            auto lP=cast(LocalProxy)cast(Object)nP;
            auto vendor=publisher.objectNamed(objName.idup); // idup avoidable?
            assert(lP!is null,"local proxy is null");
            lP.targetObj=vendor.targetObj();
            lP.objTask=vendor.objTask();
        } else {
            nP=creator.proxyCreator(proxyName,objectUrl);
        }
        nP.rpcCallHandler=&this.doRpcCall;
        return nP;
    }
    
    void sysError(ParsedUrl url,string msg,SendResHandler sendRes, string file, long line){
        sendRes(cast(ubyte[])url.anchor,delegate void(Serializer s){
            s(3);
            s(msg~" "~file~":"~to!(string )(line)~" calling "~url.url);
        });
    }
    
    struct PendingRequest{
        Time start;
        /// should be called by the Unserializer task...
        void delegate(ParsedUrl url,Unserializer u) handleRequest;
    }
    PendingRequest[ubyte[]] pendingRequests;
    
    /// adds a pending request
    void addPendingRequest(in ubyte[]reqId,void delegate(ParsedUrl url,Unserializer u) handleRequest){
        PendingRequest pReq;
        pReq.start=Clock.now;
        pReq.handleRequest=handleRequest;
        synchronized(this){
            auto r=reqId in pendingRequests;
            if (r !is null){
                throw new RpcException("duplicate pending request "~urlEncode2(reqId).idup,__FILE__,__LINE__);
            }
            pendingRequests[reqId]=pReq;
        }
    }
    
    /// starts a server that handles the incoming requests
    /// if strict is false some parameters might be changed to allow starting up (for example the post number)
    void startServer(bool strict){
        assert(0,"unimplemented");
    }
    
    /// handles a non pending request, be very careful about sending back errors for this to avoid
    /// infinite messaging
    /// trying to skip the content of the request migth be a good idea
    void handleNonPendingRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        int reqKind;
        u(reqKind);
        switch(reqKind){
        case 0:
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Warning: received result for non pending request ")(&url.urlWriter)("\n");
            });
            return;
        case 1:
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Error: received result for non pending request, possible garbling ")(&url.urlWriter)("\n");
            });
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        case 2:
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Warning: ignoring exception for non pending request ")(&url.urlWriter)("\n");
            });
            return;
        case 3:
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Warning: ignoring system error in non pending request ")(&url.urlWriter)("\n");
            });
            return;
        default:
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Error: received unknow reqKind ")(reqKind)(" for non pending request, possible garbling ")(&url.urlWriter)("\n");
            });
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        }
    }
    
    void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        version(TrackRpc){
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)(taskAtt.val)("handling request ")(&url.urlWriter)("\n");
            });
        }
        if (url.path.length>0){
            switch(url.path[0]){
            case "obj":
                publisher.handleRequest(url,u,sendRes);
                break;
            case "serv":
                servPublisher.handleRequest(url,u,sendRes);
                break;
            case "req":
                PendingRequest req;
                bool error=false;
                synchronized(this){
                    auto reqPtr=urlDecode(url.anchor) in pendingRequests;
                    if (reqPtr is null) {
                        error=true;
                    } else {
                        req=*reqPtr;
                        pendingRequests.remove(urlDecode(url.anchor));
                    }
                }
                if (!error){
                    req.handleRequest(url,u);
                } else {
                    handleNonPendingRequest(url,u,sendRes);
                }
                break;
            default:
                sinkTogether(log,delegate void(scope CharSink s){
                    dumper(s)("Warning unknown namespace ")(url.path[0])(" in ")(url)("\n");
                });
                sysError(url,"unknown namespace",sendRes,__FILE__,__LINE__);
            }
        } else {
            sinkTogether(log,delegate void(scope CharSink s){
                dumper(s)("Warning no valid path in url ")(url)("\n");
            });
        }
    }
    /// rpc call to a potentially remote server
    void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,
        Variant firstArg){
        assert(0,"unimplemented");
    }
    /// local rpc call, oneway methods might *not* executed in background (change?)
    void doRpcCallLocal(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,
        Variant firstArg){
        doRpcCall(url,serArgs,unserRes,firstArg);
    }
}

