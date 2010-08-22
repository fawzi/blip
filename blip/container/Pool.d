/// Pools to have free list based reuse of given back objects
///
/// You might wanto to use these together with a cache, more specifically
/// with cachedPoolNext and cachedPool of blip.container.Cache
///
/// author:fawzi
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
module blip.container.Pool;
import blip.core.Traits:ctfe_i2a,tryDeleteT,isNullT;
import blip.math.Math: max;
import blip.container.AtomicSLink;
import blip.sync.Atomic;

debug(TrackPools) {
    import blip.io.BasicIO;
    import blip.io.Console;
    import blip.container.GrowableArray;
}

/// describes a pool like object
interface PoolI(T){
    /// gets a new instance
    T getObj();
    static if (is(T U:U[])){
        /// gets a new instance of dimension dim (if applicable)
        U[] getObj(size_t dim);
    }
    /// returns an instance, so that it can be reused
    void giveBack(T obj);
    /// should discard all the cached objects (no guarantee)
    void flush();
    /// should not cache any objects from now on (no guarantee)
    void stopCaching();
    /// add an active user
    void addUser();
    /// removes an active user (if there are 0 active users stopCaching is called)
    void rmUser();
}

/// calls the allocator for the given type
T allocT(T,A...)(A args) {
    static if(is(T==class)){
        static if (is(typeof(new T(args)))){
            return new T(args);
        } else {
            static assert(false,"no empty constructor for "~T.stringof~" with "~A.stringof
                ~" you need to override the allocation method");
        }
    } else static if (is(T==struct)){
        return T.init;
    } else static if (is(T U:U*)){
        T t;
        static if (is(typeof(new U(args)))){
            t=new U(args);
        } else {
            static assert(false,"no empty constructor for "~T.stringof~" with "~A.stringof
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
    size_t activeUsers=1;
    T delegate(PoolI!(T)) customAllocator;
    
    this(T delegate(PoolI!(T)) customAllocator,size_t bufferSpace=8*batchSize, size_t maxEl=16*batchSize){
        this.maxEl=max(batchSize,maxEl);
        this.bufferSpace=max(batchSize,bufferSpace);
        this.customAllocator=customAllocator;
        this.activeUsers=1;
    }
    
    /// helper to have a pool generating delegate
    struct PoolFactory(U){
        U call;
        size_t bufferSpace=8*batchSize;
        size_t maxEl=16*batchSize;
        
        /// internal method that creates a new object
        T createNew(PoolI!(T)l){
            static if (is(typeof(call(l))==T)){
                return call(l);
            } else static if (is(typeof(call())==T)){
                return call();
            } else {
                static assert(0,"cannot convert "~U.stringof~" to a PoolI!("~T.stringof~"), expected a delegate that creates "~T.stringof);
            }
        }

        PoolI!(T)createPool(){
            return new Pool(&createNew,bufferSpace,maxEl);
        }
    }
    /// creates a pool generating delegate from most method to create T objects:
    /// T function(), T function(PoolI!(T)), T delegate(), T delegate(PoolI!(T))
    static PoolI!(T) delegate() poolFactory(U)(U cNew,size_t bufferSpace=8*batchSize,
        size_t maxEl=16*batchSize){
        auto factory=new PoolFactory!(U);
        factory.call=cNew;
        factory.bufferSpace=bufferSpace;
        factory.maxEl=maxEl;
        return &factory.createPool;
    }
    
    /// allocates a new object of type T
    T allocateNew(){
        debug(TrackPools){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("pool @")(cast(void*)this)(" will create new ")(T.stringof)("\n");
            });
        }
        if (customAllocator!is null){
            return customAllocator(this);
        }
        static if (is(typeof(allocT!(T)(this))==T)){
            return allocT!(T)(this);
        } else static if (is(typeof(allocT!(T)())==T)){
            return allocT!(T)();
        } else {
            assert(0,"could not allocate automatically type "~T.stringof~" and no customAllocator given");
        }
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
        debug(TrackPools){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("pool @")(cast(void*)this)(" given back ")(T.stringof)("@")(cast(void*)obj)("=")(obj)("\n");
            });
        }
        if (isNullT(obj)) return;
        obj=clear(obj);
        if (isNullT(obj)) return;
        bool deleteO=false;
        synchronized(this){
            if (nEl>=maxEl){
                deleteO=true;
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
            debug(TrackPools){
                if (!deleteO) sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("pool @")(cast(void*)this)(" added ")(T.stringof)("@")(cast(void*)obj)(" to pool, nEl=")(nEl)(" nCapacity=")(nCapacity)("\n");
                });
            }
        }
        if (deleteO){
            tryDeleteT(obj);
        }
    }
    /// returns an object, if possible from the pool
    T getObj(){
        if (nEl>0){
            T obj;
            bool found=false;
            synchronized(this){
                if (nEl>0){
                    found=true;
                    --nEl;
                    size_t pos=nEl & (batchSize-1);
                    obj=pool.array[pos];
                    pool.array[pos]=T.init;
                    if (pos==0){
                        pool=pool.next;
                    }
                    if ((nCapacity-nEl)>bufferSpace){
                        nCapacity-=batchSize;
                        auto toRm=pool.prev;
                        toRm.prev.next=toRm.next;
                        toRm.next.prev=toRm.prev;
                        tryDeleteT(toRm);
                    }
                    debug(TrackPools){
                        sinkTogether(sout,delegate void(CharSink s){
                            dumper(s)("pool @")(cast(void*)this)(" got object from pool ")(T.stringof)("@")(cast(void*)obj)(", nEl=")(nEl)(" nCapacity=")(nCapacity)("\n");
                        });
                    }
                }
            }
            if (found){
                return reset(obj);
            }
        }
        return allocateNew();
    }
    static if (is(T U:U[])){
        /// getObj with size
        U[] getObj(size_t dim){
            if (nEl>0){
                T obj;
                bool found=false;
                synchronized(this){
                    if (nEl>0){
                        --nEl;
                        size_t pos=nEl & (batchSize-1);
                        obj=pool.array[pos];
                        if (obj.length==dim){
                            found=true;
                            pool.array[pos]=T.init;
                            if (pos==0){
                                pool=pool.prev;
                            }
                            if ((nCapacity-nEl)>bufferSpace){
                                nCapacity-=batchSize;
                                auto toRm=pool.prev;
                                toRm.prev.next=toRm.next;
                                toRm.next.prev=toRm.prev;
                                tryDeleteT(toRm);
                            }
                        } else {
                            ++nEl;
                            obj=T.init;
                        }
                    }
                }
                if (found){
                    return reset(obj);
                }
            }
            return new U[](dim);
        }
    }
    /// get rid of all cached values
    void flush(){
        debug(TrackPools){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("pool @")(cast(void*)this)(" deleting cached objects nEl=")(nEl)(" nCapacity=")(nCapacity)("\n");
            });
        }
        synchronized(this){
            if (pool !is null){
                S* p=pool,pNext=pool.next;
                while (nEl!=0){
                    --nEl;
                    size_t pos=nEl&(batchSize-1);
                    debug(TrackPools){
                        sinkTogether(sout,delegate void(CharSink s){
                            dumper(s)("pool @")(cast(void*)this)(" deleting obj ")(T.stringof)("@")(cast(void*)(p.array[pos]))("\n");
                        });
                    }
                    tryDeleteT(p.array[pos]);
                    if (pos==0){
                        delete p;
                        p=pNext;
                        pNext=pNext.next;
                        assert(p!is pool || nEl==0,"nEl pool size mismatch");
                    }
                }
                while (p!is pool && p!is null){
                    delete p;
                    p=pNext;
                    pNext=pNext.next;
                    p.next=null;
                }
                nCapacity=cast(size_t)0;
            }
        }
    }
    void stopCaching(){
        maxEl=0;
        flush();
    }
    /// add an active user (when created one active user is automatically added)
    void addUser(){
        if (atomicAdd(activeUsers,cast(size_t)1)==0){
            throw new Exception("addUser called on non used pool",__FILE__,__LINE__);
        }
    }
    /// removes an active user (if there are 0 active users stopCaching is called)
    void rmUser(){
        auto oldUsers=atomicAdd(activeUsers,-cast(size_t)1);
        if (oldUsers==0){
            throw new Exception("rmUser called on non used pool",__FILE__,__LINE__);
        }
        if (oldUsers==1){
            stopCaching();
        }
    }
    /// destructor
    ~this(){
        flush();
    }
}

/// a next style unbounded freelist, can be used when T has a next attribute that builds a single linked list
/// *no* heap activity, minimal atomic ops
class PoolNext(T):PoolI!(T){
    T first=null;
    T delegate(PoolI!(T)) createNew;
    size_t activeUsers=1;
    bool cacheStopped=false;
    
    /// constructor
    this(T delegate(PoolI!(T)) cNew){
        createNew=cNew;
        activeUsers=1;
    }
    /// helper to have a pool generating delegate
    struct PoolFactory(U){
        U call;

        /// internal method that creates a new object
        T createNew(PoolI!(T)l){
            static if (is(typeof(call(l))==T)){
                return call(l);
            } else static if (is(typeof(call())==T)){
                return call();
            } else {
                static assert(0,"cannot convert "~U.stringof~" to a delegate for NFreeList("~T.stringof~")");
            }
        }
        
        PoolNext createPoolNext(){
            return new PoolNext(&createNew);
        }
        
        PoolI!(T)createPool(){
            return new PoolNext(&createNew);
        }
    }
    /// creates a pool generating delegate from most method to create T objects:
    /// T function(), T function(PoolI!(T)), T delegate(), T delegate(PoolI!(T))
    static PoolI!(T) delegate() poolFactory(U)(U cNew){
        auto factory=new PoolFactory!(U);
        factory.call=cNew;
        return &factory.createPool;
    }
    
    /// returns a new object if possible from the cached ones
    T getObj(){
        T res=popFrom(first);
        if (res is null) {
            debug(TrackPools){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" allocating new object\n");
                });
            }
            if (createNew !is null) res=createNew(this);
            else throw new Exception("no allocator",__FILE__,__LINE__);
        } else {
            debug(TrackPools){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" reusing pool object\n");
                });
            }
        }
        return res;
    }
    
    static if (is(T U:U[])){
        /// gets a new instance of dimension dim (if applicable)
        U[] getObj(size_t dim){
            T res=popFrom(first);
            if (res.length==dim){
                return res;
            }
            giveBack(res);
            return new U[](dim);
        }
    }
    
    /// removes the cached objects
    void flush(){
        debug(TrackPools){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" removing cached objects\n");
            });
        }
        T elAtt=popFrom(first);
        while(elAtt!is null){
            T oldV=elAtt;
            elAtt=popFrom(first);
            debug(TrackPools){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" deallocating object@")(cast(void*)oldV)("\n");
                });
            }
            static if (is(typeof(oldV.deallocData()))){
                oldV.deallocData();
            }
            tryDeleteT(oldV);
        }
    }
    /// stop caching
    void stopCaching(){
        cacheStopped=true;
        flush();
    }
    /// add an active user (when created one active user is automatically added)
    void addUser(){
        if (atomicAdd(activeUsers,cast(size_t)1)==0){
            throw new Exception("addUser called on non used pool",__FILE__,__LINE__);
        }
    }
    /// removes an active user (if there are 0 active users stopCaching is called)
    void rmUser(){
        auto oldUsers=atomicAdd(activeUsers,-cast(size_t)1);
        if (oldUsers==0){
            throw new Exception("rmUser called on non used pool",__FILE__,__LINE__);
        }
        if (oldUsers==1){
            stopCaching();
        }
    }
    /// returns an object to the free list to be reused
    void giveBack(T el){
        if (el!is null){
            if (!cacheStopped){
                debug(TrackPools){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" adding object@")(cast(void*)el)(" to the cache\n");
                    });
                }
                insertAt(first,el);
            } else {
                debug(TrackPools){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("PoolNext!(")(T.stringof)(")@")(cast(void*)this)(" deleting non reusable object@")(cast(void*)el)("\n");
                    });
                }
                static if(is(typeof(el.deallocData()))){
                    el.deallocData();
                }
                delete(el);
            }
        }
    }
}
