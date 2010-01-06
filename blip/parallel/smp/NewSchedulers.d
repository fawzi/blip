module blip.parallel.smp.NewSchedulers;
import blip.t.core.Thread;
import blip.t.core.Variant:Variant;
import blip.t.core.sync.Mutex;
import blip.t.core.sync.Semaphore;
import blip.t.math.Math;
import blip.t.util.log.Log;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.smp.PriQueue;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.Numa;
import blip.BasicModels;
import tango.math.random.Random;
import blip.container.Deque;
import blip.container.Cache;
import blip.container.BitVector;
import blip.container.AtomicSLink;
import blip.io.Console;

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
        pQLevelPool=new Cached!(PriQueue!(TaskI).PriQPool)(delegate PriQueue!(TaskI).PriQPool(){ return new PriQueue!(TaskI).PriQPool(); });
    }
    
    /// random source for scheduling
    RandomSync rand;
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
    /// creates a new PriQScheduler
    this(char[] name,MultiSched superScheduler,char[] loggerPath="blip.parallel.smp.queue",int level=0){
        this.name=name;
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        queue=new PriQueue!(TaskI)(pQLevelPool(_nnCache));
        this.rand=new RandomSync();
        this.inSuperSched=0;
        log=Log.lookup(loggerPath);
        _rootTask=new RootTask(this,0,name~"RootTask");
        runLevel=SchedulerRunLevel.Running;
        raiseRunlevel(superScheduler.runLevel);
    }
    void reset(char[] name,MultiSched superScheduler){
        this.name=name;
        this.superScheduler=superScheduler;
        this._nnCache=superScheduler.nnCache();
        queue.reset();
        stealLevel=int.max;
        inSuperSched=0;
        runLevel=SchedulerRunLevel.Running;
        raiseRunlevel(superScheduler.runLevel);
    }
    void addTask0(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        log.info("task "~t.taskName~" will be added to queue "~name);
        if (shouldAddTask(t)){
            synchronized(queue.queueLock){
                queue.insert(t.level,t);
                if (inSuperSched==0) {
                    inSuperSched=1;
                    if (superScheduler) superScheduler.addSched(this);
                }
            }
        }
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        log.info("task "~t.taskName~" might be added to queue "~name);
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
                synchronized(this){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        queue.nEntries==0 && activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
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
            if (superScheduler){
                superScheduler.addSched(this);
            }
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
                if (superScheduler){
                    superScheduler.addSched(this);
                }
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
                synchronized(this){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        queue.nEntries==0 && activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                return false;
            }
        }
        synchronized(queue.queueLock){
            if (queue.popBack(t,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
                t.scheduler=targetScheduler;
                targetScheduler.addTask0(t);
                while (queue.nEntries>0 && rand.uniform!(bool)()){
                    TaskI t2;
                    if (queue.popBack(t2,delegate bool(TaskI task){ return task.stealLevel>=stealLevel; })){
                        t2.scheduler=t.scheduler;
                        t.scheduler.addTask0(t2);
                    }
                }
                return true;
            }
            return false;
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
        synchronized(this){
            if (activeTasks[st]>1){
                activeTasks[st]-=1;
            } else {
                activeTasks.remove(st);
                if (runLevel>=SchedulerRunLevel.StopNoTasks && queue.nEntries==0){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
            }
        }
    }
    /// returns wether the current task should be added
    bool shouldAddTask(TaskI t){
        if (superScheduler !is null){
            return superScheduler.starvationManager.redirectedTask(t,this);
        }
        return true;
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
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level){
        synchronized(this){
            if (runLevel < cast(int)level){
                runLevel=level;
                if (runLevel==SchedulerRunLevel.Stopped){
                    queue.stop();
                    onStop();
                }
            }
        }
    }
    /// called when the queue stops
    void onStop(){
        if (superScheduler !is null){
            superScheduler.queueStopped(this);
        }
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
            res=null;
            return res;
        });
    }
    /// random source for scheduling
    RandomSync rand;
    /// queue for tasks to execute
    Deque!(PriQScheduler) queue;
    /// queueLock
    Mutex queueLock;
    /// semaphore for non busy waiting
    Semaphore zeroSem;
    /// if someome is waiting on the semaphore... (not all semaphores give that info)
    bool zeroLock;
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
    /// creates a new PriQScheduler
    this(char[] name,NumaNode numaNode,
        StarvationManager starvationManager,
        char[] loggerPath="blip.parallel.smp.queue")
    {
        this.name=name;
        this.starvationManager=starvationManager;
        this.numaNode=numaNode;
        assert(starvationManager!is null,"starvationManager must be valid");
        _nnCache=starvationManager.nnCacheForNode(numaNode);
        queue=new Deque!(PriQScheduler)();
        this.rand=new RandomSync();
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
        log.info("task "~t.taskName~" will be added to a newly created queue in "~name);
        auto newS=popFrom(*pQSchedPool(_nnCache));
        if (newS is null){
            newS=new PriQScheduler(t.taskName,this);
        } else {
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
        log.info("task "~t.taskName~" might be added to a newly created queue in "~name);
        if (shouldAddTask(t)){
            addTask0(t);
        }
    }
    /// returns nextTask if available, null if not
    TaskI nextTaskImmediate(){
        TaskI t;
        PriQScheduler sched;
        synchronized(queueLock){
            while (queue.length>0 && t is null){
                if (runLevel==SchedulerRunLevel.Stopped) return null;
                sched=queue.popFront();
                t=sched.nextTaskImmediate();
            }
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
                synchronized(this){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        queue.length==0 && activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
            }
            if (runLevel==SchedulerRunLevel.Stopped){
                return false;
            }
        }
        size_t didSteal=0;
        synchronized(queueLock){
            foreach (sched;queue){
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
        if (t !is null){
            subtaskActivated(t);
        }
        return t;
    }
    /// queue stop
    void queueStopped(PriQScheduler q){
        insertAt(*pQSchedPool(_nnCache),q);
    }
    void addSched(PriQScheduler sched){
        synchronized(queueLock){
            queue.append(sched);
            if (queue.length>0 && zeroLock){
                zeroLock=false;
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
                    synchronized(this){
                        if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                            raiseRunlevel(SchedulerRunLevel.Stopped);
                        } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                            queue.length==0 && activeTasks.length==0){
                            raiseRunlevel(SchedulerRunLevel.Stopped);
                        }
                    }
                }
                synchronized(queueLock){
                    if (queue.length>0){
                        auto sched=queue.popFront();
                        t=sched.nextTaskImmediate();
                        if (t is null) continue;
                    }
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
                // remove the trySteal? imperfect redirection just leads to inefficency, not errors
                // and the trySteal just
                t=starvationManager.trySteal(this,acceptLevel);
            }
            if (t is null) {
                zeroLock=true;
                zeroSem.wait();
                // starvationManager.rmStarvingSched(this);
                synchronized(queueLock){
                    if (queue.length>0 || runLevel==SchedulerRunLevel.Stopped)
                        zeroSem.notify();
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
    /// locks the scheduler (to perform task reorganization)
    /// if you call this then toString is threadsafe
    void lockSched(){
        queueLock.lock();
    }
    /// unlocks the scheduler
    void unlockSched(){
        queueLock.unlock();
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
        synchronized(this){
            if (activeTasks[st]>1){
                activeTasks[st]-=1;
            } else {
                activeTasks.remove(st);
                if (runLevel>=SchedulerRunLevel.StopNoTasks && queue.length==0){
                    if (runLevel==SchedulerRunLevel.StopNoQueuedTasks){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    } else if (runLevel==SchedulerRunLevel.StopNoTasks &&
                        activeTasks.length==0){
                        raiseRunlevel(SchedulerRunLevel.Stopped);
                    }
                }
            }
            if (!(st.scheduler is this)){
                st.scheduler.subtaskDeactivated(st);
            }
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
        synchronized(this){
            assert(cast(int)runLevel <= cast(int)level,"runLevel can be only increased");
            if (runLevel < cast(int)level){
                runLevel=level;
                if (runLevel==SchedulerRunLevel.Stopped){
                    if (zeroLock){
                        zeroLock=false;
                        zeroSem.notify();
                    }
                    onStop();
                }
            }
        }
    }
    /// actions executed on stop (tells the starvationManager)
    void onStop(){
        starvationManager.schedulerStopped(this);
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.length>15; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return 4; }
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
    RandomSync rand; /// random source for scheduling
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
        this.rand=new RandomSync();
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
        assert(numa2pos(sched.numaNode)>0 && numa2pos(sched.numaNode)<scheds.length,"pos out of range");
        assert(scheds[numa2pos(sched.numaNode)] is sched,"mismatched sched.pos");
        addStarvingSched(sched.numaNode);
    }
    /// removes a scheduler, regeneration of starved masks could be more efficient
    void rmStarvingSched(MultiSched sched){
        assert(numa2pos(sched.numaNode)>0 && numa2pos(sched.numaNode)<scheds.length,"pos out of range");
        auto pos=numa2pos(sched.numaNode);
        assert(scheds[pos] is sched,"mismatched sched.pos");
        synchronized(this){
            if (starved[schedLevel][pos]){
                starved[schedLevel][pos]=false;
                foreach(indx; starved[schedLevel].loopTrue){
                    NumaNode posAtt;
                    posAtt.level=1;
                    posAtt.pos=indx;
                    for (size_t i=schedLevel+1;i<starved.length;++i){
                        posAtt=topo.superNode(posAtt);
                        foreach(subN;subnodesWithLevel(1,cast(Topology!(NumaNode))topo,posAtt)){
                            starved[i][subN.pos]=true;
                        }
                    }
                }
            }
        }
    }
    /// tries to steal a task, might redistribute the tasks
    TaskI trySteal(MultiSched el,int stealLevel){
        auto superN=el.numaNode;
        NumaNode oldSuper=superN;
        auto maxLevel=max(stealLevel,topo.maxLevel);
        while (superN.level<maxLevel){
            superN=topo.superNode(superN);
            foreach(subN;randomSubnodesWithLevel(1,cast(Topology!(NumaNode))topo,superN,oldSuper)){
                auto subP=numa2pos(subN);
                if (scheds[subP].stealTask(superN.level,el)){
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
            synchronized(this){
                if (starved[sLevel][pos]){
                    if (starved[0][pos]){
                        rmStarvingSched(sched);
                        return false;
                    }
                    auto superN=sched.numaNode;
                    NumaNode oldSuper=superN;
                    while (superN.level<sLevel){
                        superN=topo.superNode(superN);
                        foreach(subN;randomSubnodesWithLevel(schedLevel,cast(Topology!(NumaNode))topo,superN,oldSuper)){
                            auto pos2=numa2pos(subN);
                            if (starved[schedLevel][pos2]){
                                addIfNonExistent(pos2);
                                t.scheduler=scheds[pos2];
                                rmStarvingSched(scheds[pos2]);
                                scheds[pos2].addTask0(t);
                                return true;
                            }
                        }
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
        synchronized(this){
            foreach(p;starved[schedLevel].loopTrue){
                addIfNonExistent(p);
                t.scheduler=scheds[p];
                scheds[p].addTask0(t);
                rmStarvingSched(scheds[p]);
                return;
            }
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
        synchronized(this){
            assert(cast(int)runLevel <= cast(int)level,"runLevel can be only increased");
            if (runLevel < cast(int)level){
                runLevel=level;
                foreach(sched;scheds){
                    sched.raiseRunlevel(runLevel);
                }
                if (runLevel==SchedulerRunLevel.Stopped) onStop();
            }
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
        log=_scheduler.starvationManager.execLogger;
        worker=new Thread(&(this.workThreadJob),16*8192);
        worker.isDaemon=true;
        worker.name=name;
        worker.start();
    }
    /// the job of the worker threads
    void workThreadJob(){
        log.info("Work thread "~Thread.getThis().name~" started");
        pin(_scheduler.starvationManager.pinLevel);
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                log.info("Work thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) return;
                t.execute(false);
                scheduler.subtaskDeactivated(t);
                log.info("Work thread "~Thread.getThis().name~" finished task "~t.taskName);
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                e.writeOut(sout.call);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
        log.info("Work thread "~Thread.getThis().name~" stopped");
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
            scope s=new GrowableArray!(char)(buf);
            s("Work thread ")(Thread.getThis().name)(" pinned to");
            writeOut(&s.appendArr,exeNode);
            log.info(s.data);
            topo.bindToNode(n);
        }
    }
}

