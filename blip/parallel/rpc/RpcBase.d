module blip.parallel.rpc.RpcBase;
import blip.parallel.smp.SmpModels;
import blip.serialization.StringSerialize;
import blip.serialization.Serialization;
import blip.parallel.smp.SmpModels;
import blip.t.util.log.Log;
import blip.sync.UniqueNumber;
import blip.t.time.Clock;
import blip.t.time.Time;
import blip.t.util.Convert;
import blip.container.GrowableArray;
import blip.BasicModels;
import blip.t.core.sync.Mutex;
import blip.io.BasicIO;

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
/// protocol:[//]host:port/path/path?query&qury#anchor
struct ParsedUrl{
    char[] protocol;
    char[] host;
    char[] port;
    char[][3] pathBuf;
    char[][] path;
    char[][] query;
    char[] anchor;
    void fullPathWriter(void delegate(char[])sink){
        foreach (p;path){
            sink("/");
            sink(p);
        }
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
    char[] url(char[]buf=null){
        return collectAppender(&urlWriter,buf);
    }
    char[] fullPath(char[]buf=null){
        return collectAppender(&fullPathWriter,buf);
    }
    void clearPath(){
        pathBuf[]=null;
        path=null;
        query=null;
        anchor=null;
    }
    void clearHost(){
        protocol=null;
        host=null;
        port=null;
    }
    void appendToPath(char[]segment){
        if (path.length<pathBuf.length){
            if (path.length!=0 && path.ptr!=pathBuf.ptr){
                foreach (i,p;path){
                    pathBuf[i]=p;
                }
            }
            pathBuf[path.length]=segment;
            path=pathBuf[0..(pathBuf.length+1)];
        } else {
            if (pathBuf.ptr==path.ptr){
                path=path~segment;
            } else {
                path~=segment;
            }
        }
    }
    void clear(){
        clearHost();
        clearPath();
    }
    static ParsedUrl parseUrl(char[] url){
        ParsedUrl res;
        if (res.parseUrlInternal(url)!=url.length){
            throw new RpcException("url parsing failed",__FILE__,__LINE__);
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
        return 3+parsePathInternal(url[j..$]);
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
    char[] urlOrPath(){
        if (url.length!=0){
            return url;
        } else {
            return fullPath;
        }
    }
}

/// at the moment just checks that no encoding is needed
/// actually reallocate and do the encoding?
char[] urlEncode(ubyte[]str,bool query=false){
    for(size_t i=0;i<str.length;++i){
        char c=cast(char)str[i];
        if ((c<'a' || c>'z')&&(c<'A' || c>'Z')&&(c<'-' || c>'9' || c=='/') && c!='_'){
            throw new Exception("only clean (not needing decoding) strings are supported (more efficient)",
                __FILE__,__LINE__);
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
    void proxyDesc(void delegate(char[]));
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
    
    void proxyDesc(void delegate(char[])s){
        s("char[] proxyDesc()\nchar[] proxyName()\nchar[]proxyObjUrl()\n");
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
    
    void remoteMainCall(char[] fName,ubyte[] reqId, Unserializer u, SendResHandler sendRes)
    {
        switch(fName){
        case "proxyDesc":
            simpleReply(sendRes,reqId,&proxyDesc);
            break;
        case "proxyName":
            simpleReply(sendRes,reqId,proxyName());
            break;
        case "proxyObjUrl":
            simpleReply(sendRes,reqId,proxyObjUrl());
            break;
        default:
            char[256] buf;
            auto appender=lGrowableArray!(char)(buf,0,GASharing.Local);
            dumper(&appender)("unknown function ")(fName)(" ")(__FILE__)(" ");
            writeOut(&appender.appendArr,__LINE__);
            exceptionReply(sendRes,reqId,appender.takeData());
        }
    }
    
    void simpleReply(T)(SendResHandler sendRes,ubyte[] reqId,T res)
    {
        sendRes(reqId,delegate void(Serializer s){
            static if (is(typeof(res)==void)){
                s(0);
            } else {
                s(1);
                s(res);
            }
        });
    }
    
    void exceptionReply(T)(SendResHandler sendRes,ubyte[] reqId,T exception)
    {
        sendRes(reqId,delegate void(Serializer s){
            s(2);
            s(collectAppender(outWriter(exception)));
        });
    }

}

/// handler that performs an Rpc call
alias void delegate(ParsedUrl url,void delegate(Serializer) serArgs,
    void delegate(Unserializer) unserRes) RpcCallHandler;

/// one can get a proxy for that object
interface Proxiable{
    char[] proxyObjUrl();
}

/// a proxy of an object, exposes a partial interface, and communicate with the real
/// object behind the scenes
interface Proxy: Proxiable,Serializable{
    RpcCallHandler rpcCallHandler();
    void rpcCallHandler(RpcCallHandler);
    char[]proxyName();
    void proxyObjUrl(char[]);
    char[] proxyObjUrl();
    ParsedUrl proxyObjPUrl();
    bool proxyIsLocal();
    equals_t opEqual(Object);
    int opCmp(Object);
}

/// basic implementation of a proxy
class BasicProxy:Proxy{
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
    static this(){
        ProtocolHandler.registerProxy(BasicProxy.mangleof,function Proxy(char[]name,char[]url){ return new BasicProxy(name,url); });
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

    PublishedObject[char[]] objects;
    UniqueNumber!(int) idNr;
    ProtocolHandler protocol;
    
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
    
    char[] publishObject(ObjVendorI obj, char[]name,Flags flags,bool makeUnique=false){
        char[] myName=name;
        PublishedObject pObj;
        pObj.obj=obj;
        pObj.flags=flags;
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
                    objects[myName]=pObj;
                    return myName;
                }
            }
        }
        return myName;
    }
    
    bool unpublishObject(char[]name){
        synchronized(this){
            bool res= (name in objects) !is null;
            objects.remove(name);
            return res;
        }
    }
}

/// handles vending (and possibly also receiving the results if using one channel for both)
class ProtocolHandler{
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
        assert(handler!is null);
        return handler.proxyForPUrl(pUrl,proxyName);
    }
    
    // dynamic part
    Publisher publisher;
    char[]_handlerUrl;
    
    this(){ }

    char[] simpleCall(ParsedUrl url){
        char[] res;
        doRpcCall(url,delegate void(Serializer){},
            delegate void(Unserializer u){ u(res); });
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
            proxyName=simpleCall(pUrl);
        }
        auto creator=proxyName in ProtocolHandler.proxyCreators;
        if (creator is null){
            throw new RpcException("does not know how to create proxy '"~proxyName~"'",
                __FILE__,__LINE__);
        }
        Proxy nP;
        char[256] buf;
        char[] objectUrl=pUrl.url(buf);
        if (localUrl(pUrl) && (*creator).localProxyCreator !is null){
            nP=(*creator).localProxyCreator(proxyName,objectUrl);
        } else {
            nP=(*creator).proxyCreator(proxyName,objectUrl);
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
                throw new RpcException("duplicate pending request "~urlEncode(reqId),__FILE__,__LINE__);
            }
            pendingRequests[reqId]=pReq;
        }
    }
    
    /// starts a server that handles the incoming requests
    void startServer(){
        assert(0,"unimplemented");
    }
    
    /// handles a non pending request, be very careful about sending back errors for this to avoid
    /// infinite messaging
    /// trying to skip the content of the request migth be a good idea
    void handleNonPendingRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
        int reqKind;
        u(reqKind);
        char[256] buf;
        switch(reqKind){
        case 0:
            Log.lookup ("blip.rpc").error("received result for non pending request {}",url.url(buf));
            return;
        case 1:
            Log.lookup ("blip.rpc").error("received result for non pending request, possible garbling {}",url.url(buf));
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        case 2:
            Log.lookup ("blip.rpc").warn("ignoring exception for non pending request {}",url.url(buf));
            return;
        case 3:
            Log.lookup ("blip.rpc").warn("ignoring system error in non pending request {}",url.url(buf));
            return;
        default:
            Log.lookup ("blip.rpc").error("received unknow reqKind {} for non pending request, possible garbling {}",reqKind,url.url(buf));
            throw new RpcException("received data for non pending request, possibly garbled receive stream",
                __FILE__,__LINE__);
        }
    }
    
    void handleRequest(ParsedUrl url,Unserializer u, SendResHandler sendRes){
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

    void doRpcCall(ParsedUrl url,void delegate(Serializer) serArgs, void delegate(Unserializer) unserRes){
        assert(0,"unimplemented");
    }
    
    char[] proxyObjUrl(char[] objectName){
        return handlerUrl()~"/obj/"~objectName;
    }
}
