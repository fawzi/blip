/// a simple priority queue optimized for adding high priority tasks
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
module blip.parallel.smp.PriQueue;
import blip.io.BasicIO;
import blip.core.sync.Mutex;
import blip.core.sync.Semaphore;
import blip.math.Math;
import blip.container.GrowableArray:collectIAppender;
import blip.BasicModels;
import blip.util.Grow:growLength;
import blip.container.Deque;
import blip.container.AtomicSLink;
import blip.Comp;
import blip.io.Console; // pippo
/// a simple priority queue optimized for adding high priority tasks
/// (otherwise a heap implementation would be better)
/// the public interface consists of
/// - insert (insert a new element )
/// - popNext (remove the next element, keeping into account priority, blocking)
/// - stop (stop queue, and return null to the waiting threads)
/// the strange use of semaphore allows someone to lock queueLock, change the queue, 
/// nr of Els,... and release it by unlocking without any problem
/// this means that task reorganizations are ok
class PriQueue(T){
    /// stores all the elements with a given level
    static class PriQLevel{
        int level;
        Deque!(T) entries;
        PriQLevel next;
        this(int level,PriQLevel next=null,int capacity=10){
            this.level=level;
            this.entries=new Deque!(T)(max(1,capacity));
            this.next=next;
        }
        /// description (for debugging)
        string toString(){
            return collectIAppender(cast(OutWriter)&desc);
        }
        /// description (for debugging)
        void desc(scope void delegate(in cstring) s){
            s("<PriQLevel@"); writeOut(s,cast(void*)this); s(" level=");
            writeOut(s,level); s(" entries=");
            writeOut(s,entries);
            s(" >");
        }
    }
    /// pool to recycle PriQLevels
    static class PriQPool{
        shared PriQLevel lastE;
        /// returns a PriQLevel to the pool for recycling
        void giveBack(PriQLevel l){ assert(l!is null); insertAt(lastE,l); }
        /// creates a PriQLevel, if possible recycling an old one.
        /// if recycled the capacity is ignored
        PriQLevel create(int level,PriQLevel next=null,int capacity=10){
            PriQLevel res=popFrom(lastE);
            if (res !is null){
                res.level=level;
                res.next=next;
                return res;
            }
            return new PriQLevel(level,next,capacity);
        }
        /// creates the pool
        this(){
            lastE=null;
        }
        /// description (for debugging)
        string toString(){
            return collectIAppender(cast(OutWriter)&desc);
        }
        /// description (for debugging)
        void desc(scope void delegate(in cstring) s){
            if (this is null){
                s("<PriQPool *NULL*>");
            } else {
                s("<PriQPool@"); writeOut(s,cast(void*)this); s(" entries=[");
                shared PriQLevel el=lastE;
                while(el !is null){
                    if (el !is lastE) s(", ");
                    s("<PriQLevel@"); writeOut(s,cast(void *)el);
                    el=el.next;
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
    /// lock for queue modifications
    Mutex queueLock;
    /// to make the threads wait when no tasks are available
    /// use a Condition instead? (on mac I should test them, I strongly suspect they don't work);
    Semaphore zeroSem;
    /// creates a new priority queue
    this(PriQPool lPool=null){
        nEntries=0;
        queue=null;
        shouldStop=false;
        queueLock=new Mutex();
        zeroSem=new Semaphore();
        if (lPool is null){
            this.lPool=new PriQPool();
        } else {
            this.lPool=lPool;
        }
    }
    /// resets a queue
    bool reset(){
        bool res=true;
        shouldStop=true;
        while(!zeroSem.tryWait()){ // unsafe, make it an error???
            zeroSem.notify();
            res=false;
        }
        if (!res) return false;
        nEntries=0;
        while(queue !is null){
            PriQLevel pNext=queue.next;
            lPool.giveBack(queue);
            queue=pNext;
        }
        shouldStop=false;
        return true;
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
                lAtt=lAtt.next;
            }
            if (lAtt !is null && lAtt.level==tLevel){
                lAtt.entries.append(t);
            } else {
                PriQLevel newL=lPool.create(tLevel,lAtt);
                newL.entries.append(t);
                if (oldL is lAtt) {
                    queue=newL;
                } else {
                    oldL.next=newL;
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
                    T res;
                    if(!queue.entries.popFront(res)){
                        throw new Exception(collectIAppender(delegate void(scope CharSink s){
                            s("Error: expected queue to have entries, queue is:");
                            desc(s);
                        }),__FILE__,__LINE__);
                    }
                    assert(res!is null);
                    if (queue.entries.length==0){
                        PriQLevel nT=queue.next;
                        queue.next=null;
                        lPool.giveBack(queue);
                        queue=nT;
                    }
                    --nEntries;
                    return res;
                } else {
                    shouldLockZero=true;
                    assert(queue is null);
                }
                if (immediate && shouldLockZero) return null;
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
    /// returns the first element from the back that satifies the given filter function
    bool popBack(ref T el,scope bool delegate(T) filter){
        PriQLevel[128] levels;
        size_t ilevel=0;
        synchronized(queueLock){
            PriQLevel lAtt=queue;
            while (lAtt!is null){
                levels[ilevel%levels.length]=lAtt;
                lAtt=lAtt.next;
                ++ilevel;
            }
            size_t iblock=levels.length;
            while(ilevel!=0){
                if (iblock==0){
                    lAtt=queue;
                    for (size_t iilev=ilevel;iilev!=0;--iilev){
                        levels[iilev%levels.length]=lAtt;
                        lAtt=lAtt.next;
                    }
                    iblock=levels.length;
                }
                --ilevel;
                --iblock;
                if (levels[ilevel%levels.length].entries.popBack(el,filter)){
                    --nEntries;
                    if (levels[ilevel%levels.length].entries.length==0){
                        if (ilevel==0){
                            queue=levels[0].next;
                        } else if (iblock!=0){
                            assert(levels[(ilevel-1)%levels.length].next is levels[ilevel%levels.length]);
                            levels[(ilevel-1)%levels.length].next=levels[ilevel%levels.length].next;
                        } else {
                            auto lPrev=queue;
                            for (size_t iilev=ilevel;iilev!=0;--iilev){
                                lPrev=lPrev.next;
                            }
                            assert(lPrev.next is levels[ilevel%levels.length]);
                            lPrev.next=levels[ilevel%levels.length].next;
                        }
                        levels[ilevel%levels.length].next=null;
                        lPool.giveBack(levels[ilevel%levels.length]);
                    }
                    return true;
                }
            }
        }
        return false;
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other thread modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) s){
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
                    lAtt=lAtt.next;
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

void pippo(){
    PriQueue!(int*) q;
    writeOut(sout,q);
}
