module blip.parallel.smp.PriQueue;
import blip.io.BasicIO;
import tango.core.sync.Mutex;
import tango.core.sync.Semaphore;
import tango.math.Math;
import blip.container.GrowableArray;
import blip.BasicModels;

/// a simple priority queue optimized for adding high priority tasks
/// the public interface consists of
/// - insert (insert a new element )
/// - popNext (remove the next element, keeping into account priority, blocking)
/// - stop (stop queue, and return null to the waiting threads)
/// the strange use of semaphore allows someone to lock queueLock, change the queue, 
/// nr of Els,... and release it by unlocking without any problem
/// this means that task reorganizations are ok
class PriQueue(T){
    /// stores all the elements with a given level
    class PriQLevel{
        int level;
        int start,nEl;
        T[] entries;
        PriQLevel subLevel;
        this(int level,PriQLevel subLevel=null,int capacity=10){
            this.level=level;
            this.entries=new T[max(1,capacity)];
            this.start=0;
            this.nEl=0;
            this.subLevel=subLevel;
        }
        /// adds a new element at the end of the level
        void append(T e){
            if (nEl==entries.length){
                int oldSize=entries.length;
                entries.length=3*entries.length/2+1;
                for (int i=0;i!=start;i++){
                    entries[oldSize]=entries[i];
                    entries[i]=null;
                    ++oldSize;
                    if (oldSize==entries.length) oldSize=0;
                }
            }
            entries[(start+nEl)%entries.length]=e;
            ++nEl;
        }
        /// peek the next element in the level
        T peek(){ if (nEl<1) return null; return entries[start]; }
        /// return the next element and removes it
        T pop(){
            if (nEl<1) return null;
            T res=entries[start]; entries[start]=null;
            ++start; --nEl;
            if (start==entries.length) start=0;
            return res;
        }
        /// description (for debugging)
        char[] toString(){
            return collectAppender(cast(OutWriter)&desc);
        }
        /// description (for debugging)
        void desc(void delegate(char[]) s){
            s("<PriQLevel@"); writeOut(s,cast(void*)this); s(" level=");
            writeOut(s,level); s(" entries=[");
            if (nEl>entries.length){
                s("*ERROR* nEl="); writeOut(s,nEl);
            } else {
                for (int i=0;i<nEl;++i){
                    if (i!=0) s(", ");
                    writeOut(s,entries[(start+i)%entries.length]);
                }
            }
            s("] capacity="); writeOut(s,entries.length); s(" >");
        }
    }
    /// pool to recycle PriQLevels
    class PriQPool{
        PriQLevel lastE;
        /// returns a PriQLevel to the pool for recycling
        void giveBack(PriQLevel l){ assert(l); l.subLevel=lastE; lastE=l; }
        /// creates a PriQLevel, if possible recycling an old one.
        /// if recycled the capacity is ignored
        PriQLevel create(int level,PriQLevel subLevel=null,int capacity=10){
            if (lastE !is null){
                PriQLevel res=lastE;
                lastE=lastE.subLevel;
                res.level=level;
                res.subLevel=subLevel;
                return res;
            }
            return new PriQLevel(level,subLevel,capacity);
        }
        /// creates the pool
        this(){
            lastE=null;
        }
        /// description (for debugging)
        char[] toString(){
            return collectAppender(cast(OutWriter)&desc);
        }
        /// description (for debugging)
        void desc(void delegate(char[]) s){
            if (this is null){
                s("<PriQPool *NULL*>");
            } else {
                s("<PriQPool@"); writeOut(s,cast(void*)this); s(" entries=[");
                PriQLevel el=lastE;
                while(el !is null){
                    if (el !is lastE) s(", ");
                    s("<PriQLevel@"); writeOut(s,cast(void *)el);
                    el=el.subLevel;
                }
                s("] >\n");
            }
        }
    }
    /// level pool
    PriQPool lPool;
    /// queue (highest level)
    PriQLevel queue;
    /// total number of entries
    int nEntries;
    /// if the queue should stop
    bool shouldStop;
    /// a super queue (asked for tasks)
    PriQueue superQueue;
    /// lock for queue modifications
    Mutex queueLock;
    /// to make the threads wait when no tasks are available
    /// use a Condition instead? (on mac I should test them, I strongly suspect they don't work);
    Semaphore zeroSem;
    /// creates a new piriority queue
    this(PriQueue superQueue=null){
        this.superQueue=superQueue;
        nEntries=0;
        queue=null;
        shouldStop=false;
        queueLock=new Mutex();
        zeroSem=new Semaphore();
        lPool=new PriQPool();
    }
    /// shuts down the priority queue
    void stop(){
        bool unlockZero=false;
        synchronized(queueLock){
            shouldStop=true;
            if (nEntries==0) unlockZero=true;
        }
        if (unlockZero) zeroSem.notify();
    }
    /// adds the given task to the queue with the given level (threadsafe)
    void insert(int tLevel,T t){
        // desc(sout("queue pre insert:").call); sout("\n");
        synchronized(queueLock){
            PriQLevel oldL=queue,lAtt=queue;
            while (lAtt !is null && lAtt.level>tLevel) {
                oldL=lAtt;
                lAtt=lAtt.subLevel;
            }
            if (lAtt !is null && lAtt.level==tLevel){
                lAtt.append(t);
            } else {
                PriQLevel newL=lPool.create(tLevel,lAtt);
                newL.append(t);
                if (oldL is lAtt) {
                    queue=newL;
                } else {
                    oldL.subLevel=newL;
                }
            }
            ++nEntries;
            // sout("XXX pushed ")(t.taskName)(nEntries)("\n");
            // sout("queue post insert:"); writeOut(sout,&desc);
            if (nEntries==1) zeroSem.notify;
        }
    }
    /// remove the next task from the queue and returns it
    /// locks if no tasks are available, if immediate is false
    /// returns null if and only if shouldStop is true
    /// threadsafe
    T popNext(bool immediate=false){
        bool shouldLockZero=false;
        while(1){
            if (shouldStop) return null;
            synchronized(queueLock){
                if (nEntries>0){
                    if (shouldStop) return null;
                    assert(queue !is null);
                    T res=queue.pop();
                    assert(res!is null);
                    if (queue.nEl==0){
                        PriQLevel nT=queue.subLevel;
                        lPool.giveBack(queue);
                        queue=nT;
                    }
                    --nEntries;
                    return res;
                } else {
                    shouldLockZero=true;
                    assert(queue is null);
                }
            }
            if (shouldLockZero) {
                if (superQueue){
                    T res=superQueue.popNext(true);
                    if (res) return res;
                }
                if (immediate) return null;
                zeroSem.wait();
                synchronized(queueLock){
                    if (nEntries>0)
                        zeroSem.notify();
                }
                shouldLockZero=false;
            }
        }
        return null;
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other thread modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) s){
        if (this is null){
            s("<PriQueue *NULL*>\n");
        } else {
            s("<PriQueue@"); writeOut(s,cast(void*)this); s(" nEntries=");
            writeOut(s,nEntries); s(",\n");
            s("  lPool="); writeOut(s,lPool); s(",\n");
            if (queue is null) {
                s("  queue=*NULL*,\n");
            } else {
                auto lAtt=queue;
                s("  queue=[");
                while(lAtt !is null){
                    s("   "); writeOut(s,lAtt); s(",\n");
                    lAtt=lAtt.subLevel;
                }
                s(" ],\n");
            }
            s("  shouldStop="); writeOut(s,shouldStop);
            bool qL=queueLock.tryLock();
            if (qL) queueLock.unlock();
            s(" queueLock:");
            if (qL){
                s("unlocked by others");
            } else {
                s("locked by others");
            }
            s(",\n");
            bool zL=zeroSem.tryWait();
            if (zL) zeroSem.notify();
            s(" zeroSem:");
            if (zL){
                s(">0");
            } else {
                s("==0");
            }
            s("\n");
            s(" >");
        }
    }
}

