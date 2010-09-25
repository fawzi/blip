/// tests of the remote procedure call part
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
module testRpc;
import blip.io.Console;
import blip.parallel.rpc.RpcBase;
import blip.parallel.rpc.RpcStcp;
import blip.parallel.rpc.RpcMixins;
import blip.stdc.stdlib;
import blip.time.RealtimeClock;
import blip.parallel.smp.WorkManager;
import blip.core.Thread;
import tango.core.Memory;
import Integer=tango.text.convert.Integer;
import tango.core.Tuple;

version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

class A{
    static A globalA;
    int iVal_=1;
    int iVal(){
        return iVal_;
    }
    void setIVal(int i){
        iVal_=i;
    }
    int b(double y){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("A.b is being called with ")(y)("\n");
        });
        return 5*cast(int)y;
    }
    double mult(double x,double y){
        return x*y;
    }
    double div(double x,double y){
        return x/y;
    }
    void notify(int i){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("A@")(cast(void*)this)(".notify(")(i)(")\n");
        });
    }
    void voidMethod(){
        sout("in voidMethod\n");
    }
    this(){}
    pragma(msg,rpcMixin("A","tst.A","","iVal|setIVal|b|mult|div|notify:oneway|voidMethod",true));
    //mixin(rpcMixin("A","tst.A","","b|mult|div|notify:oneway|voidMethod",true));
    ///__________
        alias typeof(this) AProxiedType;
        final static class AProxy:  BasicProxy{
            this(char[]name,char[]url){
                if (name.length==0)
                    name="tst.AProxy";
                super(name,url);
            }
            this(){
                this("tst.AProxy","");
            }
            static ClassMetaInfo metaI;
    static this(){
        static if (is(typeof(this) == class)){
            metaI=ClassMetaInfo.createForType!(typeof(this))(`"tst.AProxy"`);
        }else{
            metaI=ClassMetaInfo.createForType!(typeof(*this))(`"tst.AProxy"`);
        }
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serial(Ser)(Ser s){
        }

        static if (is(typeof(this)==class)) {
            alias typeof(super) SuperType;
            static if (!is(typeof(SuperType.init.preSerialize(Serializer.init)))) {
                void preSerialize(Serializer s){ }
            }
            static if (!is(typeof(SuperType.init.preUnserialize(Unserializer.init)))) {
                typeof(this) preUnserialize(Unserializer s){ return this; }
            }
            static if (!is(typeof(this.postSerialize(Serializer.init)))) {
                void postSerialize(Serializer s){ }
            }
            static if (!is(typeof(this.postUnserialize(Unserializer.init)))) {
                typeof(this) postUnserialize(Unserializer s){ return this; }
            }
            void serialize(Serializer s){
                static if (is(typeof(SuperType.init.serialize(s)))){
                    super.serialize(s);
                }
                serial(s);
            }
            void unserialize(Unserializer s){
                static if (is(typeof(SuperType.init.unserialize(s)))){
                    super.unserialize(s);
                }
                serial(s);
            }
        } else static if (is(typeof(*this) == struct)) {
            void serialize(Serializer s){
                serial(s);
            }
            void unserialize(Unserializer s){
                serial(s);
            }
        } else {
            static assert(0,"serialization supported only within classes or structs");
        }

            static if (is(typeof(AProxiedType.iVal) iValArgs==function)){
                static if (is(typeof(AProxiedType.iVal) iValReturn==return)){
                    iValReturn iVal(iValArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("iVal");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(iValReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            iValReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(iValReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".iVal");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".iVal");
            }
            static if (is(typeof(AProxiedType.setIVal) setIValArgs==function)){
                static if (is(typeof(AProxiedType.setIVal) setIValReturn==return)){
                    setIValReturn setIVal(setIValArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("setIVal");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(setIValReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            setIValReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(setIValReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".setIVal");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".setIVal");
            }
            static if (is(typeof(AProxiedType.b) bArgs==function)){
                static if (is(typeof(AProxiedType.b) bReturn==return)){
                    bReturn b(bArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("b");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(bReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            bReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(bReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".b");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".b");
            }
            static if (is(typeof(AProxiedType.mult) multArgs==function)){
                static if (is(typeof(AProxiedType.mult) multReturn==return)){
                    multReturn mult(multArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("mult");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(multReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            multReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(multReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".mult");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".mult");
            }
            static if (is(typeof(AProxiedType.div) divArgs==function)){
                static if (is(typeof(AProxiedType.div) divReturn==return)){
                    divReturn div(divArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("div");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(divReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            divReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(divReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".div");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".div");
            }
            static if (is(typeof(AProxiedType.notify) notifyArgs==function)){
                static if (is(typeof(AProxiedType.notify) notifyReturn==return)){
                    notifyReturn notify(notifyArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("notify");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static assert(is(notifyReturn == void),"oneway in non void returning function "~"tst.AProxy"~".notify");
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(notifyReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".notify");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".notify");
            }
            static if (is(typeof(AProxiedType.voidMethod) voidMethodArgs==function)){
                static if (is(typeof(AProxiedType.voidMethod) voidMethodReturn==return)){
                    voidMethodReturn voidMethod(voidMethodArgs args){
                        ParsedUrl pUrl2=proxyObjPUrl();
                        pUrl2.appendToPath("voidMethod");
                        Variant firstArg;
                        static if (is(typeof(Variant(args[0])))){
                            firstArg=Variant(args[0]);
                        }
                        void serialArgs(Serializer s){ s(args); }
                        void delegate(Unserializer u) unserialRes;
                        static if (is(voidMethodReturn == void)){
                            unserialRes=delegate void(Unserializer u){ };
                        } else {
                            voidMethodReturn res;
                            unserialRes=delegate void(Unserializer u){
                                u(res);
                            };
                        }
                        rpcCallHandler()(pUrl2,&serialArgs,unserialRes,firstArg);
                        static if (! is(voidMethodReturn == void)){
                            return res;
                        }
                    }
                } else {
                    static assert(0,"error getting return type for method "~"tst.AProxy"~".voidMethod");
                }
            } else {
                static assert(0,"error getting arguments for method "~"tst.AProxy"~".voidMethod");
            }
        }

        final static class AProxyLocal: BasicProxy,LocalProxy{
            AProxiedType _targetObj;
            TaskI _objTask;
            Object targetObj(){
                return _targetObj;
            }
            void targetObj(Object obj){
                _targetObj=cast(AProxiedType)obj;
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
                union Cl{
                    static if (is(typeof(AProxiedType.notify) notifyArgs==function)){

                        static struct notifyClsr{
                            notifyArgs args;
                            AProxiedType obj;
                            void call(){
                                obj.notify(args);
                            }
                        }
                        notifyClsr notifyClosure;
                    }
                }
                Cl closure;
                void giveBack(){
                    if (pool!is null){
                        pool.giveBack(this);
                    } else {
                        delete this;
                    }
                }
                static PoolI!(OnewayClosure*) gPool;
                static Mutex gLock;
                static this(){
                    gLock=new Mutex();
                }
                static size_t gPoolLevel;
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
                        if (gPoolLevel==0) throw new Exception("gPoolLevel is 0 in rmGPool for oneway method in "~"tst.AProxy",__FILE__,__LINE__);
                        --gPoolLevel;
                        if (gPoolLevel==0) {
                            gPool.rmUser();
                            gPool=null;
                        }
                    }
                }
                static OnewayClosure *opCall(){
                    assert(gPoolLevel>0,"opCall outside add/rmGPool in OnewayClosure of "~"tst.AProxy");
                    return gPool.getObj();
                }
            }
            this(char[]name,char[]url){
                OnewayClosure.addGPool();
                if (name=="")
                    name="tst.AProxy";
                super(name,url);
            }
            this(){
                this("tst.AProxy","");
            }
            ~this(){
                OnewayClosure.rmGPool();
            }
            static if (is(typeof(AProxiedType.iVal) iValArgs==function)){
                static if (is(typeof(AProxiedType.iVal) iValReturn==return)){
                    iValReturn iVal(iValArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".iVal",__FILE__,__LINE__);
                        }
                        static if(is(iValReturn==void)){
                            obj.iVal(args);
                        } else {
                            return obj.iVal(args);
                        }
                    }
                }
            }

            static if (is(typeof(AProxiedType.setIVal) setIValArgs==function)){
                static if (is(typeof(AProxiedType.setIVal) setIValReturn==return)){
                    setIValReturn setIVal(setIValArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".setIVal",__FILE__,__LINE__);
                        }
                        static if(is(setIValReturn==void)){
                            obj.setIVal(args);
                        } else {
                            return obj.setIVal(args);
                        }
                    }
                }
            }

            static if (is(typeof(AProxiedType.b) bArgs==function)){
                static if (is(typeof(AProxiedType.b) bReturn==return)){
                    bReturn b(bArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".b",__FILE__,__LINE__);
                        }
                        static if(is(bReturn==void)){
                            obj.b(args);
                        } else {
                            return obj.b(args);
                        }
                    }
                }
            }

            static if (is(typeof(AProxiedType.mult) multArgs==function)){
                static if (is(typeof(AProxiedType.mult) multReturn==return)){
                    multReturn mult(multArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".mult",__FILE__,__LINE__);
                        }
                        static if(is(multReturn==void)){
                            obj.mult(args);
                        } else {
                            return obj.mult(args);
                        }
                    }
                }
            }

            static if (is(typeof(AProxiedType.div) divArgs==function)){
                static if (is(typeof(AProxiedType.div) divReturn==return)){
                    divReturn div(divArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".div",__FILE__,__LINE__);
                        }
                        static if(is(divReturn==void)){
                            obj.div(args);
                        } else {
                            return obj.div(args);
                        }
                    }
                }
            }

            static if (is(typeof(AProxiedType.notify) notifyArgs==function)){
                static if (is(typeof(AProxiedType.notify) notifyReturn==return)){
                    notifyReturn notify(notifyArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".notify",__FILE__,__LINE__);
                        }
                        static assert(is(notifyReturn==void),"oneway call on non void method A.notify");
                        auto cl=OnewayClosure();
                        cl.closure.notifyClosure.obj=obj;
    		    foreach (i,TT;notifyArgs){
    			cl.closure.notifyClosure.args[i]=args[i];
    		    }
                        cl.callClosureDelegate=&cl.closure.notifyClosure.call;
                        Task("onewayMethodCallA.notify",cl.callClosureDelegate)
                            .appendOnFinish(&cl.giveBack).autorelease.submitYield(objTask);
                    }
                }
            }

            static if (is(typeof(AProxiedType.voidMethod) voidMethodArgs==function)){
                static if (is(typeof(AProxiedType.voidMethod) voidMethodReturn==return)){
                    voidMethodReturn voidMethod(voidMethodArgs args){
                        auto obj=_targetObj;
                        if (obj is null){
                            throw new RpcException("vended object is null for "~"tst.AProxy"~".voidMethod",__FILE__,__LINE__);
                        }
                        static if(is(voidMethodReturn==void)){
                            obj.voidMethod(args);
                        } else {
                            return obj.voidMethod(args);
                        }
                    }
                }
            }

            override bool proxyIsLocal(){ return true; }
        }
        static this(){
            ProtocolHandler.registerProxy("tst.AProxy",
                function Proxy(char[]name,char[]url){ return new AProxy(name,url); },
                function Proxy(char[]name,char[]url){ return new AProxyLocal(name,url); });
        }
        static class AVendor:BasicVendor{
            AProxiedType obj;
            override AProxiedType targetObj(){ return obj; }
            static struct Closure{
                void delegate() callClosureDelegate;
                PoolI!(Closure*) pool;
                union Cl{
                    static if (is(typeof(AProxiedType.iVal) iValArgs==function)){
                        static if (is(typeof(AProxiedType.iVal) iValReturn==return)){
                            struct iValClsr{
                                AVendor context;
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
                                iValArgs args;
                                void call(){
                                    static if (is(iValReturn==void)){
                                        try{
                                            context.obj.iVal(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.iVal(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            iValClsr iValClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.setIVal) setIValArgs==function)){
                        static if (is(typeof(AProxiedType.setIVal) setIValReturn==return)){
                            struct setIValClsr{
                                AVendor context;
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
                                setIValArgs args;
                                void call(){
                                    static if (is(setIValReturn==void)){
                                        try{
                                            context.obj.setIVal(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.setIVal(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            setIValClsr setIValClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.b) bArgs==function)){
                        static if (is(typeof(AProxiedType.b) bReturn==return)){
                            struct bClsr{
                                AVendor context;
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
                                bArgs args;
                                void call(){
                                    static if (is(bReturn==void)){
                                        try{
                                            context.obj.b(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.b(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            bClsr bClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.mult) multArgs==function)){
                        static if (is(typeof(AProxiedType.mult) multReturn==return)){
                            struct multClsr{
                                AVendor context;
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
                                multArgs args;
                                void call(){
                                    static if (is(multReturn==void)){
                                        try{
                                            context.obj.mult(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.mult(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            multClsr multClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.div) divArgs==function)){
                        static if (is(typeof(AProxiedType.div) divReturn==return)){
                            struct divClsr{
                                AVendor context;
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
                                divArgs args;
                                void call(){
                                    static if (is(divReturn==void)){
                                        try{
                                            context.obj.div(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.div(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            divClsr divClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.notify) notifyArgs==function)){
                        static if (is(typeof(AProxiedType.notify) notifyReturn==return)){
                            struct notifyClsr{
                                AVendor context;
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
                                notifyArgs args;
                                void call(){
                                    static assert(is(notifyReturn==void),"non void return in oneway method "~"tst.AVendor"~".notify");
                                    try{
                                        context.obj.notify(args);
                                    } catch (Exception e){ /+ communicate back?? +/
                                        sinkTogether(context.publisher.log,delegate void(CharSink s){
                                            dumper(s)("exception in oneway method ")("tst.AVendor")(".notify:")(e);
                                        });
                                    }
                                }
                            }
                            notifyClsr notifyClosure;
                        }
                    }
                    static if (is(typeof(AProxiedType.voidMethod) voidMethodArgs==function)){
                        static if (is(typeof(AProxiedType.voidMethod) voidMethodReturn==return)){
                            struct voidMethodClsr{
                                AVendor context;
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
                                voidMethodArgs args;
                                void call(){
                                    static if (is(voidMethodReturn==void)){
                                        try{
                                            context.obj.voidMethod(args);
                                            context.simpleReply!()(sendRes,reqId);
                                        } catch (Exception o) {
                                            context.exceptionReply(sendRes,reqId,o);
                                            return;
                                        }
                                    } else {
                                        try{
                                            auto res=context.obj.voidMethod(args);
                                            context.simpleReply(sendRes,reqId,res);
                                        } catch(Exception o){
                                            context.exceptionReply(sendRes,reqId,o);
                                        }
                                    }
                                }
                            }
                            voidMethodClsr voidMethodClosure;
                        }
                    }
                }
                Cl closure;
                void giveBack(){
                    if (pool!is null){
                        pool.giveBack(this);
                    } else {
                        delete this;
                    }
                }
                static PoolI!(Closure*) gPool;
                static Mutex gLock;
                static this(){
                    gLock=new Mutex();
                }
                static size_t gPoolLevel;
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
                        if (gPoolLevel==0) throw new Exception("gPoolLevel is 0 in rmGPool for vendor "~"tst.AVendor",__FILE__,__LINE__);
                        --gPoolLevel;
                        if (gPoolLevel==0) {
                            gPool.rmUser();
                            gPool=null;
                        }
                    }
                }
                static Closure *opCall(){
                    assert(gPoolLevel>0,"opCall outside add/rmGPool in Closure of "~"tst.AVendor");
                    return gPool.getObj();
                }
            }

            this(){
                super("tst.AProxy");
                Closure.addGPool();
            }
            this(AProxiedType obj){
                super("tst.AProxy"); 
                Closure.addGPool();
                this.obj=obj;
            }
            ~this(){
                Closure.rmGPool();
            }

            override void proxyDescDumper(void delegate(char[])s){
                super.proxyDescDumper(s);
                static if (is(typeof(AProxiedType.iVal) iValArgs==function)){
                    static if (is(typeof(AProxiedType.iVal) iValReturn==return)){
                        s(iValReturn.stringof);
                        s("iVal");
                        s("(");
                        s(iValArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".iVal"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".iVal"); }
                static if (is(typeof(AProxiedType.setIVal) setIValArgs==function)){
                    static if (is(typeof(AProxiedType.setIVal) setIValReturn==return)){
                        s(setIValReturn.stringof);
                        s("setIVal");
                        s("(");
                        s(setIValArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".setIVal"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".setIVal"); }
                static if (is(typeof(AProxiedType.b) bArgs==function)){
                    static if (is(typeof(AProxiedType.b) bReturn==return)){
                        s(bReturn.stringof);
                        s("b");
                        s("(");
                        s(bArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".b"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".b"); }
                static if (is(typeof(AProxiedType.mult) multArgs==function)){
                    static if (is(typeof(AProxiedType.mult) multReturn==return)){
                        s(multReturn.stringof);
                        s("mult");
                        s("(");
                        s(multArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".mult"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".mult"); }
                static if (is(typeof(AProxiedType.div) divArgs==function)){
                    static if (is(typeof(AProxiedType.div) divReturn==return)){
                        s(divReturn.stringof);
                        s("div");
                        s("(");
                        s(divArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".div"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".div"); }
                static if (is(typeof(AProxiedType.notify) notifyArgs==function)){
                    static if (is(typeof(AProxiedType.notify) notifyReturn==return)){
                        s("oneway ");
                        s(notifyReturn.stringof);
                        s("notify");
                        s("(");
                        s(notifyArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".notify"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".notify"); }
                static if (is(typeof(AProxiedType.voidMethod) voidMethodArgs==function)){
                    static if (is(typeof(AProxiedType.voidMethod) voidMethodReturn==return)){
                        s(voidMethodReturn.stringof);
                        s("voidMethod");
                        s("(");
                        s(voidMethodArgs.stringof);
                        s(")\n");
                    } else { static assert(0,"could not extract function return for "~"tst.AVendor"~".voidMethod"); }
                } else { static assert(0,"could not extract function arguments for "~"tst.AVendor"~".voidMethod"); }
            }
            void remoteCalliVal(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".iVal\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.iValClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.iVal\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"iVal",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCalliVal",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".iVal:")(o);
                    });
                }
            }
            void remoteCallsetIVal(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".setIVal\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.setIValClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.setIVal\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"setIVal",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCallsetIVal",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".setIVal:")(o);
                    });
                }
            }
            void remoteCallb(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".b\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.bClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.b\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"b",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCallb",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".b:")(o);
                    });
                }
            }
            void remoteCallmult(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".mult\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.multClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.mult\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"mult",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCallmult",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".mult:")(o);
                    });
                }
            }
            void remoteCalldiv(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".div\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.divClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.div\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"div",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCalldiv",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".div:")(o);
                    });
                }
            }
            void remoteCallnotify(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".notify\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.notifyClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.notify\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"notify",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCallnotify",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".notify:")(o);
                    });
                }
            }
            void remoteCallvoidMethod(ubyte[] reqId,Unserializer u,SendResHandler sendRes){
                version(TrackRpc){
                    publisher.log("starting rpc call "~"tst.AVendor"~".voidMethod\n");
                }
                auto cl0=Closure();
                auto cl= & cl0.closure.voidMethodClosure;
                try {
                    cl.context=this;
                    cl.reqId=reqId;
                    cl.sendRes=sendRes;
                    u(cl.args);
                    cl0.callClosureDelegate=&cl.call;
                } catch (Exception o){
                    version(TrackRpc){
                        publisher.log("exception deserializing rpc call A.voidMethod\n");
                    }
                    exceptionReply(sendRes,reqId,new Exception("exception deserializing arguments for "~"tst.AVendor"~"voidMethod",__FILE__,__LINE__,o));
                }
                try{
                    Task("rpcCallvoidMethod",cl0.callClosureDelegate)
                        .appendOnFinish(&cl0.giveBack).autorelease.submit(objTask);
                } catch (Object o){
                    sinkTogether(publisher.log,delegate void(CharSink s){
                        dumper(s)("internal exception in method ")("tst.AVendor")(".voidMethod:")(o);
                    });
                }
            }
            void remoteMainCall(char[] fName,ubyte[] reqId, Unserializer u, SendResHandler sendRes){
                switch(fName){
                case "iVal":
                    remoteCalliVal(reqId,u,sendRes);
                    break;
                case "setIVal":
                    remoteCallsetIVal(reqId,u,sendRes);
                    break;
                case "b":
                    remoteCallb(reqId,u,sendRes);
                    break;
                case "mult":
                    remoteCallmult(reqId,u,sendRes);
                    break;
                case "div":
                    remoteCalldiv(reqId,u,sendRes);
                    break;
                case "notify":
                    remoteCallnotify(reqId,u,sendRes);
                    break;
                case "voidMethod":
                    remoteCallvoidMethod(reqId,u,sendRes);
                    break;
                default:
                    super.remoteMainCall(fName,reqId,u,sendRes);
                }
            }
        }
    ///__________
}

void rpcTests(){
    try{
        //GC.disable();
        auto ol=new A.AProxyLocal();
        ol.targetObj=A.globalA;
        ol.objTask=defaultTask;
        sout("b direct:")(A.globalA.b(3))("\n");
        sout("b thorugh local proxy:")(ol.b(3))("\n");
        
        auto vendor=new A.AVendor(A.globalA);
        sout("initedVendor\n");
        auto rpc1=new StcpProtocolHandler("","1242");
        sout("register:\n");
        rpc1.register();
        sout("start\n");
        rpc1.startServer(false);
        sout("rpc1:")(cast(void*)rpc1)("\n");
        auto pName=rpc1.publisher.publishObject(vendor,"globalA");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("proxy from url: ")(vendor.proxyObjUrl())("\n");
        });
        sout("gc collect!\n");
        GC.collect();
        sout("gc did collect!\n");
        auto localP0=ProtocolHandler.proxyForUrl(vendor.proxyObjUrl());
        auto localP=cast(A.AProxyLocal)localP0;
        assert(localP!is null,"non local proxy");
        sout("will call localProxy2\n");
        {
            auto res=localP.b(4);
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("b thorugh local proxy2:")(res)("\n");
            });
        }
        double r=ol.mult(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("b mult:")(r)("\n");
        });
        r=localP.mult(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("b2 mult:")(r)("\n");
        });
        sout("gc collect2!\n");
        GC.collect();
        sout("gc did collect2!\n");
    
        auto rpc3=new StcpProtocolHandler("","1243");
        rpc3.register();
        rpc3.startServer(false);
        auto vendor2=new A.AVendor(A.globalA);
        auto pName2=rpc1.publisher.publishObject(vendor2,"globalB");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("url2:")(vendor.proxyObjUrl())("\n");
        });
    
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("non loc proxy from url: ")(vendor.proxyObjUrl())("\n");
        });
        auto localP3=ProtocolHandler.proxyForUrl(vendor.proxyObjUrl());
        auto localP4=cast(A.AProxy)localP3;
        assert(localP4 !is null,"loopBackProxy error");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("b thorugh local proxy2:")(ol.b(4))("\n");
        });
        sout("will call loopBackProxy\n");
        sout("gc collect3!\n");
        GC.collect();
        sout("gc did collect3!\n");
        {
            auto res=localP4.b(4);
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("b thorugh loopBackProxy:")(res)("\n");
            });
        }
        r=localP4.mult(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("loopBackProxy mult:")(r)("\n");
        });
        r=localP4.div(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("loopBackProxy dif:")(r)("\n");
        });
        localP4.notify(3);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("loopBackProxy notify\n");
        });
        Thread.sleep(2.0);
        localP4.voidMethod();
        sout("loopBackProxy voidMethod\n");
        char[128] buf;
        auto arr=lGrowableArray(buf,0);
        for (int itime=0;itime<1;++itime){
            auto s=dumper(&arr.appendArr);
            double tNat,tLocP1,tLocP2,tLoopBack;
            auto t0=realtimeClock();
            enum { nIter=5000 }
            double totRef=0,x0=1.23,y0=35.7;
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:Native\n");
                double tot=0,x=x0,y=y0;
                for (int i=0;i<nIter;++i){
                    x=A.globalA.mult(x,y);
                    x=A.globalA.div(x,y);
                    tot+=x;
                    if (i%100==0) A.globalA.notify(i);
                }
                auto t1=realtimeClock();
                s("native single thread:")(t1-t0)(", ")(tot)("\n");
                tNat=(t1-t0);
                totRef=tot;
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:LocalP1\n");
                double tot=0,x=x0,y=y0;
                for (int i=0;i<nIter;++i){
                    x=ol.mult(x,y);
                    x=ol.div(x,y);
                    tot+=x;
                    if (i%100==0) ol.notify(i);
                }
                auto t1=realtimeClock();
                s("localProxy1:")(t1-t0)(", ")(tot)(" err: ")(tot-totRef)("\n");
                tLocP1=(t1-t0);
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:LocalP2\n");
                double tot=0,x=x0,y=y0;
                for (int i=0;i<nIter;++i){
                    x=localP.mult(x,y);
                    x=localP.div(x,y);
                    tot+=x;
                    if (i%100==0) localP.notify(i);
                }
                auto t1=realtimeClock();
                s("localProxy2:")(t1-t0)(", ")(tot)(" err: ")(tot-totRef)("\n");
                tLocP2=(t1-t0);
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:LoopBack\n");
                double tot=0,x=x0,y=y0;
                for (int i=0;i<nIter;++i){
                    x=localP4.mult(x,y);
                    x=localP4.div(x,y);
                    tot+=x;
                    if (i%100==0) localP4.notify(i);
                }
                auto t1=realtimeClock();
                s("loopBackProxy:")(t1-t0)(", ")(tot)(" err: ")(tot-totRef)("\n");
                tLoopBack=(t1-t0);
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            s("tt:")(tNat/tNat)(" ")(tLocP1/tNat)(" ")(tLocP2/tNat)(tLoopBack/tNat)("\n");

            rpc1.log("rpc1:\n");
        }
        sout(arr.data);
    } catch (Exception e){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Exception during rpcTests:")(e)("\n");
        });
    }
}

void rpcTestServer(){
    try{
        //GC.disable();
        auto vendor=new A.AVendor(A.globalA);
        sout("initedVendor\n");
        auto rpc1=new StcpProtocolHandler("","1242");
        sout("register:\n");
        rpc1.register();
        sout("start\n");
        rpc1.startServer(false);
        sout("rpc1:")(cast(void*)rpc1)("\n");
        auto pName=rpc1.publisher.publishObject(vendor,"globalA");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("vending url: ")(vendor.proxyObjUrl())("\n");
        });
        while(true){
            Thread.sleep(10.0);
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
        }
    } catch (Exception e){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Exception during rpcTests:")(e)("\n");
        });
    }
}
void rpcTestSimpleClient(char[] url,int repeat=1){
    try{
        //GC.disable();
        
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("testing simpleCall on: ")(url)("\n");
        });
        auto pUrl=ParsedUrl.parseUrl(url);
        auto handler=ProtocolHandler.protocolForUrl(pUrl);
        for (int itime=0;itime<repeat;++itime){
            char[] res=handler.simpleCall(pUrl);
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("simpleCall returned '")(res)("'\n");
            });
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
        }
    } catch(Exception e){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("exception in rpcTestClient:")(e)("\n");
        });
    }
}

// iVal test
struct SerUnser{
    Tuple!() args;
    void serialArgs(Serializer s){ s(this.args); }
    int res;
    void unserialRes(Unserializer u){
        u(this.res);
    }
}

void rpcTestClient(char[] url){
    try{
        //GC.disable();
        
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("non loc proxy from url: ")(url)("\n");
        });
        auto pUrl=ParsedUrl.parseUrl(url);
        auto callH=ProtocolHandler.protocolForUrl(pUrl);
        auto localP3=ProtocolHandler.proxyForUrl(url);
        auto localP4=cast(A.AProxy)cast(Object)localP3;
        assert(localP4 !is null,"Proxy error");
        sout("will call Proxy\n");
        sout("gc collect3!\n");
        GC.collect();
        sout("gc did collect3!\n");
        {
            int res=10;
            {
                ParsedUrl pUrl2=pUrl;
                pUrl2.appendToPath("iVal");
                Variant firstArg;
                auto closure=new SerUnser;
                callH.doRpcCall(pUrl2,&closure.serialArgs,&closure.unserialRes,firstArg);
                res=closure.res;
            }
            {
                ParsedUrl pUrl2=pUrl;
                pUrl2.appendToPath("proxyName");
                char[] resN=callH.simpleCall(pUrl2);
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("proxyName:")(resN)("\n");
                });
            }
            res=localP4.iVal();
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("iVal:")(res)("\n");
            });
            res=localP4.b(4);
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("b(4):")(res)("\n");
            });
        }
        auto r=localP4.mult(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Proxy mult:")(r)("\n");
        });
        r=localP4.div(3.4,2.0);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Proxy div:")(r)("\n");
        });
        localP4.notify(3);
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Proxy notify\n");
        });
        Thread.sleep(2.0);
        localP4.voidMethod();
        sout("Proxy voidMethod\n");
        char[128] buf;
        auto arr=lGrowableArray(buf,0);
        for (int itime=0;itime<1;++itime){
            auto s=dumper(&arr.appendArr);
            double tNat,tProxy;
            enum { nIter=5000 }
            double totRef=0,x0=1.23,y0=35.7;
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:Native\n");
                double tot=0,x=x0,y=y0;
                auto t0=realtimeClock();
                for (int i=0;i<nIter;++i){
                    x=A.globalA.mult(x,y);
                    x=A.globalA.div(x,y);
                    tot+=x;
                    if (i%100==0) A.globalA.notify(i);
                }
                auto t1=realtimeClock();
                s("native single thread:")(t1-t0)(", ")(tot)("\n");
                tNat=(t1-t0);
                totRef=tot;
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            {
                sout("XXX:Proxy\n");
                double tot=0,x=x0,y=y0;
                auto t0=realtimeClock();
                for (int i=0;i<nIter;++i){
                    int res=10;
                    {
                        ParsedUrl pUrl2=pUrl;//localP4.proxyObjPUrl();
                        pUrl2.appendToPath("iVal");
                        sinkTogether(sout,delegate void(CharSink s){
                            dumper(s)("pUrl2:")(&pUrl2.urlWriter)("\n");
                        });
                        Variant firstArg;
                        auto closure=new SerUnser;
                        callH.doRpcCall(pUrl2,&closure.serialArgs,&closure.unserialRes,firstArg);
                        sout("cld\n");
                        res=closure.res;
                    }
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("i1=")(res)("\n");
                    });
                    res=localP4.iVal();
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("i=")(res)("\n");
                    });
                    {
                        ParsedUrl pUrl2=pUrl;
                        pUrl2.appendToPath("proxyName");
                        char[] resN=callH.simpleCall(pUrl2);
                        sinkTogether(sout,delegate void(CharSink s){
                            dumper(s)("proxyName:")(resN)("\n");
                        });
                    }
                    assert(localP4.b(i)==5*i);
                    x=localP4.mult(x,y);
                    x=localP4.div(x,y);
                    tot+=x;
                    if (i%100==0) localP4.notify(i);
                }
                auto t1=realtimeClock();
                s("Proxy:")(t1-t0)(", ")(tot)(" err: ")(tot-totRef)("\n");
                tProxy=(t1-t0);
            }
            sout("gc collect!\n");
            GC.collect();
            sout("gc did collect!\n");
            s("tt:")(tNat/tNat)(" ")(tProxy/tNat)("\n");
        }
        sout("data:")(arr.data)("\n");
    } catch (Exception e){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Exception during rpcTests:")(e)("\n");
        });
    }
}


void main(char[][]args){
    void help(){
        sout("usage:\n")
            (args[0])(" [--help|-server|-client proxUrl|-simpleClient callUrl|-combined]\n");
    }
    
    A.globalA=new A();
    if (args.length>1){
        switch(args[1]){
        case "-server":
            auto t=Task("rpcTestServer",delegate void(){ rpcTestServer(); });
            t.executeNow();
            while (t.status!=TaskStatus.Finished){
                t.wait();
            }
            break;
        case "-simpleClient":
            if (args.length!=3 && args.length!=4){
                sout("unexpected number of arguments\n");
                help();
            } else {
                auto url=args[2];
                int repeat=100;
                if (args.length>3) repeat=Integer.toInt(args[3]);
                sout("client will try calling url ")(url)("\n");
                Task("rpcTestClient",delegate void(){ rpcTestSimpleClient(url,repeat); }).autorelease.executeNow();
            }
            break;
        case "-client":
            if (args.length!=3){
                sout("unexpected number of arguments\n");
                help();
            } else {
                auto url=args[2];
                sout("client will try connecting to url ")(url)("\n");
                Task("rpcTestClient",delegate void(){ rpcTestClient(url); }).autorelease.executeNow();
            }
            break;
        case "-combined":
            Task("rpcTests",delegate void(){ rpcTests(); }).autorelease.executeNow();
            break;
        case "-help","--help":
            help();
            break;
        default:
            sout("invalid argument ")(args[0])("\n");
            help();
            break;
        }
    } else {
        Task("rpcTests",delegate void(){ rpcTests(); }).autorelease.executeNow();
    }
    sout("done!!\n");
    exit(0);
}
