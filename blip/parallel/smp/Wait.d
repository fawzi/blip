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
import blip.container.Deque;
import blip.container.GrowableArray;
import blip.io.BasicIO;

/// an smp parallelization friendly semaphore
/// uses a LIFO queue, change to FIFO (slighlty more costly)?
struct SmpSemaphore{
    struct TaskISlist{
        TaskI el; // using this rather than delegates because it is more self descriptive
        TaskISlist * next;
        int delayLevel;
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
                    t.el.resubmitDelayed(t.delayLevel);
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
                tt.delayLevel=tAtt.delayLevel;
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
    TaskI waiting0,waiting1;
    TaskI[]waiting; // using this rather than delegates because it is more self descriptive, 
    /// constructor
    this(bool delegate() cnd){
        this.cnd=cnd;
    }
    /// notify all waiters that the condition was met
    void notifyAll(){
        synchronized(this){
            if (waiting0!is null){
                waiting0.resubmitDelayed(waiting0.delayLevel-1);
                waiting0=null;
            }
            if (waiting1!is null){
                waiting1.resubmitDelayed(waiting0.delayLevel-1);
                waiting1=null;
            }
            foreach(t;waiting){
                t.resubmitDelayed(t.delayLevel-1);
            }
            waiting=null;
            if (sem!is null) sem.notify();
        }
    }
    /// notify one waiter at a time that the condition was met
    void notifyOne(){
        synchronized(this){
            if (waiting.length>0){
                waiting[$-1].resubmitDelayed(waiting[$-1].delayLevel-1);
                waiting[$-1]=null;
                waiting.length=waiting.length-1;
            } else if (waiting1!is null){
                waiting1.resubmitDelayed(waiting1.delayLevel-1);
                waiting1=null;
            } else if (waiting0!is null){
                waiting0.resubmitDelayed(waiting0.delayLevel-1);
                waiting0=null;
            }
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
                        if (waiting0 is null){
                            waiting0=tAtt;
                        } else if (waiting1 is null){
                            waiting1=tAtt;
                        } else {
                            waiting~=tAtt;
                        }
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
                volatile {
                    Semaphore mySem=sem;
                    auto myCnd=cnd;
                    while (!myCnd()){
                        mySem.wait();
                    }
                    mySem.notify();
                }
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

/// a recursive lock (detection of recursion is a bit expensive)
/// locking by all subtasks succeeds immediately
class RLock:Object.Monitor{
    TaskI locking;
    Deque!(TaskI) waiting;
    uint lockLevel;
    
    this(){}
    /// description of this lock (for debugging purposes)
    /// threadSafe only if locked...
    void desc(CharSink s){
        dumper(s)("<RLock@")(cast(void*)this)(", locking:")(locking)
            (", lockLevel:")(lockLevel)(", waiting:")(waiting)(">");
    }
    /// to string
    char[] toString(){
        return collectAppender(&desc);
    }
    /// locks the recursive lock
    void lock(){
        auto newTask=taskAtt.val;
        if (newTask is null || cast(RootTask)newTask !is null){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("warning dangerous locking in task ")(newTask);
            }),__FILE__,__LINE__); // allow aquiring a real lock??? can deadlock...
        }
        bool delayThis=false;
        { // quick path
            TaskI[128] unlockBuf=void;
            auto toUnlock=lGrowableArray(unlockBuf,0);
            synchronized(this){
                if (locking is null){
                    assert(lockLevel==0,"unexpected lockLevel with null locking");
                    if (waiting!is null && waiting.popFront(locking)){
                        waiting.filterInPlace(delegate bool(TaskI task){
                            auto t=task;
                            while (t!is null){
                                if (t is locking){
                                    toUnlock(t);
                                    ++lockLevel;
                                    return false;
                                }
                                if (t is t.superTask) break;
                                t=t.superTask;
                            }
                            return true;
                        });
                        toUnlock(locking);
                        ++lockLevel;
                        auto t=newTask;
                        delayThis=true;
                        while (t!is null){
                            if (t is locking){
                                ++lockLevel;
                                delayThis=false;
                                break;
                            }
                            if (t is t.superTask) break;
                            t=t.superTask;
                        }
                    } else {
                        locking=newTask;
                        ++lockLevel;
                        delayThis=false;
                    }
                } else {
                    auto t=newTask;
                    while (t!is null){
                        if (t is locking){
                            ++lockLevel;
                            return;
                        }
                        if (t is t.superTask) break;
                        t=t.superTask;
                    }
                    delayThis=true;
                }
            }
            foreach(t;toUnlock.data){
                t.resubmitDelayed(t.delayLevel-1);
            }
            toUnlock.deallocData();
        }
        if (delayThis){
            newTask.delay(delegate void(){
                TaskI[128] unlockBuf=void;
                auto toUnlock=lGrowableArray(unlockBuf,0);
                synchronized(this){
                    if (locking is null){
                        assert(lockLevel==0,"unexpected lockLevel with null locking");
                        if (waiting!is null && waiting.popFront(locking)){
                            waiting.append(newTask);
                            waiting.filterInPlace(delegate bool(TaskI task){
                                auto t=task;
                                while (t!is null){
                                    if (t is locking){
                                        toUnlock(t);
                                        ++lockLevel;
                                        return false;
                                    }
                                    if (t is t.superTask) break;
                                    t=t.superTask;
                                }
                                return true;
                            });
                        }
                        toUnlock(locking);
                        ++lockLevel;
                    } else {
                        auto t=newTask;
                        while (t!is null){
                            if (t is locking){
                                ++lockLevel;
                                toUnlock(newTask);
                                break;
                            }
                            if (t is t.superTask) break;
                            t=t.superTask;
                        }
                        if (toUnlock.length==0){
                            if (waiting is null) waiting=new Deque!(TaskI)();
                            waiting.append(newTask);
                        }
                    }
                }
                foreach(t;toUnlock.data){
                    t.resubmitDelayed(t.delayLevel-1);
                }
                toUnlock.deallocData();
            });
        }
    }
    
    void unlock()
    in{
        auto t=taskAtt.val;
        synchronized(this){
            while (t!is null){
                if (t is locking){
                    return;
                }
                if (t is t.superTask) break;
                t=t.superTask;
            }
        }
        assert(0,"unlock called when not locked by this task");
    }body{
        TaskI[128] unlockBuf=void;
        auto toUnlock=lGrowableArray(unlockBuf,0);
        synchronized(this){
            if (lockLevel==0) throw new Exception("mismatched unlock",__FILE__,__LINE__);
            --lockLevel;
            if (lockLevel==0){
                locking=null;
                if (waiting!is null && waiting.popFront(locking)){
                    waiting.filterInPlace(delegate bool(TaskI task){
                        auto t=task;
                        while (t!is null){
                            if (t is locking){
                                toUnlock(t);
                                ++lockLevel;
                                return false;
                            }
                            if (t is t.superTask) break;
                            t=t.superTask;
                        }
                        return true;
                    });
                }
            }
        }
        foreach(t;toUnlock.data){
            t.resubmitDelayed(t.delayLevel-1);
        }
        toUnlock.deallocData();
    }
    /// perform the given action while holding the lock
    void synchronizedDo(void delegate() op){
        lock();
        scope(exit){ unlock(); }
        op();
    }
}

/// a refining recursive lock
/// locking by a subtask refines the lock to it (i.e other subtask at the same level have to wait)
/// I thought it could be useful, but I haven't needed it yet
class RRLock:Object.Monitor{
    TaskI[] lockingStack;
    uint[] lockLevelStack;
    Deque!(TaskI) waiting;
    uint lastStack;
    
    this(){
    }
    /// description of this lock (for debugging purposes)
    /// threadSafe only if locked...
    void desc(CharSink s){
        dumper(s)("<RRLock@")(cast(void*)this)(", lockingStack:")(lockingStack)
            (", lockLevelStack:")(lockLevelStack)(", waiting:")(waiting)(", lastStack:")(lastStack)(">");
    }
    /// to string
    char[] toString(){
        return collectAppender(&desc);
    }
    /// locks the recursive lock
    void lock(){
        assert(0,"to do");
    }
    
    void unlock()
    {
        assert(0,"to do");
    }
}
