/// Basic schedulers.
/// by default now the Numa schedulers are used. Beware possible subtle differences.
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
module blip.parallel.smp.BasicSchedulers;
import blip.core.Thread;
import blip.core.Variant:Variant;
import blip.core.sync.Mutex;
import blip.math.Math;
import blip.util.TangoLog;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.parallel.smp.PriQueue;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.BasicModels;
import blip.math.random.Random;
import blip.container.Cache;
import blip.Comp;

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
    string name;
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
    @property final RandomSync rand(){ return _rand; }
    @property Cache nnCache(){
        return _nnCache;
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    /// returns the root task
    @property TaskI rootTask(){ return _rootTask; }
    /// creates a new PriQTaskScheduler
    this(string name,string loggerPath="blip.parallel.smp.queue",int level=0){
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
        debug(TrackQueues){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("task ")(t)(" will be added to queue ")(this);
            });
        }
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
        if (queue.nEntries==0 && stealLevel==0) return null;
        t=queue.popNext(true);
        if (t !is null){
            subtaskActivated(t);
        } else if (stealLevel>level){
            t=trySteal(stealLevel);
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
    string toString(){
        return cast(string)collectIAppender(cast(OutWriter)&desc);
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
    @property void executer(ExecuterI nExe){
        _executer=nExe;
    }
    /// removes the executer
    @property ExecuterI executer(){
        return _executer;
    }
    /// description (for debugging)
    void desc(scope void delegate(in cstring) s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) sink,bool shortVersion){
        auto s=dumper(sink);
        s("<PriQTaskScheduler@"); writeOut(sink,cast(void*)this);
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
    @property Logger logger(){ return log; }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    @property bool manyQueued() { return queue.nEntries>15; }
    /// number of simple tasks wanted
    @property int nSimpleTasksWanted(){ return 4; }
}
