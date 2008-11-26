/// module of the singleton (one per process) defaultScheduler
module blip.parallel.WorkManager;
public import blip.parallel.Models;
public import blip.parallel.BasicTasks;
import blip.parallel.BasicExecuters;
import blip.parallel.BasicTasks;
import tango.util.log.Config;
import tango.util.log.Log;

TaskSchedulerI defaultScheduler;
TaskI defaultTask;

static this(){
    version(SequentialWorkManager){
        auto defaultExecuter=new SExecuter("defaultWorkManager");
    } else {
        auto defaultExecuter=new PExecuter("defaultWorkManager");
    }
    defaultScheduler=defaultExecuter.scheduler();
    defaultTask=defaultScheduler.rootTask();
    (cast(RootTask)noTask)._scheduler=defaultScheduler;
    Log.lookup("blip.parallel").level(Logger.Level.Warn,true);
}

