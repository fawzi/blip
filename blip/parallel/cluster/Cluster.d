/// A simple infrastructure to handle a group of computers as peer to peer workers
/// the communication protocol is quite chatty (and thus much less efficient than mpi)
/// but it should be quite robust, if some care is taken then it should handle dynamic
/// addition or catastrophic removal of servers
///
/// a more resilient and scaling cluster structure can be created with chimera if gpl is ok
/// http://current.cs.ucsb.edu/projects/chimera , that should be available as part of dchem
/// this has an unclear future
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
module blip.parallel.cluster.Cluster;
import blip.serialization.Serialization;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.container.Deque;
import blip.core.Boxer;
import blip.time.Time;
import blip.time.Clock;
import blip.util.NotificationCenter;
import blip.container.Pool;
import blip.container.Cache;
import blip.Comp;

/+interface RemoteTask:Serializable{
    string name();
    void do_task(Cluster c);
}

class ClusterException:Exception{
    this(string msg,string file,long line){
        super(msg,file,line);
    }
}

class Worker{
    string sourceId;
    string baseUrl;
    void executeTask(RemoteTask t){
        
    }
}

class Peer{
    string sourceId;
    string baseUrl;
    mixin(serializeSome("blip.parallel.cluster.Worker","sourceId|baseUrl"));
    mixin printOut!();
    this(){}
    this(string sourceId,string baseUrl){
        this.sourceId=sourceId;
        this.baseUrl=baseUrl;
    }
}

class ListChange{
    
}

/// dead peer
struct DeadPeer{
    string sourceId;
    Time deathTime;
    long lastEntryId;
}

/// a list of weakly ordered entries: entries with the same origin are ordered,
/// entries with different origin might be off by one before the merging
class WeakList(T){
    /// an entry in the weak list
    struct Entry{
        string sourceId;
        long lastEntryIdSync; // value of lastEntryIdSync in the source when entry was added (useful to do some extra consistency checks)
        long entryId0;
        long entryId;
        T data;
        static Entry *opCall(string sourceId,long entryId0,long entryId,T data){
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
        Entry *getObj(string sourceId,long entryId0,long entryId,T data){
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
    
    Deque!(JournalEntry) journal;
    long journalFirstId;
    
    string name; /// name of the weak list
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

    ListChange mergeWithListOf(string sourceId,ListChange c){
    // find common basis:
    // find max(last from sourceId, second last local)
    // send entries 
        return null;
    }
    /// synchronizes this list with the one of sourceId
    void mergeWith(string sourceId){
        
    }
    static this(){
        eCache=new Cached!(EntryCache)(cast(EntryCache)null,"Cluster","WeakList!("~T.mangleof~")",
            Cache.EntryFlags.Purge,
            delegate EntryCache(){ return new EntryCache(); });
    }
}

/// a cluster of peer to peer servers
class Cluster{
    NotificationCenter nCenter; // notifications
    Box[string ] info;
    string sourceId;
    WeakList!(Peer) workersList;
    Peer[string ] workersDict;
    DeadPeer[] deadPeers;
    
    string firstAdd(string partialSId,string baseUrl){
        auto w=new Worker;
        string fullId;
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
    bool knowsSource(string s){
        return (s in workersDict)!is null;
    }
}
+/
