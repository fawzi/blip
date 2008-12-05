/// executers (sequential and parallel)
module blip.parallel.BasicExecuters;
import tango.core.Thread;
import tango.math.Math;
import tango.io.Stdout;
import tango.util.log.Log;
import tango.io.Print;
import blip.Stringify;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.Models;
import blip.parallel.BasicSchedulers;
import blip.parallel.BasicTasks;
import blip.parallel.PriQueue;
import blip.BasicModels;

class SExecuter:ExecuterI,TaskSchedulerI{
    /// logger for problems/info
    Logger log;
    /// run level
    SchedulerRunLevel runLevel;
    /// root task
    TaskI _rootTask;
    ///  returns the root task
    TaskI rootTask(){ return _rootTask; }
    /// name of the executer
    char[] _name;
    /// name accessor
    char[] name(){
        return _name;
    }
    /// creates a new executer
    this(char[] name,char[]loggerPath="blip.parallel.exec"){
        this._name=name;
        log=Log.lookup(loggerPath);
        runLevel=SchedulerRunLevel.Running;
        _rootTask=new RootTask(this,0,name~"DefaultTask",false);
    }
    /// returns the scheduler (itself in this case)
    TaskSchedulerI scheduler(){
        return this;
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    Print!(char) desc(Print!(char)s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s,bool shortVersion){
        s.format("<SExecuter@{} ",cast(void*)this)(name);
        if (shortVersion) {
            s(" >");
            return s;
        }
        s.newline;
        s("  log:")(log)(",").newline;
        s(" >").newline;
        return s;
    }
    /// changes the current run level of the scheduler (the level can be only raised)
    void raiseRunlevel(SchedulerRunLevel level){
        assert(cast(int)runLevel <=cast(int)level,"runLevel can only increase");
        runLevel=level;
    }
    /// adds a task to the scheduler queue
    void addTask(TaskI t){
        if (runLevel!=SchedulerRunLevel.Stopped){
            try{
                log.info("Executer "~name~", thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) {
                    log.warn("Executer "~name~", thread "~Thread.getThis().name~" stopped");
                    return;
                }
                scheduler.subtaskActivated(t); // rm?
                t.execute(true);
                scheduler.subtaskDeactivated(t); // rm?
                log.info("Main thread "~Thread.getThis().name~" finished task "~t.taskName);
            }
            catch(Exception e) {
                log.error("exception in main thread ");
                Stdout(e)(" at ")(e.file)(":")(e.line).newline;
                runLevel=SchedulerRunLevel.Stopped;
            }
        }
    }
    /// returns the next task, blocks unless the scheduler is stopped
    TaskI nextTask(){
        return null;
    }
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st) { }
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st) { }
    /// returns the executer for this task
    ExecuterI executer() { return this; }
    /// returns the executer for this task
    void executer(ExecuterI e) {
        throw new ParaException("cannot set executer of SExecuter",__FILE__,__LINE__);
    }
    /// logger for task/scheduling messages
    Logger logger() { return log; }
    /// yields the current fiber if the scheduler is not sequential
    void yield() { }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){
        return 1;
    }
    /// number of tasks (unknown if simple or not) wanted
    int nTaskWanted(){
        return 1;
    }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued() { return true; }
    /// executer log
    Logger execLogger(){ return log; }
}


class PExecuter:ExecuterI{
    /// number of processors (used as hint for the number of tasks)
    int nproc;
    /// worker threads
    Thread[] workers;
    /// logger for problems/info
    Logger log;
    /// root task
    TaskSchedulerI _scheduler;
    /// name of the executer
    char[] _name;
    /// name accessor
    char[] name(){
        return _name;
    }
    TaskSchedulerI scheduler(){ return _scheduler; }
    /// creates a new executer
    this(char[] name,TaskSchedulerI scheduler=null,int nproc=-1,char[]loggerPath="blip.parallel.exec"){
        this._name=name;
        this._scheduler=scheduler;
        if (scheduler is null) {
            this._scheduler=new PriQTaskScheduler(this.name~"sched");
        }
        this.scheduler.executer=this;
        if (nproc<1){
            // try to figure it out
            this.nproc=2;
        } else {
            this.nproc=nproc;
        }
        assert(this.nproc>0,"nproc must be at least 1");
        log=Log.lookup(loggerPath);
        workers=new Thread[this.nproc];
        for(int i=0;i<this.nproc;++i){
            workers[i]=new Thread(&(this.workThreadJob),16*8192);
            workers[i].isDaemon=true;
            workers[i].name="worker-"~ctfe_i2a(i);
            workers[i].start();
        }
    }
    /// the job of the worker threads
    void workThreadJob(){
        log.info("Work thread "~Thread.getThis().name~" started");
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                log.info("Work thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) return;
                t.execute(false);
                scheduler.subtaskDeactivated(t);
                log.info("Work thread "~Thread.getThis().name~" finished task "~t.taskName);
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                Stdout(e)(" at ")(e.file)(":")(e.line).newline;
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
        log.info("Work thread ".dup~Thread.getThis().name~" stopped");
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    Print!(char) desc(Print!(char)s){ return desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s,bool shortVersion){
        s.format("<PExecuter@{}",cast(void*)this);
        if (shortVersion) {
            s(" >");
            return s;
        }
        s.newline;
        s("  nproc:")(nproc)(",").newline;
        s("  workers:")(workers)(",").newline;
        writeDesc(scheduler,s("  scheduler:"))(",").newline;
        s("  log:")(log)(",").newline;
        s(" >").newline;
        return s;
    }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){
        return nproc;
    }
    /// number of tasks (unknown if simple or not) wanted
    int nTaskWanted(){
        return min(2,nproc);
    }
    /// logger for task execution messages
    Logger execLogger(){
        return log;
    }
}

