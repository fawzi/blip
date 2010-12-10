/// a growable array that knows its capacity, and allocates in batches
/// thus if the array only grows one can cound on pointers in the array to remain valid
/// this is what sets it apart from GrowableArray and allows multithreaded use
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
module blip.container.BatchedGrowableArray;
import blip.util.Grow;
import blip.io.BasicIO: dumper; // needed just for the desc method
import blip.parallel.smp.WorkManager;
import blip.core.Traits;
import blip.core.sync.Mutex;
import blip.sync.Atomic;
import blip.container.AtomicSLink;
import blip.container.Pool;
import blip.container.Cache;
import blip.math.Math;
import blip.stdc.stdlib;
import blip.Comp;

private int nextPower2(int i){
    int res=1;
    while(res<i){
        res*=2;
    }
    return res;
}

template defaultBatchSize(T){
    enum{ defaultBatchSize=nextPower2((2048/T.sizeof>128)?2048/T.sizeof:128) }
}
/// a growable(on one end) data storage
/// appending never invalidates older data/pointers, but data is not contiguous in memory
/// data is written, *then* the new length is set, so accessing the length with a read barrier
/// guarantees that all the data up to length has been initialized
class BatchedGrowableArray(T,int batchSize=((2048/T.sizeof>128)?2048/T.sizeof:128)){
    static assert(((batchSize-1)&batchSize)==0,"batchSize should be a power of two"); // relax?
    /// a frozen (just extent, not necessarily content) view of a piece of array
    struct View {
        T*[] batches;
        size_t start;
        size_t end;
        
        size_t length(){
            return end-start;
        }
        T*ptrI(size_t i){
            auto ii=i+start;
            assert(ii<end,"index out of bounds");
            auto bIndex=ii/batchSize;
            return &(batches[bIndex][ii-bIndex*batchSize]);
        }
        T opIndex(size_t i){
            return *ptrI(i);
        }
        void opIndexAssign(T val,size_t i){
            *ptrI(i)=val;
        }
        /// loops on a view one batch at a time
        struct BatchLoop{
            View view;
            static BatchLoop opCall(View v){
                BatchLoop res;
                res.view=v;
                return res;
            }
            /// returns the next batch
            bool next(ref T[]el){ // could cache the current batch...
                if (view.start<view.end){
                    auto ii=view.start;
                    auto bIndex=ii/batchSize;
                    auto lStart=ii-bIndex*batchSize;
                    if (batchSize<view.end-ii){
                        el=view.batches[bIndex][lStart..batchSize];
                        view.start+=batchSize-lStart;
                    } else {
                        el=view.batches[bIndex][lStart..view.end-ii];
                        view.start=view.end;
                    }
                    return true;
                }
                return false;
            }
            /// loops on the batches
            int opApply(int delegate(ref T[]el) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                auto ii=0;
                auto iEnd=view.end-view.start;
                auto bIndex=view.start/batchSize;
                auto lStart=view.start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=view.batches[bIndex][lStart..lStart+iEnd];
                    auto res=loopBody(batch);
                    return res;
                }
                iEnd-=batchSize;
                while(ii<=iEnd){
                    ++bIndex;
                    T[] batch=view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(batch)) return res;
                    ii+=batchSize;
                }
                iEnd+=batchSize;
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=view.batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(batch)) return res;
                }
                return 0;
            }
            /// loop on the batches, the index is the index of the first element of the batch
            int opApply(int delegate(ref size_t,ref T[]) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                size_t ii=0;
                auto iEnd=view.end-view.start;
                auto bIndex=view.start/batchSize;
                auto lStart=view.start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(ii,batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=view.batches[bIndex][lStart..lStart+iEnd];
                    auto res=loopBody(ii,batch);
                    return res;
                }
                iEnd-=batchSize;
                while(ii<=iEnd){
                    ++bIndex;
                    T[] batch=view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(ii,batch)) return res;
                    ii+=batchSize;
                }
                iEnd+=batchSize;
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=view.batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(ii,batch)) return res;
                }
                return 0;
            }
        }
        struct PLoop{
            union Looper{
                int delegate(ref size_t,ref T[]) indexed;
                int delegate(ref T[]) noIndex;
            }
            View view;
            int res;
            Exception exception;
            Looper loopBody;
            struct Batch{
                T[] data;
                size_t startI;
                PLoop *context;
                Batch * next;
                PoolI!(Batch*) pool;
                void giveBack(){
                    if (pool!is null){
                        pool.giveBack(this);
                    } else {
                        delete this; // avoid???
                    }
                }
                void doIndexLoop(){
                    try{
                        if ((context.res)==0 && context.exception is null){
                            auto res=context.loopBody.indexed(startI,data);
                            if (res!=0) context.res=res;
                        }
                    } catch (Exception e){
                        context.exception=e;
                    }
                }
                void doNoIndexLoop(){
                    try{
                        if (context.res==0 && context.exception is null){
                            auto res=context.loopBody.noIndex(data);
                            if (res!=0) context.res=res;
                        }
                    } catch (Exception e){
                        context.exception=e;
                    }
                }
            }
            
            static PoolI!(Batch *) pool;
            static size_t poolLevel;
            static Mutex poolLock;
            static this(){
                poolLock=new Mutex(); // avoid prealloc?
            }
            static void addPool(){
                synchronized(poolLock){
                    if (poolLevel==0){
                        pool=cachedPoolNext(function Batch*(PoolI!(Batch*)p){
                            auto res=new Batch;
                            res.pool=p;
                            return res;
                        });
                    }
                    ++poolLevel;
                }
            }
            static void rmPool(){
                synchronized(poolLock){
                    if (poolLevel==0) throw new Exception("poolLevel was 0 in rmPool",__FILE__,__LINE__);
                    --poolLevel;
                    if (poolLevel==0){
                        pool.rmUser();
                        pool=null;
                    }
                }
            }
            static PLoop opCall(View view){
                PLoop res;
                res.view=view;
                return res;
            }
            Batch* allocBatch(){
                auto res=pool.getObj();
                res.context=this;
                return res;
            }
            
            /// loops on the batches
            int opApply(int delegate(ref T[]el) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                this.loopBody.noIndex=loopBody;
                addPool();
                scope(exit){ rmPool(); }
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    auto ii=0;
                    auto iEnd=view.end-view.start;
                    auto bIndex=view.start/batchSize;
                    auto lStart=view.start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=allocBatch();
                        bAtt.startI=0;
                        bAtt.data=view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=view.batches[bIndex][lStart..lStart+iEnd];
                        this.res=this.loopBody.noIndex(batch);
                        return;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=view.batches[bIndex][0..iEnd-ii];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submit();
                    }
                }).autorelease.executeNow();
                if (exception!is null) throw new Exception("exception in BatchedGrowableArray PLoop",
                    __FILE__,__LINE__,exception);
                return res;
            }
            /// loop on the batches, the index is the index of the first element of the batch
            int opApply(int delegate(ref size_t,ref T[]) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                this.loopBody.indexed=loopBody;
                addPool();
                scope(exit){ rmPool(); }
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    size_t ii=0;
                    auto iEnd=view.end-view.start;
                    auto bIndex=view.start/batchSize;
                    auto lStart=view.start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=allocBatch();
                        bAtt.startI=0;
                        bAtt.data=view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=view.batches[bIndex][lStart..lStart+iEnd];
                        res=this.loopBody.indexed(ii,batch);
                        return;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=view.batches[bIndex][0..iEnd-ii];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submit();
                    }
                }).autorelease.executeNow();
                if (exception!is null) throw new Exception("exception in BatchedGrowableArray PLoop",
                    __FILE__,__LINE__,exception);
                return res;
            }
        }
        struct ElLoop{
            int delegate(ref T) loopEl;
            int loopBody(ref T[]a){
                for (size_t i=0;i<a.length;++i){
                    if (auto res=loopEl(a[i])) return res;
                }
                return 0;
            }
        }
        struct ElIndexLoop{
            int delegate(ref size_t,ref T) loopEl;
            int loopBody(ref size_t i0,ref T[] a){
                auto ii=i0;
                for (size_t i=0;i<a.length;++i){
                    if (auto res=loopEl(ii,a[i])) return res;
                    ++ii;
                }
                return 0;
            }
        }
        /// sequential batch loop
        BatchLoop sBatchLoop(){
            return BatchLoop(*this);
        }
        /// parallel batch loop
        PLoop pBatchLoop(){
            return PLoop(*this);
        }
        int delegate(ref T[]) toBatch(int delegate(ref T)l){
            auto res=new ElLoop;
            res.loopEl=l;
            return &res.loopBody;
        }
        int delegate(ref size_t,ref T[]) toBatch(int delegate(ref size_t,ref T)l){
            auto res=new ElIndexLoop;
            res.loopEl=l;
            return &res.loopBody;
        }
        int opApply(int delegate(ref T)loop){
            auto loopB=toBatch(loop);
            return sBatchLoop.opApply(loopB);
        }
        int opApply(int delegate(ref size_t,ref T)loop){
            auto loopB=toBatch(loop);
            return sBatchLoop.opApply(loopB);
        }
    }
    
    View data;
    
    size_t capacity(){
        return batchSize*data.batches.length;
    }
    size_t length(){
        return data.length();
    }
    
    this(){
    }
    
    void appendArr(T[] a){
        synchronized(this){
            auto rest=capacity-length;
            size_t toCopy=min(rest,a.length);
            size_t nextBatch=data.end/batchSize;
            if (toCopy>0){
                size_t localStart=data.end-nextBatch*batchSize;
                size_t localSize=batchSize-localStart;
                size_t localToCopy=min(toCopy,localSize);
                data.batches[nextBatch][localStart..localStart+localToCopy]=a[0..localToCopy];
                size_t toCopyL=toCopy-localToCopy;
                while(toCopyL!=0){
                    ++nextBatch;
                    localToCopy=min(toCopy,batchSize);
                    data.batches[nextBatch][0..localToCopy]=a[0..localToCopy];
                    toCopyL-=localToCopy;
                }
                ++nextBatch;
            }
            if (toCopy<a.length){
                growCapacityTo(length+a.length); // contiguous alloc
                data.batches[nextBatch][0..a.length-rest]=a[rest..a.length];
            }
            writeBarrier(); // this allows using just a readBarrier to access the length...
            data.end+=a.length;
        }
    }
    /// grows the array to at least the requested capacity
    void growCapacityTo(size_t c){
        if (data.length<c){
            synchronized(this){
                if (capacity<c){
                    auto newC=growLength(c,T.sizeof);
                    auto nBatches=data.batches.length;
                    size_t toAlloc=(newC-capacity+batchSize-1)/batchSize;
                    auto newHeaders=new T*[](growLength(nBatches+toAlloc));
                    newHeaders[0..nBatches]=data.batches[0..nBatches];
                    auto batchStart=(cast(T*)malloc(toAlloc*batchSize*T.sizeof));
                    if (batchStart is null) throw new Exception("allocation failed",__FILE__,__LINE__);
                    if (typeHasPointers!(T)()){
                        GC.addRange(batchStart,toAlloc*batchSize);
                    }
                    for(size_t iBatch=0;iBatch<toAlloc;++iBatch){
                        newHeaders[nBatches]=batchStart;
                        ++nBatches;
                        batchStart+=batchSize;
                    }
                    writeBarrier();
                    data.batches=newHeaders;
                }
            }
        }
        assert(data.length>=c);
    }
    /// grows the array to at least the requested size
    void growTo(size_t c){
        if (data.length<c){
            growCapacityTo(c);
            synchronized(this){
                if (data.length<c){
                    data.end=data.start+c;
                }
            }
        }
    }
    /// appends one element
    void appendEl(T a){
        synchronized(this){
            auto len=data.length;
            auto lastBatch=len/batchSize;
            if (len==(lastBatch+1)*batchSize){
                growCapacityTo(len+1);
            }
            data[len]=a;
            writeBarrier();
            ++data.end;
        }
    }
    
    void desc(void delegate(cstring)sink){
        // this is the only dependency on BasicIO...
        auto s=dumper(sink);
        s("<BatchedGrowableArray@")(cast(void*)this)(" len:")(this.data.length);
        s(" capacity:")(this.capacity)(">")("\n");
    }
    
    /// appends to the array
    void opCall(V)(V v){
        opCatAssign(v);
    }
    static if(is(T==ubyte)){
        void appendVoid(void[]t){
            if (t.length!=0){
                synchronized(this){
                    growCapacityTo(data.length+t.length);
                    auto dataLen=data.length;
                    auto dataLenNew=dataLen+t.length;
                    dataPtr[dataLen..dataLenNew]=cast(ubyte[])t;
                    writeBarrier(); // this allows using just a readBarrier to access the length...
                    data.end+=t.length;
                }
            }
        }
        //alias appendVoid opCatAssign;
        void opCatAssign(void[]t){ appendVoid(t); }
    }
    /// appends an element
    //alias appendEl opCatAssign;
    void opCatAssign(T t){ appendEl(t); }
    /// appends a slice
    //alias appendArr opCatAssign;
    void opCatAssign(T[] t){ appendArr(t); }
    /// appends what the appender delegate sends
    void opCatAssign(void delegate(void delegate(T)) appender){
        appender(&this.appendEl);
    }
    /// appends what the appender delegate sends
    void opCatAssign(void delegate(void delegate(T[])) appender){
        appender(&this.appendArr);
    }
    /// deallocates data
    void deallocData(){
        synchronized(this){
            T* oldP=null;
            foreach(ref b;data.batches){
                if (b!is null && b!is oldP+batchSize) {
                    if (typeHasPointers!(T)()) GC.removeRange(b);
                    free(b);
                }
                oldP=b;
                b=null;
            }
            data.end=data.start;
        }
    }
    View view(){
        synchronized(this){
            return data;
        }
    }
    /// returns element at index i
    T opIndex(size_t i){
        return data[i];
    }
    /// pointer to element at index i
    T *ptrI(size_t i){
        return data.ptrI(i);
    }
    /// sets element at index i
    void opIndexAssign(T val,size_t i){
        data[i]=val;
    }
}
