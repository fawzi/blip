module blip.containter.Pool;

/// a pool, tries to use little memory if not used, and grow gracefully
/// keeping heap activity small
class Pool(T,int batchSize=16){
    alias T ElType;
    static assert(batchSize & (batchSize-1)==0,"batchSize should be a power of 2");
    struct S{
        T[batchSize]array;
        S*next;
        S*prev;
    }
    size_t nEl;
    size_t nCapacity;
    size_t maxEl;
    size_t bufferSpace;
    T delegate() allocator;
    T delegate(T obj) reset;
    S* pool;
    this(T delegate() allocator=null,T delegate(T obj) reset=null,
        T delegate(T obj) clear=null, size_t bufferSpace=2*batchSize){
        this.allocator=allocator;
        this.reset=reset;
        this.clear=clear;
        this.bufferSpace=max(batchSize,bufferSpace);
    }
    /// returns an object to the pool
    void giveBack(T obj){
        if (obj is null) return;
        if (clear !is null) {
            obj=clear(obj);
            if (obj is null) return;
        }
        bool deleteObj=false;
        synchronized(this){
            if (nEl>=maxEl){
                deleteObj=true;
            }else if (nEl==nCapacity){
                S* nP=new S();
                np.array[0]=obj;
                if (pool is null){
                    nP.next=nP;
                    nP.prev=nP;
                } else {
                    nP.prev=pool.prev;
                    pool.prev.next=nP;
                    nP.next=pool;
                    pool.prev=nP;
                }
                pool=nP;
                nCapacity+=batchSize;
                ++nEl;
            } else {
                size_t pos=nEl & (batchSize-1);
                if (pos==0){
                    pool=pool.prev;
                }
                pool.array[pos]=obj;
                ++nEl;
            }
        }
        if (deleteObj) delete obj;
    }
    /// returns an object, if possible from the pool
    T getObj(){
        if (nEl>0){
            T obj;
            synchronized(this){
                if (nEl>0){
                    --nEl;
                    size_t pos=nEl & (batchSize-1);
                    obj=pool.array[pos];
                    pool.array[pos]=null;
                    if (pos==0){
                        pool=pool.prev;
                    }
                    if ((nCapacity-nEl)>bufferSpace){
                        nCapacity-=batchSize;
                        auto toRm=pool.prev;
                        toRm.prev.next=toRm.next;
                        toRm.next.prev=toRm.prev;
                        delete toRm;
                    }
                }
            }
            if (obj !is null){
                if (reset !is null) return reset(obj);
                return obj;
            }
        }
        return allocator();
    }
    /// get rid of all cached values
    void flush(){
        synchronized(this){
            if (pool !is null){
                S* p=pool,pNext=pool.next;
                while (nEl!=0){
                    --nEl;
                    size_t pos=nEl&(batchSize-1);
                    delete p.array[pos];
                    if (pos==0){
                        delete p;
                        p=pNext;
                        pNext=pNext.next;
                        assert(p!is pool || nEl==0,"nEl pool size mismatch");
                    }
                }
                while (p!is pool){
                    delete p;
                    p=pNext;
                    pNext=pNext.next;
                }
                nCapacity=cast(size_t)0;
            }
        }
    }
    /// destructor
    ~this(){
        flush();
    }
}