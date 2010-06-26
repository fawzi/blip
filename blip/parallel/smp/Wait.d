/// Various methods to wait efficiently, trying to avoid polling or locking a thread
/// WaitCondition waits for a given condition (but you most tell when the condition might change),
/// SMPSemaphore is a semaphore that does not lock a thread if possible, but suspends the task.
/// WaitLock waits for an OS lock, this can be dangerous (see its doc).
/// If you are waiting on a value the module DataFlowVar might be what you want.
///
/// author: fawzi
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
module blip.parallel.smp.Wait;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.core.Thread;
import blip.core.sync.Semaphore;
import blip.sync.Atomic;
import blip.container.AtomicSLink;

/// an smp parallelization friendly semaphore
/// uses a LIFO queue, change to FIFO (slighlty more costly)?
struct SmpSemaphore{
    struct TaskISlist{
        TaskI el; // using this rather than delegates because it is more self descriptive
        TaskISlist * next;
    }
    ptrdiff_t counter; /// the number of waiting threads
    Semaphore sem; // remove support for this? it is just for waiting non yieldable tasks or the main thread
    TaskISlist *waiting;
    
    /// constructor
    static SmpSemaphore opCall(ptrdiff_t initialValue=0){
        SmpSemaphore res;
        res.counter=initialValue;
        return res;
    }
    /// notify howMany waiting threads (this is cached, i.e. you can notify before any thread is actually waiting)
    void notify(ptrdiff_t howMany=1){
        if (howMany==0) howMany=counter;
        auto oldV=atomicAdd(counter,-howMany);
        if (oldV>0){
            auto toWake=((oldV<howMany)?oldV:howMany);
            readBarrier();
            for (ptrdiff_t i=toWake;i>0;--i){
                TaskISlist *t=null;
                while(true){
                    t=popFrom(waiting);
                    if (t !is null) break;
                    Thread.yield();
                }
                if (t.el !is null){
                    t.el.resubmitDelayed();
                } else {
                    while (sem is null){
                        Thread.yield();
                    }
                    readBarrier();
                    sem.notify();
                }
            }
        }
    }
    /// waits to be notified (counter)
    void wait(){
        auto oldV=atomicAdd!(ptrdiff_t)(counter,1);
        if (oldV>=0){
            auto tAtt=taskAtt.val;
            auto tt=new TaskISlist;
            if (tAtt!is null && tAtt.mightYield()){
                tt.el=tAtt;
                tAtt.delay(delegate void(){
                    insertAt(waiting,tt);
                });
            } else {
                if (sem is null){
                    auto newSem=new Semaphore();
                    writeBarrier();
                    atomicCAS(sem,newSem,cast(Semaphore)null);
                }
                volatile auto mySem=sem;
                assert(mySem!is null);
                insertAt(waiting,tt);
                mySem.wait();
            }
        }
    }
}

/// waits for a condition (you have to call checkCondition each time the condition might change)
/// now it wakes all waiting threads/tasks, change it in checking after each wake up? 
/// then it could use an SMPSemaphore (probably not useful due to the delay between wake up and 
/// execution)
class WaitConditionT(bool oneAtTime=true){
    bool delegate() cnd;
    Semaphore sem;
    TaskI[]waiting; // using this rather than delegates because it is more self descriptive
    /// constructor
    this(bool delegate() cnd){
        this.cnd=cnd;
    }
    /// notify all waiters that the condition was met
    void notifyAll(){
        synchronized(this){
            foreach(t;waiting){
                t.resubmitDelayed();
            }
            waiting=null;
            if (sem!is null) sem.notify();
        }
    }
    /// notify one waiter at a time that the condition was met
    void notifyOne(){
        synchronized(this){
            if (waiting.length>0){
                waiting[waiting.length-1].resubmitDelayed();
                waiting.length=waiting.length-1;
            }
            waiting=null;
            if (sem!is null) sem.notify();
        }
    }
    /// notifies that the condition was met
    void notify(){
        if (oneAtTime){
            notifyOne();
        } else {
            notifyAll();
        }
    }
    /// check if the condition was met
    /// you have to call this each time the condition might have been met
    void checkCondition(){
        if (cnd()){
            notify();
        }
    }
    /// waits for the condition
    void wait(){
        if (!cnd()){
            auto tAtt=taskAtt.val;
            if (tAtt!is null && tAtt.mightYield()){
                tAtt.delay({
                    synchronized(this){
                        waiting~=tAtt;
                    }
                });
                checkCondition();
            } else {
                if (sem is null){
                    synchronized(this){
                        if (sem is null) {
                            sem=new Semaphore();
                        }
                    }
                }
                while (!cnd()){
                    sem.wait();
                }
                sem.notify();
            }
        } else {
            checkCondition();
        }
    }
    /// checks periodically if the condition (up to at least maxT milliseconds)
    void poll(uint maxT=uint.max){
        TaskI tAtt=taskAtt.val;
        for (uint i=0;i<maxT;++i){
            for (int j=0;j<10;++j){
                if (cnd()) {
                    notify();
                    return;
                }
                if (tAtt.mightYield()){
                    tAtt.scheduler.yield();
                } else {
                    Thread.sleep(0.0001);
                }
            }
            Thread.sleep(0.001);
        }
    }
}

alias WaitConditionT!(true) WaitCondition;

/// waits for an OS lock
/// WARNING this might deadlock if alwaysLock and the task that aquires the lock might
/// be suspended non executing
class WaitLock(T){
    T lockObj;
    bool alwaysLock;
    uint maxT;
    this(T lockObj, bool alwaysLock=false,uint maxT=100_000){
        this.lockObj=lockObj;
        this.alwaysLock=alwaysLock;
        this.maxT=maxT;
    }
    void wait(){ lock(); }
    void lock(){
        for (uint i=0;i<maxT;++i){
            for (int j=0;j<20;++j){
                bool lkd=lockObj.tryLock();
                if (lkd) return;
                TaskI tAtt=taskAtt.val;
                if (tAtt.mightYield()){
                    tAtt.scheduler.yield();
                } else {
                    if (! thread_needLock())
                        throw new ParaException("deadlock",__FILE__,__LINE__);
                    if (alwaysLock) {
                        lockObj.lock();
                        return;
                    }
                }
            }
            Thread.sleep(0.001);
        }
        if (alwaysLock){
            lockObj.lock();
        } else {
            throw new ParaException("failed to wait for lock",__FILE__,__LINE__);
        }
    }
    void unlock(){
        lockObj.unlock();
    }
}
