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

alias void delegate(ubyte[] reqId,void delegate(Serializer) sRes) SendResHandler;

class RpcException:Exception{
    this(char[]msg,char[]file,long line){
        super(msg,file,line);
    }
    this(void delegate(void delegate(char[]))msg,char[]file,long line){
        super(collectAppender(msg),file,line);
    }
}

/// urls have the following form: protocol://host:port/namespace/object/function#requestId?query
/// paths skip the protocol://host:port part
/// represent an url parsed in its components
/// protocol:[//]host:port/path/path?query&query#anchor
struct ParsedUrl{
    char[] protocol;
    char[] host;
    char[] port;
    char[][4] pathBuf; // this is a hack for efficient appending to small paths
    char[]* pathPtr;   // and still be able to copy the structure...
    size_t pathLen;    //
    char[][] query;
    char[] anchor;
    void fullPathWriter(void delegate(char[])sink){
        foreach (p;path){
            sink("/");
            sink(p);
        }
    }
    char[][] path(){
        if (pathPtr is null){
            return pathBuf[0..pathLen];
        }
        return pathPtr[0..pathLen];
    }
    void path(char[][]p){
        pathPtr=p.ptr;
        pathLen=p.length;
    }
    void urlWriter(void delegate(char[])sink){
        sink(protocol);
        sink("://");
        sink(host);
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
    void pathAndRestWriter(void delegate(char[])sink){
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
    char[] url(char[]buf=null){
        return collectAppender(&this.urlWriter,buf);
    }
    char[] fullPath(char[]buf=null){
        return collectAppender(&this.fullPathWriter,buf);
    }
    char[] pathAndRest(char[]buf=null){
        return collectAppender(&this.pathAndRestWriter,buf);
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
    void appendToPath(char[]segment){
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
    static ParsedUrl parseUrl(char[] url){
        ParsedUrl res;
        auto len=res.parseUrlInternal(url);
        if (len!=url.length){
            throw new RpcException(collectAppender(delegate void(CharSink s){
                dumper(s)("url parsing failed:")(len)("vs")(url.length)(", '")(&res.urlWriter)("' vs '")(url)("'");
            }),__FILE__,__LINE__);
        }
        return res;
    }
    static ParsedUrl parsePath(char[] path){
        ParsedUrl res;
        if (res.parsePathInternal(path)!=path.length){
            throw new RpcException("path parsing failed",__FILE__,__LINE__);
        }
        return res;
    }
    size_t parseUrlInternal(char[] url){
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
        for (j=i;j<url.length;++j){
            if (url[j]=='/'||url[j]==':') break;
        }
        host=url[i..j];
        if (j==url.length) return j;
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
    
    size_t parsePathInternal(char[]fPath){
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
char[] urlEncode(ubyte[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=cast(char)str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_'){
            throw new Exception("only clean (not needing decoding) strings are supported, not '"~(cast(char[])str)~"' (more efficient)",
                __FILE__,__LINE__);
        }
    }
    return cast(char[])str;
}
/// safe encoding, never raises (switches to '' delimited hex encoding)
char[] urlEncode2(ubyte[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=cast(char)str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_'){
            return collectAppender(delegate void(CharSink s){
                dumper(s)("'")(str)("'");
            });
        }
    }
    return cast(char[])str;
}

/// ditto
ubyte[] urlDecode(char[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_'){
            throw new Exception("only clean (not needing decoding) strings are supported (more efficient)",
                __FILE__,__LINE__);
        }
    }
    return cast(ubyte[])str;
}

/// an objects that can be published (typically publishes another object)
interface ObjVendorI{
    Object targetObj();
    void proxyDescDumper(void delegate(char[]));
    char[] proxyDesc();
    char[] proxyName();
    char[] objName();
    void objName(char[] newVal);
    char[] proxyObjUrl();
    Publisher publisher();
    void publisher(Publisher newP);
    TaskI objTask();
    void objTask(TaskI task);
    void remoteMainCall(char[] functionName,ubyte[] requestId, Unserializer u, SendResHandler sendRes);
}

class BasicVendor:ObjVendorI{
    char[] _proxyName;
    char[] _objName;
    Publisher _publisher;
    TaskI _objTask;
    
    this(char[] pName=""){
        _proxyName=pName;
        _objTask=defaultTask;
    }
    
    Object targetObj(){
        return this;
    }
    void proxyDescDumper(void delegate(char[])s){
        s("char[] proxyDesc()\nchar[] proxyName()\nchar[]proxyObjUrl()\n");
    }
    char[] proxyDesc(){
        return collectAppender(&proxyDescDumper);
    }
    char[] proxyName(){
        return _proxyName;
    }
    char[] proxyObjUrl(){
        return publisher.protocol.proxyObjUrl(_objName);
    }
    char[] objName(){
        return _objName;
    }
    void objName(char[] newVal){
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
    void simpleReply()(SendResHandler sendRes,ubyte[] reqId)
    {
        sendRes(reqId,delegate void(Serializer s){
            s(0);
        });
    }
    /// returns res, this should *not* be executed in the unserialization task
    void simpleReply(T)(SendResHandler sendRes,ubyte[] reqId,T res)
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
    void exceptionReply(T)(SendResHandler sendRes,ubyte[] reqId,T exception)
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
        static PoolI!(SimpleReplyClosure*) gPool;
        ubyte[] reqId(){
            if (reqIdPtr is null){
                return reqIdBuf[0..reqIdLen];
            }
            return reqIdPtr[0..reqIdLen];
        }
        void reqId(ubyte[]v){
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
        static this(){
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
                pool.giveBack(this);
            } else {
                delete(this); // be more tolerant?
            }
        }
    }
    /// helper to more easily create closures of simpleReply
    SimpleReplyClosure!(T) *simpleReplyClosure(T)(SendResHandler sendRes,ubyte[] reqId,T res){
        auto r=SimpleReplyClosure!(T).gPool.getObj();
        r.sendRes=sendRes;
        r.reqId=reqId;
        r.res=res;
        r.obj=this;
        return r;
    }
    /// performs simpleReply in another task (detached)
    void simpleReplyBg(T)(SendResHandler sendRes,ubyte[] reqId,T res){
        auto cl=simpleReplyClosure(sendRes,reqId,res);
        Task("simpleReplyBg",&cl.doOp).appendOnFinish(&cl.giveBack).autorelease.submit(defaultTask);
    }
    /// performs exceptionReply in another task (detached)
    void exceptionReplyBg(T)(SendResHandler sendRes,ubyte[] reqId,T res){
        auto cl=simpleReplyClosure(sendRes,reqId,res);
        Task("exceptionReplyBg",&cl.doOpExcept).appendOnFinish(&cl.giveBack).autorelease.submit(defaultTask);
    }
    
    void remoteMainCall(char[] fName,ubyte[] reqId, Unserializer u, SendResHandler sendRes)
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
            dumper(&appender)("unknown function ")(fName)(" ")(__FILE__)(" ");
            writeOut(&appender.appendArr,__LINE__);
            exceptionReplyBg(sendRes,reqId,appender.takeData());
        }
    }
    
}

/// handler that performs an Rpc call
alias void delegate(ParsedUrl url,void delegate(Serializer) serArgs,
    void delegate(Unserializer) unserRes,Variant firstArg) RpcCallHandler;

/// one can get a proxy for that object
interface Proxiable{
    /// returns the url to use to get a proxy to this object
    char[] proxyObjUrl();
}

/// a proxy of an object, exposes a partial interface, and communicate with the real
/// object behind the scenes
interface Proxy: Proxiable,Serializable{
    /// returns the call handler used by this proxy
    RpcCallHandler rpcCallHandler();
    //// sets the call handler
    void rpcCallHandler(RpcCallHandler);
    /// name (class) of the proxy
    char[]proxyName();
    /// sets the url of the object this proxy connects to
    void proxyObjUrl(char[]);
    /// returns the url of the object this proxy connects to
    /// (repeating it because it seems that overloading between interfaces doesn't work)
    char[] proxyObjUrl();
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
    char[] _proxyObjUrl;
    ParsedUrl _proxyObjPUrl;
    char[] _proxyName;
    RpcCallHandler _rpcCallHandler;

    char[]proxyName(){
        return _proxyName;
    }
    char[] proxyObjUrl(){
        return _proxyObjUrl;
    }
    void proxyObjUrl(char[]u){
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
    this(char[]name,char[]url){
        proxyObjUrl=url;
        _proxyName=name;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("blip.parallel.rpc.BasicProxy");
        metaI.addFieldOfType!(char[])("proxyObjUrl","url identifying the proxied object");
        metaI.addFieldOfType!(char[])("proxyName","name identifying the class of the proxy object");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        s.field(metaI[0],_proxyObjUrl);
        char[] pName=proxyName();
        s.field(metaI[1],_proxyName);
    }
    void unserialize(Unserializer u){
        u.field(metaI[0],_proxyObjUrl);
        char[] pName;
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

    HashMap!(char[],PublishedObject) objects;
    UniqueNumber!(int) idNr;
    ProtocolHandler protocol;
    CharSink log;
    
    this(ProtocolHandler pH){
        this.protocol=pH;
        this.log=pH.log;
        this.objects=new HashMap!(char[],PublishedObject)();
        this.idNr=UniqueNumber!(int)(3);
        if (log==null){
            this.log=serr.call;
        }
    }
    
    PublishedObject publishedObjectNamed(char[]name){
        PublishedObject po;
        synchronized(this){
            auto o=name in objects;
            if (o !is null){
                po=*o;
            }
        }
        return po;
    }
    ObjVendorI objectNamed(char[]name){
        PublishedObject po=publishedObjectNamed(name);
        return po.obj;
    }
    
    void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes)
    {
        char[256] buf;
        if (url.path.length<3){
            Log.lookup ("blip.rpc").warn("ignoring invalid request {}",url.url(buf));
            protocol.sysError(url,"invalid request",sendRes,__FILE__,__LINE__);
            return;
        }
        char[]objName=url.path[1];
        char[]fName=url.path[2];
        ubyte[]requestId=urlDecode(url.anchor);
        auto o=objectNamed(objName);
        if (o is null){
            Log.lookup ("blip.rpc").warn("missing {}",url.url(buf));
            protocol.sysError(url,"missing object "~url.url(buf),sendRes,
                __FILE__,__LINE__);
            return;
        }
        o.remoteMainCall(fName,requestId,u,sendRes);
    }
    
    char[] publishObject(ObjVendorI obj, char[]name,Flags flags=Flags.Public,bool makeUnique=false){
        char[] myName=name;
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
                    myName=name~to!(char[])(idNr.next());
                } else {
                    obj.objName(myName);
                    objects[myName]=pObj;
                    return myName;
                }
            }
        }
    }
    
    bool unpublishObject(char[]name){
        synchronized(this){
            bool res= (name in objects) !is null;
            objects.removeKey(name);
            return res;
        }
    }
}

/// handles vending (and possibly also receiving the results if using one channel for both)
class ProtocolHandler{
    CharSink log;
    // static part (move to a singleton?)
    
    alias ProtocolHandler function(ParsedUrl url) ProtocolGetter;
    /// those that can actually handle the given protocol
    static ProtocolGetter[char[]] protocolHandlers;
    /// registers a handler for a given protocol
    static void registerProtocolHandler(char[] protocol,ProtocolGetter pH){
        assert((protocol in protocolHandlers)is null,"duplicate handler for protocol "~protocol);
        protocolHandlers[protocol]=pH;
    }
    /// returns the protocol handler for the given url
    static ProtocolHandler protocolForUrl(ParsedUrl url){
        auto pH=protocolHandlers[url.protocol];
        return pH(url);
    }
    
    /// internal proxy creators
    struct ProxyCreators{
        Proxy function(char[]name,char[]url) proxyCreator;
        Proxy function(char[]name,char[]url) localProxyCreator;
    }
    static ProxyCreators[char[]] proxyCreators;
    static Mutex proxyCreatorsLock;
    static this(){
        proxyCreatorsLock=new Mutex();
        ProtocolHandler.registerProxy("blip.BasicProxy",function Proxy(char[]name,char[]url){ return new BasicProxy(name,url); });
    }
    /// registers an internal proxy creator
    static void registerProxy(char[] name,Proxy function(char[]name,char[]url) generate,
        Proxy function(char[]name,char[]url) generateLocal=null)
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
    static Proxy proxyForUrl(char[]objectUrl,char[]proxyName=null){
        auto pUrl=ParsedUrl.parseUrl(objectUrl);
        auto handler=protocolForUrl(pUrl);
        assert(handler!is null,"unhandled protocol for url "~objectUrl);
        return handler.proxyForPUrl(pUrl,proxyName);
    }
    /// nicer to use method to get a prxy of the given type
    static T proxyForUrlT(T)(char[]objectUrl,char[]proxyName=null){
        auto p=proxyForUrl(objectUrl,proxyName);
        auto res=cast(T)cast(Object)p;
        if (res is null){
            throw new Exception("proxy "~objectUrl~" cannot be casted to "~T.stringof);
        }
        return res;
    }
    // dynamic part
    Publisher publisher;
    char[]_handlerUrl;
    
    this(CharSink log=null){
        this.log=log;
        if (log is null)
            this.log=serr.call;
        publisher=new Publisher(this);
    }
    
    // a function with no arguments returning a char[]
    char[] simpleCall(ParsedUrl url){
        char[] res;
        doRpcCall(url,delegate void(Serializer){},
            delegate void(Unserializer u){ u(res); },Variant.init);
        return res;
    }
    
    char[] handlerUrl(){
        return _handlerUrl;
    }
    
    bool localUrl(ParsedUrl pUrl){
        return false;
    }    
    Proxy proxyForPUrl(ParsedUrl pUrl,char[]proxyName=null){
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
        char[] objectUrl=(pUrl.url(buf)).dup;
        if (localUrl(pUrl) && creator.localProxyCreator !is null){
            nP=creator.localProxyCreator(proxyName,objectUrl);
            char[]objName=pUrl.path[1]; // kind of ugly
            auto lP=cast(LocalProxy)cast(Object)nP;
            auto vendor=publisher.objectNamed(objName.dup);
            assert(lP!is null,"local proxy is null");
            lP.targetObj=vendor.targetObj();
            lP.objTask=vendor.objTask();
        } else {
            nP=creator.proxyCreator(proxyName,objectUrl);
        }
        nP.rpcCallHandler=&this.doRpcCall;
        return nP;
    }
    
    void sysError(ParsedUrl url,char[] msg,SendResHandler sendRes, char[] file, long line){
        sendRes(cast(ubyte[])url.anchor,delegate void(Serializer s){
            s(3);
            s(msg~" "~file~":"~to!(char[])(line)~" calling "~url.url);
        });
    }
    
    struct PendingRequest{
        Time start;
        /// should be called by the Unserializer task...
        void delegate(ParsedUrl url,Unserializer u) handleRequest;
    }
    PendingRequest[ubyte[]] pendingRequests;
    
    /// adds a pending request
    void addPendingRequest(ubyte[]reqId,void delegate(ParsedUrl url,Unserializer u) handleRequest){
        PendingRequest pReq;
        pReq.start=Clock.now;
        pReq.handleRequest=handleRequest;
        synchronized(this){
            auto r=reqId in pendingRequests;
            if (r !is null){
                throw new RpcException("duplicate pending request "~urlEncode2(reqId),__FILE__,__LINE__);
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
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("Warning: received result for non pending request ")(&url.urlWriter)("\n");
            });
            return;
        case 1:
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("Error: received result for non pending request, possible garbling ")(&url.urlWriter)("\n");
            });
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        case 2:
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("Warning: ignoring exception for non pending request ")(&url.urlWriter)("\n");
            });
            return;
        case 3:
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("Warning: ignoring system error in non pending request ")(&url.urlWriter)("\n");
            });
            return;
        default:
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)("Error: received unknow reqKind ")(reqKind)(" for non pending request, possible garbling ")(&url.urlWriter)("\n");
            });
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        }
    }
    
    void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        version(TrackRpc){
            sinkTogether(log,delegate void(CharSink s){
                dumper(s)(taskAtt.val)("handling request ")(&url.urlWriter)("\n");
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
                Log.lookup ("blip.rpc").error("unknown namespace {} in {}",url.path[0],url.url());
                sysError(url,"unknown namespace",sendRes,__FILE__,__LINE__);
            }
        }
    }

    void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes,
        Variant firstArg){
        assert(0,"unimplemented");
    }
    
    char[] proxyObjUrl(char[] objectName){
        return handlerUrl()~"/obj/"~objectName;
    }
}
