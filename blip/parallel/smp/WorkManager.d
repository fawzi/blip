/// module of the singleton (one per process) defaultScheduler
module blip.parallel.smp.WorkManager;
public import blip.parallel.smp.SmpModels;
public import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.BasicExecuters;
import blip.parallel.smp.BasicTasks;
import tango.util.log.Config;
import blip.t.util.log.Log;
import blip.parallel.smp.NumaSchedulers;
import blip.parallel.smp.Numa;

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
        //version(NoNuma){
            sequentialTask=immediateTask;
        //} else { // pippo to do sequential task is broken
        //    sequentialTask=new SequentialTask("sequentialWorkManager",defaultTask,true);
        //}
    }
    version(DetailedLog){
        Log.lookup("blip.parallel.smp").level(Logger.Level.Info,true);
    } else {
        Log.lookup("blip.parallel.smp").level(Logger.Level.Warn,true);
    }
}

