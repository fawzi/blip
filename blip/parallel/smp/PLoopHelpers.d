/// helper for parallel loops using arrays and iterators
///
/// You probably want pLoopArray and pLoopIter
///
/// Notes: the current version uses a class as base type, and allocates all delegates on the heap.
/// the initial version did use only structs, and allocated the initial iteration on the stack.
/// That is faster (especially for short loops), but is more sensible to (incorrect) compiler optimizations
/// like last call optimization, or optimizations that assume that the stack is used only by the current
/// thread
///
/// author: fawzi
//
// Copyright 2010 the blip developer group
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
module blip.parallel.smp.PLoopHelpers;
import blip.container.Pool;
import blip.container.Cache;
import blip.core.sync.Mutex;
import blip.parallel.smp.WorkManager;
import blip.Comp;
import blip.core.Thread;
import blip.io.Console;
import blip.io.BasicIO;
import blip.container.GrowableArray;
public import blip.BasicModels: LoopType;

version(NoPLoop){
    version=NoPLoopIter;
}

/// creates a context for a loop.
/// ctxExtra should define a ctxName createNew() method, startLoop can define blockSize>0
/// no exception handlers are set up, you can set them up with startLoop and endLoop
string loopCtxMixin(string ctxName,string ctxExtra,string startLoop, string taskOps,
    string loopOp,string endLoop,string idxType="size_t"){
    return `
    struct `~ctxName~`{
        `~idxType~` start,end;
        `~ctxName~` *next;
        PoolI!(`~ctxName~`*) pool;
        `~ctxExtra~`
        static size_t nGPools;
        static Mutex gLock;
        static this(){
            gLock=new Mutex();
        }
        static CachedPool!(`~ctxName~`*) gPool;
        static void addGPool(){
            synchronized(gLock){
                if (nGPools==0){
                    assert(gPool is null,"gPool is non null before new alloc");
                    gPool=cachedPoolNext(function `~ctxName~`*(PoolI!(`~ctxName~`*)p){
                        auto res=new `~ctxName~`;
                        res.pool=p;
                        return res;
                    });
                }
                ++nGPools;
            }
        }
        static void rmGPool(){
            synchronized(gLock){
                if (nGPools==0) throw new Exception("unpaired rmGPool: nGPools is 0",__FILE__,__LINE__);
                --nGPools;
                if (nGPools==0){
                    gPool.stopCaching();
                    gPool=null;
                }
            }
        }
        `~ctxName~` *createNew(){
            assert(gPool!is null,"invalid gPool (forgot addGPool call?)");
            auto res=gPool.getObj();
            auto p=res.pool;
            *res=*this;
            res.pool=p;
            return res;
        }
        void exec(){
            size_t blockSize=1;
            `~startLoop~`
            if (this.end>this.start+cast(`~idxType~`)(blockSize+blockSize/2)){
                auto newChunk=this.createNew();
                auto newChunk2=this.createNew();
                auto mid=(this.end-this.start)/2;
                if (blockSize<mid) // try to have exact multiples of optimalBlockSize (so that one can have a fast path for it)
                    mid=((mid+blockSize-1)/blockSize)*blockSize;
                auto midP=this.start+mid;
                newChunk.start=this.start;
                newChunk.end=midP;
                newChunk2.start=midP;
                newChunk2.end=this.end;
                auto t1=Task("PLoopArraysub",&newChunk.exec).appendOnFinish(&newChunk.giveBack);
                auto t2=Task("PLoopArraysub2",&newChunk2.exec).appendOnFinish(&newChunk2.giveBack);
                `~taskOps~`
                t1.autorelease.submit();
                t2.autorelease.submit();
            } else {
                for (`~idxType~` idx=this.start;idx<this.end;++idx){
                    `~loopOp~`;
                }
            }
            `~endLoop~`
        }
        void giveBack(){
            if (this.pool) this.pool.giveBack(this);
        }
    }`; 
}

// should use a slice in LoopBlock and thus specialize definitely on builtin arrays?
class PLoopHelper(T,int loopType){
    size_t optimalBlockSize=1;
    Exception exception=null;
    int res=0;
    size_t firstDistribution=1;
    int stealLevel=int.max;
    static if (is(typeof(T.init[0]))){
        alias size_t IType;
        T arr;
        alias typeof(arr[0]) ElT;
        int delegate(ref ElT) loopBody1;
        int delegate(ref size_t,ref ElT) loopBody2;
        size_t iStart(){
            return 0;
        }
        size_t iEnd(){
            return arr.length;
        }
        mixin(loopCtxMixin("LoopBlock1",`
        PLoopHelper context;
        `,`
        blockSize=context.optimalBlockSize;
        if (context.res!=0||context.exception!is null) return;
        volatile{
            while (1){
                if (context.firstDistribution==0) break;
                Thread.yield();
            }
        }
        try{`,`
        t1.stealLevel=context.stealLevel;
        t2.stealLevel=context.stealLevel;
        `,`
        static if (is(T:ElT[])){
            auto r=context.loopBody1(context.arr[idx]);
        } else {
            auto el=context.arr[idx];
            auto r=context.loopBody1(el);
            static if(is(typeof(delegate void(){context.arr[idx]=el;}))){
                context.arr[idx]=el;
            }
        }
        if (r!=0){
            context.res=r;
            return;
        }`,`
        }catch(Exception e){
            context.exception=e;
        }
        `));
        mixin(loopCtxMixin("LoopBlock2",`
        PLoopHelper context;
        `,`
        blockSize=context.optimalBlockSize;
        if (context.res!=0||context.exception!is null) return;
        try{`,`
        t1.stealLevel=context.stealLevel;
        t2.stealLevel=context.stealLevel;
        `,`
        static if (is(T:ElT[])){
            auto r=context.loopBody2(idx,context.arr[idx]);
        } else {
            auto el=context.arr[idx];
            auto r=context.loopBody2(idx,el);
            static if(is(typeof(delegate void(){context.arr[idx]=el;}))){
                context.arr[idx]=el;
            }
        }
        if (r!=0){
            context.res=r;
            return;
        }`,`
        } catch(Exception e){
            context.exception=e;
        }
        `));
        this(T arr,size_t optimalBlockSize=1){
            this.arr=arr;
            this.optimalBlockSize=optimalBlockSize;
        }
    } else {
        alias T IType;
        int delegate(ref T) loopBody;
        IType iStart, iEnd;
        
        mixin(loopCtxMixin("LoopBlock3",`
        PLoopHelper context;
        `,`
        blockSize=this.context.optimalBlockSize;
        if (this.context.res!=0||this.context.exception!is null) return;
        try{`,`
        t1.stealLevel=this.context.stealLevel;
        t2.stealLevel=this.context.stealLevel;
        `,`
        auto r=this.context.loopBody(idx);
        if (r!=0){
            this.context.res=r;
            return;
        }`,`
        }catch(Exception e){
            this.context.exception=e;
        }
        `,`T`));
        this(T start, T end,size_t optimalBlockSize=1){
            this.iStart=start;
            this.iEnd=end;
            this.optimalBlockSize=optimalBlockSize;
        }
    }
    void doLoop(LoopBlockT,LoopBodyT)(){
        try{
            if (this.firstDistribution){
                scope(exit){
                    this.firstDistribution=0;
                }
                static if (loopType==LoopType.Parallel){
                    auto tAtt=taskAtt.val;
                    stealLevel=tAtt.stealLevel();
                    SchedGroupI group=tAtt.scheduler().executer().schedGroup();
                    auto scheds=group.activeScheds();
                    if (iEnd >optimalBlockSize*scheds.length+iStart){
                        Task[128] tasksB;
                        Task[] tasks;
                        if (scheds.length<=tasksB.length){
                            tasks=tasksB[0..scheds.length];
                        } else {
                            tasks=new Task[](scheds.length);
                        }
                        IType nEl=cast(IType)(iEnd-iStart); // should be the unsigned type of IType
                        auto bsLow=nEl/scheds.length;
                        bsLow=(bsLow/optimalBlockSize)*optimalBlockSize;
                        auto bsUp=bsLow+optimalBlockSize;
                        auto nBsUp=(nEl-scheds.length*bsLow)/optimalBlockSize;
                        auto nBsLow=scheds.length-nBsUp;
                        if (nBsLow>0) --nBsLow;
                        else if (nBsUp>0) --nBsUp;
                        LoopBlockT *looper=new LoopBlockT;
                        looper.context=this;
                        looper.start=this.iStart;
                        looper.end=this.iEnd;
                        IType ii=this.iStart;
                        for (size_t i=0;i<nBsUp;++i){
                            auto blockAtt=looper.createNew();
                            blockAtt.start=ii;
                            ii+=bsUp;
                            blockAtt.end=ii;
                            auto t1=Task("PLoopArrayInitial",&blockAtt.exec).appendOnFinish(&blockAtt.giveBack);
                            t1.stealLevel=0;
                            tasks[i]=t1;
                            tAtt.spawnTask0(t1,scheds[i]);
                        }
                        for (size_t i=0;i<nBsLow;++i){
                            auto blockAtt=looper.createNew();
                            blockAtt.start=ii;
                            ii+=bsLow;
                            blockAtt.end=ii;
                            auto t1=Task("PLoopArrayInitial",&blockAtt.exec).appendOnFinish(&blockAtt.giveBack);
                            t1.stealLevel=0;
                            tasks[nBsUp+i]=t1;
                            tAtt.spawnTask0(t1,scheds[nBsUp+i]);
                        }
                        auto rest=nEl-nBsUp*nBsUp-nBsLow*nBsLow;
                        if (nBsLow+nBsUp<scheds.length){
                            auto blockAtt=looper.createNew();
                            blockAtt.start=ii;
                            blockAtt.end=iEnd;
                            auto t1=Task("PLoopArrayInitial",&blockAtt.exec).appendOnFinish(&blockAtt.giveBack);
                            t1.stealLevel=0;
                            tasks[nBsUp+nBsLow]=t1;
                            tAtt.spawnTask0(t1,scheds[nBsUp+nBsLow]);
                        } else {
                            assert(rest==0);
                        }
                        // a task might be stolen after this if stealLevel>0
                        // reduces the probability of having all waiting for a slow thread
                        for (size_t iTask=0;iTask<tasks.length;++iTask) {
                            tasks[iTask].stealLevel=stealLevel;
                            tasks[iTask].release();
                        }
                        if (tasks.length>tasksB.length) delete tasks;
                        return;
                    }
                }
            }
            if (loopType == LoopType.Parallel && iEnd>optimalBlockSize+optimalBlockSize/2+iStart){
                LoopBlockT.addGPool();
                scope(exit) LoopBlockT.rmGPool();
                LoopBlockT *looper=new LoopBlockT;
                looper.context=this;
                looper.start=iStart;
                looper.end=iEnd;
                looper.exec();
            } else {
                IType end=iEnd;
                for (IType idx=iStart;idx<end;++idx){
                    static if (!is(typeof(T.init[0]))){
                        T idx2=idx; // avoid copy?
                        auto r=loopBody(idx2);
                    } else static if (is(LoopBlockT==LoopBlock1)){
                        auto r=loopBody1(arr[idx]);
                    } else static if (is(LoopBlockT==LoopBlock2)){
                        IType idx2=idx; // avoid copy?
                        auto r=loopBody2(idx2,arr[idx]);
                    } else {
                        static assert(0,"unexpected type in PLoopHelper:"~LoopBlockT.stringof);
                    }
                    if (r!=0){
                        res=r;
                        return;
                    }
                }
            }
        } catch (Exception e) {
            exception=e;
        }
    }

    static if (is(typeof(T.init[0]))){
        int opApply(int delegate(ref ElT) loopBody){
            this.loopBody1=loopBody;
            if (arr.length>optimalBlockSize+optimalBlockSize/2){
                LoopBlock1.addGPool();
            }
            scope(exit) {
                if (arr.length>optimalBlockSize+optimalBlockSize/2)
                    LoopBlock1.rmGPool();
            }
            Task("PLoopArrayMain",&doLoop!(LoopBlock1,typeof(loopBody))).autorelease.executeNow();
            if (exception!is null)
                throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
            return res;
        }

        int opApply(int delegate(ref size_t,ref ElT) loopBody){
            this.loopBody2=loopBody;
            if (arr.length>optimalBlockSize+optimalBlockSize/2){
                LoopBlock2.addGPool();
            }
            scope(exit) {
                if (arr.length>optimalBlockSize+optimalBlockSize/2)
                    LoopBlock2.rmGPool();
            }
            Task("PLoopArrayMain",&doLoop!(LoopBlock2,typeof(loopBody))).autorelease.executeNow();
            if (exception!is null)
                throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
            return res;
        }
    } else {
        int opApply(int delegate(ref T) loopBody){
            this.loopBody=loopBody;
            if (this.iEnd>this.optimalBlockSize+this.optimalBlockSize/2+this.iStart){
                LoopBlock3.addGPool();
            }
            scope(exit) {
                if (this.iEnd>this.optimalBlockSize+this.optimalBlockSize/2+this.iStart)
                    LoopBlock3.rmGPool();
            }
            Task("PLoopArrayMain",&doLoop!(LoopBlock3,typeof(loopBody))).autorelease.executeNow();
            if (exception!is null)
                throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
            return res;
        }
    }
}

/// returns a structure that does a parallel loop on the given array trying to do optimalBlockSize loops in each task
/// loop on elements and loop with index are supported
PLoopHelper!(T,LoopType.Parallel) pLoopArray(T)(T arr,size_t optimalBlockSize=1){
    assert(optimalBlockSize>0,"optimalBlockSize must be larger than 0");
    auto res=new PLoopHelper!(T,LoopType.Parallel)(arr,optimalBlockSize);
    return res;
}

/// returns a structure that does a possibly parallel loop on the given array trying to do optimalBlockSize
/// loops in each task. loop on elements and loop with index are supported
PLoopHelper!(T,loopType) loopArray(int loopType,T)(T arr,size_t optimalBlockSize=1){
    assert(optimalBlockSize>0,"optimalBlockSize must be larger than 0");
    auto res=new PLoopHelper!(T,loopType)(arr,optimalBlockSize);
    return res;
}

/// returns a structure that does a parallel loop on the given range trying to do optimalBlockSize loops in each task
PLoopHelper!(T,LoopType.Parallel) pLoopIRange(T)(T iStart,T iEnd,size_t optimalBlockSize=1){
    assert(optimalBlockSize>0,"optimalBlockSize must be larger than 0");
    auto res=new PLoopHelper!(T,LoopType.Parallel)(iStart,iEnd,optimalBlockSize);
    return res;
}

/// returns a structure that does a sequential loop on the given range
PLoopHelper!(T,LoopType.Sequential) sLoopIRange(T)(T iStart,T iEnd){
    auto res=new PLoopHelper!(T,LoopType.Sequential)(iStart,iEnd);
    return res;
}

/// returns a structure that does a possibly parallel loop on the given range trying to do optimalBlockSize loops in each task
PLoopHelper!(T,loopType) loopIRange(int loopType, T)(T iStart,T iEnd,size_t optimalBlockSize=1){
    assert(optimalBlockSize>0,"optimalBlockSize must be larger than 0");
    auto res=new PLoopHelper!(T,loopType)(iStart,iEnd,optimalBlockSize);
    return res;
}

/// structure to do a parallel loop on an iterator (each element has its own task)
class PLoopIter(T){
    bool delegate(ref T) iter;

    static if(is(T U:U*)){
        alias U ElT;
    } else {
        alias T ElT;
    }
    int delegate(ref ElT) loopBody1;
    int delegate(ref size_t,ref ElT) loopBody2;
    int res=0;
    Exception exception;
    
    this(bool delegate(ref T) iter){
        this.iter=iter;
    }
    
    static struct LoopEl{
        PLoopIter context;
        LoopEl *next;
        PoolI!(LoopEl*) pool;
        size_t idx; // do a separate structure without idx?
        T el;
        static size_t nGPools=0;
        static Mutex gLock;
        static this(){
            gLock=new Mutex();
        }
        static CachedPool!(LoopEl*) gPool;
        static void addGPool(){
            synchronized(gLock){
                if (nGPools==0){
                    assert(gPool is null,"gPool is non null before new alloc");
                    gPool=cachedPoolNext(function LoopEl*(PoolI!(LoopEl*)p){
                        auto res=new LoopEl;
                        res.pool=p;
                        return res;
                    });
                }
                ++nGPools;
            }
        }
        static void rmGPool(){
            synchronized(gLock){
                if (nGPools==0) throw new Exception("unpaired rmGPool: nGPools is 0",__FILE__,__LINE__);
                --nGPools;
                if (nGPools==0){
                    gPool.stopCaching();
                    gPool=null;
                }
            }
        }
        static LoopEl *opCall(){
            assert(gPool!is null);
            LoopEl*res=gPool.getObj();
            return res;
        }
        void exec1(){
            if (context.res==0 && context.exception is null){
                try{
                    static if (is(T==ElT)){
                        auto r=context.loopBody1(el);
                    } else {
                        assert(el!is null,"iterator returning a null pointer");
                        auto r=context.loopBody1(*el);
                    }
                    if (r!=0){
                        context.res=r;
                        return;
                    }
                } catch(Exception e){
                    context.exception=e;
                }
            }
        }
        void exec2(){
            if (context.res==0 && context.exception is null){
                try{
                    static if (is(T==ElT)){
                        auto r=context.loopBody2(idx,el);
                    } else {
                        assert(el!is null,"iterator returning a null pointer");
                        auto r=context.loopBody2(idx,*el);
                    }
                    if (r!=0){
                        context.res=r;
                        return;
                    }
                } catch(Exception e){
                    context.exception=e;
                }
            }
        }
        void giveBack(){
            if (pool) pool.giveBack(this);
            else delete this;
        }
    }
    
    void doLoop1(){
        T el;
        while(iter(el)){
            LoopEl *op=LoopEl();
            op.el=el;
            op.context=this;
            Task("PLoopIterTask",&op.exec1).appendOnFinish(&op.giveBack).autorelease.submitYield();
        }
    }
    void doLoop2(){
        T el;
        size_t idx=0;
        while(iter(el)){
            LoopEl *op=LoopEl();
            op.el=el;
            op.context=this;
            op.idx=idx;
            Task("PLoopIterTask",&op.exec2).appendOnFinish(&op.giveBack).autorelease.submitYield();
            ++idx;
        }
    }
    
    int opApply(int delegate(ref ElT) loopBody){
        version(NoPLoopIter){
            Task("PLoopArrayMainSeq",delegate void(){
                T el;
                try{
                    while (iter(el)){
                        static if (is(T==ElT)){
                            auto r=loopBody(el);
                        } else {
                            assert(el!is null,"iterator returning a null pointer");
                            auto r=loopBody(*el);
                        }
                        if (r!=0) { res=r; return; }
                    }
                } catch (Exception e){
                    exception=e;
                }
            }).autorelease.executeNow();
        } else {
            LoopEl.addGPool();
            scope(exit) LoopEl.rmGPool();
            this.loopBody1=loopBody;
            Task("PLoopIterMain",&this.doLoop1).autorelease.executeNow();
        }
        if (exception!is null)
            throw new Exception("exception in PLoopIter",__FILE__,__LINE__,exception);
        return res;
    }

    int opApply(int delegate(ref size_t,ref ElT) loopBody){
        version(NoPLoopIter){
            Task("PLoopArrayMainSeq",delegate void(){
                T el;
                size_t i=0;
                try{
                    while (iter(el)){
                        static if (is(T==ElT)){
                            auto r=loopBody(i,el);
                        } else {
                            assert(el!is null,"iterator returning a null pointer");
                            auto r=loopBody(i,*el);
                        }
                        if (r!=0) { res=r; return; }
                        ++i;
                    }
                } catch (Exception e){
                    exception=e;
                }
            }).autorelease.executeNow();
        } else {
            LoopEl.addGPool();
            scope(exit) LoopEl.rmGPool();
            this.loopBody2=loopBody;
            Task("PLoopIterRMain",&this.doLoop2).autorelease.executeNow();
        }
        if (exception!is null)
            throw new Exception("exception in PLoopIter2",__FILE__,__LINE__,exception);
        return res;
    }
}

/// returns a structure that does a parallel loop on the given iterator
/// loop on elements and loop with index are supported
/// if the iterator returns a pointer it is assumed that it is not null
PLoopIter!(T) pLoopIter(T)(bool delegate(ref T) iter){
    assert(iter!is null,"iter has to be valid");
    PLoopIter!(T) res=new PLoopIter!(T)(iter);
    return res;
}


