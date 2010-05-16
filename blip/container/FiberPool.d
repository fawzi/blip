module blip.container.FiberPool;
import blip.container.Pool;
import blip.t.core.Thread;
version(NoTrace){} else { import blip.t.core.stacktrace.TraceExceptions; }

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
            if (f.stackSize==stackSize){
                f.clear();
                return f;
            }
            delete f;
        }
        return null;
    }
    
    override Fiber reset(Fiber f){
        return f;
    }
    
    override Fiber allocateNew(){
        return new Fiber(stackSize);
    }
    
    Fiber getObj(void function() f){
//        return new Fiber(f,defaultFiberSize);
        auto res=super.getObj();
        res.reset(f);
        return res;
    }
    Fiber getObj(void delegate() f){
//        return new Fiber(f,defaultFiberSize);
        auto res=super.getObj();
        res.reset(f);
        return res;
    }
}
alias FiberPoolT!() FiberPool;
