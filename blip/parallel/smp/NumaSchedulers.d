/// schedulers that take advantage of numa topology
module blip.parallel.smp.NumaSchedulers;
import blip.t.core.Thread;
import blip.t.core.Variant:Variant;
import blip.t.core.sync.Mutex;
import blip.t.core.sync.Semaphore;
import blip.t.math.Math;
import blip.t.util.log.Log;
import blip.t.math.random.Random;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.TemplateFu:ctfe_i2a;
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
import tango.stdc.stdlib: abort; // pippo
import blip.t.core.stacktrace.StackTrace; // pippo

// locking order, be careful to change that to avoid deadlocks
// especially addSched and redirectedTask are sensible
//
// PriQSched(this): never lock anything else
// PriQSched(queue.lock): never lock anything else
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
    static Cached!(PriQueue!(TaskI).PriQPool) pQLevelPool;
    static this(){
        pQLevelPool=new Cached!(PriQueue!(TaskI).PriQPool)(delegate PriQueue!(TaskI).PriQPool(){
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
    char[] name;
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
    Cache _nnCache;
    /// cache at numa node level
    Cache nnCache(){
        return _nnCache;
    }
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    /// creates a new PriQScheduler
    this(char[] name,MultiSched superScheduler,char[] loggerPath="blip.parallel.smp.queue",int level=0){
        this.name=name;
        assert(superScheduler!is null);
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        version(NoReuse){
            queue=new PriQueue!(TaskI)();
        } else {
            queue=new PriQueue!(TaskI)(pQLevelPool(_nnCache));
        }
        this._rand=new RandomSync();
        this.inSuperSched=0;
        log=Log.lookup(loggerPath);
        _rootTask=new RootTask(this,0,name~"RootTask");
        runLevel=SchedulerRunLevel.Running;
        raiseRunlevel(superScheduler.runLevel);
    }
    void reset(char[] name,MultiSched superScheduler){
        this.name=name;
        assert(superScheduler!is null);
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        if (!queue.reset()){
            throw new Exception("someone waiting on queue, this should neve happen (wait are only on MultiSched)",
                __FILE__,__LINE__);
        }
        stealLevel=int.max;
        inSuperSched=0;
        runLevel=SchedulerRunLevel.Running;
        raiseRunlevel(superScheduler.runLevel);
    }
    void addTask0(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        version(TrackQueues){
            log.info(collectAppender(delegate void(CharSink s){
                s("pre PriQScheduler "); s(name); s(".addTask0:");writeStatus(s,4);
            }));
            log.info("task "~t.taskName~" will be added to queue "~name);
            scope(exit){
                log.info(collectAppender(delegate void(CharSink s){
                    s("post PriQScheduler "); s(name); s(".addTask0:");writeStatus(s,4);
                }));
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
        }
        if (addToSuperSched) superScheduler.addSched(this);
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        version(TrackQueues) log.info("task "~t.taskName~" might be added to queue "~name);
        if (shouldAddTask(t)){
            addTask0(t);
        }
    }
    /// returns nextTask if available, null if it should wait
    /// adds this to the super scheduler if task is not null
    TaskI nextTaskImmediate(){
        TaskI t;
        if (runLevel>=SchedulerRunLevel.StopNoTasks){
            if (queue.nEntries==0){
                if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                    queue.nEntries==0 && activeTasks.length==0){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                synchronized(queue.queueLock){
                    // empty the queue?
                    inSuperSched=0;
                }
                return null;
            }
        }
        t=queue.popNext(true);
        if (t is null){
            synchronized(queue.queueLock){
                t=queue.popNext(true);
                if (t is null) inSuperSched=0;
            }
        }
        if (t !is null){
            superScheduler.addSched(this);
            subtaskActivated(t);
        }
        return t;
    }
    /// returns nextTask (blocks, returns null only when stopped)
    TaskI nextTask(){
        TaskI t;
        t=this.nextTaskImmediate();
        if (t is null){
            if (runLevel!=SchedulerRunLevel.Stopped){
                t=queue.popNext(false);
            }
            if (t !is null){
                superScheduler.addSched(this);
                subtaskActivated(t);
            } else {
                assert(runLevel==SchedulerRunLevel.Stopped);
                inSuperSched=0;
            }
        }
        return t;
    }
    /// steals tasks from the current scheduler
    bool stealTask(int stealLevel,TaskSchedulerI targetScheduler){
        if (stealLevel>this.stealLevel) return false;
        TaskI t;
        if (runLevel>=SchedulerRunLevel.StopNoTasks){
            if (queue.nEntries==0){
                if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                    queue.nEntries==0 && activeTasks.length==0){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                return false;
            }
        }
        if (!queue.popBack(t,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
            return false;
        }
        t.scheduler=targetScheduler;
        targetScheduler.addTask0(t);
        auto scheduler2=t.scheduler;
        if(scheduler2 is null) scheduler2=targetScheduler;
        while (true){
            if(rand.uniform!(bool)()) return true;
            TaskI t2;
            if (!queue.popBack(t2,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
                return true;
            }
            t2.scheduler=scheduler2;
            scheduler2.addTask0(t2);
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
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
        synchronized(this){
            if (st in activeTasks){
                activeTasks[st]+=1;
            } else {
                activeTasks[st]=1;
            }
        }
    }
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st){
        bool checkRunLevel=false;
        synchronized(this){
            if (activeTasks[st]>1){
                activeTasks[st]-=1;
            } else {
                activeTasks.remove(st);
                if (runLevel>=SchedulerRunLevel.StopNoTasks && queue.nEntries==0){
                    checkRunLevel=true;
                }
            }
        }
        if (checkRunLevel){
            if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                raiseRunlevel(SchedulerRunLevel.Stopped);
            } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                activeTasks.length==0){
                raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
        superScheduler.subtaskDeactivated(st);
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
    void desc(void delegate(char[]) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<PriQScheduler@"); writeOut(sink,cast(void*)this);
        if (shortVersion) {
            s(" >");
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
    void writeStatus(CharSink s,int intentL){
        synchronized(queue.queueLock){
            s("{ \"sched@\":"); writeOut(s,cast(void*)this); s(", q:[");
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
                    s(e.taskName);
                    s("@");
                    writeOut(s,cast(void*)e);
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
    void raiseRunlevel(SchedulerRunLevel level){
        bool callOnStop=false;
        synchronized(this){
            if (runLevel < cast(int)level){
                runLevel=level;
                if (runLevel==SchedulerRunLevel.Stopped){
                    callOnStop=true;
                }
            }
        }
        if (callOnStop){
            queue.stop();
            onStop();
        }
    }
    /// called when the queue stops
    void onStop(){
        superScheduler.queueStopped(this);
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.nEntries>15; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return 4; }
}

class MultiSched:TaskSchedulerI {
    static Cached!(PriQScheduler*) pQSchedPool;
    static this(){
        pQSchedPool=new Cached!(PriQScheduler*)(delegate PriQScheduler*(){
            auto res=cast(PriQScheduler*)cast(void*)new size_t;
            return res;
        });
    }
    /// random source for scheduling
    RandomSync _rand;
    /// queue for tasks to execute
    Deque!(PriQScheduler) queue;
    /// semaphore for non busy waiting
    Semaphore zeroSem;
    /// how many are waiting on the semaphore... (not all semaphores give that info)
    int zeroLock;
    /// numa not this schedule is connected to
    NumaNode numaNode;
    /// logger for problems/info
    Logger log;
    /// name of the scheduler
    char[] name;
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
    this(char[] name,NumaNode numaNode,
        StarvationManager starvationManager,
        char[] loggerPath="blip.parallel.smp.queue")
    {
        this.name=collectAppender(delegate void(CharSink s){
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
    /// adds a task to be executed without checking for starvation of other schedulers
    void addTask0(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        version(TrackQueues){
            log.info(collectAppender(delegate void(CharSink s){
                s("pre MultiSched ");s(name);s(".addTask0:");writeStatus(s,4);
            }));
            scope(exit){
                log.info(collectAppender(delegate void(CharSink s){
                    s("post MultiSched ");s(name);s(".addTask0:");writeStatus(s,4);
                }));
            }
            log.info("task "~t.taskName~" will be added to a newly created queue in "~name);
        }
        version(NoReuse){
            auto newS=new PriQScheduler(t.taskName,this);
        } else {
            auto newS=popFrom(*pQSchedPool(_nnCache));
            if (newS is null){
                newS=new PriQScheduler(t.taskName,this);
            } else {
                newS.reset(t.taskName,this);
            }
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
        version(TrackQueues) log.info("task "~t.taskName~" might be added to a newly created queue in "~name);
        if (shouldAddTask(t)){
            addTask0(t);
        }
    }
    /// returns nextTask if available, null if not
    TaskI nextTaskImmediate(){
        TaskI t;
        PriQScheduler sched;
        while (t is null){
            if (runLevel==SchedulerRunLevel.Stopped) return null;
            if (!queue.popFront(sched)) break;
            t=sched.nextTaskImmediate();
        }
        if (t !is null){
            subtaskActivated(t);
        }
        return t;
    }
    /// steals tasks from this scheduler
    bool stealTask(int stealLevel,TaskSchedulerI targetScheduler){
        if (stealLevel>this.stealLevel) return false;
        if (runLevel>=SchedulerRunLevel.StopNoTasks){
            if (queue.length==0){
                if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                    queue.length==0 && activeTasks.length==0){
                    raiseRunlevel(SchedulerRunLevel.Stopped);
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                return false;
            }
        }
        size_t didSteal=0;
        synchronized(queue){
            foreach (sched;queue){
                assert(sched.inSuperSched!=0,"unexpected inSuperSched value");
                if (sched.stealLevel>=stealLevel){
                    if (sched.stealTask(stealLevel,targetScheduler)){
                        ++didSteal;
                        if (rand.uniform!(bool)()) break;
                    }
                }
            }
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
    /// queue stop
    void queueStopped(PriQScheduler q){
        version(TrackQueues){
            log.info(collectAppender(delegate void(CharSink s){
                s("scheduler "); s(q.name); s(" finished");
            }));
        }
        version(NoReuse){} else{
            insertAt(*pQSchedPool(_nnCache),q);
        }
    }
    void addSched(PriQScheduler sched){
        synchronized(queue){
            queue.append(sched);
            starvationManager.rmStarvingSched(this);
            version(TrackQueues) {
                log.info(collectAppender(delegate void(CharSink s){
                    s("MultiSched "); s(name); s(" added sched@"); writeOut(s,cast(void*)sched);
                }));
            }
            if (zeroLock>0){
                atomicAdd(zeroLock,-1);
                zeroSem.notify();
            }
        }
    }
    /// returns nextTask (blocks, returns null only when stopped)
    TaskI nextTask(){
        TaskI t;
        while(t is null){
            if (runLevel>=SchedulerRunLevel.StopNoTasks){
                if (queue.length==0){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        queue.length==0 && activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
                PriQScheduler sched;
                if (queue.popFront(sched)){
                    t=sched.nextTaskImmediate();
                    if (t is null) continue;
                }
                if (acceptLevel>numaNode.level && t is null){
                    t=starvationManager.trySteal(this,acceptLevel);
                }
                if (runLevel==SchedulerRunLevel.Stopped)
                    return null;
            }
            if (t is null) {
                starvationManager.addStarvingSched(this);
                // better close the gap in which added tasks are not redirected...
                // remove this? imperfect redirection just leads to inefficency, not errors
                t=starvationManager.trySteal(this,acceptLevel);
            }
            if (t is null) {
                atomicAdd(zeroLock,1);
                zeroSem.wait();
                synchronized(queue){
                    if (zeroLock>0 && (queue.length>0 || runLevel==SchedulerRunLevel.Stopped)){
                        atomicAdd(zeroLock,-1);
                        zeroSem.notify();
                    }
                }
            }
        }
        subtaskActivated(t);
        return t;
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
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
        if (!st.tryReuse()){
            st.release();
        }
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
    void desc(void delegate(char[]) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<MultiSched@"); writeOut(sink,cast(void*)this);
        if (shortVersion) {
            s(" >");
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
            if (atomicOp(zeroLock,delegate typeof(zeroLock)(typeof(zeroLock) x){ if (x>0) return x-1; return x; })>0){
                zeroSem.notify();
            }
            onStop();
        }
    }
    /// actions executed on stop (tells the starvationManager)
    void onStop(){
        version(TrackQueues){
            log.info(collectAppender(delegate void(CharSink s){
                s("MultiSched "); s(name); s(" stopped");
            }));
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
    void writeStatus(CharSink sink,int indentL){
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
class StarvationManager: TaskSchedulerI,ExecuterI{
    enum :int{ MaxScheds=64 }
    char[] name; /// name of the StarvationManager
    NumaTopology topo; /// numa topology
    MultiSched[] scheds; /// schedulers (at the moment from just one level, normally 1 or 0)
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
    
    /// logger for task execution messages
    Logger execLogger(){
        return _execLogger;
    }
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    
    void writeStatus(CharSink sink,int indentL){
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
            volatile schedsN=scheds;
        }
        s("q:[ ");
        foreach(i,sched;schedsN){
            if (i!=0) { s(",\n"); ind(4); }
            sched.writeStatus(sink,indentL+6);
        }
        s("]}");
    }
    this(char[] name,NumaTopology topo,int schedLevel=1,int exeLevel=0,
        char[] loggerPath="blip.parallel.smp.queue",
        char[]exeLoggerPath="blip.parallel.smp.exec"){
        _rootTask=new RootTask(this,0,name~"RootTask");
        this.name=name;
        this.topo=topo;
        this.schedLevel=schedLevel;
        this.exeLevel=exeLevel;
        this.nRunningScheds=0;
        this.pinLevel=int.max;
        this._rand=new RandomSync();
        starved=new BitVector!(MaxScheds)[](topo.maxLevel+1);
        runLevel=SchedulerRunLevel.Configuring;
        log=Log.lookup(loggerPath);
        _execLogger=Log.lookup(exeLoggerPath);
        addStarvingSched(NumaNode(schedLevel,0));
    }
    
    TaskI rootTask(){
        return _rootTask;
    }
    
    /// numa node cache for the given node
    Cache nnCacheForNode(NumaNode node){
        auto n=node;
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
        res.pos=pos;
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
        assert(scheds[numa2pos(sched.numaNode)] is sched,"mismatched sched.pos");
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
                            posAtt.pos=indx;
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
        version(TrackQueues){
            log.info(collectAppender(delegate void(CharSink s){
                s("pre trySteal in "); s(name); s(":");writeStatus(s,4);
            }));
            scope(exit){
                log.info(collectAppender(delegate void(CharSink s){
                    s("post trySteal in "); s(name); s(":");writeStatus(s,4);
                }));
            }
        }
        auto superN=el.numaNode;
        NumaNode oldSuper=superN;
        auto maxLevel=min(stealLevel,min(el.acceptLevel,topo.maxLevel));
        while (superN.level<maxLevel){
            superN=topo.superNode(superN);
            foreach(subN;randomSubnodesWithLevel(1,cast(Topology!(NumaNode))topo,superN,oldSuper)){
                auto subP=numa2pos(subN);
                if (subP<scheds.length && scheds[subP].stealTask(superN.level,el)){
                    auto t=el.nextTaskImmediate();
                    if (t !is null) return t;
                }
            }
            oldSuper=superN;
        }
        auto t=el.nextTaskImmediate();
        return t;
    }
    bool redirectedTask(TaskI t,MultiSched sched,int stealLevelMax=int.max){
        auto sLevel=min(min(sched.stealLevel,t.stealLevel),cast(int)starved.length-1);
        auto pos=numa2pos(sched.numaNode);
        if (starved[sLevel][pos]){
            auto superN=sched.numaNode;
            NumaNode oldSuper=superN;
            while (superN.level<sLevel){
                superN=topo.superNode(superN);
                foreach(subN;randomSubnodesWithLevel(schedLevel,
                    cast(Topology!(NumaNode))topo,superN,oldSuper))
                {
                    auto pos2=numa2pos(subN);
                    if (starved[schedLevel][pos2]){
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
        if (scheds.length<=pos){
            synchronized(this){
                for(size_t pAtt=scheds.length;pAtt<=pos;++pAtt){
                    ++nRunningScheds;
                    auto nAtt=pos2numa(pAtt);
                    scheds~=new MultiSched(name,nAtt,this);
                    if (exeLevel<schedLevel){
                        foreach(subN;subnodesWithLevel(exeLevel,cast(Topology!(NumaNode))topo,nAtt)){
                            startWorker(subN,scheds[pAtt]);
                        }
                    } else {
                        startWorker(nAtt,scheds[pAtt]);
                    }
                }
                if (scheds.length<topo.nNodes(schedLevel)&&runLevel!=SchedulerRunLevel.Stopped){
                    addStarvingSched(pos2numa(scheds.length));
                }
            }
            return true;
        }
        return false;
    }
    /// starts a worker thread
    void startWorker(NumaNode n, MultiSched s){
        synchronized(this){
            executers~=new MExecuter(name,n,s);
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
            if (starved[schedLevel][pos]) {
                t.scheduler=scheds[pos];
                scheds[pos].addTask0(t);
                return;
            }
        }
        synchronized(this){
            size_t i=this.rand.uniformR(scheds.length);
            size_t j=this.rand.uniformR(scheds.length-1);
            if (j>=i) ++j;
            if (scheds[i].queue.length<scheds[j].queue.length){
                t.scheduler=scheds[i];
                scheds[i].addTask(t);
            } else {
                t.scheduler=scheds[j];
                scheds[j].addTask(t);
            }
        }
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
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
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
    void desc(void delegate(char[]) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) sink,bool shortVersion){
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
    char[] _name;
    /// name accessor
    char[] name(){
        return _name;
    }
    TaskSchedulerI scheduler(){ return _scheduler; }
    /// creates a new executer
    this(char[] name,NumaNode exeNode, MultiSched scheduler){
        this._name=name;
        this._scheduler=scheduler;
        this.exeNode=exeNode;
        log=_scheduler.starvationManager.execLogger;
        worker=new Thread(&(this.workThreadJob),16*8192);
        worker.isDaemon=true;
        worker.name=collectAppender(delegate void(CharSink s){
            s(name); s("_"); writeOut(s,exeNode.level); s("_"); writeOut(s,exeNode.pos);
        });
        worker.start();
    }
    /// the job of the worker threads
    void workThreadJob(){
        log.info("Work thread "~Thread.getThis().name~" started");
        scope(exit){
            log.info("Work thread "~Thread.getThis().name~" stopped");
        }
        try{
            pin(_scheduler.starvationManager.pinLevel);
        } catch(Exception e){
            log.error("pinning failed, continuing...");
            log.error(collectAppender(&e.writeOut));
        }
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                log.info("Work thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) return;
                auto schedAtt=t.scheduler; // the task scheduler can change just after execution, but before subtaskDeactivated is called...
                t.execute(false);
                auto tName=t.taskName;
                schedAtt.subtaskDeactivated(t);
                log.info("Work thread "~Thread.getThis().name~" finished task "~tName);
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                log.error(collectAppender(&e.writeOut));
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(CharSink s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(CharSink s,bool shortVersion){
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
            char[128] buf;
            scope s=new GrowableArray!(char)(buf,0);
            s("Work thread ")(Thread.getThis().name)(" pinned to");
            writeOut(&s.appendArr,exeNode);
            log.info(s.data);
            topo.bindToNode(n);
        }
    }
}

