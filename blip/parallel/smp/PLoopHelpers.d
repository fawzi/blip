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

version(NoPLoop){
    version=NoPLoopIter;
}
// ploop iter has/exposes a subtle bug that I did not fix yet, deactivating it
version=NoPLoopIter;

/// creates a context for a loop.
/// ctxExtra should define a ctxName createNew() method, startLoop can define blockSize>0
/// no exception handlers are set up, you can set them up with startLoop and endLoop
char[] loopCtxMixin(char[]ctxName,char[]ctxExtra,char[] startLoop,char[]loopOp,char[] endLoop){
    return `
    struct `~ctxName~`{
        size_t start,end;
        `~ctxName~` *next;
        PoolI!(`~ctxName~`*) pool;
        `~ctxExtra~`
        static size_t nGPools;
        static auto gLock=typeid(typeof(*this));
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
        static void gPoolSync(){
            synchronized(gLock){ }
        }
        `~ctxName~` *createNew(){
            assert(gPool!is null,"invalid gPool (forgot addGPool call?)");
            auto res=gPool.getObj();
            //auto res=new `~ctxName~`; // pippo
            auto p=res.pool;
            *res=*this;
            res.pool=p;
            return res;
        }
        void exec(){
            size_t blockSize=1;
            `~startLoop~`
            if (end>start+blockSize+blockSize/2){
                auto newChunk=createNew();
                auto newChunk2=createNew();
                auto mid=(end-start)/2;
                if (blockSize<mid) // try to have exact multiples of optimalBlockSize (so that one can have a fast path for it)
                    mid=((mid+blockSize-1)/blockSize)*blockSize;
                auto midP=start+mid;
                newChunk.start=start;
                newChunk.end=midP;
                newChunk2.start=midP;
                newChunk2.end=end;
                Task("PLoopArraysub",&newChunk.exec).appendOnFinish(&newChunk.giveBack).autorelease.submit();
                Task("PLoopArraysub2",&newChunk2.exec).appendOnFinish(&newChunk2.giveBack).autorelease.submit();
            } else {
                for (size_t idx=start;idx<end;++idx){
                    `~loopOp~`;
                }
            }
            `~endLoop~`
        }
        void giveBack(){
            if (pool) pool.giveBack(this);
        }
    }`; 
}

// should use a slice in LoopBlock and thus specialize definitely on builtin arrays?
class PLoopArray(T){
    T arr;
    alias typeof(arr[0]) ElT;
    size_t optimalBlockSize=1;
    int delegate(ref ElT) loopBody1;
    int delegate(ref size_t,ref ElT) loopBody2;
    Exception exception=null;
    int res=0;
    
    mixin(loopCtxMixin("LoopBlock1",`
    PLoopArray context;
    `,`
    blockSize=context.optimalBlockSize;
    if (context.res!=0||context.exception!is null) return;
    try{`,`
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
    PLoopArray context;
    `,`
    blockSize=context.optimalBlockSize;
    if (context.res!=0||context.exception!is null) return;
    try{`,`
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
    int opApply(int delegate(ref ElT) loopBody){
        version(NoPLoop){} else {
            this.loopBody1=loopBody;
            if (arr.length>optimalBlockSize+optimalBlockSize/2){
                LoopBlock1.addGPool();
                scope(exit) LoopBlock1.rmGPool();
                LoopBlock1 *looper=new LoopBlock1;
                looper.context=this;
                looper.start=0;
                looper.end=arr.length;
                Task("PLoopArrayMain",&looper.exec).autorelease.executeNow();
                if (exception!is null)
                    throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
                return res;
            }
        }
        Task("PLoopArrayMainSeq",delegate void(){
            try{
                size_t end=arr.length;
                for (size_t idx=0;idx<end;++idx){
                    auto r=loopBody(arr[idx]);
                    if (r!=0){
                        res=r;
                        return;
                    }
                }
            } catch (Exception e) {
                exception=e;
            }
        }).autorelease.executeNow();
        if (exception!is null)
            throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
        return res;
    }

    int opApply(int delegate(ref size_t,ref ElT) loopBody){
        version(NoPLoop){} else {
            this.loopBody2=loopBody;
            if (arr.length>optimalBlockSize+optimalBlockSize/2){
                LoopBlock2.addGPool();
                scope(exit) LoopBlock2.rmGPool();
                LoopBlock2 *looper=new LoopBlock2;
                looper.context=this;
                looper.start=0;
                looper.end=arr.length;
                Task("PLoopArrayMain",&looper.exec).autorelease.executeNow();
                if (exception!is null)
                    throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
                return res;
            }
        }
        Task("PLoopArrayMainSeq",delegate void(){
            size_t end=arr.length;
            try{
                for (size_t idx=0;idx<end;++idx){
                    auto r=loopBody(idx,arr[idx]);
                    if (r!=0){
                        res=r;
                        return;
                    }
                }
            } catch (Exception e) {
                exception=e;
            }
        }).autorelease.executeNow();
        if (exception!is null)
            throw new Exception("exception in PLoopArray",__FILE__,__LINE__,exception);
        return res;
    }
    
}


/// returns a structure that does a parallel loop on the given array trying to do optimalBlockSize loops in each task
/// loop on elements and loop with index are supported
PLoopArray!(T) pLoopArray(T)(T arr,size_t optimalBlockSize=1){
    assert(optimalBlockSize>0,"optimalBlockSize must be lareger than 0");
    PLoopArray!(T) res=new PLoopArray!(T)(arr,optimalBlockSize);
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
        static auto gLock=typeid(typeof(*this));
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
        static void gPoolSync(){
            synchronized(gLock){ }
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
            //else delete this;
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
