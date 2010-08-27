/// tests of the remote procedure call part
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

version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

class A{
    static A globalA;
    int b(double y){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("A.b is being called with ")(y)("\n");
        });
        return 5*cast(int)y;
    }
    this(){}
    //pragma(msg,rpcMixin("A","tst.A","","b",true));
    mixin(rpcMixin("A","tst.A","","b",true));
    ///__________
    ///__________
}

void rpcTests(){
    try{
        auto ol=new A.AProxyLocal();
        ol.targetObj=A.globalA;
        sout("b direct:")(A.globalA.b(3))("\n");
        sout("b thorugh local proxy:")(ol.b(3))("\n");
        auto vendor=new A.AVendor(A.globalA);
        sout("initedVendor\n");
        auto rpc1=new StcpProtocolHandler("","1242");
        sout("register:\n");
        rpc1.register();
        sout("start\n");
        rpc1.startServer(true);
        sout("rpc1:")(cast(void*)rpc1)("\n");
        sout("publisher:")(cast(void*)rpc1.publisher)("\n");
        auto pName=rpc1.publisher.publishObject(vendor,"globalA");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("prox from url:")(vendor.proxyObjUrl())("\n");
        });
        auto localP0=ProtocolHandler.proxyForUrl(vendor.proxyObjUrl());
        auto localP=cast(A.AProxy)localP0;
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("b thorugh local proxy2:")(ol.b(4))("\n");
        });
    
        auto rpc3=new StcpProtocolHandler("","1243");
        rpc3.register();
        rpc3.startServer(true);
        auto vendor2=new A.AVendor(A.globalA);
        auto pName2=rpc1.publisher.publishObject(vendor2,"globalB");
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("url1:")(vendor.proxyObjUrl())("\n");
        });
    
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("non loc proxy from url:")(vendor.proxyObjUrl())("\n");
        });
        auto localP3=ProtocolHandler.proxyForUrl(vendor.proxyObjUrl());
        auto localP4=cast(A.AProxy)localP3;
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("b thorugh local proxy2:")(ol.b(4))("\n");
        });
    } catch (Exception e){
        sinkTogether(sout,delegate void(CharSink s){
            dumper(s)("Exception during rpcTests:")(e)("\n");
        });
    }
}

void main(){
    A.globalA=new A();
    
    Task("rpcTests",delegate void(){ rpcTests(); }).autorelease.executeNow();
}