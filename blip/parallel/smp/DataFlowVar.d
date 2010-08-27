/// implementation of oz like dataflow variables (at smp level)
///
/// The unification between unset variables is just istantaneous and onesided
/// unify(a,b); unify(b,4); does not automatically set a=4.
/// change the behaviour???
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
module blip.parallel.smp.DataFlowVar;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.WorkManager:taskAtt;
import blip.sync.Atomic;
import blip.core.Thread;
import blip.container.GrowableArray;
import blip.io.BasicIO;

class WaitList{
    TaskI[]waiting; // using this rather than delegates because it is more self descriptive
    void notify(){
        synchronized(this){
            foreach(t;waiting){
                t.resubmitDelayed(t.delayLevel-1);
            }
            waiting=null;
        }
    }
}

struct WaitListPtr{
    union WaitListU{
        WaitList wlist;
        void*    ptr;
        size_t   data;
    }
    WaitListU data;
    bool ifNoVal(void delegate(WaitList) op){
        volatile void *p=data.ptr;
        if (((cast(size_t)p)&1)==1){
            while(((cast(size_t)p)&3)==3){
                assert((cast(size_t)p)==3,"invalid value ");
                Thread.yield();
                volatile p=data.ptr; // spin
            }
            return false;
        } else if (p is null){
            auto w=new WaitList(); // should use cache, and avoid allocation
            memoryBarrier!(false,false,false,true)();
            atomicCAS(data.wlist,w,cast(WaitList)null);
            p=data.ptr;
        }
        assert(p!is null,"unexpected null");
        WaitList wl=cast(WaitList)p;
        synchronized(wl){
            if (wl is data.wlist){
                op(wl);
                return true;
            } else {
                while(true) {
                    volatile p=data.ptr;
                    if (((cast(size_t)p)&3)!=3) break;
                    Thread.yield();
                }
                volatile assert(((cast(size_t)p)&1)==1,"no val when expected one");
                static if (is(typeof(this.value))) memoryBarrier!(true,false,false,false)();
            }
        }
        return false;
    }
    /// returns true if the value has been set (useful for the fast path)
    bool hasVal(){
        if ((data.data & 3)==1){
            static if (is(typeof(this.value))) memoryBarrier!(true,false,false,false)();
            return true;
        } else {
            return false;
        }
    }
    
    bool addTask(TaskI t){
        return ifNoVal(delegate void(WaitList w){
            w.waiting~=t;
        });
    }
    
    void maybeSetValShort(ref WaitListPtr newVal){
        while(true){
            volatile size_t nV=newVal.data.data;
            switch (nV&3){
            case 0:
                return;
            case 1:
                setValShort(nV);
                return;
            case 3:
                Thread.yield();
                break; // spin
            default:
                assert(0);
            }
        }
    }
    
    void setValShort(size_t newVal){
        assert((newVal&3)==1,"newVal binary rep has to end with 01");
        while(true){
            volatile void* oldV=data.ptr;
            switch((cast(size_t)oldV)&3){
            case 0:
                if (atomicCASB(data.data,newVal,cast(size_t)oldV)){
                    if (oldV !is null){
                        (cast(WaitList)oldV).notify();
                    }
                    return;
                }
                break; // spin
            case 1:
                if (data.data !is newVal){
                    throw new Exception(collectAppender(delegate void(CharSink sink){
                        auto s=dumper(sink);
                        s("invalid change of value from ")(data.data)(" to ")(newVal);
                    }),__FILE__,__LINE__);
                }
                return;
            case 3:
                Thread.yield();
                break; // spin
            default:
                throw new Exception("invalid value in setValShort",__FILE__,__LINE__);
            }
        }
    }

    void setValLong(void delegate(bool) setOp){
        while(true){
            volatile void* oldV=data.ptr;
            switch((cast(size_t)oldV)&3){
            case 0:
                size_t waitP=3;
                if (atomicCASB(data.data,waitP,cast(size_t)oldV)){
                    if (oldV !is null){
                        auto wl=cast(WaitList)oldV;
                        synchronized(wl){
                            setOp(false);
                            memoryBarrier!(false,false,false,true)();
                            size_t valP=1;
                            if (!atomicCASB(data.data,valP,waitP)){
                                throw new Exception("internal error, expected value 3",__FILE__,__LINE__);
                            }
                            wl.notify();
                        }
                    } else {
                        setOp(false);
                        memoryBarrier!(false,false,false,true)();
                        size_t valP=1;
                        if (!atomicCASB(data.data,valP,waitP)){
                            throw new Exception("internal error, expected value 3",__FILE__,__LINE__);
                        }
                    }
                    return;
                }
                break; // spin
            case 1:
                setOp(true);
                return;
            case 3:
                assert((cast(size_t)oldV)==3);
                Thread.yield();
                break; // spin
            default:
                throw new Exception("invalid value in setValShort",__FILE__,__LINE__);
            }
        }
    }
}

void unifyVals(T)(ref T a, T b){
    static if (is(typeof(a.unify(b)))){
        static if(is(typeof(a is null))){
            if (a is null){
                a=b; // correct???
            } else {
                a.unify(b);
            }
        }
    } else static if(is(T U :U[])){
        if (a.length!=b.length)
            throw new Exception("unification exception, incompatible values",__FILE__,__LINE__);
        auto aLen=a.length;
        for(size_t i=0;i<aLen;++i){
            unifyVals(a[i],b[i]);
        }
    } else {
        if (a!=b){
            throw new Exception("unification exception, incompatible values",__FILE__,__LINE__);
        }
    }
}

/// implementation of a data flaow variable similar to what Oz does, this is related to futures and I-vars
/// accessing the value of a dataflow variable blocks, until it has a value.
/// the value can be assigned more than once, but only the same value (or in general a compatible value)
struct DataFlow(T){
    WaitListPtr waitL;
    static if (T.sizeof>=size_t.sizeof && !is(T==bool)){
        T value;
    }
    
    void opAssign(T newVal){
        size_t rVal=1;
        static if (is(T==bool)){
            if (newVal){
                waitL.setValShort(cast(size_t) 5);
            } else {
                waitL.setValShort(cast(size_t) 1);
            }
        } else static if (is(typeof(this.value))){
            waitL.setValLong(delegate void(bool hasV){
                if (hasV){
                    unifyVals!(T)(value,newVal);
                } else {
                    value=newVal;
                }
            });
        } else {
            rVal=0;
            ubyte *v=cast(ubyte*)&newVal; // this is endiannes dependent...
            for (int ib=0;ib<T.sizeof;++ib){
                rVal |= cast(size_t)(v[ib]);
                rVal <<= 8;
                ++ib;
            }
            rVal |= 1;
            waitL.setValShort(rVal);
        }
    }
    
    T val(){
        if (!waitL.hasVal){
            auto tAtt=taskAtt.val;
            assert(tAtt!is null);
            tAtt.delay(delegate void(){
                if (!waitL.addTask(tAtt)){
                    tAtt.resubmitDelayed(tAtt.delayLevel-1);
                }
            });
        }
        static if (is(T==bool)){
            assert(waitL.data.data==5 || waitL.data.data==1,"unexpected value");
            return waitL.data.data==5;
        } else static if (T.sizeof>=size_t.sizeof){
            return value;
        } else {
            size_t rVal=waitL.data.data;
            assert((rVal&3)==1,"unexpected value");
            T res;
            ubyte *v=cast(ubyte*)&res;
            for (int ib=0;ib<T.sizeof;++ib){
                rVal >>= 8;
                *v=cast(ubyte)(rVal&0xFF);
                ++ib;
            }
            return res;
        }
    }

    void val(T newV){
        opSliceAssign(newV);
    }
    
    void opSliceAssign(T newVal){
        opAssign(newVal);
    }
    void opSliceAssign(DataFlow newVal){
        size_t rVal=1;
        static if (!is(typeof(this.value))){
            waitL.maybeSetValShort(newVal.waitL);
        } else {
            if (newVal.waitL.hasVal){
                waitL.setValLong(delegate void(bool hasV){
                    if (hasV){
                        unifyVals!(T)(value,newVal.val);
                    } else {
                        value=newVal.val;
                    }
                });
            }
        }
    }
    
    T opCall(){
        return val();
    }
    
    void unify(DataFlow b){
        opSliceAssign(b);
    }
}
