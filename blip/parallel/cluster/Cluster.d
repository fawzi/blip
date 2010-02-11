/// A simple infrastructure to handle a group of computers as peer to peer workers
/// the communication protocol is quite chatty (and thus much less efficient than mpi)
/// but it should be quite robust, if some care is taken then it should handle dynamic
/// addition or catastrophic removal of servers
///
/// a more resilient and scaling cluster structure can be created with chimera if gpl is ok
/// http://current.cs.ucsb.edu/projects/chimera , that should be available as part of dchem
module blip.parallel.cluster.ThightCluster;
import blip.serialization.Serialization;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.container.Deque;
import blip.t.core.Variant;
import blip.t.time.Time;
import blip.t.time.Clock;
import blip.util.NotificationCenter;
import blip.container.Pool;
import blip.container.Cache;

interface RemoteTask:Serializable{
    char[]name();
    void do_task(Cluster c);
}

class ClusterException:Exception{
    this(char[]msg,char[]file,long line){
        super(msg,file,line);
    }
}

class Worker{
    char[] sourceId;
    char[] baseUrl;
    void executeTask(RemoteTask t){
        
    }
}


class Peer{
    char[] sourceId;
    char[] baseUrl;
    mixin(serializeSome("blip.parallel.cluster.Worker","sourceId|baseUrl"));
    mixin printOut!();
    this(char[] sourceId,char[] baseUrl){
        this.sourceId=sourceId;
        this.baseUrl=baseUrl;
    }
}

class ListChange{
    
}

/// dead peer
struct DeadPeer{
    char[] sourceId;
    Time deathTime;
    long lastEntryId;
}

/// a cluster of peer to peer servers
class Cluster{
    NotificationCenter nCenter; // notifications
    Variant[char[]] info;
    char[] sourceId;
    WeakList!(Peer) workersList;
    Peer[char[]] workersDict;
    DeadPeer[] deadPeers;
    
    char[] firstAdd(char[]partialSId,char[]baseUrl){
        auto w=new Worker;
        char[] fullId;
        synchronized(workersList){
            fullId=collectAppender(delegate void(CharSink s){
                writeOut(s,workersList.lastEntryId+1,":d6");
                s("_");
                s(partialSId);
            });
            w.sourceId=fullId;
            w.baseUrl=baseUrl;
        }
        //workersList.addLocalEntry0(fullId,w);
        return fullId;
    }
    void removeWorker(WeakList!(Peer),WeakList!(Peer).Entry*){
        synchronized(this){
            
        }
    }
    bool knowsSource(char[]s){
        return (s in workersDict)!is null;
    }
}

/// a list of weakly ordered entries: entries with the same origin are ordered,
/// entries with different origin might be off by one before the merging
class WeakList(T){
    char[] name; /// name of the weak list
    Cluster cluster;
    
    T[]     sharedData;     /// data shared by the whole cluster
    long[]  sharedEntryIds; /// id of the shared data
    Entry*[] additions;      /// additions since last Sync
    Entry*[] removals;       /// removals since last Sync
    
    long lastEntryIdSync;   /// last entryId that is locally known to be shared over the whole cluster
    long lastEntryIdGSync;  /// last entryId that is globally known to be shared on the whole cluster
    long lastEntryId;       /// last entryId
    
    DeadPeer[] deadPeers;   /// dead peers (to check if additions are valid or come form a peer that has been disconnected)
    
    // callbacks
    void delegate(WeakList list)         _sharedDataChanged;
    void delegate(WeakList list,Entry *) _willRemoveEntry;
    void delegate(WeakList list,Entry *) _didRemoveEntry;
    void delegate(WeakList list,Entry *) _willAddEntry;
    void delegate(WeakList list,Entry *) _didAddEntry;
    
    void sharedDataChanged(){
        if (_sharedDataChanged !is null){
            _sharedDataChanged(this);
        }
    }
    void willRemoveEntry  (Entry *e){
        if (_willRemoveEntry !is null){
            _willRemoveEntry(this,e);
        }
    }
    void didRemoveEntry   (Entry *e){
        if (_didRemoveEntry !is null){
            _didRemoveEntry(this,e);
        }
    }
    void willAddEntry     (Entry *e){
        if (_willAddEntry !is null){
            _willAddEntry(this,e);
        }
    }
    void didAddEntry      (Entry *e){
        if (_didAddEntry !is null){
            _didAddEntry(this,e);
        }
    }
    
    /// an entry in the weak list
    struct Entry{
        char[] sourceId;
        long lastEntryIdSync; // value of lastEntryIdSync in the source when entry was added (useful to do some extra consistency checks)
        long entryId0;
        long entryId;
        T data;
        static Entry *opCall(char[]sourceId,long entryId0,long entryId,T data){
            auto res=new Entry;
            res.sourceId=sourceId;
            res.entryId0=entryId0;
            res.entryId=entryId;
            res.data=data;
            return res;
        }
        int opCmp(ref Entry e2){
            if (entryId0<e2.entryId0){
                return -1;
            } else if (entryId0==e2.entryId0){
                if (sourceId<e2.sourceId){
                    return -1;
                } else if (sourceId==e2.sourceId){
                    assert(data==e2.data,"same entry with different data");// remove?
                    return 0;
                } else {
                    return 1;
                }
            } else {
                return 1;
            }
        }
        mixin(serializeSome("WeakList!("~T.mangleof~")","sourceId|entryId|data"));
        mixin printOut!();
    }
    
    static class JournalEntry{
        enum Status{
            Added,
            RemoveGId,
            SyncPoint
        }
        Status status;
        long jId;
        Entry *entry;
    }
    static class EntryCacheT(int batchSize=16):Pool!(Entry*,batchSize){
        this(size_t bufferSpace=8*batchSize,
            size_t maxEl=8*batchSize){
            super(bufferSpace,maxEl);
        }
        override Entry *allocateNew(){
            return new Entry;
        }
        Entry *getObj(char[]sourceId,long entryId0,long entryId,T data){
            Entry *res=super.getObj();
            res.sourceId=sourceId;
            res.entryId0=entryId0;
            res.entryId=entryId;
            res.data=data;
            return res;
        }
    }
    alias EntryCacheT!() EntryCache;
    
    static Cached!(EntryCache) eCache;
    static this(){
        eCache=new Cached!(EntryCache)(cast(EntryCache)null,"Cluster","WeakList!("~T.mangleof~")",
            Cache.EntryFlags.Purge,
            delegate EntryCache(){ return new EntryCache(); });
    }
    
    Deque!(JournalEntry) journal;
    long journalFirstId;
    
    /// adds an entry to the weak list
    Entry *addLocalEntry0(Entry *e){
        return e;
        // JournalEntry(Status.Added,pos0,e);
    }
    Entry addLocalEntry(Entry *e){
        if (cluster.knowsSource(e.sourceId)){
            addLocalEntry0(e);
        } else {
            bool shouldAdd=false;
            synchronized(this){
                foreach (d;deadPeers){
                    if (d.sourceId==e.sourceId){
                        if (d.lastEntryId>=e.lastEntryIdSync){
                            shouldAdd=true;
                        }
                    }
                }
            }
            if (shouldAdd){
                addLocalEntry0(e);
            } else {
                throw new ClusterException("unknown source "~e.sourceId~"(late wake up?) ignoring",
                    __FILE__,__LINE__);
            }
        }
    }
    void addJournalEntry(JournalEntry j){
        
    }
    void waitNextSyncPoint(){
        assert(0);
    }
    /// tells that the current status is at least lastGE, and other peers are
    /// at least at lastGEold
    void syncPoint(long lastGE,long lastGEold){
        
    }

    ListChange mergeWithListOf(char[]sourceId,ListChange c){
    // find common basis:
    // find max(last from sourceId, second last local)
    // send entries 
        return null;
    }
    /// synchronizes this list with the one of sourceId
    void mergeWith(char[]sourceId){
        
    }
}

