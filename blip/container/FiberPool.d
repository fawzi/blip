/// a pool for fiber objects
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
module blip.container.FiberPool;
import blip.container.Pool;
import blip.core.Thread;

debug(TrackFibers) {
    import blip.io.BasicIO;
    import blip.io.Console;
    import blip.container.GrowableArray;
}

version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }

size_t defaultFiberSize=1024*1024; // a largish (1MB) stack

class FiberPoolT(int batchSize=16):Pool!(Fiber,batchSize){
    size_t stackSize;
    static void dummyF(){}
    
    this(size_t stackSize=defaultFiberSize,size_t bufferSpace=8*batchSize,
        size_t maxEl=8*batchSize){
        super(null,bufferSpace,maxEl);
        this.stackSize=stackSize;
    }
    
    override Fiber clear(Fiber f){
        if (f !is null){
            f.reset(function void(){}); // clear releases the stack...
            //if (f.stackSize==stackSize){
            return f;
            //}
        }
        return null;
    }
    
    override Fiber reset(Fiber f){
        return f;
    }
    
    override Fiber allocateNew(){
        auto el=new Fiber(function void() {},stackSize);
        debug(TrackFibers){
            sinkTogether(sout,delegate void(scope CharSink s){
                auto ctx=el.m_ctxt;
                writeOut!(CharSink,uint,char[1])(sout.call,34u,"x");
                dumper(s)("FiberPool @")(cast(void*)this)(" created new Fiber@")(cast(void*)el)(" m_ctxt.bstack:")(((ctx is null)?cast(size_t)0:cast(size_t)ctx.bstack),"x")(" m_ctxt.tstack:")(((ctx is null)?cast(size_t)0:cast(size_t)ctx.tstack),"x")(" m_size:")(el.m_size)("\n");
            });
        }
        return el;
    }
    
    Fiber getObj(void function() f){
//        return new Fiber(f,defaultFiberSize);
        auto res=getObj();
        res.reset(f);
        return res;
    }
    Fiber getObj(void delegate() f){
//        return new Fiber(f,defaultFiberSize);
        auto res=getObj();
        res.reset(f);
        return res;
    }
    override Fiber getObj(){
        auto el=super.getObj();
        debug(TrackFibers){
            sinkTogether(sout,delegate void(scope CharSink s){
                auto ctx=el.m_ctxt;
                dumper(s)("FiberPool @")(cast(void*)this)(" getObj will return Fiber@")(cast(void*)el)("\n");
            });
        }
        return el;
    }
    override void giveBack(Fiber obj){
        debug(TrackFibers){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("pool @")(cast(void*)this)(" got back Fiber@")(cast(void*)obj)("\n");
            });
        }
        super.giveBack(obj);
    }
    
}
alias FiberPoolT!() FiberPool;
