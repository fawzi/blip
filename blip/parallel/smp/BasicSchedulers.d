module blip.parallel.smp.BasicSchedulers;
import blip.t.core.Thread;
import blip.t.core.Variant:Variant;
import blip.t.core.sync.Mutex;
import blip.t.math.Math;
import blip.t.util.log.Log;
import tango.util.container.LinkedList;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.smp.PriQueue;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.BasicModels;
import blip.t.math.random.Random;
import blip.container.Cache;

/// task scheduler that tries to perform a depth first reduction of the task
/// using the maximum parallelization available.
/// This allows to have parallelization without generating too many suspended
/// tasks, it can be seen as a parallelization of eager evaluation.
/// Just as eager evaulation it has the great advantage of being relatively easy
/// to understand and to have good performance.
///
/// integrate PriQueue in this? it would be slighly more efficient, and already now
/// depends on its implementation details, or they should be better separated
class PriQTaskScheduler:TaskSchedulerI {
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
    /// level of the scheduler (mirrors a numa topology level)
    int level;
    /// executer
    ExecuterI _executer;
    Cache _nnCache;
    RandomSync _rand;
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    Cache nnCache(){
        return _nnCache;
    }
    /// returns the root task
    TaskI rootTask(){ return _rootTask; }
    /// creates a new PriQTaskScheduler
    this(char[] name,char[] loggerPath="blip.parallel.smp.queue",int level=0){
        this.name=name;
        queue=new PriQueue!(TaskI)();
        this._rand=new RandomSync();
        log=Log.lookup(loggerPath);
        _rand=new RandomSync();
        _rootTask=new RootTask(this,0,name~"RootTask");
        runLevel=SchedulerRunLevel.Running;
        _nnCache=new Cache();
    }
    /// adds a task to be executed
    void addTask(TaskI t){
        assert(t.status==TaskStatus.NonStarted ||
            t.status==TaskStatus.Started,"initial");
        log.info("task "~t.taskName~" will be added to queue "~name);
        if (shouldAddTask(t)){
            queue.insert(t.level,t);
        }
    }
    // alias addTask addTask0;
    void addTask0(TaskI t){
        addTask(t);
    }
    /// returns nextTask if available, null if it should wait
    TaskI nextTaskImmediate(int stealLevel){
        TaskI t;
        if (queue.nEntries==0){
            if (stealLevel==0) return null;
        } else {
            t=queue.popNext(true);
        }
        if (stealLevel>level && t is null){
            t=trySteal(stealLevel);
        }
        if (t !is null){
            subtaskActivated(t);
        }
        return t;
    }
    /// tries to steal a task, might redistribute the tasks
    TaskI trySteal(int stealLevel){
        return null;
    }
    /// returns nextTask (blocks, returns null only when stopped)
    TaskI nextTask(){
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
            if (runLevel==SchedulerRunLevel.Stopped)
                return null;
        }
        t=queue.popNext();
        if (t !is null){
            subtaskActivated(t);
        }
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
        s("<PriQTaskScheduler@"); writeOut(sink,cast(void*)this);
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
                    queue.stop();
                }
            }
        }
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.nEntries>15; }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){ return 4; }
}
