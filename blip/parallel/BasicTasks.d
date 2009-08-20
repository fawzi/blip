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

size_t defaultFiberSize=1024*1024; // a largish (1MB) stack

class FiberPoolT(int batchSize=16):Pool!(Fiber,batchSize){
    size_t stackSize;
    
    this(size_t stackSize=defaultFiberSize,size_t bufferSpace=8*batchSize,
        size_t maxEl=16*batchSize){
        super(bufferSpace,maxEl);
        this.stackSize=stackSize;
    }
    
    override Fiber clear(Fiber f){
        if (f !is null){
            if (f.stackSize==stackSize){
                f.clear();
                return f;
            }
            delete f;
        }
        return null;
    }
    
    Fiber reset(Fiber f){
        return f;
    }
    
    override Fiber allocateNew(){
        return new Fiber(function void(){},stackSize);
    }
    
    Fiber getObj(void function() f){
        auto res=super.getObj();
        res.reset(f);
        return res;
    }
    Fiber getObj(void delegate() f){
        auto res=super.getObj();
        res.reset(f);
        return res;
    }
}
alias FiberPoolT!() FiberPool;

class TaskPoolT(int batchSize=16):Pool!(Task,batchSize){
    this(size_t bufferSpace=8*batchSize, size_t maxEl=16*batchSize){
        super(bufferSpace,maxEl);
    }
    Task getObj(char[] name, void delegate() taskOp,bool mightSpawn=true){
        auto res=super.getObj();
        res.reset(name,taskOp,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, mightSpawn);
        return res;
    }
    /// constructor with a possibly yieldable call
    Task getObj(char[] name, YieldableCall c,bool mightSpawn=true){
        auto res=super.getObj();
        res.reset(name,c,mightSpawn);
        return res;
    }
    /// constructor (with fiber)
    Task getObj(char[] name,Fiber fiber,bool mightSpawn=true){
        auto res=super.getObj();
        res.reset(name,&res.runFiber,fiber,cast(bool delegate())null,
            cast(TaskI delegate())null, mightSpawn);
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, bool delegate() generator,bool mightSpawn=true){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator,cast(Fiber)null,generator,
            cast(TaskI delegate())null, mightSpawn);
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, TaskI delegate() generator2,bool mightSpawn=true){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator2,cast(Fiber)null,cast(bool delegate())null,
        generator2, mightSpawn);
        return res;
    }
    /// general constructor
    Task getObj(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, bool mightSpawn=true, FiberPool fPool=null){
        auto res=super.getObj();
        res.reset(name,taskOp,fiber,generator,generator2,mightSpawn,fPool);
        return res;
    }
}

alias TaskPoolT!(16) TaskPool;

class SchedulerPools{
    FiberPool fiberPool;
    TaskPool taskPool;
    this(FiberPool fiberPool=null,TaskPool taskPool=null){
        this.fiberPool=fiberPool;
        if (this.fiberPool is null){
            this.fiberPool=new FiberPool(defaultFiberSize);
        }
        this.taskPool=taskPool;
        if (taskPool is null){
            taskPool=new TaskPool();
        }
    }
}

ThreadLocal!(SchedulerPools) _schedulerPools;

static this(){
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
    bool mightYield;
    static YieldableCall opCall(void delegate() dlg,bool mightYield=true,
        FiberPool fiberPool=null){
        YieldableCall res;
        res.dlg=dlg;
        res.fPool=fiberPool;
        res.mightYield=mightYield;
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
    char[] _taskName; /// name of the task
    bool resubmit; /// if the task should be resubmitted
    bool holdSubtasks; /// if subtasks should be kept on hold
    TaskI[] holdedSubtasks; /// the subtasks on hold
    int spawnTasks; /// number of spawn tasks
    int finishedTasks; /// number of finished subtasks
    Mutex taskLock; /// lock to update task numbers and status
    TaskSchedulerI _scheduler; /// scheduer of the current task
    bool _mightSpawn; /// if the task might spawn other subtasks
    bool _mightYield; /// if the task might be yielded
    Semaphore waitSem; /// lock to wait for task end
    LinkedList!(Variant) variants; /// variants to help with full closures and gc
    
    /// clears a task for reuse
    void clear(){
        assert(_status==TaskStatus.Finished || _status==TaskStatus.Building || 
            _status==TaskStatus.NonStarted,"invalid status for clear");
        _level=0;
        _status=TaskStatus.Finished;
        taskOp=null; generator=null; generator2=null;
        if (fiber){
            defaultFiberPool(fPool).giveBack(fiber);
            fiber=null;
        }
        fPool=null;
        onFinish.clear();
        _superTask=null;
        _taskName=null;
        resubmit=false;
        holdSubtasks=false;
        holdedSubtasks=null;
        spawnTasks=0;
        finishedTasks=0;
        _scheduler=null;
        _mightSpawn=false;
        _mightYield=false;
        variants.clear();
    }
    /// it the task might be yielded (i.e. if it is a fiber)
    bool mightYield(){ return _mightYield && (fiber !is null); }
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
    bool mightSpawn() { return _mightSpawn; }
    /// empty constructor, task will need to be reset before using
    this(){}
    /// constructor (with single delegate)
    this(char[] name, void delegate() taskOp,bool mightSpawn=true){
        reset(name,taskOp,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, mightSpawn);
    }
    /// constructor with a possibly yieldable call
    this(char[] name, YieldableCall c,bool mightSpawn=true){
        reset(name,c,mightSpawn);
    }
    void reset(char[] name, YieldableCall c,bool mightSpawn=true){
        if (! c.mightYield){
            reset(name,c.dlg,cast(Fiber)null,cast(bool delegate())null,
                cast(TaskI delegate())null, mightSpawn);
        } else {
            reset(name,c.dlg,cast(Fiber)null,cast(bool delegate())null,
                cast(TaskI delegate())null, mightSpawn, defaultFiberPool(c.fPool));
            this._mightYield=c.mightYield;
        }
    }
    /// constructor (with fiber)
    this(char[] name,Fiber fiber,bool mightSpawn=true){
        reset(name,&runFiber,fiber,cast(bool delegate())null,
            cast(TaskI delegate())null, mightSpawn);
    }
    /// constructor (with generator)
    this(char[] name, bool delegate() generator,bool mightSpawn=true){
        reset(name,&runGenerator,cast(Fiber)null,generator,
            cast(TaskI delegate())null, mightSpawn);
    }
    /// constructor (with generator)
    this(char[] name, TaskI delegate() generator2,bool mightSpawn=true){
        reset(name,&runGenerator2,cast(Fiber)null,cast(bool delegate())null,
        generator2, mightSpawn);
    }
    /// general constructor
    this(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, bool mightSpawn=true, FiberPool fPool=null){
        reset(name,taskOp,fiber,generator,generator2,mightSpawn,fPool);
    }
    void reset(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, bool mightSpawn=true, FiberPool fPool=null){
        assert(taskOp !is null);
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
        this.taskLock=new Mutex();
        this.status=TaskStatus.Building;
        this.spawnTasks=0;
        this.finishedTasks=0;
        this._mightSpawn=mightSpawn;
        this.variants=new LinkedList!(Variant)();
        this._mightYield=fiber !is null;
        this.fPool=fPool;
    }
    /// has value for tasks
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
                fiber=defaultFiberPool(fPool).getObj(taskOp);
                taskOp=&runFiber;
            }
            synchronized(taskLock) {
                assert(status==TaskStatus.NonStarted);
                status=TaskStatus.Started;
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
        synchronized(taskLock){
            if (status==TaskStatus.WaitingEnd && spawnTasks==finishedTasks){
                status=TaskStatus.PostExec;
                callOnFinish=true;
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
            synchronized(taskLock){
                assert(status==TaskStatus.PostExec);
                status=TaskStatus.Finished;
                if (waitSem !is null) waitSem.notify();
            }
        }
        if (superTask !is null){
            superTask.subtaskEnded(this);
        }
    }
    /// called when a subtasks has finished
    void subtaskEnded(TaskI st){
        bool callOnFinish=false;
        synchronized(taskLock){
            ++finishedTasks;
            if (status==TaskStatus.WaitingEnd && spawnTasks==finishedTasks){
                status=TaskStatus.PostExec;
                callOnFinish=true;
            }
        }
        if (callOnFinish){
            finishTask();
        }
    }
    /// called before spawning a new subtask
    void willSpawn(TaskI st){
        synchronized(taskLock){
            ++spawnTasks;
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
    }
    /// runs the generator (can be used as taskOp)
    void runGenerator(){
        assert(generator!is null);
        resubmit=generator();
    }
    /// runs a generator that returns a pointer to a task (can be used as taskOp)
    void runGenerator2(){
        assert(generator2!is null);
        TaskI t=generator2();
        if (t !is null) spawnTask(t);
        resubmit=t !is null;
    }
    /// returns the number of variant
    uint nVariants(){
        return variants.size();
    }
    
    // ------------------------ task setup ops -----------------------
    /// adds an onFinish operation
    Task appendOnFinish(void delegate() onF) {
        assert(status==TaskStatus.Building,"appendOnFinish allowed only during task building"); // change?
        onFinish.append(onF);
        return this;
    }
    /// adds a variant
    Task appendVariant(Variant v) {
        assert(status==TaskStatus.Building,"appendVariant allowed only during task building"); // change?
        variants.append(v);
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
        synchronized(taskLock){ // should not be needed
            holdSubtasks=true;
        }
        return this;
    }
    /// lets the holded tasks run (can be called also when the task is running)
    Task releaseSub(){
        TaskI[] tToRel;
        synchronized(taskLock){ // should not be needed
            holdSubtasks=false;
            tToRel=holdedSubtasks;
            holdedSubtasks=[];
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
        bool lokD=taskLock.tryLock();
        if (lokD) taskLock.unlock();
        s("  taskLock:");
        if (lokD)
            s("locked by others");
        else
            s("unlocked by others");
        s(",").newline;
        s("  mightSpawn:")(mightSpawn);
        return s;
    }
    /// waits for the task to finish
    void wait(){
        if (status!=TaskStatus.Finished && waitSem is null) {
            synchronized(taskLock) {
                 if (status!=TaskStatus.Finished && waitSem is null) {
                     waitSem=new Semaphore();
                 }
            }
        }
        if (status!=TaskStatus.Finished) {
            waitSem.wait();
            assert(status==TaskStatus.Finished,"unexpected status after wait");
            waitSem.notify();
        }
    }
}

/// a task that does nothing
class EmptyTask: Task{
    this(char[] name="EmptyTask", bool mightSpawn=false){
        super(name,&internalExe,mightSpawn);
    }
    override void internalExe(){ }
}

/// root pseudo task
/// is not executed itself, but is the supertask of other tasks
class RootTask: Task{
    Logger log;
    bool warnSpawn;
    this(TaskSchedulerI scheduler, int level=0, char[] name="RootTask", bool warnSpawn=false){
        super(name,&internalExe,true);
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

/// Task generators
class TaskSet:Task{
    long subCost;
    /// constructor with a possibly yieldable call
    this(char[] name, YieldableCall c,bool mightSpawn=true){
        assert(c.mightYield,"TaskSet should generate tasks...");
        super(name,c,mightSpawn);
    }
    this(char[] name, bool delegate() gen) {
        super(name, gen, true);
    }
    this(char[] name, TaskI delegate() gen) {
        super(name, gen, true);
    }
    this(char[] name, Fiber fib) {
        super(name, fib, true);
    }
    
    /// generates a subtasks (returns true if successful), does not resubmit itself
    TaskI generate(){
        TaskI res=null;
        if (status==TaskStatus.NonStarted){
            synchronized(taskLock) {
                assert(status==TaskStatus.NonStarted);
                status=TaskStatus.Started;
            }
        }
        if (status==TaskStatus.Started){
            {
                scope(exit){
                    taskAtt.val=noTask;
                }
                taskAtt.val=this;
                res=internalGen();
            }
        }
        return res;
    }
    /// generate a task and returns it (null if no tasks are left)
    TaskI internalGen(){
        TaskI res=null;
        bool hold=!holdSubtasks;
        if (hold) holdSub();
        int nHolded=holdedSubtasks.length;
        taskOp();
        if (nHolded<holdedSubtasks.length){
            assert(nHolded+1==holdedSubtasks.length,"generated more than one task");
            res=holdedSubtasks[$];
        }
        if (hold) releaseSub();
        if (!resubmit) {
            startWaiting();
        }
        return res;
    }
    // generate nproc subtasks
    override void internalExe(){
        long maxCost=subCost+scheduler.executer.nSimpleTasksWanted();
        do{
            taskOp();
            if (!resubmit) break;
        } while (!scheduler.manyQueued() && subCost<maxCost)
    }
    override void willSpawn(TaskI t){
        long cost=1;
        if (cast(TaskSet)t || t.mightSpawn) cost+=scheduler.executer.nSimpleTasksWanted();
        synchronized(taskLock){
            subCost+=cost;
        }
        super.willSpawn(t);
    }
}
