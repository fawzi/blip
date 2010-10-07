/// interfaces for tasks, schedulers and executers
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
module blip.parallel.smp.SmpModels;
import blip.util.TangoLog;
import blip.BasicModels;
import blip.io.BasicIO;
import blip.container.FiberPool;
import blip.container.Cache;
import blip.container.Pool;
import blip.math.random.Random;
import blip.core.Traits: ctfe_i2a;

enum TaskStatus:int{
    Building=-1,
    NonStarted=0,
    Started=1,
    WaitingEnd=2,
    PostExec=3,
    Finished=4
}

/// conversion TaskStatus -> str
char[] taskStatusStr(TaskStatus s){
    switch(s){
        case TaskStatus.Building:
            return "Building";
        case TaskStatus.NonStarted:
            return "NonStarted";
        case TaskStatus.Started:
            return "Started";
        case TaskStatus.WaitingEnd:
            return "WaitingEnd";
        case TaskStatus.PostExec:
            return "PostExec";
        case TaskStatus.Finished:
            return "Finished";
        default:
            return "TaskStatus"~ctfe_i2a(cast(int)s);
    }
}

/// conversion str -> TaskStatus
TaskStatus taskStatusFromStr(char[] s){
    switch(s){
    case "Building":
        return TaskStatus.Building;
    case "NonStarted":
        return TaskStatus.NonStarted;
    case "Started":
        return TaskStatus.Started;
    case "WaitingEnd":
        return TaskStatus.WaitingEnd;
    case "PostExec":
        return TaskStatus.PostExec;
    case "Finished":
        return TaskStatus.Finished;
    default:
        char[] t="TaskStatus";
        if (s.length>t.length && s[0..t.length]==t){
            long res=0;
            size_t i=t.length;
            if (s[t.length]=='-') ++i;
            while (i<s.length){
                if (s[i]<'0'||s[i]<'9'){
                    throw new Exception("could not interpret taskStatus "~s,__FILE__,__LINE__);
                }
                res=10*res+cast(long)(s[i]-'0');
            }
            if (s[t.length]=='-') res=-res;
            return cast(TaskStatus)cast(int)res;
        }
        throw new Exception("could not interpret taskStatus "~s,__FILE__,__LINE__);
    }
}

interface ExecuterI:BasicObjectI {
    /// logger for task execution messages
    Logger execLogger();
}

enum SchedulerRunLevel:int{
    Configuring, /// configuring phase
    Running, /// running (blocks if no task available)
    StopNoTasks, /// stops as soon as no tasks are in the queue or executing
    StopNoQueuedTasks, /// stops as soon as no tasks are in the queue
    Stopped /// stopped
}

interface TaskSchedulerI:BasicObjectI {
    /// random source (for scheduling)
    RandomSync rand();
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level);
    /// adds a task to the scheduler queue (might redirect the task)
    void addTask(TaskI t);
    /// adds a task to the scheduler queue (will not redirect the task)
    void addTask0(TaskI t);
    /// returns the next task, blocks unless the scheduler is stopped
    TaskI nextTask();
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st);
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st);
    /// returns the executer for this scheduler
    ExecuterI executer();
    /// sets the executer for this scheduler
    void executer(ExecuterI nExe);
    /// logger for task/scheduling messages
    Logger logger();
    /// yields the current fiber if the scheduler is not sequential
    void yield();
    /// maybe yields the current fiber (use this to avoid creating too many tasks while reducing context switches)
    void maybeYield();
    /// root task, the easy way to add tasks to this scheduler
    TaskI rootTask();
    /// description
    void desc(void delegate(char[]) s);
    /// possibly short description
    void desc(void delegate(char[]) s,bool shortVersion);
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued();
    /// number of simple tasks wanted
    int nSimpleTasksWanted();
    /// a cache local to the current numa node (useful for memory pools)
    Cache nnCache();
}

// the following subdivisions are more to structure the methods of a task
// and are not really used alone

/// methods needed in a queued task
interface TaskI:SubtaskNotificationsI{
    /// executes the task
    void execute(bool sequential=false);
    /// returns the status of the task
    TaskStatus status();
    /// sets the status of the task
    void status(TaskStatus s);
    /// returns the level of the task
    int level();
    /// sets the level of the task
    void level(int level);
    /// returns the steal level of the task (how much it can be stolen)
    int stealLevel();
    /// sets the steal level of the task
    void stealLevel(int level);
    /// sets the super task of this task (the one that spawned this)
    void superTask(TaskI task);
    /// sets the scheduler of this task
    void scheduler(TaskSchedulerI sched);
    /// returns the super task of this task (the one that spawned this)
    TaskI superTask();
    /// returns the scheduler of this task
    TaskSchedulerI scheduler();
    /// name of the task
    char[] taskName();
    /// description
    void desc(void delegate(char[]) s);
    /// possibly short description
    void desc(void delegate(char[]) s,bool shortVersion);
    /// if this task might spawn
    bool mightSpawn();
    /// if this task might Yield
    bool mightYield();
    /// waits for task completion
    void wait();
    /// retains the task (call it if you want to avoid reuse of the task before you release it)
    TaskI retain();
    /// releases the task (call it when you don't need the task anymore)
    void release();
    /// call this when you don't need the task anymore, but it should not be reused immediately (typically before submit)
    TaskI autorelease();
    /// return the fiberpool to be used to allocate fibers (null if the default one should be used)
    /// sets the fiber pool used
    TaskI setFiberPool(FiberPool fPool);
    /// returns the fiber pool used
    FiberPool fiberPool(bool canBeNull=false);
    /// if possible gives back the task for later reuse (makes the task invalid)
    
    // methods to submit a task, merged them here due to http://d.puremagic.com/issues/show_bug.cgi?id=3706
    // interface SubmittingI:BasicObjectI {
    /// submits this task (with the given supertask, or with the actual task as supertask)
    TaskI submit(TaskI t=null);
    /// submits the current task and maybe yields the current one (if not SequentialWorkManager)
    /// The current task must be a Fiber or Yieldable or RootTask
    TaskI submitYield(TaskI t=null);
    /// spawns the task t from the present task
    void spawnTask(TaskI t);
    /// spawns the task t from the present task and waits for its completion
    void spawnTaskSync(TaskI t);
    /// delays the current task (which should be yieldable)
    /// opStart is executed after the task has been flagged as delayed, but before
    /// stopping the current execution. Use it to start the operation that will resume
    /// the task (so that it is not possible to resume before the delay is effective)
    void delay(void delegate()opStart=null);
    /// resubmit a task that was delayed just once
    void resubmitDelayedSingle();
    /// resubmit a delayed task, the value is the delayLevel at which the task will return
    /// (thus you should use delayLevel-1 from within the delay task)
    void resubmitDelayed(int);
    /// the current level of delay
    int delayLevel();
    /// executes the task, and waits for its completion
    void executeNow(TaskI t=null);
    //}
    
}

/// notifications called by direct subtasks
interface SubtaskNotificationsI:BasicObjectI {
    /// called before spawning a new subtask
    void willSpawn(TaskI st);
    /// subtask has finished
    void subtaskEnded(TaskI st);
}

/// exception for parallelization problems
class ParaException: Exception{
    this(char[] msg, char[] file, size_t line, Exception next = null){
        super(msg,file,line,next);
    }
}

/// closure to resubmit a task safely (is now needed due to the recursive delay support)
/// recursive delay support has shown to be of dubious utility, the ratio usefulness/complexity is not convincing
/// probably it should be removed...
struct Resubmitter{
    TaskI task;
    PoolI!(Resubmitter*)pool;
    int delayLevel=int.max;
    void resub(){
        task.resubmitDelayed(delayLevel);
        giveBack();
    }
    void giveBack(){
        if (pool!is null){
            pool.giveBack(this);
        } else {
            task=null;
            delayLevel=int.max;
            delete this;
        }
    }
    static PoolI!(Resubmitter*) gPool;
    static this(){
        gPool=cachedPool(function Resubmitter*(PoolI!(Resubmitter*)p){
            auto res=new Resubmitter;
            res.pool=p;
            return res;
        });
    }
    static Resubmitter *opCall(TaskI t,int delayLevel){
        auto r=gPool.getObj();
        r.task=t;
        r.delayLevel=delayLevel;
        return r;
    }
    void desc(CharSink s){
        dumper(s)("{class:Resubmitter, @:")(cast(void*)this)(", task:")(task)(", delayLevel:")(delayLevel)("}");
    }
}
/// returns a delegate that resubmits the task with the given delayLevel
void delegate() resubmitter(TaskI task,int delayLevel){
    auto res=Resubmitter(task,delayLevel);
    return &res.resub;
}
