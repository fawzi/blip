/// basic support for a cache of various kinds of objects.
///
/// for memory reuse you probably want to use the defaultCache(), and the utility methods
/// cachedPoolNext and cachedPool...
///
/// author: fawzi
//
// Copyright 2009-2010 the blip developer group
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
module blip.container.Cache;
import blip.time.Time;
import blip.core.Variant;
import blip.time.Clock;
import blip.sync.UniqueNumber;
import blip.sync.Atomic;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.parallel.smp.Tls;
import blip.container.Pool;
import blip.core.Traits;
import blip.Comp;

enum EntryFlags{
    Keep=0, /// will never be purged
    Purge=1 /// might be purged when unused
}

alias size_t CKey; // use ulong in all cases???

__gshared UniqueNumber!(CKey) cacheKey;

shared static this(){
    cacheKey=UniqueNumber!(size_t)(1); // skip init and begin at 0?
}

/// an object that can create cache entries
interface CacheElFactory{
    Variant createEl();
    void deleteEl(Variant);
    EntryFlags flags();
    string name();
    CKey key();// this should be constant!!!
}

class Cache{
    static struct CacheEntry{
        Variant entry;
        CacheElFactory factory;
        Time lastUsed; // avoid storing??
        size_t idNr; // used to detect looping wrapping
    }
    UniqueNumber!(size_t) lastIdNr;
    CacheEntry*[CKey] entries;
    Cache nextCache; // loops on all caches that are "togheter", should be a circular loop
    
    /// creates a new cache in the group of the cache given as argument
    this(Cache addTo=null){
        lastIdNr=UniqueNumber!(size_t)(1);
        if (addTo is null){
            nextCache=this;
        } else {
            synchronized(addTo){
                nextCache=addTo.nextCache;
                memoryBarrier!(false,false,false,true)();
                addTo.nextCache=this;
            }
        }
    }
    // internal, should be called from a synchronized method
    // to reduce the cost of this (and have a higher purge cost) the links are not updated anymore
    // this assumes that lastUsed is updated atomically (or at least without creating much smaller partial values)
    void updateAccess(CacheEntry* el){
        assert(el !is null);
        el.lastUsed=Clock.now;
    }
    /// returns a cache entry if stored
    bool getIfCached(CacheElFactory factory,ref CacheEntry el){
        synchronized(this){
            auto e=factory.key() in entries;
            if (e is null) return false;
            el= **e;
            updateAccess(*e);
        }
        return true;
    }
    /// clears a cache entry, returns true if it was present
    bool clear(CKey key){
        Variant entry;
        CacheElFactory factory;
        synchronized(this){
            auto e=key in entries;
            if (e is null) return false;
            auto el= *e;
            if (el.factory!is null){
                entry=el.entry;
                factory=el.factory;
            }
            entries.remove(key);
        }
        if (factory!is null){
            factory.deleteEl(entry);
        }
        return true;
    }
    /// clears a cache entry, returns true if it was present
    bool clear(CacheElFactory factory){
        return clear(factory.key);
    }
    /// performs an operation on a cache entry (creating it if needed)
    void cacheOp(CacheElFactory factory,void delegate(ref CacheEntry) op){
        CacheEntry c;
        synchronized(this){
            auto key=factory.key();
            auto e=key in entries;
            if (e !is null) {
                updateAccess(*e);
                op(**e);
            } else {
                CacheEntry *newE=new CacheEntry;
                newE.entry=factory.createEl();
                newE.factory=factory;
                newE.lastUsed=Clock.now;
                newE.idNr=lastIdNr.next(); // synchronized(this)+ atomic op ensure strict monotonicity within one cache
                if (newE.idNr==0) throw new Exception("idNr wrapped",__FILE__,__LINE__);
                entries[key]=newE;
                op(*newE);
            }
        }
    }
    /// performs an operation on a cache entry if present (without creating it)
    void cacheOpIf(CacheElFactory factory,void delegate(ref CacheEntry) op){
        CacheEntry c;
        synchronized(this){
            auto e=factory.key() in entries;
            if (e !is null) {
                updateAccess(*e);
                op(**e);
            }
        }
    }
    /// gets a value (if possible from the cache)
    T get(T)(CacheElFactory factory){
        T res;
        cacheOp(factory,delegate void(ref CacheEntry c){
            res=c.entry.get!(T)(); });
        return res;
    }
    /// sets a value in the cache (and returns the old value as variant)
    Variant set(T)(CacheElFactory factory,T newVal){
        Variant res;
        cacheOp(factory,delegate void(ref CacheEntry c){
            res=c.entry;
            static if (is(T==Variant)){
                c.entry=newVal;
            } else {
                c.entry=Variant(newVal);
            }
        });
        return res;
    }
    
    /// removecached objects that satisfy the filter
    void purge(bool delegate(ref CacheEntry) filter){
        CKey[128] buf;
        auto toRm=lGrowableArray(buf,0);
        synchronized(this){
            foreach (k,v;entries){
                if (filter(*v)) toRm(k);
            }
        }
        foreach (k;toRm.data){
            clear(k);
        }
    }
    static struct AllCaches{
        Cache first;
        int opApply(int delegate(ref Cache c)loopBody){
            if (first is null) return 0;
            auto cAtt=first;
            do {
                assert(cAtt!is null,"null cache in circular loop");
                auto res=loopBody(cAtt);
                if (res!=0) return res;
                cAtt=cAtt.nextCache;
            } while(!(cAtt is first));
            return 0;
        }

        int opApply(int delegate(ref size_t i,ref Cache c)loopBody){
            if (first is null) return 0;
            auto cAtt=first;
            size_t i=0;
            do {
                assert(cAtt!is null,"null cache in circular loop");
                auto res=loopBody(i,cAtt);
                if (res!=0) return res;
                cAtt=cAtt.nextCache;
                ++i;
            } while(!(cAtt is first));
            return 0;
        }
    }
    /// loops on a group of caches
    AllCaches allCaches(){
        AllCaches res;
        res.first=this;
        return res;
    }
}

/// global (one per process) cache
__gshared Cache gCache;
static this(){
    gCache=new Cache();
}

mixin(tlsMixin("Cache","_defaultCache"));

/// the "best" cache, this might be gCache or more local cache (as created by NumaSchedulers)
Cache defaultCache(){
    auto res=_defaultCache();
    if (res !is null){
        return res;
    }
    return gCache;
}

/// set the local cache of the current thread.
/// It is assumed that caches are associated with a thread group,
/// and you can purge them all (with clearAll) from any of the threads in the group, so when setting 
/// the cache you should keep that into account.
void setDefaultCache(Cache c){
    _defaultCache(c);
}

/// base class for object that are cached (make the use of the cache easier)
class Cached:CacheElFactory{
    CKey _key;
    string _name;
    EntryFlags _flags;
    
    this(string name="", EntryFlags flags=EntryFlags.Purge){
        this._key=cacheKey.next();
        if (name.length==0){
            this._name=collectIAppender(delegate void(CharSink sink){
                sink("Cache_");
                writeOut(sink,key);
            });
        } else if (name[$-1]=='_') {
            this._name=collectIAppender(delegate void(CharSink s){
                s(name);
                writeOut(s,key);
            });
        } else {
            this._name=name;
        }
        this._flags=flags;
    }
    Variant createEl(){
        return Variant.init;
    }
    void deleteEl(Variant x){}
    
    EntryFlags flags(){
        return _flags;
    }
    string name(){
        return _name;
    }
    final CKey key(){
        return _key;
    }
    void clearLocal(Cache cache){
        cache.clear(this);
    }
    void clearAll(Cache cache){
        foreach(cAtt;cache.allCaches){
            cAtt.clear(this);
        }
    }
}

/// cache for objects of type T
/// if the name ends with "_" or is empty a unique string is generated
/// if needed override the create method
/// should allow also delegates for creation/destruction? until now not needed
final class CachedT(T):Cached{
    T function() createOp;
    void function(T) freeOp;
    
    EntryFlags _flags;
    /// creates a new cached value with c as creation function, freeing if d is not given defaults
    /// to call stopCaching if available, doing nothing otherwise
    this(string name,T function()c,void function(T)d=null,EntryFlags flags=EntryFlags.Purge)
    {
        super(((name.length==0)?"cache_"~T.stringof~"_":name),flags);
        this.createOp=c;
        this.freeOp=d;
    }
    Variant createEl(){
        static if (is(T==Variant)){
            return createOp();
        } else {
            return Variant(createOp());
        }
    }
    void deleteEl(Variant e){
        static if (is(T==Variant)){
            if (freeOp !is null) {
                freeOp(e);
            }
        } else {
            if (freeOp !is null) {
                freeOp(e.get!(T)());
            } else {
                static if (is(typeof(T.init.stopCaching()))){
                    T el=e.get!(T)();
                    static if(is(typeof(el !is null))){
                        if (el !is null) el.stopCaching();
                    } else {
                        el.stopCaching();
                    }
                }
            }
        }
    }
    T getFromCache(Cache cache){
        return cache.get!(T)(this);
    }
    T setInCache(Cache cache,T newVal){
        auto res=cache.set!(T)(this,newVal);
        return res.get!(T)();
    }
    T opCall(Cache cache){
        return getFromCache(cache);
    }
    void opCall(Cache cache,T newVal){
        setInCache(cache,newVal);
    }
}

/// cache for pool of objects of type T
class CachedPool(T):Cached,PoolI!(T){
    PoolI!(T) function() poolCreatorF;
    PoolI!(T) delegate() poolCreatorD;
    size_t activeUsers=1;
    bool cacheStopped=false;
    
    this(PoolI!(T) function() poolCreatorF){
        this.poolCreatorF=poolCreatorF;
        this.activeUsers=1;
    }
    this(PoolI!(T) delegate() poolCreatorD){
        this.poolCreatorD=poolCreatorD;
        this.activeUsers=1;
    }
    
    /// creates a pool
    PoolI!(T) poolCreator(){
        if (poolCreatorF!is null) return poolCreatorF();
        if (poolCreatorD!is null) return poolCreatorD();
        throw new Exception("no pool creator",__FILE__,__LINE__);
    }
    /// returns a new object
    T getObj(Cache cache){
        return cache.get!(PoolI!(T))(this).getObj();
    }
    /// returns a new object from the default cache
    T getObj(){
        return defaultCache().get!(PoolI!(T))(this).getObj();
    }
    /// returns an instance, so that it can be reused (this returns it to the current cache if it is
    /// possible that you call this from a different thread than the one that called getObj then it is 
    /// better to cache the NFreeList in the object and returns to it)
    void giveBack(Cache cache,T obj){
        assert(! isNullT(obj),"cannot give back null objects");
        if (!cacheStopped){
            cache.get!(PoolI!(T))(this).giveBack(obj);
        } else {
            tryDeleteT(obj);
        }
    }
    void giveBack(T obj){
        giveBack(defaultCache(),obj);
    }
    /// internal method, creates a new Pool for the cache
    Variant createEl(){
        auto res=poolCreator();
        if (cacheStopped) res.stopCaching();
        return Variant(res);
    }
    /// deletes the NFreeList from the cache
    void deleteEl(Variant el){
        auto c=el.get!(PoolI!(T))();
        if (c!is null){
            c.stopCaching();
        }
        // don't delete c itself as it could be dangerous...
    }
    /// discards all the cached objects from all the caches
    void flush(Cache cache){
        foreach(cAtt;cache.allCaches){
            cAtt.cacheOpIf(this,delegate void(ref Cache.CacheEntry c){ c.entry.get!(PoolI!(T))().flush(); });
        }
    }
    /// ditto
    void flush(){
        flush(defaultCache());
    }
    /// stops caching and discards all cached objects
    void stopCaching(Cache cache){
        cacheStopped=true;
        clearAll(cache);
    }
    /// ditto
    void stopCaching(){
        stopCaching(defaultCache());
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
}

/// utility method that creates a cached pool given a creation operation that creates an object.
///
/// the pool is a blip.container.Pool.PoolNext, an unbounded pool that uses a free list built
/// using the next attribute of the object (that must exist).
CachedPool!(ReturnTypeOf!(U)) cachedPoolNext(U)(U createOp){
    alias ReturnTypeOf!(U) T;
    return new CachedPool!(T)(PoolNext!(T).poolFactory(createOp));
}

/// utility method that creates a cached pool given a creation operation that creates an object.
///
/// the pool is a blip.container.Pool.Pool, batchSize, bufferSpace and maxEl of the pool can be set
CachedPool!(ReturnTypeOf!(U)) cachedPool(U,int batchSize=16)(U createOp,size_t bufferSpace=8*batchSize,
    size_t maxEl=16*batchSize)
{
    alias ReturnTypeOf!(U) T;
    return new CachedPool!(T)(Pool!(T,batchSize).poolFactory(createOp,bufferSpace,maxEl));
}

