/// mixins to vend (publish/export) and aquire an object
/// have to be mixed in in the class
module blip.parallel.rpc.RpcMixins;
import blip.serialization.SerializationMixins:extractFieldsAndDocs;
public import blip.t.util.log.Log;

/// main mixin, creates proxies (local and remote)
char[] rpcMixin(char[] name,char[] extraProxyInterfaces,char[]functions,bool localProxy=true){
    assert(name.length>0,"name cannot be empty");
    auto functionsComments=extractFieldsAndDocs(functions);
    char[] res;
    res=rpcProxyMixin(name,extraProxyInterfaces,functionsComments,localProxy);
    res~=rpcVendorMixin(name,functionsComments);
    return res;
}

/// mixin definition for proxy objects
char[] rpcProxyMixin(char[] name,char[] extraInterfaces,char[][] functionsComments,
    bool localProxy=true)
{
    char[] res=`
    alias typeof(this) `~name~`ProxiedType;`;
    res~=`
    static class `~name~`Proxy: `~extraInterfaces~` BasicProxy{
        this(char[]name,char[]url){
            if (name=="")
                name=`~name~`Proxy.mangleof;
            super(name,url);
        }
        this(){
            this(`~name~`Proxy.mangleof,"");
        }
        static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(this))(`~name~`Proxy.mangleof);
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        `;
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        auto comment=functionsComments[2*ifield+1];
        bool oneway=false;
        if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
            if (comment.length>=6 && comment[0..6]=="oneway"){
                oneway=true;
            } else {
                assert(0,"invalid comment '"~comment~"'");
            }
        }
        res~=`
        static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args=function)){
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return=return)){
                `~functionName~`Return `~functionName~`(`~functionName~`Args args){
                    _proxyCallbacks.doPreCall("`~functionName~`",`~(oneway?"true"[]:"false")~`,this);
                    scope(exit){
                        _proxyCallbacks.doPostCall("`~functionName~`",`~(oneway?"true"[]:"false")~`,this);
                    }
                    Task("proxySerializeArgs`~functionName~`",{
                        _proxyCallbacks.doPreSerialize("`~functionName~`",`~(oneway?"true"[]:"false")~`,serializer,this);
                        serializer(args);
                        _proxyCallbacks.doPostSerialize("`~functionName~`",`~(oneway?"true"[]:"false")~`,serializer,this);
                    }).autorelease.executeNow(sTask);`;
        if (oneway){
            res~=`
                    _proxyCallbacks.doDoCall("`~functionName~`",true,this);
                    }`;
        } else {
            res~=`
                    _proxyCallbacks.doDoCall("`~functionName~`",false,this);
                    `~functionName~`Return res;
                    char[] exceptionStr;
                    bool hadExceptions=false;
                    Task("unserializeResult`~functionName~`",{
                        try{
                            _proxyCallbacks.doPreUnserialize("`~functionName~`",false,serializer,unserializer,this);
                            scope(exit){
                                _proxyCallbacks.doPostUnserialize("`~functionName~`",false,serializer,unserializer,this);
                            }
                            int i;
                            unserializer(i);
                            switch(i){
                                case 2:
                                    static if (! is(T == void)){
                                        exceptionStr="invaild return type2";
                                        hadExceptions=true;
                                    } else {
                                        return;
                                    }
                                    break;
                                case 1:
                                    static if (is(T == void)){
                                        exceptionStr="invaild return type1";
                                        hadExceptions=true;
                                    } else {
                                        unserializer(res);
                                    }
                                    break;
                                case 0;
                                    unserializer(exceptionStr);
                                    hadExceptions=true;
                                    break;
                                default:
                                    exceptionStr="unexpected return type";
                                    hadExceptions=true;
                            }
                        } catch(Exception e){
                            exceptionStr="unserializing exception:"~e.toString();
                            hadExceptions=true;
                        }
                    }).autorelease.executeNow(ERROR!!!!unserializerTask);
                    if (hadExceptions){
                        throw new Exception(exceptionStr,__FILE__,__LINE__)
                    }
                    return res;
                    `;
        }
        res~=`
                }
            }
        }
        `;
    }
    res~=`
    }
    `;
    if (localProxy){
        res~=`
    static class `~name~`ProxyLocal:`~extraInterfaces~` BasicProxy{
        this(char[]name,char[]url){
            if (name=="")
                name=`~name~`Proxy.mangleof;
            super(name,url);
        }
        this(){
            this(`~name~`Proxy.mangleof,"");
        }
        static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(this))(`~name~`Proxy.mangleof);
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        `;
        for (int ifield=0;ifield<functionsComments.length/2;++ifield){
            auto functionName=functionsComments[2*ifield];
            auto comment=functionsComments[2*ifield+1];
            bool oneway=false;
            if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
                if (comment.length>=6 && comment[0..6]=="oneway"){
                    oneway=true;
                } else {
                    assert(0,"invalid comment '"~comment~"'");
                }
            }
            res~=`
        static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args=function)){
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return=return)){
                `~functionName~`Return `~functionName~`(`~functionName~`Args args){
                    _proxyCallbacks.doPreCall("`~functionName~`",`~(oneway?"true"[]:"false")~`,this);
                    scope(exit){
                        _proxyCallbacks.doPostCall("`~functionName~`",`~(oneway?"true"[]:"false")~`,this);
                    }
                    auto obj=publisher.objNamed(objName);
                    if (obj is null){
                        throw new RpcException()
                    }`;
            if (oneway){
                res~=`
                    try{
                        obj.`~functionName~`(args);
                    } catch(Object o){
                        Log.lookup ("blip.rpc").warn("exception during oneway call for `~functionName~` {}",o);
                    }`;
            } else {
                res~=`
                    obj.`~functionName~`(args);`;
            }
            res~=`
                }
            }
        }
        `;
        }
        res~=`
        override proxyIsLocal(){ return true; }
    }
    static this(){
        AquirerShop.registerProxy(`~name~`Proxy.mangleof,
            function Proxy(char[]name,char[]url){ return new `~name~`Proxy(name,url); },
            function Proxy(char[]name,char[]url){ return new `~name~`ProxyLocal(name,url); });
    }
    `;
    } else {
            res~=`
        }
        static this(){
            AquirerShop.registerProxy(`~name~`Proxy.mangleof,
                function Proxy(char[]name,char[]url){ return new `~name~`Proxy(name,url); });
        }
        `;
    }
    return res;
}

char[] rpcVendorMixin(char[] name, char[][] functionsComments){
    char[] res=`
    class `~name~`Vendor:BasicVendor{
        `~name~`ProxiedType obj;
        
        struct Closure{
            Closure *next;
            union Cl{`;
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        auto comment=functionsComments[2*ifield+1];
        bool oneway=false;
        if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
            if (comment.length>=6 && comment[0..6]=="oneway"){
                oneway=true;
            } else {
                assert(0,"invalid comment '"~comment~"'");
            }
        }
        char[] onewayStr=(oneway?"true":"false");
        res~=`
                static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args=function)){
                    struct Closure`~functionName~`{
                        Closure *top;
                        `~name~`Vendor context;
                        TaskI sTask;
                        Serializer serializer;
                        bool oneway;
                        `~functionName~`Args args;
                        void call(){
                            scope(exit){
                                try{
                                    context._vendorCallbacks.doPostCall("`~functionName~`",reqId,`~onewayStr~`,context,this);
                                    Closure *topAtt=top;
                                    `~name~`Vendor contextAtt=context;
                                    memset(this.`~functionName~`,0,closure.`~functionName~`.sizeof);
                                    memBarrier!(false,false,false,true)(); /+ not really needed +/
                                    insertAt(contextAtt.freeList,topAtt);
                                } catch(Object o){
                                    Log.lookup ("blip.rpc").warn("exception in post ops of `~functionName~`:{}",o);
                                }
                            }
                            if (oneway){
                                try{
                                    context._vendorCallbacks.doPreCall("`~functionName~`",reqId,oneway,context,this);
                                    context.obj.`~functionName~`(args);
                                } catch (Exception e){
                                    Log.lookup("blip.rpc").warn("exception in oneway method `~functionName~`:{}",e);
                                } catch (Object o){
                                    Log.lookup("blip.rpc").warn("exception in oneway method `~functionName~`:{}",o);
                                }
                            } else {
                                `~functionName~`Return res;
                                try{
                                    context._vendorCallbacks.doPreCall("`~functionName~`",reqId,oneway,context,this);
                                    static if (is(typeof(res)==void)){
                                        context.obj.`~functionName~`(args);
                                    } else {
                                        res=obj.`~functionName~`(args);
                                    }
                                } catch (Object o) {
                                    context.exceptionReply("`~functionName~`",reqId,serializer,sTask,this,o);
                                }
                                static if (! is(typeof(res)==void)){
                                    try{
                                        context.simpleReply(T)(`~functionName~`,requestId, serializer,
                                            sTask,this,res);
                                    } catch(Object o){
                                        Log.lookup ("blip.rpc").warn("exception sending result of `~functionName~`:{}",o);
                                    }
                                }
                            }
                        }
                    }
                }
        
                Closure`~functionName~` `~functionName~`;`; 
    }
    
    res~=`
            }
            Cl cl;
        }
    
        Closure *freeList;
    
        override void proxyDesc(void delegate(char[])s){
            super.proxyDesc(s);`;
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        auto comment=functionsComments[2*ifield+1];
        bool oneway=false;
        if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
            if (comment.length>=6 && comment[0..6]=="oneway"){
                oneway=true;
            } else {
                assert(0,"invalid comment '"~comment~"'");
            }
        }
        res~=`
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args=function)){
                    static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return=return)){
                    if (oneway){
                        s("oneway ");
                    }
                    s(`~functionName~`Return.stringof);
                    s("`~functionName~`");
                    s(`~functionName~`Args.stringof);
                    s("\n");
                } else { static assert(0,"could not extract function return for `~functionName~`"); }
            } else { static assert(0,"could not extract function arguments for `~functionName~`"); }`;
    }
    res~=`
        }`;
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        auto comment=functionsComments[2*ifield+1];
        bool oneway=false;
        if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
            if (comment.length>=6 && comment[0..6]=="oneway"){
                oneway=true;
            } else {
                assert(0,"invalid comment '"~comment~"'");
            }
        }
        res~=`
        void remoteCall`~functionName~`(char[] reqId,Unserializer u,Serializer s,TaskI sTask){
            `~functionName~`Args args;
            auto closure=popFrom(freeList);
            if (closure is null){
                closure=new Closure;
            } else {
                volatile memoryBarrier!(true,false,false,false)(); /+ does the right thing in an if? +/
            }
            auto cl=&closure.cl.`~functionName~`;
            try {
                cl.top=closure;
                cl.context=this;
                cl.sTask=sTask;
                cl.serializer=serializer;
                cl.oneway=`~(oneway?"true"[]:"false"[])~`;
                _vendorCallbacks.doPreUnserialize("`~functionName~`",cl.oneway,unserializer,context,cast(void*)cl);
                u(cl.args);
                _vendorCallbacks.doPostUnserialize("`~functionName~`",cl.oneway,unserializer,context,cast(void*)cl);
            } catch (Object o){
                exceptionReply("`~functionName~`",reqId,serializer,serializerTask,cast(void*)cl,
                    "exception deserializing arguments for `~functionName~`:"~to!(char[])(o));
            }
            try{
                Task("rpcCall`~functionName~`",&cl.call).autorelease.submit(objTask);
            } catch (Object o){
                Log.lookup ("blip.rpc").error("internal exception making call for `~functionName~` {}",o);
            }
        }`;
    }
    res~=`
        void remoteMainCall(char[] functionName,char[]reqId,Unserializer u,Serializer s,TaskI sTask){
            assert(0,"unimplemented for local proxies");
        }
    }
    `;
    return res;
}

