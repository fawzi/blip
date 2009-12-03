/// module of the singleton (one per process) defaultScheduler
module blip.parallel.smp.WorkManager;
public import blip.parallel.smp.SmpModels;
public import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.BasicExecuters;
import blip.parallel.smp.BasicTasks;
import tango.util.log.Config;
import blip.t.util.log.Log;

/// size_t the default size for simple work
/// this is used to calculate the default block size for splitting up parallel tasks
/// (this should probably be at least comparable to the l1 cache per thread)
const size_t defaultSimpleLoopSize=64*1024;
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
TaskI immediateTask;

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
    auto immediateScheduler=new ImmediateExecuter("immediateWorkManager");
    sequentialScheduler=new ImmediateExecuter("sequentialWorkManager");
    sequentialTask=sequentialScheduler.rootTask();
    immediateTask=immediateScheduler.rootTask();
    Log.lookup("blip.parallel.smp").level(Logger.Level.Warn,true);
}

