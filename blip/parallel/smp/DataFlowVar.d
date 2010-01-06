/// implementation of oz like dataflow variables (at smp level)
module blip.parallel.smp.DataFlowVar;
import blip.parallel.smp.SmpModels;
import blip.sync.Atomic;
import blip.t.core.Thread;
import blip.container.GrowableArray;
import blip.io.BasicIO;

class WaitList{
    TaskI[]waiting;
    void notify(){
        synchronized(this){
            foreach(t;waiting){
                t.resubmitDelayed();
            }
            waiting=null;
        }
    }
}

struct WaitListPtr{
    WaitList _ptr;
    
    bool ifNoVal(void delegate(WaitList) op){
        volatile WaitList p=_ptr;
        if (((cast(size_t)cast(void*)p)&1)==1){
            while(((cast(size_t)cast(void*)p)&3)==3){
                Thread.yield();
                volatile p=_ptr; // spin
            }
            return false;
        } else if (p is null){
            auto w=new WaitList(); // should use cache, and avoid allocation
            memoryBarrier!(false,false,false,true)();
            atomicCAS(_ptr,w,cast(WaitList)null);
            p=_ptr;
            assert(p!is null,"unexpected null");
            synchronized(p){
                if (p==_ptr){
                    op(p);
                    return true;
                } else {
                    do {
                        volatile p=_ptr;
                        Thread.yield();
                    } while(((cast(size_t)cast(void*)p)&3)==3);
                    volatile assert(((cast(size_t)cast(void*)_ptr)&1)==1,"no val when expected one");
                }
            }
            return false;
        }
    }
    /// returns true if the value has been set (useful for the fast path)
    bool hasVal(){
        if (((cast(size_t)cast(void*)_ptr) & 3)==1){
            memoryBarrier!(true,false,false,false)();
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
    
    void maybeSetValShort(ref WaitList newVal){
        while(true){
            volatile size_t nV=cast(size_t)cast(void*)newVal;
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
            volatile WaitList oldV=_ptr;
            switch((cast(size_t)cast(void*)oldV)&3){
            case 0:
                if (atomicCASB(_ptr,cast(WaitList)cast(void*)newVal,oldV)){
                    if (oldV !is null){
                        oldV.notify();
                    }
                    return;
                }
            case 1:
                if (cast(size_t)cast(void*)_ptr !is newVal){
                    throw new Exception(collectAppender(delegate void(CharSink sink){
                        auto s=dumper(sink);
                        s("invalid change of value from ")(cast(size_t)cast(void*)_ptr)(" to ")(newVal);
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
            volatile WaitList oldV=_ptr;
            switch((cast(size_t)cast(void*)oldV)&3){
            case 0:
                void *waitP=cast(void*)(cast(size_t)3);
                if (atomicCASB(_ptr,cast(WaitList)cast(Object)waitP,oldV)){
                    if (oldV !is null){
                        synchronized(oldV){
                            setOp(false);
                            memoryBarrier!(false,false,false,true)();
                            void *valP=cast(void*)(cast(size_t)1);
                            if (!atomicCASB(_ptr,cast(WaitList)cast(Object)valP,cast(WaitList)cast(Object)waitP)){
                                    throw new Exception("internal error, expected value 3",__FILE__,__LINE__);
                            }
                            oldV.notify();
                        }
                    }
                    return;
                }
            case 1:
                setOp(true);
                return;
            case 3:
                Thread.yield();
                break; // spin
            default:
                throw new Exception("invalid value in setValShort",__FILE__,__LINE__);
            }
        }
    }
}

void unifyVals(T)(ref T a, ref T b){
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
        T val;
    }
    
    void opAssign(T newVal){
        size_t rVal=1;
        static if (is(T==bool)){
            if (newVal){
                waitL.setValShort(cast(size_t) 5);
            } else {
                waitL.setValShort(cast(size_t) 1);
            }
        } else static if (T.sizeof>=size_t.sizeof){
            waitL.setValLong(delegate void(bool hasV){
                if (hasV){
                    unifyVals(val,newVal);
                } else {
                    val=newVal;
                }
            });
        } else {
            size_t rVal=0;
            ubyte *v=cast(ubyte*)&newVal; // this is endiannes dependent...
            for (int ib=0;ib<T.sizeof;++ib){
                rVal |= cast(size_t)(*ib);
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
                    tAtt.resubmitDelayed();
                }
            });
        }
        static if (is(T==bool)){
            assert(cast(size_t)waitL._ptr==5 || cast(size_t)waitL._ptr==1,"unexpected value");
            return cast(size_t)waitL._ptr==5;
        } else static if (T.sizeof>=size_t.sizeof){
            return val;
        } else {
            size_t rVal=cast(size_t)waitL._ptr;
            assert((rVal&3)==1,"unexpected value");
            T res;
            ubyte *v=cast(ubyte*)&res;
            for (int ib=0;ib<T.sizeof;++ib){
                rVal >>= 8;
                *v=cast(ubyte)(rVal&0xFF);
                ++ib;
            }
        }
    }

    void val(T newV){
        opAssign(newV);
    }
    
    void opAssign(DataFlow newVal){
        size_t rVal=1;
        waitL.maybeSetValShort(newVal.waitL._ptr);
    }
    
    T opCall(){
        return val();
    }
    
    void unify(DataFlow b){
        opAssign(b);
    }
}
