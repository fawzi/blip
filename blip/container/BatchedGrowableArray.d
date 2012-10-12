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
import blip.stdc.stdlib: malloc,free;
import blip.Comp;
import blip.io.Console;
import blip.core.Traits;
import blip.serialization.Serialization;

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
class BatchedGrowableArray(T,int batchSize1=((2048/T.sizeof>128)?2048/T.sizeof:128)){
    enum :bool{ initialize=true }
    enum{batchSize=batchSize1}
    static assert(((batchSize-1)&batchSize)==0,"batchSize should be a power of two"); // relax?
    /// a frozen (just extent, not necessarily content) view of a piece of array
    static struct View {
        T*[] batches;
        size_t start;
        size_t end;
        
        size_t length(){
            return this.end-this.start;
        }
        T*ptrINoCheck(size_t i){
            auto ii=i+this.start;
            auto bIndex=ii/batchSize;
            return &(this.batches[bIndex][ii-bIndex*batchSize]);
        }
        T*ptrI(size_t i){
            auto ii=i+this.start;
            assert(ii<this.end,"index out of bounds");
            auto bIndex=ii/batchSize;
            return &(this.batches[bIndex][ii-bIndex*batchSize]);
        }
        ref T opIndex(size_t i){
            return *this.ptrI(i);
        }
        void opIndexAssign(T val,size_t i){
            *this.ptrI(i)=val;
        }
        /// loops on a view one batch at a time
        static struct BatchLoop{
            View view;
            static BatchLoop opCall(View v){
                BatchLoop res;
                res.view=v;
                return res;
            }
            /// returns the next batch
            bool next(ref T[]el){ // could cache the current batch...
                if (this.view.start<this.view.end){
                    auto ii=this.view.start;
                    auto bIndex=ii/batchSize;
                    auto lStart=ii-bIndex*batchSize;
                    if (batchSize<this.view.end-ii){
                        el=this.view.batches[bIndex][lStart..batchSize];
                        this.view.start+=batchSize-lStart;
                    } else {
                        el=this.view.batches[bIndex][lStart..this.view.end-ii];
                        this.view.start=this.view.end;
                    }
                    return true;
                }
                return false;
            }
            /// loops on the batches
            int opApply(scope int delegate(ref T[]el) loopBody){
                if (this.view.start==this.view.end) return 0;
                assert(this.view.start<this.view.end);
                auto ii=0;
                auto iEnd=this.view.end-this.view.start;
                auto bIndex=this.view.start/batchSize;
                auto lStart=this.view.start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=this.view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=this.view.batches[bIndex][lStart..lStart+iEnd];
                    auto res=loopBody(batch);
                    return res;
                }
                if (iEnd>batchSize){
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        T[] batch=this.view.batches[bIndex][0..batchSize];
                        if (auto res=loopBody(batch)) return res;
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                }
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=this.view.batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(batch)) return res;
                }
                return 0;
            }
            /// loop on the batches, the index is the index of the first element of the batch
            int opApply(scope int delegate(ref size_t,ref T[]) loopBody){
                if (this.view.start==this.view.end) return 0;
                assert(this.view.start<this.view.end);
                size_t ii=0;
                auto iEnd=this.view.end-this.view.start;
                auto bIndex=this.view.start/batchSize;
                auto lStart=this.view.start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=this.view.batches[bIndex][0..batchSize];
                    if (auto res=loopBody(ii,batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=this.view.batches[bIndex][lStart..lStart+iEnd];
                    auto res=loopBody(ii,batch);
                    return res;
                }
                if (iEnd>batchSize){
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        T[] batch=this.view.batches[bIndex][0..batchSize];
                        if (auto res=loopBody(ii,batch)) return res;
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                }
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=this.view.batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(ii,batch)) return res;
                }
                return 0;
            }
        }
        static struct PLoop{
            union Looper{
                int delegate(ref size_t,ref T[]) indexed;
                int delegate(ref T[]) noIndex;
            }
            View view;
            int res;
            Exception exception;
            Looper loopBody;
            static struct Batch{
                T[] data;
                size_t startI;
                PLoop *context;
                Batch * next;
                PoolI!(Batch*) pool;
                void giveBack(){
                    if (this.pool!is null){
                        this.pool.giveBack(&this);
                    } else {
                        //delete &this; // not possible in d2
                        this=Batch();
                    }
                }
                void doIndexLoop(){
                    try{
                        if ((this.context.res)==0 && this.context.exception is null){
                            auto res=this.context.loopBody.indexed(this.startI,this.data);
                            if (res!=0) this.context.res=res;
                        }
                    } catch (Exception e){
                        this.context.exception=e;
                    }
                }
                void doNoIndexLoop(){
                    try{
                        if (this.context.res==0 && this.context.exception is null){
                            auto res=this.context.loopBody.noIndex(this.data);
                            if (res!=0) this.context.res=res;
                        }
                    } catch (Exception e){
                        this.context.exception=e;
                    }
                }
            }
            
            static __gshared PoolI!(Batch *) pool;
            static __gshared size_t poolLevel;
            static __gshared Mutex poolLock;
            shared static this(){
                if (poolLock is null) poolLock=new Mutex(); // avoid prealloc?
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
                auto res=this.pool.getObj();
                res.context=&this;
                return res;
            }
            
            /// loops on the batches
            int opApply(scope int delegate(ref T[]el) loopBody){
                if (this.view.start==this.view.end) return 0;
                assert(this.view.start<this.view.end);
                this.loopBody.noIndex=loopBody;
                addPool();
                scope(exit){ rmPool(); }
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    auto ii=0;
                    auto iEnd=this.view.end-this.view.start;
                    auto bIndex=this.view.start/batchSize;
                    auto lStart=this.view.start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=this.allocBatch();
                        bAtt.startI=0;
                        bAtt.data=this.view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=this.view.batches[bIndex][lStart..lStart+iEnd];
                        this.res=this.loopBody.noIndex(batch);
                        return;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=this.allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=this.view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=this.allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=this.view.batches[bIndex][0..iEnd-ii];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submit();
                    }
                }).autorelease.executeNow();
                if (this.exception!is null) throw new Exception("exception in BatchedGrowableArray PLoop",
                    __FILE__,__LINE__,this.exception);
                return this.res;
            }
            /// loop on the batches, the index is the index of the first element of the batch
            int opApply(scope int delegate(ref size_t,ref T[]) loopBody){
                if (this.view.start==this.view.end) return 0;
                assert(this.view.start<this.view.end);
                this.loopBody.indexed=loopBody;
                addPool();
                scope(exit){ rmPool(); }
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    size_t ii=0;
                    auto iEnd=this.view.end-this.view.start;
                    auto bIndex=this.view.start/batchSize;
                    auto lStart=this.view.start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=this.allocBatch();
                        bAtt.startI=0;
                        bAtt.data=this.view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=this.view.batches[bIndex][lStart..lStart+iEnd];
                        this.res=this.loopBody.indexed(ii,batch);
                        return;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=this.allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=this.view.batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=this.allocBatch();
                        bAtt.startI=ii;
                        bAtt.data=this.view.batches[bIndex][0..iEnd-ii];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submit();
                    }
                }).autorelease.executeNow();
                if (this.exception!is null) throw new Exception("exception in BatchedGrowableArray PLoop",
                    __FILE__,__LINE__,this.exception);
                return this.res;
            }
        }
        struct ElLoop{
            int delegate(ref T) loopEl;
            int loopBody(ref T[]a){
                for (size_t i=0;i<a.length;++i){
                    if (auto res=this.loopEl(a[i])) return res;
                }
                return 0;
            }
        }
        struct ElIndexLoop{
            int delegate(ref size_t,ref T) loopEl;
            int loopBody(ref size_t i0,ref T[] a){
                auto ii=i0;
                for (size_t i=0;i<a.length;++i){
                    if (auto res=this.loopEl(ii,a[i])) return res;
                    ++ii;
                }
                return 0;
            }
        }
        /// sequential batch loop
        BatchLoop sBatchLoop(){
            return BatchLoop(this);
        }
        /// parallel batch loop
        PLoop pBatchLoop(){
            return PLoop(this);
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
        int opApply(scope int delegate(ref T)loop){
            auto loopB=this.toBatch(loop);
            return this.sBatchLoop.opApply(loopB);
        }
        int opApply(scope int delegate(ref size_t,ref T)loop){
            auto loopB=this.toBatch(loop);
            return this.sBatchLoop.opApply(loopB);
        }
    }
    
    View data;
    
    size_t capacity(){
        return batchSize*this.data.batches.length;
    }
    size_t length(){
        return this.data.length();
    }
    
    this(){
    }
    
    T *appendArrT(T[] a){
        T* res;
        synchronized(this){
            auto rest=this.capacity-this.length;
            size_t toCopy=min(rest,a.length);
            size_t nextBatch=this.data.end/batchSize;
            if (toCopy>0){
                size_t localStart=this.data.end-nextBatch*batchSize;
                size_t localSize=batchSize-localStart;
                size_t localToCopy=min(toCopy,localSize);
                res=&(this.data.batches[nextBatch][localStart]);
                this.data.batches[nextBatch][localStart..localStart+localToCopy]=a[0..localToCopy];
                size_t toCopyL=toCopy-localToCopy;
                auto pos=localToCopy;
                while(toCopyL!=0){
                    ++nextBatch;
                    localToCopy=min(toCopyL,batchSize);
                    this.data.batches[nextBatch][0..localToCopy]=a[pos..pos+localToCopy];
                    toCopyL-=localToCopy;
                    pos+=localToCopy;
                }
                ++nextBatch;
            }
            if (a.length>toCopy){
                this.growCapacityTo(this.length+a.length); // contiguous alloc
                assert(rest==toCopy);
                this.data.batches[nextBatch][0..a.length-rest]=a[rest..a.length];
            }
            writeBarrier(); // this allows using just a readBarrier to access the length...
            this.data.end+=a.length;
        }
        return res;
    }
    final void appendArr(T[] a){
        this.appendArrT(a);
    }
    /// grows the array to at least the requested capacity
    void growCapacityTo(size_t c){
        if (this.data.length<c){
            synchronized(this){
                if (this.capacity<c){
                    auto newC=growLength(c,T.sizeof);
                    auto nBatches=this.data.batches.length;
                    size_t toAlloc=(newC-this.capacity+batchSize-1)/batchSize;
                    auto newHeaders=new T*[](nBatches+toAlloc);
                    newHeaders[0..nBatches]=this.data.batches[0..nBatches];
                    //auto batchStart=(cast(T*)malloc(toAlloc*batchSize*T.sizeof));
                    //static if (initialize) batchStart[0..toAlloc*batchSize]=T.init;
                    auto addedBatch=new T[](toAlloc*batchSize);
                    auto batchStart=addedBatch.ptr;
                    if (batchStart is null) throw new Exception("allocation failed",__FILE__,__LINE__);
                    //if (typeHasPointers!(T)()){
                    //    GC.addRange(batchStart,toAlloc*batchSize*T.sizeof);
                    //}
                    for(size_t iBatch=0;iBatch<toAlloc;++iBatch){
                        newHeaders[nBatches]=batchStart;
                        ++nBatches;
                        batchStart+=batchSize;
                    }
                    assert(nBatches==newHeaders.length);
                    writeBarrier();
                    this.data.batches=newHeaders;
                }
            }
        }
        assert(this.capacity>=c);
    }
    /// grows the array to at least the requested size
    /// should initialize what is added...
    void growTo(size_t c){
        if (this.data.length<c){
            this.growCapacityTo(c);
            synchronized(this){
                if (this.data.length<c){
                    this.data.end=this.data.start+c;
                }
            }
        }
        assert(this.data.length>=c);
    }
    /// appends one element
    T *appendElT(T a){
        T* res;
        synchronized(this){
            auto len=this.data.length;
            auto lastBatch=(len+batchSize-1)/batchSize;
            if (len==lastBatch*batchSize){
                this.growCapacityTo(len+1);
            }
            res=this.data.ptrINoCheck(len);
            *res=a;
            writeBarrier();
            ++this.data.end;
        }
        return res;
    }
    final void appendEl(T a){
        this.appendElT(a);
    }
    
    /// index from pointer
    size_t ptr2Idx(T* p){
        size_t res=size_t.max;
        foreach(i,b;this.data.batches){
            if (p>=b && p<b+batchSize){
                res=i*batchSize+(p-b);
                break;
            }
        }
        return res;
    }
    
    /// appends to the array
    void opCall(V)(V v){
        opCatAssign(v);
    }
    static if(is(T==ubyte)||is(T==byte)){
        void appendVoid(void[]t){
            this.appendArr(cast(T[])t);
        }
        //alias appendVoid opCatAssign;
        void opCatAssign(void[]t){ this.appendVoid(t); }
    }
    /// appends an element
    //alias appendEl opCatAssign;
    void opCatAssign(T t){ this.appendEl(t); }
    /// appends a slice
    //alias appendArr opCatAssign;
    void opCatAssign(T[] t){ this.appendArr(t); }
    /// appends what the appender delegate sends
    void opCatAssign(scope void delegate(scope void delegate(T)) appender){
        appender(&this.appendEl);
    }
    /// appends what the appender delegate sends
    void opCatAssign(scope void delegate(scope void delegate(T[])) appender){
        appender(&this.appendArr);
    }
    /// deallocates data
    void deallocData(){
        synchronized(this){
            T* oldP=null;
            foreach(ref b;this.data.batches){
                if (b!is null && b!is oldP+batchSize) {
                    //if (typeHasPointers!(T)()) GC.removeRange(b);
                    //free(b);
                }
                oldP=b;
                b=null;
            }
            this.data.end=this.data.start;
            this.data.batches=null;
        }
    }
    View view(){
        synchronized(this){
            return this.data;
        }
    }
    /// returns element at index i
    ref T opIndex(size_t i){
        return this.data[i];
    }
    /// pointer to element at index i
    T *ptrI(size_t i){
        return this.data.ptrI(i);
    }
    /// sets element at index i
    void opIndexAssign(T val,size_t i){
        this.data[i]=val;
    }
    
    static if (isCoreType!(T) ||is(typeof(T.init.serialize(Serializer.init)))) {
        static __gshared ClassMetaInfo metaI;
        shared static this(){
            if (metaI is null){
                metaI=ClassMetaInfo.createForType!(typeof(this))("blip.container.BatchedGrowableArray("~T.mangleof~")","a batched growable array");
                metaI.addFieldOfType!(T[])("array","the items in the array");
            }
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        void preSerialize(Serializer s){ }
        void postSerialize(Serializer s){ }
        void serialize(Serializer s){
            LazyArray!(T) la=LazyArray!(T)(delegate int(scope int delegate(ref T)loopBody){
                int res=0;
                foreach (b;this.view.sBatchLoop){
                    for (size_t i=0;i<b.length;++i){
                        res=loopBody(b[i]);
                        if (res!=0) break;
                    }
                    if (res!=0) break;
                }
                return res;
            },cast(ulong)this.length);
            s.field(metaI[0],la);
        }

        void unserialize(Unserializer s){
            LazyArray!(T) la=LazyArray!(T)(&this.appendEl,delegate void(ulong l){ 
                if (l!=ulong.max) this.growCapacityTo(cast(size_t) l);
            });
            s.field(metaI[0],la);
        }
    
        mixin printOut!();
    } else {
        /// description of the object
        void desc(scope void delegate(in cstring)sink){
            // this is the only dependency on BasicIO...
            auto s=dumper(sink);
            s("<BatchedGrowableArray@")(cast(void*)this)(" len:")(this.data.length);
            s(" capacity:")(this.capacity)(">")("\n");
        }
    }
    
}
