/// schedulers that take advantage of numa topology
/// these are the main, and more feature complete schedulers
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
module blip.parallel.smp.NumaSchedulers;
import blip.core.Thread;
import blip.core.Variant:Variant;
import blip.core.sync.Mutex;
import blip.core.sync.Semaphore;
import blip.math.Math;
import blip.util.TangoLog;
import blip.math.random.Random;
import blip.time.Time;
import blip.time.Clock;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.parallel.smp.PriQueue;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.Numa;
import blip.BasicModels;
import blip.container.Deque;
import blip.container.Cache;
import blip.container.BitVector;
import blip.container.AtomicSLink;
import blip.io.Console;
import blip.sync.Atomic;
import blip.container.Pool;
import blip.util.RefCount;
import blip.core.stacktrace.StackTrace;
import blip.Comp;
import blip.stdc.stdlib: abort;

// locking order, be careful to change that to avoid deadlocks
// especially addSched and redirectedTask are sensible
//
// PriQSched(this): never lock anything else
// PriQSched(queue.lock): locks PriQSched(this)
// 
// MultiSched(this): never lock anything else
// MultiSched(queue): lock PriQSched(queue.lock), *(this)
// 
// StarvationManager(this): never lock anything else


/// task scheduler that tries to perform a depth first reduction of the task
/// using the maximum parallelization available.
/// This allows to have parallelization without generating too many suspended
/// tasks, it can be seen as a parallelization of eager evaluation.
/// Just as eager evaulation it has the great advantage of being relatively easy
/// to understand and to have good performance.
///
/// integrate PriQueue in this? it would be slighly more efficient, and already now
/// depends on its implementation details, or they should be better separated
class PriQScheduler:TaskSchedulerI {
    static __gshared CachedT!(PriQueue!(TaskI).PriQPool) pQLevelPool;
    shared static this(){
        pQLevelPool=new CachedT!(PriQueue!(TaskI).PriQPool)("PriQPool_",function PriQueue!(TaskI).PriQPool(){
            auto res=new PriQueue!(TaskI).PriQPool();
            return res;
        });
    }
    
    /// random source for scheduling
    RandomSync _rand;
    /// queue for tasks to execute
    PriQueue!(TaskI) queue;
    /// logger for problems/info
    Logger log;
    /// name of the scheduler
    string name;
    /// root Task
    TaskI _rootTask;
    /// runLevel of the scheduler
    SchedulerRunLevel runLevel;
    /// active tasks (tasks that have been taken from the scheduler and not yet finished)
    int[TaskI] activeTasks;
    /// stealLevel of the scheduler (mirrors a numa topology level)
    /// tasks from this scheduler will be stolen from scheduler that have the given level
    /// in common
    int stealLevel;
    /// if the scheduler is in the super scheduler
    size_t inSuperSched;
    /// executer
    ExecuterI _executer;
    /// returns the root task
    TaskI rootTask(){ return _rootTask; }
    /// super scheduler, only subclasses of MultiSched are accepted
    MultiSched superScheduler;
    /// liked list for pool of schedulers
    PriQScheduler next;
    /// how long this scheduler has been waiting with no tasks executing
    Time waitingSince;
    Cache _nnCache;
    /// cache at numa node level
    Cache nnCache(){
        return _nnCache;
    }
    PoolI!(PriQScheduler) pool;
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    /// constructor for the pool
    this(PoolI!(PriQScheduler)p,string loggerPath="blip.parallel.smp.queue"){
        version(TrackCollections){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("creating PriQScheduler@")(cast(void*)this)("\n");
            });
        }
        this._rand=new RandomSync();
        this.inSuperSched=0;
        log=Log.lookup(loggerPath);
        runLevel=SchedulerRunLevel.Configuring;
        stealLevel=int.max;
        waitingSince=Time.max;
        superScheduler=null;
        _nnCache=null; // needs superScheduler
        queue=null; // needs _nnCache
        _rootTask=null; // needs _nnCache
        pool=p;
    }
    /// creates a new PriQScheduler
    this(string name,MultiSched superScheduler,string loggerPath="blip.parallel.smp.queue"){
        version(TrackCollections){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("creating PriQScheduler@")(cast(void*)this)("\n");
            });
        }
        this.name=name;
        assert(superScheduler!is null);
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        this._executer=superScheduler.executer;
        version(NoReuse){
            queue=new PriQueue!(TaskI)();
        } else {
            queue=new PriQueue!(TaskI)(pQLevelPool(_nnCache));
        }
        this._rand=new RandomSync();
        this.inSuperSched=0;
        log=Log.lookup(loggerPath);
        runLevel=SchedulerRunLevel.Running;
        auto newLev=superScheduler.runLevel;
        if (runLevel < cast(int)newLev){
            runLevel=newLev;
            if (runLevel==SchedulerRunLevel.Stopped){
                log.warn("adding task "~name~" to stopped scheduler...");
            }
        }
        stealLevel=int.max;
        waitingSince=Time.max;
        _rootTask=new RootTask(this,0,name~"RootTask");
    }
    void reset(string name,MultiSched superScheduler){
        this.name=name;
        assert(superScheduler!is null);
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        this._executer=superScheduler.executer;
        if (queue is null){
            version(NoReuse){
                queue=new PriQueue!(TaskI)();
            } else {
                assert(_nnCache!is null,"nnCache null 2");
                assert(pQLevelPool!is null,"pQLevelPool null 2");
                queue=new PriQueue!(TaskI)(pQLevelPool(_nnCache));
            }
        } else { // should update the pool used??
            if (!queue.reset()){
                throw new Exception("someone waiting on queue, this should neve happen (wait are only on MultiSched)",
                    __FILE__,__LINE__);
            }
        }
        stealLevel=int.max;
        inSuperSched=0;
        version(NoReuse){
            runLevel=SchedulerRunLevel.Running;
        } else {
            version(ReusePriQSched){
                runLevel=SchedulerRunLevel.StopNoTasks;
            } else {
                runLevel=SchedulerRunLevel.Running;
            }
        }
        auto levelN=this.superScheduler.runLevel;
        if (runLevel < cast(int)levelN){
            runLevel=levelN;
            if (runLevel==SchedulerRunLevel.Stopped){
                log.warn("adding task "~name~" to stopped scheduler...");
            }
        }
        waitingSince=Time.max;
        if (rootTask is null){
            _rootTask=new RootTask(this,0,name~"RootTask");
        }
    }
    bool noActiveTasks(){
        synchronized(queue.queueLock){
            synchronized(this){
                return queue.nEntries==0 && activeTasks.length==0;
            }
        }
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    void release0(){
        if (pool!is null){
            refCount=1;
            debug(TrackQueues){
                sinkTogether(&logMsg,delegate void(scope CharSink s){
                    dumper(s)("giving back ")(this,false)(" to pool");
                });
            }
            pool.giveBack(this);
        } else {
            debug(TrackQueues){
                sinkTogether(&logMsg,delegate void(scope CharSink s){
                    dumper(s)("deleting ")(this,false);
                });
            }
            next=null;
            runLevel=SchedulerRunLevel.Stopped;
            queue=null;
            _nnCache=null;
            delete this;
        }
    }
    version(TrackCollections){
        ~this(){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("destructor of PriQScheduler@")(cast(void*)this)(" refCount:")(refCount)("\n");
            });
        }
    }
    void addTask0(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("will PriQScheduler ")(this,true)(".addTask0(")(t)(",with superTask:")(t.superTask)(" in task ")(taskAtt)("):");writeStatus(s,4);
            });
            scope(exit){
                sinkTogether(&logMsg,delegate void(scope CharSink s){
                    dumper(s)("did PriQScheduler@")(cast(void*)this)(".addTask0");
                });
            }
        }
        if (t.scheduler!is this){
            assert(t.scheduler is cast(TaskSchedulerI)superScheduler ||
                t.scheduler is cast(TaskSchedulerI)superScheduler.starvationManager,
                "wrong scheduler in task");
            t.scheduler=this;
        }
        bool addToSuperSched=false;
        synchronized(queue.queueLock){
            queue.insert(t.level,t);
            if (inSuperSched==0) {
                inSuperSched=1;
                addToSuperSched=true;
            }
            if (queue.nEntries==1){
                synchronized(this){
                    if (activeTasks.length==0){
                        waitingSince=Clock.now;
                    }
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                throw new Exception(collectIAppender(delegate void(scope CharSink s){
                        dumper(s)("addTask0 to stopped PriQScheduler@")(cast(void*)this);
                    }));
            }
        }
        if (addToSuperSched) superScheduler.addSched(this);
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        debug(TrackQueues) log.info(collectIAppender(delegate void(scope CharSink s){
            dumper(s)("task ")(t)(" might be added to queue ")(this,true);
        }));
        if (shouldAddTask(t)){
            addTask0(t);
        }
    }
    /// returns nextTask if available, null if it should wait
    /// adds this to the super scheduler if task is not null
    TaskI nextTaskImmediate(){
        return nextTaskImmediate(true);
    }
    TaskI nextTaskImmediate(bool checkEnd){
        if (runLevel==SchedulerRunLevel.Stopped){
            return null;
        }
        TaskI t;
        bool callReuse=false;
        synchronized(queue.queueLock){ // ugly, but needed to close the hole between pop and activation...
            t=queue.popNext(true);
            if (t is null) {
                inSuperSched=0;
                if (checkEnd && runLevel>=SchedulerRunLevel.StopNoTasks){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks && noActiveTasks){
                        callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped);
                    }
                }
            } else {
                subtaskActivated(t);
            }
        }
        if (callReuse){
            reuse();
            return null;
        }
        if (t !is null){
            superScheduler.addSched(this);
        }
        return t;
    }
    /// returns nextTask (blocks, returns null only when stopped)
    TaskI nextTask(){
        TaskI t;
        t=this.nextTaskImmediate(false);
        if (t is null && runLevel!=SchedulerRunLevel.Stopped){
            bool callReuse=false;
            synchronized(queue.queueLock){
                t=queue.popNext(true);
                if (t is null) {
                    inSuperSched=0;
                    if (runLevel>=SchedulerRunLevel.StopNoTasks){
                        if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                            callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped);
                        } else if (runLevel==SchedulerRunLevel.StopNoTasks && noActiveTasks){
                            callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped);
                        }
                    }
                } else {
                    subtaskActivated(t);
                }
            }
            if (callReuse){
                assert(inSuperSched==0);
                reuse();
                return null;
            }
            if (t is null){
                t=queue.popNext(false);
                if (t !is null){
                    superScheduler.addSched(this);
                    subtaskActivated(t);
                }
                assert(false,"hole between activation ad popping!"); // at the moment this method is not used...
            }
        }
        return t;
    }
    /// steals tasks from the current scheduler
    bool stealTask(int stealLevel,TaskSchedulerI targetScheduler){
        assert(targetScheduler!is this);
        if (stealLevel>this.stealLevel) {
            return false;
        }
        TaskI t;
        if (runLevel==SchedulerRunLevel.Stopped){
            return false;
        }
        bool callReuse=false;
        if (!queue.popBack(t,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
            return false;
        }
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink sink){
                dumper(sink)("stealing task ")(t)(" from scheduler ")(this,true)
                    (" for scheduler ")(targetScheduler,true);
            });
        }
        t.scheduler=targetScheduler;
        targetScheduler.addTask0(t);
        // steal more
        /+  pippo to do
        // in general this is dangerous, as the scheduler might get reused in the meantime...
        // should be rewritten for example collecting first all tasks and adding them at once
        // (adding a addTasks0 method) or changing the runlevel before adding them...

        auto scheduler2=t.scheduler;
        if(scheduler2 is null) scheduler2=targetScheduler;
        while (true){
            if(rand.uniform!(bool)()) return true;
            TaskI t2;
            if (!queue.popBack(t2,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
                return true;
            }
            t2.scheduler=scheduler2;
            debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink sink){
                    sink("stealing other task "); writeOut(sink,t2,true); sink(" from ");
                    writeOut(sink,this,true); sink(" to "); writeOut(sink,scheduler2,true); sink("\n");
                }));
            }
            scheduler2.addTask0(t2);
        }+/
        return true;
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// locks the scheduler (to perform task reorganization)
    /// if you call this then toString is threadsafe
    void lockSched(){
        queue.queueLock.lock();
    }
    /// unlocks the scheduler
    void unlockSched(){
        queue.queueLock.unlock();
    }
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st){
        synchronized(queue.queueLock){
            if (st in activeTasks){
                activeTasks[st]+=1;
            } else {
                activeTasks[st]=1;
            }
            waitingSince=Time.max;
        }
        superScheduler.subtaskActivated(st);
    }
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st){
        bool callReuse=false;
        synchronized(queue.queueLock){
            if (activeTasks[st]>1){
                activeTasks[st]-=1;
            } else {
                activeTasks.remove(st);
                if (runLevel>=SchedulerRunLevel.StopNoTasks && queue.nEntries==0){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks && noActiveTasks){
                        callReuse=raiseRunlevelB(SchedulerRunLevel.Stopped) && inSuperSched==0;
                    }
                }
                if (activeTasks.length==0){
                    waitingSince=Clock.now;
                }
            }
        }
        superScheduler.subtaskDeactivated(st);
        if (callReuse){
            reuse();
        }
    }
    /// returns wether the current task should be added
    bool shouldAddTask(TaskI t){
        return !superScheduler.starvationManager.redirectedTask(t,this);
    }
    /// yields the current task if the scheduler is not sequential
    void yield(){
        Fiber.yield();
    }
    /// maybe yields the current task if the scheduler is not sequential
    /// at the moment it is quite crude (50%, i.e. 25% less switches when the queue is full,
    /// and 25% (37.5% less switches) when the queue is empty)
    void maybeYield(){
        if (((!manyQueued()) || rand.uniform!(bool)()) && rand.uniform!(bool)())
            Fiber.yield();
    }
    /// sets the executer
    void executer(ExecuterI nExe){
        _executer=nExe;
    }
    /// removes the executer
    ExecuterI executer(){
        return _executer;
    }
    /// description (for debugging)
    void desc(scope void delegate(in cstring) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<PriQScheduler@"); writeOut(sink,cast(void*)this);
        if (shortVersion) {
            s(", name:")(name)(" runLevel:")(runLevel)(" >");
            return;
        }
        s("\n");
        s("  name:")(name)(",\n");
        s("  runLevel:")(runLevel)(",\n");
        s("  queue:")(queue)(",\n");
        s("  log:")(log)(",\n");
        s("  inSuperSched:")(inSuperSched)(",\n");
        s("  activeTasks:[\n");
        s("    ");
        bool nonFirst=false;
        foreach (t,r;activeTasks){
            if (nonFirst) { s(",\n"); nonFirst=true; }
            s("    ")(r);
            writeOut(sink,t,true);
        }
        s("\n");
        s("  ],\n");
        s("  rootTask:"); writeOut(sink,rootTask);
        s("\n >");
    }
    /// writes the status of the queue in a compact and 
    void writeStatus(scope CharSink s,int intentL){
        synchronized(queue.queueLock){
            s("{ \"sched@\":"); writeOut(s,cast(void*)this); s(", rl:"); writeOut(s,runLevel); s(", q:[");
            auto lAtt=queue.queue;
            while(lAtt !is null){
                s("\n");
                if (lAtt !is queue) writeSpace(s,intentL+1);
                s("{ level:"); writeOut(s,lAtt.level); s(", q:[");
                foreach(i,e;lAtt.entries){
                    if (i!=0) {
                        s("\", \"");
                    } else {
                        s("\"");
                    }
                    writeOut(s,e);
                }
                if (lAtt.entries.length>0) s("\"");
                s("] }\n");
                lAtt=lAtt.next;
            }
            s("]}");
        }
    }
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    bool raiseRunlevelB(SchedulerRunLevel level){
        bool callReuse=false;
        synchronized(this){
            if (runLevel < cast(int)level){
                runLevel=level;
                return true;
            }
        }
        return false;
    }
    void raiseRunlevel(SchedulerRunLevel level){
        raiseRunlevelB(level);
    }
    /// called when the queue stops
    void reuse(){
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("PriQScheduler@")(cast(void*)this)(" reused");
            });
        }
        release();
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.nEntries>15; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return 4; }
    // add ref counting
    mixin RefCountMixin!();
    static __gshared CachedPool!(PriQScheduler) gPool;
    shared static this(){
        gPool=cachedPoolNext(function PriQScheduler(PoolI!(PriQScheduler)p){
            auto res=new PriQScheduler(p);
            debug(TrackQueues){
                sinkTogether(sout,delegate void(scope CharSink s){
                    dumper(s)("new PriQScheduler@")(cast(void*)res)("\n");
                });
            }
            return res;
        });
    }
}

class MultiSched:TaskSchedulerI {
    /// random source for scheduling
    RandomSync _rand;
    /// queue for tasks to execute
    Deque!(PriQScheduler) queue;
    /// semaphore for non busy waiting
    Semaphore zeroSem;
    /// numa not this schedule is connected to
    NumaNode numaNode;
    /// logger for problems/info
    Logger log;
    /// name of the scheduler
    string name;
    /// root Task
    TaskI _rootTask;
    /// runLevel of the scheduler
    SchedulerRunLevel runLevel;
    /// active tasks (tasks that have been taken from the scheduler and not yet finished)
    int[TaskI] activeTasks;
    /// steal level of the scheduler (mirrors a numa topology level)
    int stealLevel;
    /// level used for stealing from other schedulers
    int acceptLevel;
    /// executer
    ExecuterI _executer;
    /// returns the root task
    TaskI rootTask(){ return _rootTask; }
    /// numa node cache
    Cache _nnCache;
    /// running schedulers
    int nRunningScheds;
    /// starvationManager
    StarvationManager starvationManager;
    /// numa numa cache
    Cache nnCache(){
        return _nnCache;
    }
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    /// creates a new PriQScheduler
    this(string name,NumaNode numaNode,
        StarvationManager starvationManager,
        string loggerPath="blip.parallel.smp.queue")
    {
        this.name=collectIAppender(delegate void(scope CharSink s){
            s(name); s("_"); writeOut(s,numaNode.level); s("_"); writeOut(s,numaNode.pos);
        });
        this.starvationManager=starvationManager;
        this.numaNode=numaNode;
        assert(starvationManager!is null,"starvationManager must be valid");
        _nnCache=starvationManager.nnCacheForNode(numaNode);
        queue=new Deque!(PriQScheduler)();
        this._rand=new RandomSync();
        log=Log.lookup(loggerPath);
        _rootTask=new RootTask(this,0,name~"RootTask");
        stealLevel=int.max;
        acceptLevel=int.max;
        nRunningScheds=0;
        runLevel=SchedulerRunLevel.Running;
        zeroSem=new Semaphore();
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    /// adds a task to be executed without checking for starvation of other schedulers
    void addTask0(TaskI t){
        if (!(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started)){
            sout("task:")(t)("\n");
        }
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("pre MultiSched ")(this,true)(".addTask0(")(t)("):");writeStatus(s,4);
            });
            scope(exit){
                sinkTogether(&logMsg,delegate void(scope CharSink s){
                    dumper(s)("post MultiSched ")(this,true)(".addTask0:");writeStatus(s,4);
                });
            }
        }
        PriQScheduler newS;
        version(NoReuse){
            newS=new PriQScheduler(t.taskName,this);
        } else {
            newS=PriQScheduler.gPool.getObj(_nnCache);
            newS.reset(t.taskName,this);
        }
        if (t.scheduler is null || t.scheduler is this){
            t.scheduler=newS;
        }
        newS.addTask0(t);
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        debug(TrackQueues) log.info("task "~t.taskName~" might be added to a newly created queue in "~name);
        if (shouldAddTask(t)){
            addTask0(t);
        }
    }
    /// returns nextTask if available, null if not
    TaskI nextTaskImmediate(){
        TaskI t;
        PriQScheduler sched;
        while (t is null && runLevel!=SchedulerRunLevel.Stopped && queue.popFront(sched)){
            t=sched.nextTaskImmediate();
        }
        return t;
    }
    bool noActiveTasks(){
        synchronized(this){
            return activeTasks.length==0;
        }
    }
    /// steals tasks from this scheduler
    bool stealTask(int stealLevel,TaskSchedulerI targetScheduler){
        if (targetScheduler is this){
            synchronized(queue){
                if (queue.length>0) return true;
            }
            return false;
        }
        if (stealLevel>this.stealLevel) {
            return false;
        }
        if (runLevel>=SchedulerRunLevel.StopNoTasks){
            if (queue.length==0){
                if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                    queue.length==0 && noActiveTasks){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                return false;
            }
        }
        size_t didSteal=0;
        size_t pos=0;
        while (true){
            PriQScheduler sched;
            synchronized(queue){
                if (pos>=queue.length) break;
                sched=queue[pos];
                assert(sched.inSuperSched!=0,"unexpected inSuperSched value");
                sched.retain();
            }
            scope(exit){
                sched.release();
            }
            if (sched.stealLevel>=stealLevel){
                if (sched.stealTask(stealLevel,targetScheduler)){
                    ++didSteal;
                    if (rand.uniform!(bool)()) break;
                }
            }
            ++pos;
        }
        return didSteal!=0;
    }
    /// returns nextTask if available, null if it should wait
    TaskI nextTaskImmediate(int stealLevel){
        TaskI t=nextTaskImmediate();
        if (t is null && stealLevel>this.numaNode.level){
            t=starvationManager.trySteal(this,stealLevel);
        }
        return t;
    }
    void addSched(PriQScheduler sched){
        synchronized(queue){
            if (queue.appendL(sched)==0){
                debug(TrackQueues) {
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        s("MultiSched "); writeOut(s,this,true); s(" added sched@"); writeOut(s,cast(void*)sched);
                    });
                }
                zeroSem.notify();
            }
            //starvationManager.rmStarvingSched(this); // starvation removed only when a task is actually taken. (change?)
        }
    }
    /// returns nextTask (blocks, returns null only when stopped)
    TaskI nextTask(){
        TaskI t;
        bool starving=false;
        while(t is null){
            if (runLevel>=SchedulerRunLevel.StopNoTasks){
                if (queue.length==0){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        queue.length==0 && noActiveTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped) break;
            t=nextTaskImmediate(acceptLevel);
            if (t !is null || runLevel==SchedulerRunLevel.Stopped) break;
            if (!starving){
                starvationManager.addStarvingSched(this);
                starving=true;
                t=nextTaskImmediate(acceptLevel);
                if (t !is null || runLevel==SchedulerRunLevel.Stopped) break;
            }
            zeroSem.wait();
            synchronized(queue){
                if (queue.length>0 || runLevel==SchedulerRunLevel.Stopped){
                    zeroSem.notify();
                }
            }
        }
        if (starving){
            starvationManager.rmStarvingSched(this);
        }
        return t;
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st){
        synchronized(this){
            if (st in activeTasks){
                activeTasks[st]+=1;
            } else {
                activeTasks[st]=1;
            }
        }
        st.retain();
    }
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the inner scheduler
    void subtaskDeactivated(TaskI st){
        synchronized(this){
            if (activeTasks[st]>1){
                activeTasks[st]-=1;
            } else {
                activeTasks.remove(st);
            }
        }
        st.release();
    }
    /// returns wether the current task should be added (check for starvation)
    bool shouldAddTask(TaskI t){
        return ! starvationManager.redirectedTask(t,this);
    }
    /// yields the current task if the scheduler is not sequential
    void yield(){
        Fiber.yield();
    }
    /// maybe yields the current task if the scheduler is not sequential
    /// at the moment it is quite crude (50%, i.e. 25% less switches when the queue is full,
    /// and 25% (37.5% less switches) when the queue is empty)
    void maybeYield(){
        if (((!manyQueued()) || rand.uniform!(bool)()) && rand.uniform!(bool)())
            Fiber.yield();
    }
    /// sets the executer
    void executer(ExecuterI nExe){
        _executer=nExe;
    }
    /// removes the executer
    ExecuterI executer(){
        return _executer;
    }
    /// description (for debugging)
    void desc(scope void delegate(in cstring) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<MultiSched@"); writeOut(sink,cast(void*)this);
        if (shortVersion) {
            s(", name:")(name)(" >");
            return;
        }
        s("\n");
        s("  name:")(name)(",\n");
        s("  runLevel:")(runLevel)(",\n");
        s("  queue:")(queue)(",\n");
        s("  log:")(log)(",\n");
        s("  activeTasks:[\n");
        s("    ");
        bool nonFirst=false;
        foreach (t,r;activeTasks){
            if (nonFirst) { s(",\n"); nonFirst=true; }
            s("    ")(r);
            writeOut(sink,t,true);
        }
        s("\n");
        s("  ],\n");
        s("  rootTask:"); writeOut(sink,rootTask);
        s("\n >");
    }
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level){
        bool callOnStop=false;
        synchronized(this){
            assert(cast(int)runLevel <= cast(int)level,"runLevel can be only increased");
            if (runLevel < cast(int)level){
                runLevel=level;
                if (runLevel==SchedulerRunLevel.Stopped){
                    callOnStop=true;
                }
            }
        }
        if (callOnStop){
            zeroSem.notify();
            onStop();
        }
    }
    /// actions executed on stop (tells the starvationManager)
    void onStop(){
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                s("MultiSched "); writeOut(s,this,true); s(" stopped");
            });
        }
        starvationManager.schedulerStopped(this);
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.length>15; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return 4; }
    /// writes just the scheduling status in a way that looks good
    void writeStatus(scope CharSink sink,int indentL){
        auto s=dumper(sink);
        synchronized(queue){
            s("{ class:MultiSched, name:\"")(name)("\", scheds:\n");
            foreach(i,sched;queue){
                if (i!=0) s(",\n");
                writeSpace(sink,indentL+4);
                sched.writeStatus(sink,indentL+4);
            }
            s("\n");
            writeSpace(sink,indentL);
            s("}");
        }
    }
}

/// starvation manager helps distribution the tasks when some scheduler have no tasks
/// the algorithm is not perfect (does not lock always when it should),
/// but it is fast, as incorrectness just leads to suboptimal work loading
class StarvationManager: TaskSchedulerI, ExecuterI, SchedGroupI {
    enum :int{ MaxScheds=64 }
    string name; /// name of the StarvationManager
    NumaTopology topo; /// numa topology
    TaskSchedulerI[] scheds; /// schedulers (at the moment from just one level, normally 1 or 0)
    TaskI _rootTask; /// root task
    int schedLevel;  /// numa level of the schedulers (normally 1 or 0)
    int exeLevel;    /// numa level of the executer threads (normally 0 or 1)
    RandomSync _rand; /// random source for scheduling
    BitVector!(MaxScheds)[] starved; /// which schedulers are starved (or from which schedulers starved schedulers would accept tasks)
    SchedulerRunLevel runLevel; /// run level of the main queue
    int nRunningScheds; /// number of running schedulers
    int pinLevel; /// pinning level of the threads
    MExecuter[] executers; /// executer threads
    ExecuterI _executer; /// just because it is needed...
    /// logger for problems/info
    Logger log;
    /// logger for execution info
    Logger _execLogger;
    Cache[] nnCaches; /// numa node caches
    OnStarvingScheduler onStarvingSched; /// scheduler for low priority (idle) tasks
    
    /// logger for task execution messages
    Logger execLogger(){
        return _execLogger;
    }
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    
    void writeStatus(scope CharSink sink,int indentL){
        void ind(int l){
            writeSpace(sink,indentL+l);
        }
        auto s=dumper(sink);
        auto maxScheds=topo.nNodes(schedLevel);
        auto schedsN=scheds;
        synchronized(this){
            s("{ class:StarvationManager, runLevel:")(runLevel)(",\n");
            ind(2); s("starved:[\n");
            foreach(i,st;starved){
                if (i!=0) {
                    s("\",\n");
                }
                ind(4);
                s("\"");
                foreach(ibit,b;st){
                    if (ibit>=maxScheds) break;
                    if (b){
                        s("+");
                    } else {
                        s("-");
                    }
                }
            }
            s("\"],\n");
            ind(2);
            schedsN=scheds;
        }
        s("q:[ ");
        foreach(i,sched;schedsN){
            if (i!=0) { s(",\n"); ind(4); }
            (cast(MultiSched)sched).writeStatus(sink,indentL+6);
        }
        s("]}");
    }
    this(string name,NumaTopology topo,int schedLevel=1,int exeLevel=0,
        string loggerPath="blip.parallel.smp.queue",
        string exeLoggerPath="blip.parallel.smp.exec"){
        _rootTask=new RootTask(this,0,name~"RootTask");
        this.name=name;
        this.topo=topo;
        this.schedLevel=schedLevel;
        this.exeLevel=exeLevel;
        this.nRunningScheds=0;
        this.pinLevel=int.max;
        this._rand=new RandomSync();
        this._executer=this;
        starved=new BitVector!(MaxScheds)[](topo.maxLevel+1);
        runLevel=SchedulerRunLevel.Configuring;
        log=Log.lookup(loggerPath);
        _execLogger=Log.lookup(exeLoggerPath);
        this.onStarvingSched=new OnStarvingScheduler(this);
        addStarvingSched(NumaNode(schedLevel,0));
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    
    /// root task execution in one of the schedulers
    TaskI rootTask(){
        return _rootTask;
    }
    /// numa node cache for the given node
    Cache nnCacheForNode(NumaNode node){
        auto n=node;
        auto lNuma=((topo.maxLevel<=2)?topo.maxLevel:2);
        while (n.level<2){
            n=topo.superNode(n);
        }
        if (n.level==2){
            synchronized(this){
                if (n.pos<nnCaches.length) return nnCaches[n.pos]; // if append is atomic then sync is not needed for this statement
                for(int icache=cast(int)nnCaches.length;icache<=n.pos;++icache){
                    Cache oldC;
                    if (icache>0) oldC=nnCaches[icache-1];
                    nnCaches~=new Cache(oldC);
                }
                return nnCaches[n.pos];
            }
        } else {
            synchronized(this){
                if (0<nnCaches.length) return nnCaches[0]; // if append is atomic then sync is not needed for this statement
                nnCaches~=new Cache();
                return nnCaches[0];
            }
        }
    }
    /// nnCache, should not be used
    Cache nnCache(){
        return nnCacheForNode(NumaNode(2,0));
    }
    /// correspondence numa node -> position of the scheduler
    size_t numa2pos(NumaNode n){
        assert(n.level==schedLevel,"not a node of a scheduler");
        return cast(size_t)n.pos;
    }
    NumaNode pos2numa(size_t pos){
        NumaNode res;
        res.level=schedLevel;
        res.pos=cast(typeof(res.pos))pos;
        return res;
    }
    void addStarvingSched(NumaNode pos){
        assert(pos.level==schedLevel,"only uniform level is supported for now");
        synchronized(this){
            if (! starved[schedLevel][numa2pos(pos)]){
                NumaNode posAtt=pos;
                starved[schedLevel][numa2pos(posAtt)]=true;
                for (size_t i=schedLevel+1;i<starved.length;++i){
                    posAtt=topo.superNode(posAtt);
                    foreach(subN;subnodesWithLevel!(NumaNode)(schedLevel,cast(Topology!(NumaNode))topo,posAtt)){
                        starved[i][numa2pos(subN)]=true;
                    }
                }
            }
        }
    }
    /// adds the given scheduler to the list of starving ones
    void addStarvingSched(MultiSched sched){
        assert(numa2pos(sched.numaNode)>=0 && numa2pos(sched.numaNode)<scheds.length,"pos out of range");
        assert(scheds[numa2pos(sched.numaNode)] is cast(TaskSchedulerI)sched,"mismatched sched.pos");
        addStarvingSched(sched.numaNode);
    }
    /// removes a scheduler, regeneration of starved masks could be more efficient
    void rmStarvingSched(MultiSched sched){
        auto pos=numa2pos(sched.numaNode);
        assert(pos>=0 && pos<topo.nNodes(schedLevel),"pos out of range");
        assert(scheds[pos] is sched,"mismatched sched.pos");
        if (starved[schedLevel][pos]){ // might be wrong... but is much faster, if wrong it is just less efficient
            synchronized(this){
                if (starved[schedLevel][pos]){
                    starved[schedLevel][pos]=false;
                    for (size_t ilevel=schedLevel+1;ilevel<starved.length;++ilevel){
                        BitVector!(MaxScheds) lAttBit;
                        foreach(indx; starved[schedLevel].loopTrue){
                            NumaNode posAtt;
                            posAtt.level=schedLevel;
                            posAtt.pos=cast(typeof(posAtt.pos))indx;
                            for(int i=schedLevel;i<ilevel;++i){
                                posAtt=topo.superNode(posAtt);
                            }
                            foreach(subN;subnodesWithLevel(1,cast(Topology!(NumaNode))topo,posAtt)){
                                lAttBit[subN.pos]=true;
                            }
                        }
                        starved[ilevel]=lAttBit;
                    }
                }
            }
        }
    }
    /// tries to steal a task, might redistribute the tasks
    TaskI trySteal(MultiSched el,int stealLevel){
        TaskI t;
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                s("pre trySteal for "); writeOut(s,el,true); s(" in "); writeOut(s,this,true); s(":");writeStatus(s,4);
            });
            scope(exit){
                sinkTogether(&logMsg,delegate void(scope CharSink s){
                    dumper(s)("trySteal for ")(el.name)(" in ")(this,true)(" returns ")(t)(", status:");
                    writeStatus(s,4);
                });
            }
        }
        auto superN=el.numaNode;
        NumaNode oldSuper=superN;
        auto maxLevel=min(stealLevel,min(el.acceptLevel,topo.maxLevel));
        while (superN.level<maxLevel){
            superN=topo.superNode(superN);
            foreach(subN;randomSubnodesWithLevel(1,cast(Topology!(NumaNode))topo,superN,oldSuper)){
                auto subP=numa2pos(subN);
                if (subP<scheds.length && scheds[subP]!is cast(TaskSchedulerI)el && 
                    (cast(MultiSched)(scheds[subP])).stealTask(superN.level,el)){
                    t=el.nextTaskImmediate();
                    if (t !is null) {
                        return t;
                    }
                }
            }
            oldSuper=superN;
        }
        t=el.nextTaskImmediate();
        if (t is null){
            onStarvingSched.queue.popFront(t);
            if (t!is null) {
                el.addTask0(t);
                t=el.nextTaskImmediate();
            }
        }
//        if (t!is null){
//            rmStarvingSched(el); // to ensure that the scheduler is removed
//        }
        return t;
    }
    bool redirectedTask(TaskI t,MultiSched sched,int stealLevelMax=int.max){
        auto sLevel=min(min(sched.stealLevel,t.stealLevel),cast(int)starved.length-1);
        auto pos=numa2pos(sched.numaNode);
        bool ss;
        ss=starved[sLevel][pos];
        if (ss){
            auto superN=sched.numaNode;
            NumaNode oldSuper=superN;
            while (superN.level<sLevel){
                superN=topo.superNode(superN);
                foreach(subN;randomSubnodesWithLevel(schedLevel,
                    cast(Topology!(NumaNode))topo,superN,oldSuper))
                {
                    auto pos2=numa2pos(subN);
                    bool ss2;
                    ss2=starved[schedLevel][pos2];
                    if (ss2){
                        synchronized(this){
                            if (!starved[sLevel][pos] || starved[schedLevel][pos]){
                                return false;
                            }
                            if (!starved[schedLevel][pos2]) continue;
                        }
                        addIfNonExistent(pos2);
                        t.scheduler=scheds[pos2];
                        scheds[pos2].addTask0(t);
                        return true;
                    }
                }
            }
        }
        return false;
    }
    bool redirectedTask(TaskI t,PriQScheduler sched,int stealLevelMax=int.max){
        return redirectedTask(t,sched.superScheduler,min(sched.stealLevel,stealLevelMax));
    }
    bool addIfNonExistent(size_t pos){
        assert(pos<topo.nNodes(schedLevel),"cannot add more schedulers than nodes");
        raiseRunlevel(SchedulerRunLevel.Running);
        synchronized(this){
            if (scheds.length<=pos){
                for(size_t pAtt=scheds.length;pAtt<=pos;++pAtt){
                    ++nRunningScheds;
                    auto nAtt=pos2numa(pAtt);
                    auto nSched=new MultiSched(name,nAtt,this);
                    scheds~=nSched;
                    assert(scheds[pAtt] is cast(TaskSchedulerI)nSched);
                    rmStarvingSched(nSched);
                    if (exeLevel<schedLevel){
                        foreach(subN;subnodesWithLevel(exeLevel,cast(Topology!(NumaNode))topo,nAtt)){
                            startWorker(subN,nSched);
                        }
                    } else {
                        startWorker(nAtt,nSched);
                    }
                }
                if (scheds.length<topo.nNodes(schedLevel)&&runLevel!=SchedulerRunLevel.Stopped){
                    addStarvingSched(pos2numa(scheds.length));
                }
                return true;
            }
        }
        return false;
    }
    /// starts a worker thread
    void startWorker(NumaNode n, MultiSched s){
        synchronized(this){
            executers~=new MExecuter(name,n,s,this);
        }
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        // try starved, otherwise random...
        while(true) {
            bool hasStarved=false;
            size_t pos;
            synchronized(this){
                foreach(p;starved[schedLevel].loopTrue){
                    hasStarved=true;
                    pos=p;
                    break;
                }
            }
            if (!hasStarved) break;
            addIfNonExistent(pos);
            bool ss;
            ss=starved[schedLevel][pos];
            if (ss) {
                t.scheduler=scheds[pos];
                scheds[pos].addTask0(t);
                return;
            }
        }
        size_t selectedSched;
        assert(scheds.length>0);
        if (scheds.length==1){
            selectedSched=0;
        } else {
            synchronized(this){
                size_t i=this.rand.uniformR(scheds.length);
                size_t j=this.rand.uniformR(scheds.length-1);
                if (j>=i) ++j;
                if ((cast(MultiSched)(scheds[i])).queue.length<(cast(MultiSched)(scheds[j])).queue.length){
                    selectedSched=i;
                } else {
                    selectedSched=j;
                }
            }
        }
        t.scheduler=scheds[selectedSched];
        scheds[selectedSched].addTask0(t);
    }
    // alias addTask addTask0;
    void addTask0(TaskI t){
        addTask(t);
    }
    /// called when a scheduler stops
    void schedulerStopped(MultiSched s){
        synchronized(this){
            --nRunningScheds;
            if (nRunningScheds==0){
                raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
    }
    /// returns nextTask (not meaningful for this scheduler)
    TaskI nextTask(){
        return null;
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// subtask has started execution (not meaningful for this scheduler)
    void subtaskActivated(TaskI st){
    }
    /// subtask has stopped execution (but is not necessarily finished)
    /// (not meaningful for this scheduler)
    void subtaskDeactivated(TaskI st){
    }
    /// yields the current task if the scheduler is not sequential
    void yield(){
        Fiber.yield();
    }
    /// maybe yields the current task if the scheduler is not sequential
    /// at the moment it is quite crude (50%, i.e. 25% less switches when the queue is full,
    /// and 25% (37.5% less switches) when the queue is empty)
    void maybeYield(){
        if (((!manyQueued()) || rand.uniform!(bool)()) && rand.uniform!(bool)())
            Fiber.yield();
    }
    /// sets the executer
    void executer(ExecuterI nExe){
        _executer=nExe;
    }
    /// removes the executer
    ExecuterI executer(){
        return _executer;
    }
    /// description (for debugging)
    void desc(scope void delegate(in cstring) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<StarvationManager@"); writeOut(sink,cast(void*)this);
        if (shortVersion) {
            s(" >");
            return;
        }
        s("\n");
        s("  name:")(name)(",\n");
        s("  topo:")(topo)(",\n");
        s("  sched:")(scheds)(",\n");
        s("  rootTask:"); writeOut(sink,_rootTask);
        s("  rand:")(rand)("\n");
        s("  starved:")(starved)("\n");
        s("  runLevel:")(runLevel)(",\n");
        s("  pinLevel:")(pinLevel)(",\n");
        s("  schedLevel:")(schedLevel)(",\n");
        s("  exeLevel:")(exeLevel)(",\n");
        s("  nRunningScheds:")(nRunningScheds)(",\n");
        s("  log:")(log)(",\n");
        s("  execLogger:")(execLogger)(",\n");
        s("  executers:");writeOut(sink,execLogger,true);s(",\n");
        s("  rootTask:"); writeOut(sink,rootTask,true);
        s("\n >");
    }
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level){
        bool callOnStop=false;
        synchronized(this){
            if (runLevel < cast(int)level){
                runLevel=level;
                foreach(sched;scheds){
                    sched.raiseRunlevel(runLevel);
                }
                if (runLevel==SchedulerRunLevel.Stopped) callOnStop=true;
            }
        }
        if (callOnStop){
            onStop();
        }
    }
    /// called when the scheduler stops
    void onStop(){
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return false; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return max(2,topo.nNodes(exeLevel)/topo.nNodes(schedLevel)); }
    
    /// group of this executer, can be used for deterministic task distribution
    SchedGroupI schedGroup(){
        return this;
    }
    // schedGroupI
    /// activate all possible schedulers in the current group
    void activateAll() {
        if (runLevel>=SchedulerRunLevel.Stopped) return;
        size_t i, nTot;
        synchronized(this){
            i=scheds.length;
            nTot=topo.nNodes(schedLevel);
        }
        while (i<nTot){
            addIfNonExistent(i++);
        }
    }
    /// returns the currently active schedulers
    TaskSchedulerI[] activeScheds() {
        return scheds;
    }
    /// logger for the group
    Logger groupLogger() {
        return log;
    }
    /// global root task (should submit to the least used scheduler)
    TaskI gRootTask() {
        return rootTask();
    }
    /// root task for things that should be executed only if nothing else is executing
    TaskI onStarvingTask(){
        return onStarvingSched.rootTask();
    }
}

class MExecuter:ExecuterI{
    /// numa node associated with the thread
    NumaNode exeNode;
    /// scheduler from which tasks are taken
    MultiSched _scheduler;
    /// the worker thread
    Thread worker;
    /// logger for problems/info
    Logger log;
    /// name of the executer
    string _name;
    /// global group
    StarvationManager sManager;
    /// name accessor
    string name(){
        return _name;
    }
    TaskSchedulerI scheduler(){ return _scheduler; }
    /// creates a new executer
    this(string name,NumaNode exeNode, MultiSched scheduler, StarvationManager sManager){
        this._name=name;
        this._scheduler=scheduler;
        this.exeNode=exeNode;
        this.sManager=sManager;
        this._scheduler.executer=this;
        log=_scheduler.starvationManager.execLogger;
        worker=new Thread(&(this.workThreadJob),16*8192);
        worker.isDaemon=true;
        worker.name=collectIAppender(delegate void(scope CharSink s){
            s(name); s("_"); writeOut(s,exeNode.level); s("_"); writeOut(s,exeNode.pos);
        });
        worker.start();
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    /// the job of the worker threads
    void workThreadJob(){
        sinkTogether(&logMsg,delegate void(scope CharSink s){
            dumper(s)("Work thread ")(Thread.getThis().name)(" started");
        });
        scope(exit){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("Work thread ")(Thread.getThis().name)(" stopped");
            });
        }
        try{
            setDefaultCache(_scheduler.nnCache());
        } catch(Exception e){
            log.error("setDefaultCache failed, continuing...");
            //log.error(collectIAppender(&e.writeOut));
            log.error(e.toString());
        }
        try{
            pin(_scheduler.starvationManager.pinLevel);
        } catch(Exception e){
            log.error("pinning failed, continuing...");
            //log.error(collectIAppender(&e.writeOut));
            log.error(e.toString());
        }
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" starting task ")(t);
                    });
                }
                if (t is null) return;
                auto schedAtt=t.scheduler; // the task scheduler can change just after execution, but before subtaskDeactivated is called...
                auto tPos=cast(void*)cast(Object)t;
                t.execute(false);
                auto tName=t.taskName;
                schedAtt.subtaskDeactivated(t);
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" finished task ")(tName)("@")(tPos);
                    });
                }
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                //log.error(collectIAppender(&e.writeOut));
		log.error(e.toString);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
                abort();
            }
        }
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(scope CharSink s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope CharSink s,bool shortVersion){
        s("<MExecuter@");writeOut(s,cast(void*)this);
        if (shortVersion) {
            s("  name:\""); writeOut(s,name); s("\"");
            s(" >");
            return;
        }
        s("\n");
        s("  name:"); writeOut(s,name); s(",\n");
        s("  exeNode:"); writeOut(s,exeNode); s(",\n");
        s("  worker:"); writeOut(s,worker); s(",\n");
        s("  scheduler:"); writeOut(s,scheduler,true); s(",\n");
        s("  log:"); writeOut(s,log); s(",\n");
        s(" >");
    }
    /// logger for task execution messages
    Logger execLogger(){
        return log;
    }
    void pin(int pinLevel){
        auto topo=_scheduler.starvationManager.topo;
        if (pinLevel<topo.maxLevel){
            auto n=exeNode;
            while(n.level<pinLevel){
                n=topo.superNode(n);
            }
            auto res=topo.bindToNode(n);
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("Work thread ")(Thread.getThis().name);
                if (res){
                    s(" pinned to ");
                } else {
                    s(" *not* pinned to ");
                }
                writeOut(s,exeNode);
            });
        }
    }
    SchedGroupI schedGroup(){
        return sManager;
    }
}

/// scheduler for the onStarving queue
class OnStarvingScheduler:TaskSchedulerI{
    StarvationManager mainSched;
    Deque!(TaskI) queue; /// tasks to execute only if a scheduler is starving (i.e. low priority tasks)
    TaskI _rootTask; /// root task that adds to the onStarvingQueue
    
    this(StarvationManager st){
        this.queue=new Deque!(TaskI)();
        this.mainSched=st;
        this._rootTask=new RootTask(this,0,mainSched.name~"OnStarvingRootTask");
    }
    
    /// random source (for scheduling)
    RandomSync rand(){
        return mainSched.rand();
    }
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level){
        mainSched.raiseRunlevel(level);
    }
    /// adds a task to the scheduler queue (might redirect the task)
    void addTask(TaskI t){
        queue.append(t);
        TaskI t2;
        int isched;
        synchronized(mainSched){
            foreach(p;mainSched.starved[mainSched.schedLevel].loopTrue){
                if (queue.popFront(t2)){
                    isched=cast(typeof(isched))p;
                }
                break;
            }
        }
        if (t2!is null){
            mainSched.addIfNonExistent(isched);
            t2.scheduler=mainSched;
            mainSched.scheds[isched].addTask(t2);
        }
    }
    /// adds a task to the scheduler queue (will not redirect the task)
    void addTask0(TaskI t){
        addTask(t);
    }
    /// returns the next task, blocks unless the scheduler is stopped
    TaskI nextTask(){
        assert(0,"not supposed to be called for OnStarvingScheduler");
    }
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st){
        assert(0,"not supposed to be called for OnStarvingScheduler");
    }
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st){
        assert(0,"not supposed to be called for OnStarvingScheduler");
    }
    /// returns the executer for this scheduler
    ExecuterI executer(){
        return mainSched.executer();
    }
    /// sets the executer for this scheduler
    void executer(ExecuterI nExe){
        mainSched.executer(nExe);
    }
    /// logger for task/scheduling messages
    Logger logger(){
        return mainSched.logger();
    }
    /// yields the current fiber if the scheduler is not sequential
    void yield(){
        mainSched.yield();
    }
    /// maybe yields the current fiber (use this to avoid creating too many tasks)
    void maybeYield(){
        mainSched.maybeYield();
    }
    /// root task, the easy way to add tasks to this scheduler
    TaskI rootTask(){
        return _rootTask;
    }
    /// description
    void desc(scope void delegate(in cstring) s){
        desc(s,false);
    }
    /// possibly short description
    void desc(scope void delegate(in cstring) s,bool shortVersion){
        s("<OnStarvingScheduler@");writeOut(s,cast(void*)this);
        if (shortVersion) {
            s(" >");
            return;
        }
        s("\n");
        s("  mainSched:"); writeOut(s,mainSched,true); s(",\n");
        s("  queue:"); writeOut(s,queue); s(",\n");
        s(" >");
        
    }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued(){
        return mainSched.manyQueued();
    }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){
        return mainSched.nSimpleTasksWanted();
    }
    /// a cache local to the current numa node (useful for memory pools)
    Cache nnCache(){
        return mainSched.nnCache();
    }
    
}
