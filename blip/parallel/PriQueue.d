module blip.parallel.PriQueue;
import tango.io.Print;
import tango.core.sync.Mutex;
import tango.core.sync.Semaphore;
import tango.math.Math;
import blip.Stringify;
import blip.BasicModels;

/// a simple priority queue optimized for adding high priority tasks
/// the public interface consists of
/// - insert (insert a new element )
/// - popNext (remove the next element, keeping into account priority, blocking)
/// - stop (stop queue, and return null to the waiting threads)
/// the strange use of semaphore allows someone to lock queueLock, chang the queue, 
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
            return getString(desc(new Stringify()).newline);
        }
        /// description (for debugging)
        Print!(char) desc(Print!(char)s){
            s.format("<PriQLevel@{} level={} entries=[",cast(void*)this,level);
            if (nEl>entries.length){
                s("*ERROR* nEl=")(nEl);
            } else {
                for (int i=0;i<nEl;++i){
                    if (i!=0) s(", ");
                    writeDesc(entries[(start+i)%entries.length],s);
                }
            }
            s("] capacity=")(entries.length)(" >").newline;
            return s;
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
            return getString(desc(new Stringify()).newline);
        }
        /// description (for debugging)
        Print!(char) desc(Print!(char)s){
            if (this is null){
                s("<PriQPool *NULL*>").newline;
            } else {
                s.format("<PriQPool@{} entries=[",cast(void*)this);
                PriQLevel el=lastE;
                while(el !is null){
                    if (el !is lastE) s(", ");
                    s.format("<PriQLevel@{}",cast(void *)el);
                    el=el.subLevel;
                }
                s("] >").newline;
            }
            return s;
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
    /// lock for queue modifications
    Mutex queueLock;
    /// to make the threads wait when no tasks are available
    /// use a Condition instead? (on mac I should test them, I strongly suspect they don't work);
    Semaphore zeroSem;
    /// creates a new piriority queue
    this(){
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
        // desc(Stdout("queue pre insert:")).newline;
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
            //Stdout("XXX pushed ")(t.taskName)(nEntries).newline;
            // desc(Stdout("queue post insert:")).newline;
            if (nEntries==1) zeroSem.notify;
        }
    }
    /// remove the next task from the queue and returns it
    /// locks if no tasks are available, returns null if and only if shouldStop is true
    /// threadsafe
    T popNext(){
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
                    //Stdout("XXX popping ")(res.taskName)(nEntries).newline;
                    return res;
                } else {
                    shouldLockZero=true;
                    assert(queue is null);
                }
            }
            if (shouldLockZero) {
                zeroSem.wait();
                synchronized(queueLock){
                    if (nEntries>0)
                        zeroSem.notify();
                }
                shouldLockZero=false;
            }
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other thread modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s){
        if (this is null){
            s("<PriQueue *NULL*>").newline;
        } else {
            s.format("<PriQueue@{} nEntries={},",cast(void*)this,nEntries).newline;
            writeDesc(lPool,s("  lPool="))(",").newline;
            if (queue is null) {
                s("  queue=*NULL*,").newline;
            } else {
                auto lAtt=queue;
                s("  queue=[");
                while(lAtt !is null){
                    writeDesc(lAtt,s("   "))(",").newline;
                    lAtt=lAtt.subLevel;
                }
                s(" ],").newline;
            }
            s("  shouldStop=")(shouldStop);
            bool qL=queueLock.tryLock();
            if (qL) queueLock.unlock();
            s(" queueLock:");
            if (qL){
                s("unlocked by others");
            } else {
                s("locked by others");
            }
            s(",").newline;
            bool zL=zeroSem.tryWait();
            if (zL) zeroSem.notify();
            s(" zeroSem:");
            if (zL){
                s(">0");
            } else {
                s("==0");
            }
            s.newline;
            s(" >").newline;
        }
        return s;
    }
}

