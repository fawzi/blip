/// basic support for a cache of various kinds of objects
/// the cached object provides some nicer support to use the cache
module blip.container.Cache;
import blip.t.time.Time;
import blip.t.core.Variant;
import blip.t.time.Clock;
import blip.sync.UniqueNumber;
import blip.sync.Atomic;
import blip.container.GrowableArray;
import blip.io.BasicIO;

class Cache{
    enum EntryFlags{
        Keep=0, /// will never be purged
        Purge=1 /// might be purged when unused
    }
    static struct CacheEntry{
        char[] name;
        char[] kind;
        Variant entry;
        Time lastUsed; // avoid storing??
        EntryFlags flags;
        CacheEntry *next;
        CacheEntry *prev;
    }
    
    CacheEntry*[char[]] entries;
    CacheEntry*last;
    Cache nextCache; // loops on all caches that are "togheter", should be a circular loop
    
    /// creates a new cache in the group of the cache given as argument
    this(Cache addTo=null){
        if (addTo is null){
            nextCache=this;
        } else {
            synchronized(addTo){
                volatile nextCache=addTo.nextCache;
                memoryBarrier!(false,false,false,true)();
                addTo.nextCache=this;
            }
        }
    }
    /// returns a cache entry if stored
    bool getIfCached(char[]name,ref CacheEntry el){
        synchronized(this){
            auto e=name in entries;
            if (e is null) return false;
            el= **e;
            el.next=null;
            el.prev=null;
            if (el.name != last.name){
                auto p1=(*e).prev;
                auto p2=(*e).next;
                p1.next=p2;
                p2.prev=p1;
                (*e).next=last;
                (*e).prev=last.prev;
                last.prev=(*e);
                last=(*e);
            }
            (*e).lastUsed=Clock.now;
        }
        return true;
    }
    /// clears a cache entry, returns true if it was present
    bool clear(char[]name){
        synchronized(this){
            auto e=name in entries;
            if (e is null) return false;
            auto el= *e;
            auto t1=el.prev;
            auto t2=el.next;
            t1.next=t2;
            t2.prev=t1;
            if (el is last){
                if (el is t2){
                    last=null;
                } else {
                    last=t2;
                }
            }
            entries.remove(name);
        }
        return true;
    }
    
    /// performs an operation on a cache entry 
    void cacheOp(char[] name, Variant delegate()create,EntryFlags flags,char[] kind,void delegate(ref CacheEntry) op){
        CacheEntry c;
        synchronized(this){
            if (getIfCached(name,c)){
                op(c);
                return;
            }
            CacheEntry *newE=new CacheEntry;
            newE.entry=create();
            newE.name=name;
            newE.kind=kind;
            newE.flags=flags;
            newE.lastUsed=Clock.now;
            if (last is null){
                newE.next=newE;
                newE.prev=newE;
                last=newE;
            } else {
                newE.prev=last.prev;
                newE.next=last;
                last.prev=newE;
                last=newE;
            }
            entries[name]=newE;
            return op(*newE);
        }
    }
    /// gets a value (if possible from the cache)
    T get(T)(char[] name, Variant delegate()create,EntryFlags flags,char[] kind){
        T res;
        cacheOp(name,create,flags,kind,delegate void(ref CacheEntry c){
            res=c.entry.get!(T)(); });
        return res;
    }
    /// sets a value in the cache
    void set(T)(char[] name, Variant delegate()create,EntryFlags flags,char[] kind,T newVal){
        cacheOp(name,create,flags,kind,delegate void(ref CacheEntry c){
            c.entry=Variant(newVal); });
    }
    
    /// remove old cached objects that satisfy the filter
    void purgeOld(Time time,bool delegate(ref CacheEntry) filter){
        synchronized(this){
            if (last !is null){
                auto pos=last.prev;
                while(pos.lastUsed<time){
                    if ((pos.flags & 1)==0 && filter(*pos)){
                        auto t1=pos.prev;
                        auto t2=pos.next;
                        t1.next=t2;
                        t2.prev=t1;
                        entries.remove(pos.name);
                        if (pos is last){
                            if (t1 is last){
                                last=null;
                            } else {
                                last=t1;
                            }
                            return;
                        }
                    }
                    if (pos is last) return;
                }
            }
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

/// base class for object that are cached (make the use of the cache easier)
/// if the name ends with "_" or is empty a unique string is generated
/// if needed override the create method
class Cached(T){
    static UniqueNumber!(size_t) cacheId;
    static this(){
        cacheId=UniqueNumber!(size_t)(1);
    }
    
    T val0;
    T delegate() createOp;
    char[]name;
    char[]kind;
    Cache.EntryFlags flags;
    
    this(T val0, char[] kind="Cached",char[] name="",
        Cache.EntryFlags flags=Cache.EntryFlags.Purge,
        T delegate()c=null){
        if (name.length==0){
            this.name=collectAppender(outWriter(cacheId.next()));
        } else if (name[$-1]=='_') {
            this.name=collectAppender(delegate void(CharSink s){
                s(name);
                writeOut(s,cacheId.next());
            });
        } else {
            this.name=name;
        }
        this.flags=flags;
        this.val0=val0;
        this.kind=kind;
        this.createOp=c;
    }
    this(T delegate()createOp, char[] kind="Cached",char[] name="",
        Cache.EntryFlags flags=Cache.EntryFlags.Purge){
        this(T.init,kind,name,flags,createOp);
    }
    Variant create(){
        if (createOp !is null) return Variant(createOp());
        return Variant(val0);
    }
    final T getFromCache(Cache cache){
        return cache.get!(T)(name,&create,flags,kind);
    }
    final void setInCache(Cache cache,T newVal){
        cache.set!(T)(name,&create,flags,kind,newVal);
    }
    final T opCall(Cache cache){
        return getFromCache(cache);
    }
    final void opCall(Cache cache,T newVal){
        setInCache(cache,newVal);
    }
    void clearLocal(Cache cache){
        cache.clear(name);
    }
    void clearAll(Cache cache){
        foreach(cAtt;cache.allCaches){
            cAtt.clear(name);
        }
    }
}
