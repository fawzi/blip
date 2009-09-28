module blip.parallel.BasicTasks;
import blip.parallel.Models;
import tango.core.Thread;
import tango.core.Variant:Variant;
import tango.core.sync.Mutex;
import tango.math.Math;
import tango.io.Stdout;
import tango.util.log.Log;
import tango.util.container.LinkedList;
import tango.io.stream.Format;
import blip.text.Stringify;
import tango.core.sync.Semaphore;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.Models;
import blip.BasicModels;
import blip.container.Pool;
import tango.core.sync.Atomic;
import blip.container.FiberPool;

enum TaskFlags:uint{
    None=0, // no flags
    NoSpawn=1, // the task will not spawn other tasks
    NoYield=2, // the task will not yield
    TaskSet=4, // the task is basically just a collection of other tasks
    Pin=8,    // the task should be pinned (i.e. cannot be stealed)
    HoldTasks=16, // tasks are holded
    FiberPoolTransfer=32, // the fiber pool is transferred to subtasks
    Resubmit=64, // the task should be resubmitted
}

class TaskPoolT(int batchSize=16):Pool!(Task,batchSize){
    this(size_t bufferSpace=8*batchSize, size_t maxEl=16*batchSize){
        super(bufferSpace,maxEl);
    }
    Task getObj(char[] name, void delegate() taskOp,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,taskOp,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
        return res;
    }
    /// constructor with a possibly yieldable call
    Task getObj(char[] name, YieldableCall c){
        auto res=super.getObj();
        res.reset(name,c);
        return res;
    }
    /// constructor (with fiber)
    Task getObj(char[] name,Fiber fiber,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runFiber,fiber,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, bool delegate() generator,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator,cast(Fiber)null,generator,
            cast(TaskI delegate())null, f);
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, TaskI delegate() generator2,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator2,cast(Fiber)null,cast(bool delegate())null,
        generator2, f);
        return res;
    }
    /// general constructor
    Task getObj(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, TaskFlags f=TaskFlags.None, FiberPool fPool=null){
        auto res=super.getObj();
        res.reset(name,taskOp,fiber,generator,generator2,f,fPool);
        return res;
    }
}

alias TaskPoolT!(16) TaskPool;
// to do: this should be solved with a number of pools limited by the number of cpus or even sockets
class SchedulerPools{
    FiberPool fiberPool;
    TaskPool taskPool;
    this(FiberPool fiberPool=null,TaskPool taskPool=null){
        this.fiberPool=fiberPool;
        if (this.fiberPool is null){
            this.fiberPool=new FiberPool(defaultFiberSize);
        }
        this.taskPool=taskPool;
        if (this.taskPool is null){
            this.taskPool=new TaskPool();
        }
    }
}
SchedulerPools __schedulerPools; // to remove
ThreadLocal!(SchedulerPools) _schedulerPools;

static this(){
    __schedulerPools=new SchedulerPools(); // to remove
    _schedulerPools=new ThreadLocal!(SchedulerPools)(null);
}

SchedulerPools defaultSchedulerPools(){
    auto sPool=_schedulerPools.val;
    if (sPool is null){
        synchronized{
            volatile sPool=_schedulerPools.val;
            if (sPool is null){
                sPool=new SchedulerPools();
                _schedulerPools.val=sPool;
            }
        }
    }
    assert(sPool !is null);
    return sPool;
}
FiberPool defaultFiberPool(FiberPool fPool=null){
    if (fPool) return fPool;
    auto sPools=defaultSchedulerPools();
    return sPools.fiberPool;
}

/// a fiber if work manager is parallel, a simple delegate call if not
/// this allows to easily remove the depenedence of fibers in most cases
struct YieldableCall{
    void delegate() dlg;
    FiberPool fPool;
    TaskFlags flags;
    static YieldableCall opCall(void delegate() dlg,TaskFlags f=TaskFlags.None,
        FiberPool fiberPool=null){
        YieldableCall res;
        res.dlg=dlg;
        res.fPool=fiberPool;
        res.flags=f;
        return res;
    }
    /// returns a new fiber that performs the call
    Fiber fiber(){
        return defaultFiberPool(fPool).getObj(this.dlg);
    }
}

/// level of simple tasks, tasks with ths level or higher should not spawn
/// other tasks. Tasks with higher level are tasks (like communication) that
/// should be done as soon as possible, even if overlap with other tasks is
/// then needed
const int SimpleTaskLevel=int.max/2;

Task noTask;

/// thread local data to store current task
ThreadLocal!(TaskI) taskAtt;

static this(){
    noTask=new RootTask(null,0,"noTask",true);
    taskAtt=new ThreadLocal!(TaskI)(noTask);
}

class Task:TaskI{
    int _level; /// priority level of the task, the higher the better
    TaskStatus _status; /// execution status of the task
    
    void delegate() taskOp; /// task to execute
    bool delegate() generator; /// generator to run
    TaskI delegate() generator2; /// generator to run
    
    Fiber fiber; /// fiber to run
    FiberPool fPool; /// if non null allocates a fiber executing taskOp with the given stack (unless Sequential)
    
    LinkedList!(void delegate()) onFinish; /// actions to execute sequentially at the end of the task
    
    TaskI _superTask; /// super task of this task
    char[] _taskName; /// name of the task (might be null, for debugging purposes)

    TaskI[] holdedSubtasks; /// the subtasks on hold (debug, to remove)
    
    TaskFlags flags; /// various flags wrt. the task
    int refCount; /// number of references to this task
    int spawnTasks; /// number of spawn tasks
    int finishedTasks; /// number of finished subtasks
    version(NoTaskLock){ } else {
        Mutex taskLock; /// lock to update task numbers and status (remove and use atomic ops)
    }
    TaskSchedulerI _scheduler; /// scheduer of the current task
    Semaphore waitSem; /// lock to wait for task end

    /// the task should be resubmitted
    bool resubmit(){
        return (flags & TaskFlags.Resubmit)!=0;
    }
    /// ditto
    void resubmit(bool v){
        flags=cast(TaskFlags)((flags & ~TaskFlags.Resubmit)|(v?TaskFlags.Resubmit:0));
    }
    /// if subtasks should be kept on hold
    bool holdSubtasks() {
        return (flags & TaskFlags.HoldTasks)!=0;
    }
    /// ditto
    void holdSubtasks(bool v) {
        flags=cast(TaskFlags)((flags & ~TaskFlags.HoldTasks)|(v?TaskFlags.HoldTasks:0));
    }
    
    /// clears a task for reuse
    void clear(){
        assert(_status==TaskStatus.Finished || _status==TaskStatus.Building || 
            _status==TaskStatus.NonStarted,"invalid status for clear");
        _level=0;
        _status=TaskStatus.Finished;
        taskOp=null; generator=null; generator2=null;
        if (fiber!is null && fPool!is null){
            fPool.giveBack(fiber);
            fiber=null;
        }
        fPool=null;
        onFinish.clear();
        _superTask=null;
        _taskName=null;
        holdedSubtasks=null;
        spawnTasks=0;
        finishedTasks=0;
        refCount=1;
        flags=TaskFlags.None;
        _scheduler=null;
        waitSem=null;
    }
    /// it the task might be yielded (i.e. if it is a fiber)
    bool mightYield(){ return !(flags & TaskFlags.NoYield) && (fiber !is null); }
    /// return the name of this task
    char[] taskName(){ return _taskName; }
    /// returns the the status of the task
    TaskStatus status(){ return _status; }
    /// sets the task status
    void status(TaskStatus s) { assert(cast(int)s>=cast(int)_status); _status=s;}
    /// returns the level of the task
    int level(){ return _level; }
    /// sets the level of the task
    void level(int l){ assert(status==TaskStatus.Building); _level=l; }
    /// return the superTask of this task
    TaskI superTask(){ return _superTask; }
    /// sets the superTask of this task
    void superTask(TaskI task){ assert(status==TaskStatus.Building); _superTask=task; }
    /// return the scheduler of this task
    TaskSchedulerI scheduler(){ return _scheduler; }
    /// sets the scheduler of this task
    void scheduler(TaskSchedulerI sched){ assert(status==TaskStatus.Building); _scheduler=sched; }
    /// it the task might spawn other tasks
    bool mightSpawn() { return !(flags & TaskFlags.NoSpawn); }

    /// efficient allocation constructor (with single delegate)
    static Task opCall(char[] name, void delegate() taskOp,TaskFlags f=TaskFlags.None){
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,taskOp,f);
    }
    /// efficient allocation constructor with a possibly yieldable call
    static Task opCall(char[] name, YieldableCall c){
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,c);
    }
    /// efficient allocation constructor (with fiber)
    static Task opCall(char[] name,Fiber fiber,TaskFlags f=TaskFlags.None){
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,fiber,f);
    }
    /// efficient allocation constructor (with generator)
    static Task opCall(char[] name, bool delegate() generator,TaskFlags f=TaskFlags.None){
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,generator,f);
    }
    /// efficient allocation constructor (with generator)
    static Task opCall(char[] name, TaskI delegate() generator2,TaskFlags f=TaskFlags.None){
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,generator2,f);
    }
    /// efficient allocation general constructor
    static Task opCall(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, TaskFlags f=TaskFlags.None, FiberPool fPool=null)
    {
        auto tPool=defaultSchedulerPools().taskPool;
        return tPool.getObj(name,taskOp,fiber,generator,generator2,f,fPool);
    }

    /// empty constructor, task will need to be reset before using
    this(){}
    /// constructor (with single delegate)
    this(char[] name, void delegate() taskOp,TaskFlags f=TaskFlags.None){
        reset(name,taskOp,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
    }
    /// constructor with a possibly yieldable call
    this(char[] name, YieldableCall c){
        reset(name,c);
    }
    void reset(char[] name, YieldableCall c){
        reset(name,c.dlg,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, c.flags, c.fPool);
    }
    /// constructor (with fiber)
    this(char[] name,Fiber fiber,TaskFlags f=TaskFlags.None){
        reset(name,&runFiber,fiber,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
    }
    /// constructor (with generator)
    this(char[] name, bool delegate() generator,TaskFlags f=TaskFlags.None){
        reset(name,&runGenerator,cast(Fiber)null,generator,
            cast(TaskI delegate())null, f);
    }
    /// constructor (with generator)
    this(char[] name, TaskI delegate() generator2,TaskFlags f=TaskFlags.None){
        reset(name,&runGenerator2,cast(Fiber)null,cast(bool delegate())null,
        generator2, f);
    }
    /// general constructor
    this(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, TaskFlags f=TaskFlags.None, FiberPool fPool=null){
        reset(name,taskOp,fiber,generator,generator2,f,fPool);
    }
    void reset(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, TaskFlags f=TaskFlags.None, FiberPool fPool=null){
        assert(taskOp !is null);
        this._status=TaskStatus.Building;
        this.level=0;
        this._taskName=name;
        this.taskOp=taskOp;
        this.fiber=fiber;
        this.generator=generator;
        this.onFinish=new LinkedList!(void delegate())();
        this._superTask=null;
        this._scheduler=null;
        this.resubmit=false;
        this.holdSubtasks=false;
        this.holdedSubtasks=[];
        version(NoTaskLock){} else {
            this.taskLock=new Mutex();
        }
        this.refCount=1;
        this.status=TaskStatus.Building;
        this.spawnTasks=0;
        this.finishedTasks=0;
        this.flags=f;
        this.fPool=fPool;
    }
    /// hash value for tasks
    uint getHash(){
        return cast(uint)(cast(void*)this);
    }
    /// equality of tasks
    override int opEquals(Object o){ return (o is this); }
    /// executes the actual task (after all the required setup)
    void internalExe(){
        assert(taskOp !is null);
        taskOp();
    }
    /// executes the task (called by the executing thread, performs all setups)
    /// be careful overriding this (probably you should override internalExe)
    void execute(bool sequential=false){
        if (status==TaskStatus.NonStarted){
            if (fiber is null && (! sequential) && (mightSpawn || fPool)) {
                fPool=defaultFiberPool(fPool);
                fiber=fPool.getObj(taskOp);
                taskOp=&runFiber;
            }
            version(NoTaskLock){
                assert(status==TaskStatus.NonStarted);
                status=TaskStatus.Started;
            } else {
                synchronized(taskLock) {
                    assert(status==TaskStatus.NonStarted);
                    status=TaskStatus.Started;
                }
            }
        }
        if (status==TaskStatus.Started){
            {
                scope(exit){
                    taskAtt.val=noTask;
                }
                taskAtt.val=this;
                internalExe();
            }
            if (resubmit) {
                scheduler.addTask(this);
            } else {
                startWaiting();
            }
        } else {
            assert(0,"unexpected status in excute: "~status.stringof);
        }
    }
    /// called when the main task is finished, and should start waiting for
    /// the subtasks..
    void startWaiting(){
        assert(status==TaskStatus.Started);
        status=TaskStatus.WaitingEnd;
        bool callOnFinish=false;
        version(NoTaskLock){
            volatile auto finishTaskAtt=finishTask;
            volatile memoryBarrier!(true,false,false,false)(); // probably excessive
            volatile auto spawnTasksAtt=spawnTasks;
            volatile statusAtt=status;
            if (status==TaskStatus.WaitingEnd){
                if (spawnTasksAtt==finishTaskAtt){
                    if (atomicCAS(status,TaskStatus.PostExec,statusAtt))
                        callOnFinish=true;
                }
            }
        } else {
            synchronized(taskLock){
                if (status==TaskStatus.WaitingEnd && spawnTasks==finishedTasks){
                    status=TaskStatus.PostExec;
                    callOnFinish=true;
                }
            }
        }
        if (callOnFinish){
            finishTask();
        }
    }
    /// called after the task (and all its subtasks) have finished
    /// runs onFinish, and then tells supertask, and remove task from running ones
    void finishTask()
    {
        {
            scope(exit){
                taskAtt.val=noTask;
            }
            taskAtt.val=this;
            assert(status==TaskStatus.PostExec);
            if (onFinish !is null) {
                foreach(t;onFinish){
                    t();
                }
            }
            version(NoTaskLock){
                assert(status==TaskStatus.PostExec);
                status=TaskStatus.Finished;
                volatile auto waitSemAtt=waitSem;
                if (waitSemAtt !is null) waitSemAtt.notify();
            } else {
                synchronized(taskLock){
                    assert(status==TaskStatus.PostExec);
                    status=TaskStatus.Finished;
                    if (waitSem !is null) waitSem.notify();
                }
            }
        }
        if (superTask !is null){
            superTask.subtaskEnded(this);
        }
        volatile auto refCountAtt=refCount;
        if (refCountAtt==1){
            if (this.classinfo == Task.classinfo){
                auto tPool=defaultSchedulerPools().taskPool;
                tPool.giveBack(this); // already returns the fiber
            } else if (fiber !is null && fPool!is null){
                fPool.giveBack(fiber);
                fiber=null;
            }
        }
    }
    /// called when a subtasks has finished
    void subtaskEnded(TaskI st){
        bool callOnFinish=false;
        version(NoTaskLock){
            volatile auto oldTasks=flagAdd(finishedTasks,1);
            volatile memoryBarrier!(true,false,false,false)();// probably excessive
            volatile auto spawnTasksAtt=spawnTasks;
            volatile auto statusAtt=status;
            if (statusAtt==TaskStatus.WaitingEnd && spawnTasksAtt==oldTasks+1){
                if (atomicCAS(statusAtt,TaskStatus.PostExec,statusAtt)){
                    callOnFinish=true;
                }
            }
        } else {
            synchronized(taskLock){
                ++finishedTasks;
                if (status==TaskStatus.WaitingEnd && spawnTasks==finishedTasks){
                    status=TaskStatus.PostExec;
                    callOnFinish=true;
                }
            }
        }
        if (callOnFinish){
            finishTask();
        }
    }
    /// called before spawning a new subtask
    void willSpawn(TaskI st){
        version(NoTaskLock){
            flagAdd(spawnTasks,1); // probably atomicAdd would be sufficient...
        } else {
            synchronized(taskLock){
                ++spawnTasks;
            }
        }
    }
    /// operation that spawn the given task as subtask of this one
    void spawnTask(TaskI task){
        assert(mightSpawn,"task '"~taskName~"' tried to spawn '"~task.taskName~"' and has mightSpawn false");
        assert(task.status==TaskStatus.Building,"spawnTask argument should have building status");
        if (task.superTask is null) task.superTask=this;
        assert(task.superTask is this,"task '"~taskName~"' tried to spawn '"~task.taskName~"' that has different superTask");
        if (task.scheduler is null) task.scheduler=scheduler;
        assert(task.scheduler is scheduler,"task '"~taskName~"' tried to spawn '"~task.taskName~"' that has different scheduler");
        if (task.mightSpawn){
            task.level=task.level+level+1;
        } else {
            task.level=task.level+SimpleTaskLevel;
        }
        task.retain;
        if ((flags & TaskFlags.FiberPoolTransfer)!=0 && fPool !is null && 
            task.fiberPool(true) is null){
            task.setFiberPool(fPool);
        }
        task.status=TaskStatus.NonStarted;
        willSpawn(task);
        if (holdSubtasks){
            holdedSubtasks~=task;
        } else {
            scheduler.addTask(task);
        }
    }
    /// runs the fiber (can be used as taskOp)
    void runFiber(){
        assert(fiber !is null);
        if (fiber.state==Fiber.State.TERM){
            resubmit=false;
            return;
        }
        fiber.call;
        resubmit=(fiber.state!=Fiber.State.TERM);
        if (resubmit && (flags & TaskFlags.TaskSet) && !scheduler.manyQueued()
            && scheduler.executer.nSimpleTasksWanted()>1)
        {
            // to be smarter should store the cost and update it in willSpawn
            fiber.call;
            resubmit=(fiber.state!=Fiber.State.TERM);
        }
    }
    /// runs the generator (can be used as taskOp)
    void runGenerator(){
        assert(generator!is null);
        resubmit=generator();
        if (resubmit && !scheduler.manyQueued()
            && scheduler.executer.nSimpleTasksWanted()>1) {
                // to be smarter should store the cost and update it in willSpawn
                resubmit=generator();
        }
        
    }
    /// runs a generator that returns a pointer to a task (can be used as taskOp)
    void runGenerator2(){
        assert(generator2!is null);
        long subCost=0,maxCost=scheduler.executer.nSimpleTasksWanted();
        do {
            TaskI t=generator2();
            resubmit=t !is null;
            if (resubmit) {
                if (t.mightSpawn) {
                    subCost+=maxCost;
                    if (maxCost>1) subCost-=1;
                } else {
                    subCost+=1;
                }
                spawnTask(t.autorelease);
            }
        } while (!scheduler.manyQueued() && subCost<maxCost)
    }
    
    // ------------------------ task setup ops -----------------------
    /// adds an onFinish operation
    Task appendOnFinish(void delegate() onF) {
        assert(status==TaskStatus.Building,"appendOnFinish allowed only during task building"); // change?
        onFinish.append(onF);
        return this;
    }
    /// changes the level of the task (before submittal)
    Task changeLevel(int dl){
        assert(status==TaskStatus.Building,"changeLevel allowed only during task building");
        level=level+dl;
        return this;
    }
    /// holds all the tasks (can be called also when the task is running)
    Task holdSub(){
        version(NoTaskLock){
            holdSubtasks=true;
        } else {
            synchronized(taskLock){ // should not be needed
                holdSubtasks=true;
            }
        }
        return this;
    }
    /// lets the holded tasks run (can be called also when the task is running)
    Task releaseSub(){
        TaskI[] tToRel;
        version(NoTaskLock){
            holdSubtasks=false;
            tToRel=holdedSubtasks;
            holdedSubtasks=[];
        } else {
            synchronized(taskLock){ // should not be needed
                holdSubtasks=false;
                tToRel=holdedSubtasks;
                holdedSubtasks=[];
            }
        }
        foreach(t;tToRel){
            scheduler.addTask(t);
        }
        return this;
    }
    /// sets the fiber pool used
    Task setFiberPool(FiberPool fPool){
        this.fPool=fPool;
        return this;
    }
    /// returns the fiber pool used
    FiberPool fiberPool(bool canBeNull=false){
        if (canBeNull)
            return fPool;
        else
            return defaultFiberPool(fPool);
    }
    /// submits this task (with the given supertask, or with the actual task as supertask)
    Task submit(TaskI superTask=null){
        if (superTask !is null){
            assert(this.superTask is null || this.superTask is superTask,"superTask was already set");
            this.superTask=superTask;
        }
        if (this.superTask is null){
            if (scheduler !is null){
                this.superTask=scheduler.rootTask;
            } else {
                this.superTask=taskAtt.val;
            }
        }
        this.superTask.spawnTask(this);
        return this;
    }
    /// submits the current task and yields the current one
    /// needs a Fiber or Yieldable task
    Task submitYield(TaskI superTask=null){
        submit(superTask);
        auto tAtt=taskAtt.val;
        if (tAtt.mightYield)
            scheduler.yield();
        else if ((cast(RootTask)tAtt)is null){
            throw new ParaException(taskName
                ~" submitYield called with non yieldable executing task ("~tAtt.taskName~")",
                __FILE__,__LINE__); // allow?
        }
        return this;
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    FormatOutput!(char) desc(FormatOutput!(char)s){
        return desc(s,false);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    FormatOutput!(char) desc(FormatOutput!(char)s,bool shortVersion){
        if (this is null){
            s("<Task *NULL*>").newline;
        } else {
            s("<")(this.classinfo.name).format("@{} '{}' status:",cast(void*)this,taskName);
            s(status.stringof);
            if (shortVersion) {
                s(" >");
                return s;
            }
            s.newline;
            fieldsDesc(s);
            s(" >").newline;
        }
        return s;
    }
    /// prints the fields (superclasses can override this an call it through super)
    FormatOutput!(char) fieldsDesc(FormatOutput!(char)s){
        s("  level=")(level)(",").newline;
        s("  taskOp:");
        if (taskOp is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  fiber:");
        if (fiber is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  generator:");
        if (generator is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  onFinish:[");
        bool atStart=true;
        foreach (t;onFinish){
            if (!atStart) s(", ");
            atStart=true;
            if (t is null)
                s("*NULL*");
            else
                s("associated");
        }
        s("],").newline;
        writeDesc(s("  superTask="),superTask,true)(",").newline;
        s("  resubmit:")(resubmit)(",").newline;
        s("  holdSubtasks:")(holdSubtasks)(",").newline;
        s("  holdedSubtasks:")(holdedSubtasks)(",").newline;
        s("  spawnTasks:")(spawnTasks)(",").newline;
        s("  finishedTasks:")(finishedTasks)(",").newline;
        writeDesc(s("  scheduler:"),scheduler,true)(",").newline;
        version(NoTaskLock){} else {
            bool lokD=taskLock.tryLock();
            if (lokD) taskLock.unlock();
            s("  taskLock:");
            if (lokD)
                s("locked by others");
            else
                s("unlocked by others");
            s(",").newline;
        }
        s("  mightSpawn:")(mightSpawn);
        return s;
    }
    /// waits for the task to finish
    void wait(){
        if (status!=TaskStatus.Finished && waitSem is null) {
            version(NoTaskLock){
                volatile auto statusAtt=statusAtt;
                if (statusAtt!=TaskStatus.Finished){
                    if (waitSem is null){
                        auto waitSemNew=new Semaphore();
                        if (!atomicCAS(waitSem,waitSemNew,null)){
                            delete waitSemNew;
                        }
                    }
                }
            } else {
                synchronized(taskLock) {
                     if (status!=TaskStatus.Finished && waitSem is null) {
                         waitSem=new Semaphore();
                     }
                }
            }
        }
        if (status!=TaskStatus.Finished) {
            waitSem.wait();
            assert(status==TaskStatus.Finished,"unexpected status after wait");
            waitSem.notify();
        }
    }
    
    typeof(this) autorelease(){
        assert(refCount>0,"invalid refCount in autorelease");
        auto oldRefC=atomicAdd(refCount,-1);
        return this;
    }
    void release(){
        assert(refCount>0,"invalid refCount in release");
        auto oldRefC=atomicAdd(refCount,-1);
        /+if (oldRefC==0){
            // does nothing (leave the work to the gc, as it might be too late to avoid collection)
        }+/
    }
    typeof(this) retain(){
        assert(refCount>=0,"invalid refCount in retain");
        auto oldRefC=atomicAdd(refCount,1);
        return this;
    }
}

/// a task that does nothing
class EmptyTask: Task{
    this(char[] name="EmptyTask", TaskFlags f=TaskFlags.None){
        super(name,&internalExe,f);
    }
    override void internalExe(){ }
}

/// root pseudo task
/// is not executed itself, but is the supertask of other tasks
class RootTask: Task{
    Logger log;
    bool warnSpawn;
    this(TaskSchedulerI scheduler, int level=0, char[] name="RootTask", bool warnSpawn=false){
        super(name,&internalExe,TaskFlags.None);
        this.scheduler=scheduler;
        this.level=level;
        this.status=TaskStatus.Started;
        log=Log.lookup("blip.parallel."~name);
        this.warnSpawn=warnSpawn;
    }
    override void internalExe(){
        log.error("root task '"~taskName~"' should not be executed");
        assert(0,"root task '"~taskName~"' should not be executed");
    }
    override void willSpawn(TaskI t){
        if (warnSpawn)
            log.warn("root task '"~taskName~"' spawned task "~t.taskName);
        super.willSpawn(t);
    }
}

