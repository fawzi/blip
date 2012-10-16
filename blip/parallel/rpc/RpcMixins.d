/// mixins to vend (publish/export) and aquire an object
/// have to be mixed in in the class
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
module blip.parallel.rpc.RpcMixins;
public import blip.parallel.rpc.RpcBase;
public import blip.serialization.Serialization;
public import blip.container.Pool;
public import blip.container.Cache;
public import blip.core.sync.Mutex;
public import blip.core.Variant;
public import blip.parallel.smp.WorkManager;
public import blip.container.GrowableArray;
public import blip.io.BasicIO;
import blip.Comp;

/// main mixin, creates proxies (possibly also local) and vendor, called 'name~"Proxy"', 'name~"LocalProxy"',
/// 'name~"Vendor"', extName is used to build the serializer and proxy registration names, it defaults to
/// the mangleof.
string rpcMixin(string extName, string extraProxyInterfaces,string functions,bool localProxy=true,string name="Default"){
    assert(name.length>0,"name cannot be empty");
    auto functionsComments=extractFieldsAndDocs(functions);
    string res;
    res=rpcProxyMixin(name,extName,extraProxyInterfaces,functionsComments,localProxy);
    res~=rpcVendorMixin(name,extName,functionsComments);
    return res;
}

/// mixin definition for proxy objects
///
/// at the moment the local proxy is not strict (i.e. does not always spawn a task), this while faster
/// might introduce subtle changes (with respect to behaviour of the spawned subtasks, that might be non
/// finished when the function returns). Switch to always spawn??
string rpcProxyMixin(string name,string extName,string extraInterfaces,string [] functionsComments,
    bool localProxy=true)
{
    string extNameProxy;
    if (extName.length==0){
        extNameProxy=name~`Proxy.mangleof`;
    } else {
        extNameProxy=`"`~extName~`Proxy"`;
    }
    string res=`
    alias typeof(this) `~name~`ProxiedType;`;
    res~=`
    final static class `~name~`Proxy: BasicProxy`~((extraInterfaces.length!=0)?",":" ")~extraInterfaces~` {
        this(string name,string url){
            if (name.length==0)
                name=`~extNameProxy~`;
            super(name,url);
        }
        this(){
            this(`~extNameProxy~`,"");
        }
        `;
    res~=serializeSome(extNameProxy,"an rpc proxy","");
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        auto comment=functionsComments[2*ifield+1];
        bool oneway=false;
        if (comment.length>0 && comment[0]>' ' && comment[0]<'~'){
            if (comment.length>=6 && comment[0..6]=="oneway"){
                oneway=true;
            } else {
                assert(0,"invalid comment '"~comment~"' in "~extNameProxy);
            }
        }
        res~=`
        static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args==function)){
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return==return)){
                `~functionName~`Return `~functionName~`(`~functionName~`Args args){
                    ParsedUrl pUrl2=proxyObjPUrl();
                    pUrl2.appendToPath("`~functionName~`");
                    Variant firstArg;
                    static if (is(typeof(Variant(args[0])))){
                        firstArg=Variant(args[0]);
                    }
                    void serialArgs(Serializer s){ s(args); }
                    void delegate(Unserializer u) unserialRes;`;
        if (oneway){
            res~=`
                    static assert(is(`~functionName~`Return == void),"oneway in non void returning function "~`~extNameProxy~`~".`~functionName~`");`;
        } else {
            res~=`
                    static if (is(`~functionName~`Return == void)){
                        unserialRes=delegate void(Unserializer u){ };
                    } else {
                        `~functionName~`Return res;
                        unserialRes=delegate void(Unserializer u){
                            u(res);
                        };
                    }`;
        }
        res~=`
                    rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                    static if (! is(`~functionName~`Return == void)){
                        return res;
                    }
                }
            } else {
                static assert(0,"error getting return type for method "~`~extNameProxy~`~".`~functionName~`");
            }
        } else {
            static assert(0,"error getting arguments for method "~`~extNameProxy~`~".`~functionName~`");
        }`;
    }
    res~=`
    }
    `;
    if (localProxy){
        res~=`
    final static class `~name~`ProxyLocal: BasicProxy`~((extraInterfaces.length==0)?` `:`,`)~extraInterfaces~`,LocalProxy {
        `~name~`ProxiedType _targetObj;
        TaskI _objTask;
        Object targetObj(){
            return _targetObj;
        }
        void targetObj(Object obj){
            _targetObj=cast(`~name~`ProxiedType)obj;
        }
        TaskI objTask(){
            return _objTask;
        }
        void objTask(TaskI t){
            _objTask=t;
        }
        static struct OnewayClosure{
            void delegate() callClosureDelegate;
            PoolI!(OnewayClosure*) pool;
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
            } else {
                assert(comment.length==0,"invalid comment '"~comment~"'");
            }
            if (oneway){
                res~=`
                static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args==function)){
                
                    static struct `~functionName~`Clsr{
                        `~functionName~`Args args;
                        `~name~`ProxiedType obj;
                        void call(){
                            obj.`~functionName~`(args);
                        }
                    }
                    `~functionName~`Clsr `~functionName~`Closure;
                }`;
            }
        }
        res~=`
            }
            Cl closure;
            void giveBack(){
                if (pool!is null){
                    pool.giveBack(&this);
                } else {
                    destroy(this);
                }
            }
            static __gshared PoolI!(OnewayClosure*) gPool;
            static __gshared Mutex gLock;
            shared static this(){
                gLock=new Mutex();
            }
            static __gshared size_t gPoolLevel;
            static void addGPool(){
                synchronized(gLock){
                    if (gPoolLevel==0){
                        gPool=cachedPool(function OnewayClosure*(PoolI!(OnewayClosure*) p){
                            auto res=new OnewayClosure;
                            res.pool=p;
                            return res;
                        });
                    }
                    ++gPoolLevel;
                }
            }
            static void rmGPool(){
                synchronized(gLock){
                    if (gPoolLevel==0) throw new Exception("gPoolLevel is 0 in rmGPool for oneway method in "~`~extNameProxy~`,__FILE__,__LINE__);
                    --gPoolLevel;
                    if (gPoolLevel==0) {
                        gPool.rmUser();
                        gPool=null;
                    }
                }
            }
            static OnewayClosure *opCall(){
                assert(gPoolLevel>0,"opCall outside add/rmGPool in OnewayClosure of "~`~extNameProxy~`);
                return gPool.getObj();
            }
            void desc(scope void delegate(in char[]) s){
                s("blip.parallel.rpc.RpcMixins.OnewayClosure");
            }
        }
        this(string name,string url){
            OnewayClosure.addGPool();
            if (name=="")
                name=`~extNameProxy~`;
            super(name,url);
        }
        this(){
            this(`~extNameProxy~`,"");
        }
        ~this(){
            //OnewayClosure.rmGPool(); // forces rmGPool to be non blocking (no alloc lo lock aquire)
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
            } else {
                assert(comment.length==0,"invalid comment '"~comment~"'");
            }
            res~=`
        static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args==function)){
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return==return)){
                `~functionName~`Return `~functionName~`(`~functionName~`Args args){
                    auto obj=_targetObj;
                    if (obj is null){
                        throw new RpcException("vended object is null for "~`~extNameProxy~`~".`~functionName~`",__FILE__,__LINE__);
                    }`;
            if (oneway){
                res~=`
                    static assert(is(`~functionName~`Return==void),"oneway call on non void method `~name~`.`~functionName~`");
                    auto cl=OnewayClosure();
                    cl.closure.`~functionName~`Closure.obj=obj;
                    foreach (i,TT;`~functionName~`Args){
                        cl.closure.`~functionName~`Closure.args[i]=args[i];
                    }
                    cl.callClosureDelegate=&cl.closure.`~functionName~`Closure.call;
                    Task("onewayMethodCall`~name~`.`~functionName~`",cl.callClosureDelegate)
                        .appendOnFinish(&cl.giveBack).autorelease.submitYield(objTask);`;
            } else {
                res~=`
                    static if(is(`~functionName~`Return==void)){
                        obj.`~functionName~`(args);
                    } else {
                        return obj.`~functionName~`(args);
                    }`;
            }
            res~=`
                }
            }
        }
        `;
        }
        res~=`
        override bool proxyIsLocal(){ return true; }
    }
    shared static this(){
        ProtocolHandler.registerProxy(`~extNameProxy~`,
            function Proxy(string name,string url){ return new `~name~`Proxy(name,url); },
            function Proxy(string name,string url){ return new `~name~`ProxyLocal(name,url); });
    }`;
    } else {
        res~=`
        }
        shared static this(){
            ProtocolHandler.registerProxy(`~extNameProxy~`,
                function Proxy(string name,string url){ return new `~name~`Proxy(name,url); });
        }
        `;
    }
    return res;
}

string rpcVendorMixin(string name,string extName_, string [] functionsComments){
    string extNameProxy;
    if (extName_.length==0){
        extNameProxy=name~`Proxy.mangleof`;
    } else {
        extNameProxy=`"`~extName_~`Proxy"`;
    }
    string extName=`"`~extName_~`Vendor"`;
    if (extName_.length==0) {
        extName=name~`Vendor.mangleof`;
    }
    string res=`
    final static class `~name~`Vendor:BasicVendor{
        `~name~`ProxiedType obj;
        override `~name~`ProxiedType targetObj(){ return obj; }
        static struct Closure{
            void delegate() callClosureDelegate;
            PoolI!(Closure*) pool;
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
        res~=`
                static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args==function)){
                    static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return==return)){
                        struct `~functionName~`Clsr{
                            `~name~`Vendor context;
                            SendResHandler sendRes;
                            ubyte* reqIdPtr; size_t reqIdLen;
                            ubyte[64] reqIdBuf; // it would be better to move this to the end of the structure, but I don't feel like playing with forward refs...
                            ubyte[] reqId(){
                                if (reqIdPtr is null){ return reqIdBuf[0..reqIdLen]; }
                                return reqIdPtr[0..reqIdLen];
                            }
                            void reqId(ubyte[]v){
                                if (v.length<reqIdBuf.length){
                                    reqIdBuf[0..v.length]=v; reqIdPtr=null; reqIdLen=v.length;
                                } else {
                                    auto nV=v.dup; reqIdPtr=nV.ptr; reqIdLen=nV.length;
                                }
                            }
                            `~functionName~`Args args;
                            void call(){`;
        version(TrackRpc){
            res~=`
                                context.publisher.log("started real execution of rpc call "~`~extName~`~".`~functionName~`\n");
                                scope(exit){
                                    context.publisher.log("finished rpc call "~`~extName~`~".`~functionName~`\n");
                                }`;
        }
        if (oneway){
            res~=`
                                static assert(is(`~functionName~`Return==void),"non void return in oneway method "~`~extName~`~".`~functionName~`");
                                try{
                                    context.obj.`~functionName~`(args);
                                } catch (Exception e){ /+ communicate back?? +/
                                    sinkTogether(context.publisher.log,delegate void(scope CharSink s){
                                        dumper(s)("exception in oneway method ")(`~extName~`)(".`~functionName~`:")(e);
                                    });
                                }`;
    
        } else {
            res~=`
                                static if (is(`~functionName~`Return==void)){
                                    try{
                                        context.obj.`~functionName~`(args);
                                        context.simpleReply!()(sendRes,reqId);
                                    } catch (Exception o) {`;
            version(TrackRpc){
                res~=`
                                        context.publisher.log("sending back exception in rpc call "~`~extName~`~".`~functionName~`\n");`;
            }
            res~=`
                                        context.exceptionReply(sendRes,reqId,o);
                                        return;
                                    }
                                } else {
                                    try{
                                        auto res=context.obj.`~functionName~`(args);
                                        context.simpleReply(sendRes,reqId,res);`;
            version(TrackRpc){
                res~=`
                                        sinkTogether(context.publisher.log,delegate void(scope CharSink s){
                                            dumper(s)("sending back result in rpc call "~`~extName~`~".`~functionName~`, resVal:")(res)("\n");
                                        });`;
            }
            res~=`
                                    } catch(Exception o){`;
            version(TrackRpc){
                res~=`
                                            context.publisher.log("sending back exception in rpc call "~`~extName~`~".`~functionName~`\n");`;
            }
            res~=`
                                        context.exceptionReply(sendRes,reqId,o);
                                    }
                                }`;
        }
        res~=`
                            }
                        }
                        `~functionName~`Clsr `~functionName~`Closure;
                    }
                }`;
    }
    res~=`
            }
            Cl closure;
            void giveBack(){
                if (pool!is null){
                    pool.giveBack(&this);
                } else {
                    typeof(this) dummy;
                    this=dummy;
                    // delete this;
                }
            }
            static __gshared PoolI!(Closure*) gPool;
            static __gshared Mutex gLock;
            shared static this(){
                gLock=new Mutex();
            }
            static __gshared size_t gPoolLevel;
            static void addGPool(){
                synchronized(gLock){
                    if (gPoolLevel==0){
                        gPool=cachedPool(function Closure*(PoolI!(Closure*) p){
                            auto res=new Closure;
                            res.pool=p;
                            return res;
                        });
                    }
                    ++gPoolLevel;
                }
            }
            static void rmGPool(){
                synchronized(gLock){
                    if (gPoolLevel==0) throw new Exception("gPoolLevel is 0 in rmGPool for vendor "~`~extName~`,__FILE__,__LINE__);
                    --gPoolLevel;
                    if (gPoolLevel==0) {
                        gPool.rmUser();
                        gPool=null;
                    }
                }
            }
            static Closure *opCall(){
                assert(gPoolLevel>0,"opCall outside add/rmGPool in Closure of "~`~extName~`);
                return gPool.getObj();
            }
            void desc(scope void delegate(in char[]) s){
                s("blip.parallel.rpc.RpcMixin.Closure");
            }
        }
        
        this(){
            super(`~extNameProxy~`);
            Closure.addGPool();
        }
        this(`~name~`ProxiedType obj){
            super(`~extNameProxy~`); 
            Closure.addGPool();
            this.obj=obj;
        }
        ~this(){
            // Closure.rmGPool();
        }
        
        override void proxyDescDumper(scope void delegate(in cstring)s){
            super.proxyDescDumper(s);`;
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
            static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Args==function)){
                static if (is(typeof(`~name~`ProxiedType.`~functionName~`) `~functionName~`Return==return)){`;
        if (oneway){
            res~=`
                    s("oneway ");`;
        }
        res~=`
                    s(`~functionName~`Return.stringof);
                    s("`~functionName~`");
                    s("(");
                    s(`~functionName~`Args.stringof);
                    s(")\n");
                } else { static assert(0,"could not extract function return for "~`~extName~`~".`~functionName~`"); }
            } else { static assert(0,"could not extract function arguments for "~`~extName~`~".`~functionName~`"); }`;
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
        void remoteCall`~functionName~`(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
            version(TrackRpc){
                publisher.log("starting rpc call "~`~extName~`~".`~functionName~`\n");
            }
            auto cl0=Closure();
            auto cl= & cl0.closure.`~functionName~`Closure;
            try {
                cl.context=this;
                cl.reqId=reqId;
                cl.sendRes=sendRes;
                u(cl.args);
                cl0.callClosureDelegate=&cl.call;
            } catch (Exception o){
                version(TrackRpc){
                    publisher.log("exception deserializing rpc call `~name~`.`~functionName~`\n");
                }
                exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~`~extName~`~"`~functionName~`",__FILE__,__LINE__,o));
            }
            try{
                Task("rpcCall`~functionName~`",cl0.callClosureDelegate)
                    .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
            } catch (Throwable o){
                sinkTogether(publisher.log,delegate void(scope CharSink s){
                    dumper(s)("internal exception in method ")(`~extName~`)(".`~functionName~`:")(o);
                });
            }
        }`;
    }
    res~=`
        void remoteMainCall(string fName,ubyte[] reqId, Unserializer u, SendResHandler sendRes){
            switch(fName){`;
    for (int ifield=0;ifield<functionsComments.length/2;++ifield){
        auto functionName=functionsComments[2*ifield];
        res~=`
            case "`~functionName~`":
                remoteCall`~functionName~`(reqId,u,sendRes);
                break;`;
    }
    res~=`
            default:
                super.remoteMainCall(fName,reqId,u,sendRes);
            }
        }
    }`;
    return res;
}

