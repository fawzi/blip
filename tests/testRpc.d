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

version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

class A{
    static A globalA;
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
    pragma(msg,rpcMixin("A","tst.A","","b|mult|div|notify:oneway|voidMethod",true));
    mixin(rpcMixin("A","tst.A","","b|mult|div|notify:oneway|voidMethod",true));
    ///__________
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
            dumper(s)("prox from url:")(vendor.proxyObjUrl())("\n");
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
            dumper(s)("non loc proxy from url:")(vendor.proxyObjUrl())("\n");
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
                    //if (i%100==0) localP4.notify(i);
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

void main(){
    A.globalA=new A();
    
    Task("rpcTests",delegate void(){ rpcTests(); }).autorelease.executeNow();
    sout("done!!\n");
    exit(0);
}