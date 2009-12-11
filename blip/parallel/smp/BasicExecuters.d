/// executers (sequential and parallel)
module blip.parallel.smp.BasicExecuters;
import tango.core.Thread;
import tango.math.Math;
import blip.io.Console;
import blip.t.util.log.Log;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.TemplateFu:ctfe_i2a;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicSchedulers;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.PriQueue;
import blip.BasicModels;
import blip.parallel.smp.Numa;

static this(){
    Log.lookup("blip.parallel.smp.exec").level(Logger.Level.Warn,true);
}

/// executes the task immediately in the current context
class ImmediateExecuter:ExecuterI,TaskSchedulerI{
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
    this(char[] name,char[]loggerPath="blip.parallel.smp.exec"){
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
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(void delegate(char[]) s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) s,bool shortVersion){
        s("<ImmediateExecuter@");
        writeOut(s,cast(void*)this);
        s(" ");
        s(name);
        if (shortVersion) {
            s(" >");
            return;
        }
        s("\n");
        s("  log:"); writeOut(s, log); s(",\n");
        s(" >\n");
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
                e.writeOut(sout.call);
                soutStream.flush();
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
        throw new ParaException("cannot set executer of ImmediateExecuter",__FILE__,__LINE__);
    }
    /// logger for task/scheduling messages
    Logger logger() { return log; }
    /// yields the current fiber if the scheduler is not sequential
    void yield() { }
    /// yields the current fiber if the scheduler is not sequential
    void maybeYield() { }
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
    this(char[] name,TaskSchedulerI scheduler=null,int nproc=-1,char[]loggerPath="blip.parallel.smp.exec"){
        this._name=name;
        this._scheduler=scheduler;
        if (scheduler is null) {
            this._scheduler=new PriQTaskScheduler(this.name~"sched");
        }
        this.scheduler.executer=this;
        if (nproc==-1){
            this.nproc=defaultTopology.nNodes(0);
        } else {
            this.nproc=nproc;
        }
        assert(this.nproc>0,"nproc must be at least 1");
        log=Log.lookup(loggerPath);
        workers=new Thread[this.nproc];
        for(int i=0;i<this.nproc;++i){
            workers[i]=new Thread(&(this.workThreadJob),16*8192);
            workers[i].isDaemon=true;
            workers[i].name=name~"-worker-"~ctfe_i2a(i);
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
                e.writeOut(sout.call);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
        log.info("Work thread ".dup~Thread.getThis().name~" stopped");
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(CharSink s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(CharSink s,bool shortVersion){
        s("<PExecuter@");writeOut(s,cast(void*)this);
        if (shortVersion) {
            s(" >");
            return;
        }
        s("\n");
        s("  nproc:"); writeOut(s,nproc); s(",\n");
        s("  workers:"); writeOut(s,workers); s(",\n");
        s("  scheduler:"); writeOut(s,scheduler); s(",\n");
        s("  log:"); writeOut(s,log); s(",\n");
        s(" >\n");
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

class TWorker{
    ExecuterI executer;
    NumaTopology topology;
    TaskSchedulerI scheduler;
    NumaNode node;
    this(ExecuterI exec,TaskSchedulerI sched,NumaTopology topo,NumaNode n){
        executer=exec;
        scheduler=sched;
        topology=topo;
        node=n;
    }
    /// the job of the worker threads
    void workThreadJob(){
        auto log=executer.execLogger;
        log.info("Work thread "~Thread.getThis().name~" started");
        if (topology.bindToNode(node)){
            log.info(Thread.getThis().name~" bound to node");
        } {
            log.info(Thread.getThis().name~" binding failed");
        }
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
                e.writeOut(sout.call);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
        log.info("Work thread ".dup~Thread.getThis().name~" stopped");
    }
    
}
/// topolgy using executer
class TExecuter:ExecuterI{
    // StarvationManager // to do
    PriQTaskScheduler[NumaNode] schedulers;
    PriQTaskScheduler rootScheduler;
    /// number of processors (used as hint for the number of tasks)
    int nproc;
    /// Numa topology (for executers)
    NumaTopology topology;
    /// worker threads
    Thread[] workers;
    /// logger for problems/info
    Logger log;
    /// name of the executer
    char[] _name;
    /// name accessor
    char[] name(){
        return _name;
    }
    TaskSchedulerI scheduler(){ return rootScheduler; }
    /// creates a new executer
    this(char[] name,NumaTopology topology,char[]loggerPath="blip.parallel.smp.exec"){
        this._name=name;
        int level=topology.maxLevel();
        this.rootScheduler=new PriQTaskScheduler(this.name~"sched_"~ctfe_i2a(level)~"_"~ctfe_i2a(0),
            "blip.parallel.smp.queue",level);
        schedulers[NumaNode(level,0)]=this.rootScheduler;
        this.rootScheduler.level=level;
        this.rootScheduler.executer=this;
        while (level>0){
            --level;
            foreach (nodeAtt;topology.nodes(level)){
                auto superN=topology.superNode(nodeAtt);
                auto superS=schedulers[superN];
                auto newS=new PriQTaskScheduler(this.name~"sched_"~ctfe_i2a(level)~"_"~ctfe_i2a(nodeAtt.pos),
                    "blip.parallel.smp.queue",level,superS);
                schedulers[nodeAtt]=newS;
                newS.executer=this;
            }
        }
        this.topology=topology;
        assert(topology!is null,"a valid topology is needed");
        this.nproc=topology.nNodes(0);
        assert(this.nproc>0,"nproc must be at least 1");
        log=Log.lookup(loggerPath);
        workers=new Thread[this.nproc];
        for(int i=0;i<this.nproc;++i){
            auto nodeAtt=NumaNode(0,i);
            auto closure=new TWorker(this,schedulers[nodeAtt],topology,nodeAtt);
            workers[i]=new Thread(&(closure.workThreadJob),16*8192);
            workers[i].isDaemon=true;
            workers[i].name=name~"-worker-"~ctfe_i2a(i);
            workers[i].start();
        }
    }
    
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return collectAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(void delegate(char[]) s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(void delegate(char[]) s,bool shortVersion){
        s("<TExecuter@"); writeOut(s,cast(void*)this);
        if (shortVersion) {
            s(" >");
            return;
        }
        s("\n");
        s("  nproc:"); writeOut(s,nproc); s(",\n");
        s("  workers:"); writeOut(s,workers); s(",\n");
        s("  scheduler:"); writeOut(s,scheduler); s(",\n");
        s("  log:"); writeOut(s,log); s(",\n");
        s(" >\n");
    }
    /// number of simple tasks wanted
    int nSimpleTasksWanted(){
        return nproc/2+1;
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
