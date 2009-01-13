module blip.parallel.BasicSchedulers;
import tango.io.protocol.model.IWriter;
import tango.io.protocol.model.IReader;
import tango.core.Thread;
import tango.core.Variant:Variant;
import tango.core.sync.Mutex;
import tango.math.Math;
import tango.io.Stdout;
import tango.util.log.Log;
import tango.util.container.LinkedList;
import tango.io.stream.Format;
import blip.text.Stringify;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.PriQueue;
import blip.parallel.Models;
import blip.parallel.BasicTasks;
import blip.BasicModels;

/// task scheduler that tries to perform a depth first reduction of the task
/// using the maximum parallelization available.
/// This allows to have parallelization without generating too many suspended
/// tasks, it can be seen as a parallelization of eager evaluation.
/// Just as eager evaulation it has the great advantage of being relatively easy
/// to understand and to have good performance.
/// This is closely related to work stealing, and you can implement
/// a work stealing approach based on this (I am thinking about it)
/// this would have more tasks, but a better cpu affinity, so it might be better
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
    /// executer
    ExecuterI _executer;
    /// returns the root task
    TaskI rootTask(){ return _rootTask; }
    /// creates a new PriQTaskScheduler
    this(char[] name,char[] loggerPath="blip.parallel.queue"){
        this.name=name;
        queue=new PriQueue!(TaskI)();
        log=Log.lookup(loggerPath);
        _rootTask=new RootTask(this,0,name~"RootTask");
        runLevel=SchedulerRunLevel.Running;
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
    /// returns nextTask (blocks, returns null only when stopped)
    Task nextTask(){
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
        return getString(desc(new Stringify()).newline);
    }
    /// locks the scheduler (to perform task reorganization)
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
    /// sets the executer
    void executer(ExecuterI nExe){
        _executer=nExe;
    }
    /// removes the executer
    ExecuterI executer(){
        return _executer;
    }
    /// description (for debugging)
    FormatOutput!(char) desc(FormatOutput!(char)s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    FormatOutput!(char) desc(FormatOutput!(char)s,bool shortVersion){
        if (this is null){
            s("<PriQTaskScheduler *NULL*>").newline;
        } else {
            s.format("<PriQTaskScheduler@{}",cast(void*)this);
            if (shortVersion) {
                s(" >");
                return s;
            }
            s.newline;
            s("  name:")(name)(",").newline;
            s("  runLevel:")(runLevel)(",").newline;
            s("  queue:")(queue)(",").newline;
            s("  log:")(log)(",").newline;
            s("  activeTasks:[").newline;
            s("    ");
            bool nonFirst=false;
            foreach (t,r;activeTasks){
                if (nonFirst) { s(",").newline; nonFirst=true; }
                writeDesc(t,s("    ")(r),true);
            }
            s.newline;
            s("  ],").newline;
            writeDesc(rootTask,s("  rootTask:")).newline;
            s(" >").newline;
        }
        return s;
    }
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level){
        synchronized(this){
            assert(cast(int)runLevel <= cast(int)level,"runLevel can be only increased");
            if (runLevel < cast(int)level)
                runLevel=level;
                if (runLevel==SchedulerRunLevel.Stopped){
                    queue.stop();
                }
        }
    }
    /// scheduler logger
    Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return queue.nEntries>15; }
}
