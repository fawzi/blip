/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.container.Pool;
import blip.t.core.Traits:ctfe_i2a;
import blip.t.math.Math: max;

/// describes a pool like object
interface PoolI(T){
    /// gets a new instance
    T getObj();
    static if (is(T U:U[])){
        /// gets a new instance of dimension dim (if applicable)
        T getObj(size_t dim);
    }
    /// returns an instance, so that it can be reused
    void giveBack(T obj);
    /// should discard all the cached objects (no guarantee)
    void flush();
    /// should not cache any objects from now on (no guarantee)
    void stopCaching();
}

/// calls the allocator for the given type
T allocT(T,A...)(A args) {
    static if(is(T==class)){
        static if (is(typeof(new T(args)))){
            return new T(args);
        } else {
            assert(false,"no empty constructor for "~T.stringof~" with "~A.stringof
                ~" you need to override the allocation method");
        }
    } else static if (is(T==struct)){
        return T.init;
    } else static if (is(T U:U*)){
        T t;
        static if (is(typeof(new U(args)))){
            t=new U(args);
        } else {
            assert(false,"no empty constructor for "~T.stringof~" with "~A.stringof
                ~" you need to override the allocation method");
        }
        return t;
    }
}

/// a pool, tries to use little memory if not used, and grow gracefully
/// keeping heap activity small
class Pool(T,int _batchSize=16):PoolI!(T){
    enum :int{ batchSize=_batchSize }
    alias T ElType;
    static assert((batchSize & (batchSize-1))==0,"batchSize should be a power of 2 "~ctfe_i2a(batchSize));
    struct S{
        T[batchSize]array;
        S*next;
        S*prev;
    }
    size_t nEl;
    size_t nCapacity;
    size_t maxEl;
    size_t bufferSpace;
    S* pool;
    
    this(size_t bufferSpace=8*batchSize, size_t maxEl=16*batchSize){
        this.maxEl=max(batchSize,maxEl);
        this.bufferSpace=max(batchSize,bufferSpace);
    }
    /// allocates a new object of type T
    T allocateNew(){
        return allocT!(T)();
    }
    /// clears object T before adding it to pool storage
    T clear(T obj){
        static if(is(typeof(obj.clear()))){
            obj.clear();
        }
        return obj;
    }
    /// resets a object just before returning it as new
    T reset(T obj){
        static if(is(typeof(obj.reset()))){
            obj.reset();
        }
        return obj;
    }
    /// returns an object to the pool
    void giveBack(T obj){
        if (obj is null) return;
        obj=clear(obj);
        if (obj is null) return;
        bool deleteObj=false;
        synchronized(this){
            if (nEl>=maxEl){
                deleteObj=true;
            }else if (nEl==nCapacity){
                S* nP=new S();
                nP.array[0]=obj;
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
                return reset(obj);
            }
        }
        return allocateNew();
    }
    static if (is(T U:U[])){
        /// getObj with size unsupported...
        T getObj(size_t dim){
            if (nEl>0){
                T obj;
                synchronized(this){
                    if (nEl>0){
                        --nEl;
                        size_t pos=nEl & (batchSize-1);
                        obj=pool.array[pos];
                        if (obj.length==dim){
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
                        } else {
                            ++nEl;
                            obj=null;
                        }
                    }
                }
                if (obj !is null){
                    return reset(obj);
                }
            }
            return new T(dim);
        }
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
    void stopCaching(){
        maxEl=0;
        flush();
    }
    /// destructor
    ~this(){
        flush();
    }
}