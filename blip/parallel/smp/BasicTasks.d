/// Tasks represent the basic parallelization block at smp level.
/// All the main Task types are described here
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
module blip.parallel.smp.BasicTasks;
import blip.parallel.smp.SmpModels;
import blip.core.Thread;
import blip.core.Variant:Variant;
import blip.core.sync.Mutex;
import blip.math.Math;
import blip.util.TangoLog;
import blip.util.TangoConvert;
import blip.stdc.string;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.core.sync.Semaphore;
import blip.util.TemplateFu:ctfe_i2a;
import blip.BasicModels;
import blip.container.Pool;
import blip.sync.Atomic;
import blip.container.FiberPool;
import blip.container.Deque;
import tango.core.Memory:GC;
import tango.util.container.LinkedList;
import blip.core.BitManip;
debug(TrackTasks){
    version=ImportConsole;
}
debug(TrackFibers){
    version=ImportConsole;
}
debug(TrackDelayFlags){
    version=ImportConsole;
}
version(ImportConsole) import blip.io.Console;

enum TaskFlags:uint{
    None=0,         /// no flags
    NoSpawn=1,      /// the task will not spawn other tasks
    NoYield=1<<1,   /// the task will not yield
    TaskSet=1<<2,   /// the task is basically just a collection of other tasks
    Pin=1<<3,       /// the task should be pinned (i.e. cannot be stealed)
    HoldTasks=1<<4, /// tasks are holded
    FiberPoolTransfer=1<<5,      /// the fiber pool is transferred to subtasks
    Resubmit=1<<6,               /// the task should be resubmitted
    ThreadPinned=1<<7,           /// the task should stay pinned to the same thread
    WaitingSubtasks=1<<10,       /// the task is waiting for subtasks to end
    ImmediateSyncSubtasks=1<<11, /// subtasks submitted with spawnTaskSync are executed immediately if possible
}

class TaskPoolT(int batchSize=16):Pool!(Task,batchSize){
    this(size_t bufferSpace=8*batchSize, size_t maxEl=16*batchSize){
        super(null,bufferSpace,maxEl);
    }
    Task getObj(char[] name, void delegate() taskOp,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,taskOp,cast(Fiber)null,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
        res.tPool=this;
        return res;
    }
    /// constructor with a possibly yieldable call
    Task getObj(char[] name, YieldableCall c){
        auto res=super.getObj();
        res.reset(name,c);
        res.tPool=this;
        return res;
    }
    /// constructor (with fiber)
    Task getObj(char[] name,Fiber fiber,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runFiber,fiber,cast(bool delegate())null,
            cast(TaskI delegate())null, f);
        res.tPool=this;
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, bool delegate() generator,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator,cast(Fiber)null,generator,
            cast(TaskI delegate())null, f);
        res.tPool=this;
        return res;
    }
    /// constructor (with generator)
    Task getObj(char[] name, TaskI delegate() generator2,TaskFlags f=TaskFlags.None){
        auto res=super.getObj();
        res.reset(name,&res.runGenerator2,cast(Fiber)null,cast(bool delegate())null,
        generator2, f);
        res.tPool=this;
        return res;
    }
    /// general constructor
    Task getObj(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator,TaskI delegate() generator2, TaskFlags f=TaskFlags.None, FiberPool fPool=null){
        auto res=super.getObj();
        res.reset(name,taskOp,fiber,generator,generator2,f,fPool);
        res.tPool=this;
        return res;
    }
    
    override void giveBack(Task obj){
        if (obj.status!=TaskStatus.Finished && obj.status>=TaskStatus.Started){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("unexpected status ")(obj.status)(" in given back task ")(obj)("\n");
            }),__FILE__,__LINE__);
        }
        super.giveBack(obj);
    }
}

alias TaskPoolT!(16) TaskPool;
// to do: this should be migrate to a blip.container.Cache solution...
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
        auto fib=defaultFiberPool(fPool).getObj(this.dlg); // should track this???
        return fib;
    }
}

/// level of simple tasks, tasks with ths level or higher should not spawn
/// other tasks. Tasks with higher level are tasks (like communication) that
/// should be done as soon as possible, even if overlap with other tasks is
/// then needed
const int SimpleTaskLevel=int.max/2;

/// no task is executing (just a way to get an error when spawning)
TaskI noTask;

/// thread local data to store current task
ThreadLocal!(TaskI) taskAtt;

static this(){
    noTask=new RootTask(null,0,"noTask",true);
    taskAtt=new ThreadLocal!(TaskI)(noTask);
}

class Task:TaskI{
    int _level; /// priority level of the task, the higher the better
    int _stealLevel; /// maximum steal level of the task (0 thread, 1 core, 2 numa node/socket), default fully stealable
    TaskStatus _status; /// execution status of the task
    
    void delegate() taskOp; /// task to execute
    bool delegate() generator; /// generator to run
    TaskI delegate() generator2; /// generator to run
    
    Fiber fiber; /// fiber to run
    FiberPool fPool; /// if non null allocates a fiber executing taskOp with the given stack (unless Sequential)
    TaskPool tPool; /// pool for the task (used just to give this back to the correct pool)
    
    LinkedList!(void delegate()) onFinish; /// actions to execute sequentially at the end of the task
    void delegate() onFinish0;// placeholder to have onFinish tasks without allocation
    void delegate() onFinish1;// placeholder to have onFinish tasks without allocation
    
    TaskI _superTask; /// super task of this task
    char[] _taskName; /// name of the task (might be null, for debugging purposes)

    TaskI[] holdedSubtasks; /// the subtasks on hold (debug, to remove)
    
    TaskFlags flags; /// various flags wrt. the task
    int refCount; /// number of references to this task
    int spawnTasks; /// number of spawn tasks executing at the moment
    version(NoTaskLock){ } else {
        Mutex taskLock; /// lock to update task numbers and status (remove and use atomic ops)
    }
    TaskSchedulerI _scheduler; /// scheduler of the current task
    Semaphore waitSem; /// lock to wait for task end
    uint delayFlags=1; /// the top bit set represents the current delayLevel, single bits pairs are the state of the various levels
    enum DelayStat{
        NormalRun=0,
        WantSuspend=1,
        SuspendStart=2,
        Suspended=3,
    }
    /// yields the current task (which must be yieldable)
    static bool yield(){
        auto tAtt=taskAtt.val;
        if (tAtt is null || !tAtt.mightYield()){
            return false;
        }
        tAtt.scheduler.yield();
        return true;
    }
    /// might Yield the current task (which must be yieldable)
    /// root tasks are ignored (and no yielding is performed) to make the use of maybeYield simpler.
    /// should ignore all non yieldable tasks???
    static void maybeYield(){
        auto tAtt=taskAtt.val;
        if (tAtt is null || !tAtt.mightYield()){
            if (tAtt !is null || cast(RootTask)tAtt !is null) return;
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("asked to yield task ")(tAtt)(" which cannot be yielded");
            }),__FILE__,__LINE__);
        }
        tAtt.scheduler.maybeYield();
    }
    /// returns the last flags of the delayFlags
    static int lastDelayFlags(int flags){
        int level=bsr(flags);
        assert((level&1)==0);
        if (level>0){
            return (0x3 &(flags>> (level-2)));
        }
        return 0; // change?
    }
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
        _stealLevel=int.max;
        _status=TaskStatus.Finished;
        taskOp=null; generator=null; generator2=null;
        if (fiber!is null && fPool!is null){
            fPool.giveBack(fiber);
            fiber=null;
        }
        fPool=null;
        onFinish0=null;
        onFinish1=null;
        if(onFinish!is null)
            onFinish.clear();
        _superTask=null;
        _taskName=null;
        holdedSubtasks=null;
        spawnTasks=0;
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
    /// returns the steal level of the task
    int stealLevel(){ return _stealLevel; }
    /// sets the steal level of the task
    void stealLevel(int l){ assert(status==TaskStatus.Building); _stealLevel=l; }
    /// return the superTask of this task
    TaskI superTask(){ return _superTask; }
    /// sets the superTask of this task
    void superTask(TaskI task){ assert(status==TaskStatus.Building,"unexpected status when setting superTask:"~to!(char[])(status)); _superTask=task; }
    /// return the scheduler of this task
    TaskSchedulerI scheduler(){ return _scheduler; }
    /// sets the scheduler of this task
    void scheduler(TaskSchedulerI sched){ _scheduler=sched; }
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
        this._stealLevel=int.max;
        this._taskName=name;
        this.taskOp=taskOp;
        this.fiber=fiber;
        this.generator=generator;
        this.onFinish=null;
        this._superTask=null;
        this._scheduler=null;
        this.resubmit=false;
        this.delayFlags=1;
        this.holdSubtasks=false;
        this.holdedSubtasks=[];
        version(NoTaskLock){} else {
            this.taskLock=new Mutex();
        }
        this.refCount=1;
        this.status=TaskStatus.Building;
        this.spawnTasks=0;
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
        if (delayFlags==1){ // not in some delay level
            taskOp();
        } else {
            assert(fiber!is null);
            synchronized(taskLock) {
                auto delayLevel=bsr(delayFlags);
                assert((delayLevel&1)==0);
                auto endFlags=(delayFlags>>(delayLevel-2));
                auto lastLevel=(endFlags&0x3);
                debug(TrackDelayFlags){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("preExe, flags:")(delayFlags,"x")("\n");
                    });
                }
                switch(lastLevel){
                    case DelayStat.NormalRun: assert(0,"invalid stat in exe DelayStat.NormalRun");
                    case DelayStat.WantSuspend: assert(0,"invalid stat in exe DelayStat.WantSuspend");
                    case DelayStat.SuspendStart: assert(0,"invalid stat in exe DelayStat.SuspendStart");
                    case DelayStat.Suspended:
                        break;
                    default: assert(0);
                }
                delayFlags=(delayFlags^(endFlags^1)<<(delayLevel-2)); // reduce level by one
                assert(bsr(delayFlags)+2==delayLevel);
            }
            fiber.call();
        }
    }
    /// executes the task (called by the executing thread, performs all setups)
    /// be careful overriding this (probably you should override internalExe)
    void execute(bool sequential=false){
        if (status==TaskStatus.NonStarted){
            if (fiber is null && (! sequential) && (mightSpawn || fPool)) {
                fPool=defaultFiberPool(fPool);
                fiber=fPool.getObj(taskOp);
                debug(TrackFibers){
                    sinkTogether(localLog,delegate void(CharSink s){
                        dumper(s)("task ")(this)(" is using Fiber@")(cast(void*)fiber)("\n");
                    });
                }
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
            bool resub=resubmit;
            int delayLevel;
            synchronized(taskLock){
                delayLevel=bsr(delayFlags);
                assert((delayLevel&1)==0);
                if (delayLevel>0){
                    auto endFlags=(delayFlags>>(delayLevel-2));
                    debug(TrackDelayFlags){
                        sinkTogether(sout,delegate void(CharSink s){
                            dumper(s)("PostExe, flags:")(delayFlags,"x")("\n");
                        });
                    }
                    switch(0x3 & endFlags){
                        case DelayStat.NormalRun: assert(0,"invalid stat in post exe DelayStat.NormalRun");
                        case DelayStat.WantSuspend: assert(0,"invalid stat in post exe DelayStat.WantSuspend");
                        case DelayStat.SuspendStart:
                            resub=false;
                            static assert(DelayStat.Suspended==3);
                            delayFlags |= (DelayStat.Suspended<<(delayLevel-2));
                            assert(lastDelayFlags(delayFlags)==DelayStat.Suspended);
                            break;
                        case DelayStat.Suspended:
                            resub=true;
                            break;
                        default: assert(0);
                    }
                }
            }
            if (resub) {
                volatile auto sched=scheduler;
                sched.addTask(this);
            } else if(delayLevel==0){
                startWaiting();
            }
        } else {
            assert(0,"unexpected status in excute: "~taskStatusStr(status));
        }
    }
    /// called when the main task is finished, and should start waiting for
    /// the subtasks..
    void startWaiting(){
        assert(status==TaskStatus.Started);
        bool callOnFinish=false;
        version(NoTaskLock){
            if (0==flagGet(spawnTasks)){
                if (atomicCASB(status,TaskStatus.PostExec,TaskStatus.WaitingEnd)){
                    callOnFinish=true;
                }
            }
        } else {
            // tries to already give back the fiber if possible (agressively reuse fibers, as they are expensive)
            if (fiber !is null && fPool!is null){
                fPool.giveBack(fiber);
                fiber=null;
            }
            synchronized(taskLock){
                status=TaskStatus.WaitingEnd;
                if (spawnTasks==0){
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
            if (onFinish0 !is null){
                onFinish0();
                if (onFinish1 !is null){
                    onFinish1();
                    if (onFinish !is null) {
                        foreach(t;onFinish){
                            t();
                        }
                    }
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
        release();
    }
    /// tries to give back the task for later reuse
    void release(){
        auto oldRefC=atomicAdd(refCount,-1);
        assert(oldRefC>0,"invalid refCount in release");
        if (oldRefC==1){
            giveBack();
        } else {
            debug(TrackTasks) sinkTogether(localLog,delegate void(CharSink s){
                dumper(s)("could not yet reuse Task@")(cast(void*)this)(" in release as refCount was ")(oldRefC)("\n"); // do this because this could be released before printing...
            });
        }
    }
    /// gives back the task (called automatically when you release the last time)
    void giveBack(){
        version(NoReuse){ } else {
            debug(TrackTasks) sinkTogether(localLog,delegate void(CharSink s){
                dumper(s)("giving back task ")(this)("\n");
            });
            if (fiber !is null && fPool!is null){
                fPool.giveBack(fiber); /// at least gives back the fiber...
                fiber=null;
            }
            if (tPool!is null){
                tPool.giveBack(this.retain);
            } else {
                if (fiber!is null){
                    debug(TrackTasks) sinkTogether(localLog,delegate void(CharSink s){
                        dumper(s)("could not reuse fiber@")(cast(void*)fiber)(" of task ")(taskName)("@")(cast(void*)this)(", destroying\n");
                    });
                    delete fiber;
                }
                debug(TrackTasks) sinkTogether(localLog,delegate void(CharSink s){
                    dumper(s)("could not reuse task ")(this)(", destroying\n");
                });
                delete this;
            }
        }
    }
    /// the current delay level
    int delayLevel(){
        auto res=bsr(delayFlags);
        assert((res&1)==0,collectAppender(delegate void(CharSink s){
            dumper(s)("unexpected delayFlags:")(delayFlags);
        }));
        return (res>>1);
    }
    /// called when a subtasks has finished
    void subtaskEnded(TaskI st){
        bool callOnFinish=false;
        version(NoTaskLock){ // mmh suspicious, I should recheck this... especially barriers wrt. to the rest
            volatile auto oldTasks=flagAdd(spawnTasks,-1);
            if (oldTasks==1){
                if (atomicCASB(statusAtt,TaskStatus.PostExec,TaskStatus.WaitingEnd)){
                    callOnFinish=true;
                    assert((flags & TaskFlags.WaitingSubtasks)==0 && delayFlags==1);
                } else {
                    volatile memoryBarrier!(true,false,false,true)();
                     while ((flagsAtt & TaskFlags.WaitingSubtasks)!=0){
                        if (atomicCASB(flags,flagsAtt & (~TaskFlags.WaitingSubtasks),flagsAtt)){
                            callOnFinish=true;
                        }
                        volatile flagsAtt=flags;
                    }
                }
            }
        } else {
            synchronized(taskLock){
                --spawnTasks;
                if (spawnTasks==0){
                    if (status==TaskStatus.WaitingEnd){
                        status=TaskStatus.PostExec;
                        callOnFinish=true;
                        assert((flags & (TaskFlags.WaitingSubtasks))==0 && delayFlags==1,"flags="~to!(char[])(flags));
                    } else if ((flags & TaskFlags.WaitingSubtasks)!=0){
                        flags=flags & (~TaskFlags.WaitingSubtasks);
                        callOnFinish=true;
                    }
                }
            }
        }
        if (callOnFinish){
            if (status==TaskStatus.PostExec){
                finishTask();
            } else {
                resubmitDelayed(delayLevel-1); // ugly takes advantage that the level will be the top most
            }
        }
    }
    /// resubmits this task that has been delayed
    /// by default it throws if the task wasn't delayed
    /// delayLevel is the level at which you will go back
    void resubmitDelayed(int delayLevel_){
        version(NoTaskLock){
            assert(false,"unimplemented");
        } else {
            int delayLevel=(delayLevel_<<1);
            debug(TrackTasks) sinkTogether(localLog,delegate void(CharSink s){
                dumper(s)("will resubmit task ")(this)("\n");
            });
            bool resub=false;
            synchronized(taskLock){
                debug(TrackDelayFlags){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("preResubmit")(delayLevel_)(", flags:")(delayFlags,"x")("\n");
                    });
                }
                auto delayLevelAtt=bsr(delayFlags);
                assert(delayLevel<delayLevelAtt,"invalid delayLevel");
                auto myFlag=((delayFlags>>delayLevel)&0x3);
                switch(myFlag){
                    case DelayStat.NormalRun: assert(0,"invalid stat in resubmit DelayStat.NormalRun for task "~taskName);
                    case DelayStat.WantSuspend:
                        static assert(DelayStat.NormalRun==0);
                        delayFlags=(delayFlags^(DelayStat.WantSuspend<<delayLevel));
                        break;
                    case DelayStat.SuspendStart:
                        static assert(DelayStat.Suspended==3);
                        delayFlags |= (DelayStat.Suspended<<delayLevel);
                        break;
                    case DelayStat.Suspended:
                        if (delayLevel+2==delayLevelAtt)
                            resub=true;
                        break;
                    default: assert(0);
                }
            }
            if (resub){
                debug(TrackDelayFlags){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("preResubmit add task back ")(delayLevel_)(", flags:")(delayFlags,"x")("\n");
                    });
                }
                volatile auto sched=scheduler;
                sched.addTask(this);
            }
            debug(TrackDelayFlags){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("postResubmit ")(delayLevel_)(", flags:")(delayFlags,"x")("\n");
                });
            }
        }
    }
    /// delays the current task (which should be yieldable)
    /// opStart is executed after the task has been flagged as delayed, but before
    /// stopping the current execution. Use it to start the operation that will resume
    /// the task (so that it is not possible to resume before the delay is effective)
    /// a similar thing could be done using a "delay count" but I find this cleaner and safer
    void delay(void delegate() opStart=null){
        int myDelayLevel;
        auto tAtt=taskAtt.val;
        if (tAtt !is this){
            throw new ParaException("delay '"~taskName~"' called while executing '"~((tAtt is null)?"*null*":tAtt.taskName),
                __FILE__,__LINE__);
        }
        version(NoTaskLock){
            assert(false,"unimplemented");
        } else {
            synchronized(taskLock){
                debug(TrackDelayFlags){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("preDelay, flags:")(delayFlags,"x")("\n");
                    });
                }
                myDelayLevel=bsr(delayFlags);
                if (myDelayLevel>=30) {
                    throw new Exception("hit maximum recursive level of delay in task "~taskName,
                        __FILE__,__LINE__);
                }
                assert(delayFlags>0 && (myDelayLevel&1)==0);
                static assert(DelayStat.WantSuspend==1);
                delayFlags|=(0x4<<myDelayLevel);
                assert(lastDelayFlags(delayFlags)==DelayStat.WantSuspend);
                debug(TrackDelayFlags){
                    sinkTogether(sout,delegate void(CharSink s){
                        dumper(s)("delay, preOp flags:")(delayFlags,"x")("\n");
                    });
                }
            }
        }
        if (!mightYield) {
            throw new ParaException("delay called on non yieldable task ("~taskName~")",
                __FILE__,__LINE__);
        } else {
            assert(opStart!is null);
            opStart();
            debug(TrackDelayFlags){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("delay postTask, flags:")(delayFlags,"x")("\n");
                });
            }
            volatile auto flagAtt=flags;
            bool do_yield=false;
            synchronized(taskLock){
                auto levelAtt=bsr(delayFlags);
                if (levelAtt!=myDelayLevel+2){
                    throw new ParaException(collectAppender(delegate void(CharSink s){
                        dumper(s)("unexpected 2*delay level at the end of delay of (")(taskName)("), ")
                            (levelAtt)(" vs ")(myDelayLevel);
                    }), __FILE__,__LINE__);
                }
                auto endFlags=(delayFlags>>myDelayLevel);
                switch(endFlags&0x3){
                    case DelayStat.NormalRun:
                        static assert(DelayStat.NormalRun==0);
                        delayFlags=(delayFlags^(0x5<<myDelayLevel)); // reduce level and continue execution
                        break;
                    case DelayStat.WantSuspend:
                        do_yield=true;
                        static assert(DelayStat.WantSuspend==1&&DelayStat.SuspendStart==2);
                        delayFlags=(delayFlags^(0x3<<myDelayLevel));
                        assert(lastDelayFlags(delayFlags)==DelayStat.SuspendStart);
                        break;
                    case DelayStat.SuspendStart: assert(0,"invalid stat in post delay: DelayStat.SuspendStart");
                    case DelayStat.Suspended: assert(0,"invalid stat in post delay: DelayStat.SuspendStart");
                    default: assert(0);
                }
            }
            debug(TrackDelayFlags){
                sinkTogether(sout,delegate void(CharSink s){
                    dumper(s)("delay preYield, flags:")(delayFlags,"x")("\n");
                });
            }
            if (do_yield) {
                scheduler.yield();
            }
        }
        debug(TrackDelayFlags){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("postDelay, flags:")(delayFlags,"x")("\n");
            });
        }
        assert(myDelayLevel==bsr(delayFlags),"unexpected delay level after delay");
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
    /// internal submitting op
    protected void spawnTask(TaskI task,void delegate()subOp){
        assert(mightSpawn,"task '"~taskName~"' tried to spawn '"~task.taskName~"' and has mightSpawn false");
        assert(task.status==TaskStatus.Building,"spawnTask argument should have building status");
        if (task.superTask is null) task.superTask=this;
        assert(cast(Object)task.superTask is this,"task '"~taskName~"' tried to spawn '"~task.taskName~"' that has different superTask:"~task.superTask.taskName);
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
            subOp();
        }
    }
    /// operation that spawn the given task as subtask of this one
    void spawnTask(TaskI task){
        spawnTask(task,delegate void(){ volatile auto sched=scheduler; sched.addTask(task); });
    }
    /// spawn a task and waits for its completion
    void spawnTaskSync(TaskI task){
        auto tAtt=taskAtt.val;
        if (tAtt is null || ((cast(RootTask)tAtt)!is null) || tAtt is noTask || !tAtt.mightYield){
            if (tAtt !is null && ((cast(RootTask)tAtt)is null) && tAtt !is noTask && !tAtt.mightYield) {
                scheduler.logger.warn("unsafe execution in spawnTaskSync of task "~task.taskName~" in "~tAtt.taskName~"\n");
            }
            task.retain();
            this.spawnTask(task);
            if (task.status!=TaskStatus.Finished)
                task.wait();
            task.release();
        } else {
            (cast(Task)task).appendOnFinish(resubmitter(tAtt,tAtt.delayLevel));
            tAtt.delay(delegate void(){
                if ((flags & TaskFlags.ImmediateSyncSubtasks)!=0){
                    // add something like && rand.uniform!(bool)() to avoid excessive task length?
                    this.spawnTask(task,delegate void(){ task.execute(); });
                } else {
                    // to do: allowing the task to be stolen here introduces some problems
                    // not sure why, should investigate (probably connected with scheduler change)
                    spawnTask(task,delegate void(){ volatile auto sched=scheduler; sched.addTask0(task); });
                }
            });
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
            && scheduler.nSimpleTasksWanted()>1)
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
            && scheduler.nSimpleTasksWanted()>1) {
                // to be smarter should store the cost and update it in willSpawn
                resubmit=generator();
        }
        
    }
    /// runs a generator that returns a pointer to a task (can be used as taskOp)
    void runGenerator2(){
        assert(generator2!is null);
        long subCost=0,maxCost=scheduler.nSimpleTasksWanted();
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
        assert(onF!is null,"null tasks not accepted");
        assert(status==TaskStatus.Building,"appendOnFinish allowed only during task building"); // change?
        if (onFinish0 is null){
            onFinish0=onF;
        } else if (onFinish1 is null){
            onFinish1=onF;
        } else {
            if (onFinish is null) onFinish=new LinkedList!(void delegate())();
            onFinish.append(onF);
        }
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
    /// executes this task synchroneously
    void executeNow(TaskI supertask=null){
        if (supertask !is null){
            assert(this.superTask is null || this.superTask is superTask,"superTask was already set");
            this.superTask=supertask;
        }
        if (this.superTask is null){
            if (scheduler !is null){
                this.superTask=scheduler.rootTask;
            } else {
                this.superTask=taskAtt.val;
            }
        }
        superTask.spawnTaskSync(this);
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
        retain();
        submit(superTask);
        auto tAtt=taskAtt.val;
        if (tAtt.mightYield)
            scheduler.maybeYield();
        else if ((cast(RootTask)tAtt)is null){
            throw new ParaException(taskName
                ~" submitYield called with non yieldable executing task ("~tAtt.taskName~")",
                __FILE__,__LINE__); // allow?
        }
        release();
        return this;
    }
    /// yields until the subtasks have finished (or waits if Yielding is not possible),
    /// then adds to the tasks to do at the end a task that continues the fiber of the current one
    /// remove? not really worth having...
    void finishSubtasks(){
        auto tAtt=taskAtt.val;
        if (cast(Object)tAtt !is this){
            throw new ParaException("finishSubtasks called on task '"~taskName~"' while executing '"~((tAtt is null)?"*null*"[]:tAtt.taskName),
                __FILE__,__LINE__);
        }
        if (mightYield){
            delay({
                bool resub=false;
                synchronized(taskLock){
                    if (spawnTasks==0){
                        resub=true;
                    } else {
                        flags|=TaskFlags.WaitingSubtasks;
                    }
                }
                if (resub) resubmitDelayed(delayLevel-1);
            });
        } else {
            bool noSubT=false;
            version(NoTaskLock){
                noSubT=(flagGet(spawnTasks)==0);
            } else {
                synchronized(taskLock){
                    noSubT=(spawnTasks==0);
                }
            }
            // this is not so nice, with some status hacking it should be possible to make it
            // work in general, but as it is tricky, and the payoff small I haven't done it for now.
            // this works in an immediate or a sequential executer.
            // it will also normally trigger the notification of possibly waiting tasks
            if (!noSubT) throw new ParaException("finishSubtasks called on non yieldable task ("~taskName~")",__FILE__,__LINE__);
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(void delegate(char[]) s){
        return desc(s,true);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) s,bool shortVersion){
        if (this is null){
            s("<Task *NULL*>");
        } else {
            s("<"); s(this.classinfo.name); s("@"); writeOut(s,cast(void*)this);
            s(" '"); s(taskName); s("' ");
            s(taskStatusStr(status));
            if (shortVersion) {
                s(" >");
                return;
            }
            s("\n");
            fieldsDesc(s);
            s(" >");
        }
    }
    /// prints the fields (superclasses can override this an call it through super)
    void fieldsDesc(void delegate(char[]) sink){
        auto s=dumper(sink);
        s("  level=")(level)(",\n");
        s("  taskOp:");
        if (taskOp is null)
            s("*NULL*");
        else
            s("associated");
        s(",\n");
        s("  fiber:");
        if (fiber is null)
            s("*NULL*");
        else
            s("associated");
        s(",\n");
        s("  generator:");
        if (generator is null)
            s("*NULL*");
        else
            s("associated");
        s(",\n");
        s("  onFinish:[");
        if (onFinish0!is null){
            s("associated");
            if (onFinish1!is null){
                s(",associated");
                if (onFinish!is null){
                    foreach (t;onFinish){
                        if (t is null)
                            s(",*NULL*");
                        else
                            s(",associated");
                    }
                }
            }
        }
        s("],\n");
        s("  superTask=");
        writeOut(s,superTask,true);
        s(",\n");
        s("  resubmit:")(resubmit)(",\n");
        s("  holdSubtasks:")(holdSubtasks)(",\n");
        s("  holdedSubtasks:")(holdedSubtasks)(",\n");
        s("  spawnTasks:")(spawnTasks)(",\n");
        s("  scheduler:"); writeOut(sink,scheduler,true); s(",\n");
        version(NoTaskLock){} else {
            bool lokD=taskLock.tryLock();
            if (lokD) taskLock.unlock();
            s("  taskLock:");
            if (lokD)
                s("locked by others");
            else
                s("unlocked by others");
            s(",\n");
        }
        s("  mightSpawn:")(mightSpawn);
    }
    /// waits for the task to finish
    void wait()
    in{
        if (refCount<=0){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("waiting on released task ")(this)(" is dangerous (and you should have retained it before starting it)");
            }),__FILE__,__LINE__);
        }
    }
    out{
        if (refCount<=0){
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("waiting on released task ")(this)(" (after wait) is dangerous (and you should have retained it before starting it)");
            }),__FILE__,__LINE__);
        }
    }
    body{
        Semaphore wSem;
        if (status!=TaskStatus.Finished){
            volatile wSem=waitSem;
            if (waitSem is null) {
                version(NoTaskLock){
                    volatile auto statusAtt=statusAtt;
                    if (statusAtt!=TaskStatus.Finished){
                        if (waitSem is null){
                            auto waitSemNew=new Semaphore();
                            if (!atomicCASB(waitSem,waitSemNew,null)){
                                delete waitSemNew;
                            }
                        }
                    }
                } else {
                    synchronized(taskLock) {
                         if (status!=TaskStatus.Finished){
                             if (waitSem is null) {
                                 waitSem=new Semaphore();
                             } else {
                                 return;
                             }
                         }
                    }
                }
            }
            if (status!=TaskStatus.Finished) {
                assert(waitSem !is null);
                volatile wSem=waitSem;
                wSem.wait();
                //assert(status==TaskStatus.Finished,"unexpected status after wait");
                wSem.notify();
            }
        }
    }
    
    typeof(this) autorelease(){
        auto oldRefC=atomicAdd(refCount,-1);
        assert(oldRefC>0,"invalid refCount in autorelease");
        return this;
    }
    typeof(this) retain(){
        auto oldRefC=atomicAdd(refCount,1);
        assert(oldRefC>=0,"invalid refCount in retain"); // it can be 0 due to autorelease, ugly but works
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
        log=Log.lookup("blip.parallel.smp."~name);
        this.warnSpawn=warnSpawn;
    }
    override void internalExe(){
        log.error("root task '"~taskName~"' should not be executed");
        assert(0,"root task '"~taskName~"' should not be executed");
    }
    override void willSpawn(TaskI t){
        if (warnSpawn){
            if (this is noTask){
                log.warn("root task '"~taskName~"' spawned task "~t.taskName~" if you want to implicitly spawn from this thread without this warning you should do some thing like taskAtt.val=defaultTask; in it");
            } else {
                log.warn("root task '"~taskName~"' spawned task "~t.taskName);
            }
        }
        super.willSpawn(t);
    }
}

/// root task that enforces a sequential execution of the submitted tasks
/// should override submitSync and possibly execute immediately
class SequentialTask:RootTask{
    Deque!(TaskI) queue; // FIFO queue
    int nExecuting;
    
    this(char[] name,TaskSchedulerI scheduler, int level=0,bool canBeImmediate=true){
        super(scheduler,level,name,false);
        if (canBeImmediate){
            version(NoReuse){ } else {
                flags|=TaskFlags.ImmediateSyncSubtasks;
            }
        }
        queue=new Deque!(TaskI)();
        nExecuting=0;
    }
    this(char[]name,TaskI t,bool canBeImmediate=true){
        if (t is null){
            throw new ParaException("sequential task with no super task",__FILE__,__LINE__);
        }
        this(name,t.scheduler,t.level+1,canBeImmediate);
    }
    
    override void spawnTask(TaskI t){
        TaskI toExe;
        synchronized(queue){
            flagAdd(spawnTasks,1);
            if (atomicCASB(nExecuting,1,0)){
                if (queue.popFront(toExe)){
                    queue.append(t);
                } else {
                    toExe=t;
                }
            } else {
                queue.append(t);
            }
        }
        if (toExe){
            super.spawnTask(toExe);
        }
    }
    
    /// spawn a task and waits for its completion
    void spawnTaskSync(TaskI task){
        auto tAtt=taskAtt.val;
        if (tAtt is null || ((cast(RootTask)tAtt)!is null) || tAtt is noTask || !tAtt.mightYield){
            if (tAtt !is null && ((cast(RootTask)tAtt)is null) && tAtt !is noTask && !tAtt.mightYield) {
                scheduler.logger.warn("unsafe execution in spawnTaskSync of task "~task.taskName~" in "~tAtt.taskName~"\n");
            }
            task.retain();
            this.spawnTask(task);
            if (task.status!=TaskStatus.Finished)
                task.wait();
            task.release();
        } else {
            (cast(Task)task).appendOnFinish(resubmitter(tAtt,tAtt.delayLevel));
            tAtt.delay(delegate void(){
                if (tAtt.superTask is this){
                    synchronized(queue){
                        flagAdd(spawnTasks,1);
                        if (queue.length>0){
                            throw new ParaException("sequential queue violation by recursive subtask",
                                __FILE__,__LINE__);// allow??
                        }
                    }
                    log.warn("'"~this.taskName~"'.spawnTaskSync('"~task.taskName~"') called while executing '"~tAtt.taskName~"' which is sequential task of '"~this.taskName~"'"); // remove?
                    if (atomicAdd(nExecuting,1)<1){
                        throw new ParaException("unexpected value of nExecuting",__FILE__,__LINE__);
                    }
                    super.spawnTask(task,{ task.execute(); });
                } else if ((flags & TaskFlags.ImmediateSyncSubtasks)!=0){
                    // add && scheduler.rand.uniform!(bool)() to avoid excessive task length
                    TaskI toExe;
                    synchronized(queue){
                        flagAdd(spawnTasks,1);
                        if (atomicCASB(nExecuting,1,0)){
                            if (queue.popFront(toExe)){
                                queue.append(task);
                            } else {
                                toExe=task;
                            }
                        } else {
                            queue.append(task);
                        }
                    }
                    if (toExe){
                        super.spawnTask(toExe,{ toExe.execute(); }); // could even loop until task is executed... but might give subtle priority problems
                    }
                } else {
                    spawnTask(task);
                }
            });
        }
    }
    
    override void willSpawn(TaskI st){ }
    
    void subtaskEnded(TaskI st)
    in{
        volatile auto nExecutingAtt=nExecuting;
        assert(nExecutingAtt==0 || nExecutingAtt==1);
    }
    out{
            volatile auto nExecutingAtt=nExecuting;
            assert(nExecutingAtt==0 || nExecutingAtt==1);
    }
    body{
        TaskI toExe;
        super.subtaskEnded(st);
        synchronized(queue){
            if (nExecuting==1 && queue.length>0){
                // add && scheduler.rand.uniform!(bool)() ?
                toExe=queue.popFront;
            } else if (atomicAdd(nExecuting,-1)<1){
                throw new ParaException("unexpected value for nExecuting "~to!(char[])(nExecuting),__FILE__,__LINE__);
            }
        }
        if (toExe){
            super.spawnTask(toExe);
        }
    }
}
