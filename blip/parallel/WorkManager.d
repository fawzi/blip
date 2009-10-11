/// module of the singleton (one per process) defaultScheduler
module blip.parallel.WorkManager;
public import blip.parallel.Models;
public import blip.parallel.BasicTasks;
import blip.parallel.BasicExecuters;
import blip.parallel.BasicTasks;
import tango.util.log.Config;
import tango.util.log.Log;

/// a real scheduler (unless one has version SequentialWorkManager)
/// shares the work on a pool of threads
TaskSchedulerI defaultScheduler;
/// the root task that can be used to add work to the defaultScheduler
TaskI defaultTask;
/// a sequantial scheduler, executes the tasks as soon as they are submitted
/// in the current thread, no subthread, no fiber (if possible), normal
/// immediate execution
TaskSchedulerI sequentialScheduler;
/// the root task that can be used to add work to the sequentialScheduler
TaskI sequentialTask;

static this(){
    version(SequentialWorkManager){
        auto defaultExecuter=new ImmediateExecuter("defaultWorkManager");
    } else {
        auto defaultExecuter=new PExecuter("defaultWorkManager");
    }
    defaultScheduler=defaultExecuter.scheduler();
    defaultTask=defaultScheduler.rootTask();
    // tasks submitted to noTask print a warning, and are routed to the default executer
    (cast(RootTask)noTask)._scheduler=defaultScheduler;
    sequentialScheduler=new ImmediateExecuter("sequentialWorkManager");
    sequentialTask=sequentialScheduler.rootTask();
    Log.lookup("blip.parallel").level(Logger.Level.Warn,true);
}

