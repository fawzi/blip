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
import blip.parallel.rpc.RpcMixins;

version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

class A{
    static A globalA;
    int b(double y){
        return 5*cast(int)y;
    }
    this(){}
    pragma(msg,rpcMixin("A","tst.A","","b",true));
    mixin(rpcMixin("A","tst.A","","b",true));
    ///__________
    ///__________
}

void main(){
    A.globalA=new A();
    auto ol=new A.AProxyLocal();
    ol.targetObj=A.globalA;
    sout("b direct:")(A.globalA.b(3))("\n");
    sout("b thorugh local proxy:")(ol.b(3))("\n");
}