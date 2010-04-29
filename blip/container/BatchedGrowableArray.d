/// a growable array that knows its capacity, and allocates in batches
/// thus if the array only grows one can cound on pointers in the array to remain valid
/// this is what sets it apart from GrowableArray and allows multithreaded use
module blip.container.BatchedGrowableArray;
import blip.util.Grow;
import blip.io.BasicIO: dumper; // needed just for the desc method
import blip.parallel.smp.WorkManager;

enum GASharing{
    Local, /// local, don't free
    GlobalNoFree, /// global, don't free, don't grow
    Global, /// global, free
}

int nextPower2(int i){
    int res=1;
    while(res<i){
        res*=2;
    }
    return i;
}

template defaultBatchSize(T){
    enum{ defaultBatchSize=nextPower2((2048/T.sizeof>128)?2048/T.sizeof:128) }
}
/// a growable(on one end) data storage
/// appending never invalidates older data/pointers, but data is not contiguous in memory
class BatchedGrowableArray(T,int batchSize=((2048/T.sizeof>128)?2048/T.sizeof:128)){
    static assert(((batchSize-1)&batchSize)==0,"batchSize should be a power of two"); // relax?
    /+
    /// structure to build a persistent tree of BatchHeader
    /// this is nice and all, but I thought that just using a GC collected jump table that is reallocated
    /// when too small is a better solution, so this will go (still here just to have a copy in the 
    /// repository..., fawzi)
    struct BatchHeader{
        size_t pos;
        T*batch;
        BatchHeader*prev;
        BatchHeader*next;
        static void subV(size_t v,ref size_t prevV,ref size_t nextV){
            size_t p=v;
            size_t idx=1;
            while((p&1)!=0){
                idx<<=1;
            }
            auto c=idx-1;
            prevV=(v&(~c))|(c>>1);
            nextV=prevV|idx;
        }
        size_t superV(size_t v){
            size_t p=v;
            size_t idx=1;
            while((p&1)!=0){
                idx<<=1;
            }
            return (v&(~(idx<<1)))|idx;
        }
        static BatchHeader*findHeader(size_t pos,BatchHeader*root){
            if (root is null) throw new Exception("pos not found",__FILE__,__LINE__);
            if (pos<root.pos) return findHeader(pos,root.prev);
            if (pos>root.pos) return findHeader(pos,root.next);
            return root;
        }
        static BatchHeader*findOrAdd(size_t pos,BatchHeader*root){
            assert(root!is null); // roots are added by another path
            if (pos<root.pos) {
                if (root.prev !is null) {
                    return findOrAdd(pos,root.prev);
                }
                size_t prevV,nextV;
                subV(root.pos,prevV,nextV);
                auto newBatchHeader=new BatchHeader;
                newBatchHeader.pos=prevV;
                root.prev=newBatchHeader;
                if (prevV==pos){
                    return newBatchHeader;
                }
                return findOrAdd(pos,newBatchHeader);
            }
            if (pos>root.pos) {
                if (root.next !is null) {
                    return findOrAdd(pos,root.next);
                }
                size_t prevV,nextV;
                subV(root.pos,prevV,nextV);
                auto newBatchHeader=new BatchHeader;
                newBatchHeader.pos=nextV;
                root.next=newBatchHeader;
                if (nextV==pos){
                    return newBatchHeader;
                }
                return findOrAdd(pos,newBatchHeader);
            }
            return root;
        }
        static BatchHeader*addHeader(ref BatchHeader*root,size_t pos,T*val){
            if(((pos+1)&pos)==0){// new root
                auto newHeader=BatchHeader;
                newHeader.pos=pos;
                newHeader.batch=val;
                size_t prevV,nextV;
                if (pos!=0){
                    subV(pos,prevV,nextV);
                    newHeader.prev=findHeader(prevV,root);
                    assert(newHeader.prev is root);
                }
                root=newHeader;
                return newHeader;
            }
            auto h=findOrAdd(pos,root);
            assert(h.batch is null,"double add");
            h.batch=val;
        }
        static void destroyAll(BatchHeader*root){
            if (root is null) return;
            if (root.prev !is null) destroyAll(root.prev);
            if (root.next !is null) destroyAll(root.next);
            if (root.batch !is null) free(root.batch);
            delete root;
        }
    }
    +/
    /// a frozen (just extent, not necessarily content) view of an array
    struct View {
        T*[] batches;
        size_t start;
        size_t end;
        
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
                if (view.start!=view.end){
                    auto ii=i+start;
                    assert(ii<length,"index out of bounds");
                    auto bIndex=ii/batchSize;
                    auto lStart=ii-bIndex*batchSize;
                    if (batchSize<view.end-ii){
                        el=batches[bIndex][lStart..batchSize];
                        view.start+=batchSize-lStart;
                    } else {
                        el=batches[bIndex][lStart..view.end-ii];
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
                auto iEnd=end-start;
                auto bIndex=start/batchSize;
                auto lStart=start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=batches[bIndex][0..batchSize];
                    if (auto res=loopBody(batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=batches[bIndex][0..batchSize];
                    auto res=loopBody(batches[bIndex][lStart..lStart+iEnd]);
                    return res;
                }
                iEnd-=batchSize;
                while(ii<=iEnd){
                    ++bIndex;
                    T[] batch=batches[bIndex][0..batchSize];
                    if (auto res=loopBody(batch)) return res;
                    ii+=batchSize;
                }
                iEnd+=batchSize;
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(batch)) return res;
                }
                return 0;
            }
            /// loop on the batches, the index is the index of the first element of the batch
            int opApply(int delegate(ref size_t,ref T[]) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                auto ii=0;
                auto iEnd=end-start;
                auto bIndex=start/batchSize;
                auto lStart=start-bIndex*batchSize;
                if (batchSize<lStart+iEnd){
                    T[] batch=batches[bIndex][0..batchSize];
                    if (auto res=loopBody(ii,batch)) return res;
                    ii+=batchSize-lStart;
                } else { // at end
                    T[] batch=batches[bIndex][0..batchSize];
                    auto res=loopBody(ii,batches[bIndex][lStart..lStart+iEnd]);
                    return res;
                }
                iEnd-=batchSize;
                while(ii<=iEnd){
                    ++bIndex;
                    T[] batch=batches[bIndex][0..batchSize];
                    if (auto res=loopBody(ii,batch)) return res;
                    ii+=batchSize;
                }
                iEnd+=batchSize;
                if (ii!=iEnd){
                    ++bIndex;
                    T[] batch=batches[bIndex][0..iEnd-ii];
                    if (auto res=loopBody(ii,batch)) return res;
                }
                return 0;
            }
        }
        struct Batch{
            T[] data;
            size_t startI;
            PLoop *context;
            Batch * next;
            void giveBack(){
                insertAt(context.pool,this);
            }
            void doIndexLoop(){
                try{
                    if ((context.res)==0 && context.exception is null){
                        auto res=loopBody.indexed(startI,data);
                        if (res!=0) *resPtr=res;
                    }
                } catch (Exception e){
                    *exceptionPtr=e;
                }
            }
            void doNoIndexLoop(){
                try{
                    if ((*resPtr)==0 && exceptionPtr is null){
                        auto res=loopBody.noIndex(data);
                        if (res!=0) *resPtr=res;
                    }
                } catch (Exception e){
                    *exceptionPtr=e;
                }
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
            Batch *pool;
            Looper loopBody;
            
            static PLoop opCall(View view){
                PLoop res;
                res.view=view;
                return res;
            }
            Batch* allocBatch(){
                auto newBatch=popFrom(pool);
                if (newBatch is null) newBatch=new Batch;
                newBatch.context=this;
                return new Batch;
            }
            
            void deallocBatches(){
                Batch *p=pool;
                while(p!is null){
                    auto n=p.next;
                    delete p;
                    p=n;
                }
            }
            /// loops on the batches
            int opApply(int delegate(ref T[]el) loopBody){
                if (view.start==view.end) return 0;
                assert(view.start<view.end);
                loopBody.noIndex=loopBody;
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    auto ii=0;
                    auto iEnd=end-start;
                    auto bIndex=start/batchSize;
                    auto lStart=start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=allocBatch();
                        bAtt.start=0;
                        bAtt.data=batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=batches[bIndex][0..batchSize];
                        auto res=loopBody(batches[bIndex][lStart..lStart+iEnd]);
                        return res;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.start=ii;
                        bAtt.data=batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doNoIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.start=ii;
                        bAtt.data=batches[bIndex][0..iEnd-ii];
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
                loopBody.indexed=loopBody;
                Task("BatchedGrowableArrayPLoopMain",delegate void(){
                    auto ii=0;
                    auto iEnd=end-start;
                    auto bIndex=start/batchSize;
                    auto lStart=start-bIndex*batchSize;
                    if (batchSize<lStart+iEnd){
                        auto bAtt=allocBatch();
                        bAtt.start=0;
                        bAtt.data=batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopFirst",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize-lStart;
                    } else { // at end
                        T[] batch=batches[bIndex][0..batchSize];
                        auto res=loopBody(batches[bIndex][lStart..lStart+iEnd]);
                        return res;
                    }
                    iEnd-=batchSize;
                    while(ii<=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.start=ii;
                        bAtt.data=batches[bIndex][0..batchSize];
                        Task("BatchedGrowableArrayPLoopIter",&bAtt.doIndexLoop)
                            .appendOnFinish(&bAtt.giveBack).autorelease.submitYield();
                        ii+=batchSize;
                    }
                    iEnd+=batchSize;
                    if (ii!=iEnd){
                        ++bIndex;
                        auto bAtt=allocBatch();
                        bAtt.start=ii;
                        bAtt.data=batches[bIndex][0..iEnd-ii];
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
                for (size_t i=0;i<t.length;++i){
                    if (auto res=loopEl(a[i])) return res;
                }
                return 0;
            }
        }
        struct ElIndexLoop{
            int delegate(ref size_t,ref T) loopEl;
            int loopBody(ref size_t i0,ref T[] a){
                auto ii=i0;
                for (size_t i=0;i<t.length;++i){
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
        BatchLoop pBatchLoop(){
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
    }
    
    View data;
    Mutex headerLock;
    
    size_t capacity(){
        return batchSize*batchStarts.length;
    }
    
    this(size_t batchSize=((2048/T.sizeof>128)?2048/T.sizeof:128)){
        data.batchSize=batchSize;
        headerLock=new Mutex();
    }
    
    size_t capacity(){
        return batchSize*batchStarts.length;
    }
    
    void appendArr(T[] a){
        synchronized(this){
            auto rest=capacity-length;
            size_t toCopy=min(rest,a.length);
            size_t lastBatch=length/batchSize;
            data.batches[lastBatch][batchSize-rest..batchSize+toCopy-rest]=a[0..toCopy];
            if (toCopy<a.length){
                size_t toAlloc=(a.length-rest+batchSize-1)/batchSize;
                if (lastBatch+toAlloc>data.batches.length){
                    auto newHeaders=T*[](growLength(lastBatch+toAlloc));
                    newHeaders[0..lastBatch]=data.batches[0..lastBatch];
                    data.batches=newHeaders;
                }
                auto batchStart=cast(T*)malloc(toAlloc*batchSize*T.sizeof);
                if (batchStart is null) throw new Exception("allocation failed",__FILE__,__LINE__);
                auto newBatches=batchStart[0..toAlloc*batchSize];
                if ((typeid(T).flags&1)!=0){
                    GC.addRange(newBatches.ptr,toAlloc*batchSize);
                }
                newBatches[0..a.length-rest]=a[rest..a.length];
                auto batchStart=newBatches.ptr;
                for(size_t iBatch=0;iBatch<toAlloc;++iBatch){
                    ++lastBatch;
                    data.batches[lastBatch]=batchStart;
                    batchStart+=batchSize;
                }
                data.length+=a.length;
            }
        }
    }
    /// grows the array to at least the requested size
    void growTo(size_t c){
        if (data.length<c){
            synchronized(this){
                if (capacity<c){
                    lastBatch=data.length/data.batchSize;
                    size_t toAlloc=(c-data.length+batchSize-1)/batchSize;
                    if (lastBatch+toAlloc>data.batches.length){
                        auto newHeaders=T*[](growLength(lastBatch+toAlloc));
                        newHeaders[0..lastBatch]=data.batches[0..lastBatch];
                        data.batches=newHeaders;
                    }
                    auto batchStart=(cast(T*)malloc(toAlloc*batchSize*T.sizeof));
                    if (batchStart is null) throw new Exception("allocation failed",__FILE__,__LINE__);
                    if ((typeid(T).flags&1)!=0){
                        GC.addRange(batchStart,toAlloc*batchSize);
                    }
                    for(size_t iBatch=0;iBatch<toAlloc;++iBatch){
                        ++lastBatch;
                        data.batches[lastBatch]=batchStart;
                        batchStart+=batchSize;
                    }
                }
                data.length=c;
            }
        }
        assert(data.length>=c);
    }
    
    void appendEl(T a){
        synchronized(this){
            auto len=data.length;
            auto lastBatch=len/batchSize;
            if (len==(lastBatch+1)*batchSize){
                growTo(len+1);
            } else{
                ++data.length;
            }
            data[len]=a;
        }
    }
    
    void desc(void delegate(char[])sink){
        // this is the only dependency on BasicIO...
        auto s=dumper(sink);
        s("<BatchedGrowableArray@")(cast(void*)this)(" len:")(this.data.length);
        s(" capacity:")(this.data.capacity)(">")("\n");
    }
    
    /// appends to the array
    void opCall(V)(V v){
        opCatAssign(v);
    }
    static if(is(T==ubyte)){
        void appendVoid(void[]t){
            if (t.length!=0){
                growTo(data.length+t.length);
                dataPtr[(dataLen-t.length)..dataLen]=cast(ubyte[])t;
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
            lastBatch=data.length/batchSize;
            foreach(b;data.batches[0..lastBatch]){
                if (b!is null) {
                    removeRange(b);
                    free(b);
                }
            }
            data.length=0;
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
