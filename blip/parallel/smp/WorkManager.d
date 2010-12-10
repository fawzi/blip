/// module of the singleton (one per process) defaultScheduler
///
/// == Blip Overview: Parallel smp execution (from blip.parallel.smp.WorkManager) ==
/// 
/// At smp level blip uses a parallelization strategy based on tasks
/// Blip uses a parallelization scheme that is described more in details in ParallelizationConcepts .
/// To use smp parallelization the easiest thing is to just import blip.parallel.smp.WorkManager.
/// The basic Parallel unity is a Task, for example to create a task that will execute the delegate &obj.myOp you can:
/// {{{
/// auto t=Task("myOpTask",&obj.myOp);
/// }}}
/// It is important to note that the delegate and all the memory it accesses have to remain valid for the whole execution of the task. Thus it is dangerous to use stack allocated delegates/objects unless you are sure they will remain valid. The simplest solution to be on the safe side is to always use a method of an objet (or heap allocated struct).
/// 
/// Now you can attach operations to be executed at the end of the task
/// {{{
/// t.appendOnFinish(&obj.cleanup).appendOnFinish(&submitNewTask);
/// }}}
/// If you don't want to use the task after submission you can tell it that it is ok to
/// immediately reuse the task
/// {{{
/// t.autorelease;
/// }}}
/// And finally you can submit it and wait for it to complete
/// {{{
/// t.executeNow();
/// }}}
/// or you can submit it an immediately go on executing the rest of the current function
/// {{{
/// t.submit();
/// }}}
/// to avoid submitting too many tasks at once you might want to "pause" the current task
/// so that it will be resumed when more tasks are requested:
/// {{{
/// if (!Task.yield()) throw Exception("cannot yield");
/// }}}
/// you might also insert a possible pause, which might be done or not with
/// {{{
/// Task.maybeYield();
/// }}}
/// As it is common to do a pause just after submitting, you can submit a task with
/// {{{
/// t.submitYield();
/// }}}
/// which is equivalent to
/// {{{
/// t.submit(); Task.maybeYield();
/// }}}
/// 
/// The current task can be suspended as follows
/// {{{
/// auto tAtt=taskAtt.val; // get the current task
/// tAtt.delay(delegate void(){
///     waitForSomeEvent(tAtt);
/// })
/// }}}
/// where waitForSomeEvent should call tAtt.resubmitDelayed() when the task can be restarted.
/// This allows to remove tasks that wait (for example) for i/o events from the active tasks
/// and keep the processor busy executing tasks that are available in the meantime.
/// 
/// A tasks is considered finished only when all its subtasks have finished executing.
/// You can wait for the end of a task t with
/// {{{
/// t.wait();
/// }}}
/// It is important that the task is either not yet started, or retained (i.e. do not wait on an autoreleased task, that will give you an error).
/// 
/// Submitting a task as we did before starts the task as subtask of the currently executing
/// task. If you want to schedule it differently you can start it by giving it and explicit
/// superTask
/// {{{
/// t.submit(superTask);
/// }}}
/// In particular the defaultTask will start the task as an independent task, and one can
/// define other tasks that have different scheduling, for example sequentialTask enforces
/// a sequential execution of its subtasks.
/// 
/// Tasks give a lot of power and freedom to define the parallel workflow of an algorithm,
/// but sometime they are a bit too much to simply perform a parallel loop.
/// For this there are some helpers, for example
/// {{{
/// int[] myBeautifulArray=...;
/// foreach(i,ref el;pLoopArray(myBeautifulArray,30)){
///     el+=i;
/// }
/// }}}
/// makes a parallel loop on myBeautifulArray, trying to do 30 elements in a task.
/// whereas
/// {{{
/// int i=0;
/// auto iterator=bool(ref int el){
///     if (i<10){
///         el=i;
///         ++i;
///         return true;
///     }
///     return false;
/// }
/// foreach(i;pLoopIter(iterator)){
///     sinkTogether(sout,delegate void(CharSink s){
///         dumper(s)("did ")(i)("\n");
///     });
/// }
/// }}}
/// does a parallel loop on an iterator that goes over the first 10 elements (this is less
/// efficient than the previous, because an iterator serializes things).
/// 
/// Clearly in both cases it is the programmer responsibility to make sure that the body
/// of the loop can be executed in parallel without problems.
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
module blip.parallel.smp.WorkManager;
public import blip.parallel.smp.SmpModels;
public import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.BasicExecuters;
import blip.parallel.smp.BasicTasks;
import tango.util.log.Config;
import blip.util.TangoLog;import blip.parallel.smp.NumaSchedulers;
import blip.parallel.smp.Numa;
import blip.Comp;

string [] ctfe_splitCompress(string sep,string str){
    string [] res;
    size_t fromI=0;
    bool wasSpace=false;
    foreach(i,c;str){
        if (wasSpace) fromI=i;
        wasSpace=false;
        bool isSep=false;
        foreach(c2;sep){
            if (c==c2) isSep=true;
        }
        if (isSep){
            if (i>fromI){
                res ~= str[fromI..i];
            }
            wasSpace=true;
        }
    }
    if (!wasSpace){
        res ~= str[fromI..$];
    }
    return res;
}
/// creates an action, i.e. a void delegate() called name, that captures the local
/// variables locals, and executes the action action.
/// lives in the heap, so it is safe
string mkActionMixin(string name,string locals_,string action){
    string [] locals=ctfe_splitCompress("|",locals_);
    string res= `
    void delegate() `~name~`;
    {`;
    foreach(v;locals){
        res~=`
        alias typeof(`~v~`) `~v~`Type_;`;
    }
    res~=`
        struct `~name~`Closure{`;
    foreach(v;locals){
        res~=`
        `~v~`Type_ `~v~`;`;
    }
    res~=`
            void doIt(){
                `~action~`
            }
        }
        auto `~name~`Cl=new `~name~`Closure;`;
    foreach(v;locals){
        res~=`
        `~name~`Cl.`~v~`=`~v~`;`;
    }
    res~=`
        `~name~`=&`~name~`Cl.doIt;
    }`;
    return res;
}

/// size_t the default size for simple work
/// this is used to calculate the default block size for splitting up parallel tasks
/// (this should probably be at least comparable to the l1 cache per thread)
const size_t defaultSimpleLoopSize=64*1024;

/// a real scheduler (unless one has version SequentialWorkManager)
/// shares the work on a pool of threads
TaskSchedulerI defaultScheduler;
/// the root task that can be used to add work to the defaultScheduler
TaskI defaultTask;
/// a root task that can be used to add work to a sequential worker that never
/// executes two tasks concurrently
TaskI sequentialTask;
/// a task that can be used as supertask to the tasks that should be
/// executed immediately, if possible in the current context
TaskI immediateTask;

static this(){
    version(SequentialWorkManager){
        auto defaultExecuter=new ImmediateExecuter("defaultWorkManager");
        defaultScheduler=defaultExecuter.scheduler();
    } else {
        version(NoNuma){
            auto defaultExecuter=new PExecuter("defaultWorkManager");
            defaultScheduler=defaultExecuter.scheduler();
        } else {
            auto defaultExecuter=new StarvationManager("defaultWorkManager",defaultTopology,1,1);
            defaultExecuter.pinLevel=1; // pin threads to hardware threads
            defaultScheduler=defaultExecuter;
        }
    }
    defaultTask=defaultScheduler.rootTask();
    // tasks submitted to noTask print a warning, and are routed to the default executer
    (cast(RootTask)noTask)._scheduler=defaultScheduler;
    auto immediateScheduler=new ImmediateExecuter("immediateWorkManager");
    immediateTask=immediateScheduler.rootTask();
    version(SequentialWorkManager){
        sequentialTask=immediateTask;
    } else {
        version(NoNuma){
            sequentialTask=immediateTask;
        } else {
            sequentialTask=new SequentialTask("sequentialWorkManager",defaultTask,true);
        }
    }
    version(DetailedLog){
        Log.lookup("blip.parallel.smp").level(Logger.Level.Info,true);
    } else {
        Log.lookup("blip.parallel.smp").level(Logger.Level.Warn,true);
    }
    
    // allow implicit submission form the main thread
    taskAtt.val=defaultTask;
}

