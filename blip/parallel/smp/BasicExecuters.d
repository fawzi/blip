/// executers (sequential and parallel)
/// For the parallel ones by default now the NumaSchedulers & executers are used.
/// these still can be useful though. Beware possible subtle differences.
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
module blip.parallel.smp.BasicExecuters;
import blip.core.Thread;
import blip.core.Traits: ctfe_i2s;
import blip.math.Math;
import blip.math.random.Random;
import blip.io.Console;
import blip.util.TangoLog;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicSchedulers;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.PriQueue;
import blip.BasicModels;
import blip.parallel.smp.Numa;
import blip.container.Cache;
import blip.Comp;

shared static this(){
    version(DetailedLog){
        Log.lookup("blip.parallel.smp.exec").level(Logger.Level.Info,true);
    } else {
        Log.lookup("blip.parallel.smp.exec").level(Logger.Level.Warn,true);
    }
}

/// executes the task immediately in the current context
class ImmediateExecuter:ExecuterI,TaskSchedulerI,SchedGroupI{
    /// logger for problems/info
    Logger log;
    /// run level
    SchedulerRunLevel runLevel;
    /// root task
    TaskI _rootTask;
    ///  returns the root task
    @property TaskI rootTask(){ return _rootTask; }
    /// name of the executer
    string _name;
    Cache _nnCache;
    RandomSync _rand;
    SchedGroupI _schedGroup;
    TaskSchedulerI[1] _activeSchedulers;
    /// returns a random source for scheduling
    @property final RandomSync rand(){ return _rand; }
    /// name accessor
    @property string name(){
        return _name;
    }
    @property Cache nnCache(){
        auto tAtt=taskAtt;
        if (tAtt!is null && tAtt.superTask !is null && tAtt.superTask.scheduler !is this){
            return tAtt.superTask.scheduler.nnCache();
        } else {
            if (_nnCache is null){
                synchronized(this){
                    if (_nnCache is null){
                        _nnCache=new Cache();
                    }
                }
            }
            return _nnCache;
        }
    }
    /// creates a new executer
    this(string name,string loggerPath="blip.parallel.smp.exec"){
        this._name=name;
        log=Log.lookup(loggerPath);
        runLevel=SchedulerRunLevel.Running;
        _rand=new RandomSync();
        _rootTask=new RootTask(this,0,name~"DefaultTask",false);
        _schedGroup=this;
        _activeSchedulers[0]=this;
    }
    /// returns the scheduler (itself in this case)
    @property TaskSchedulerI scheduler(){
        return this;
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(scope void delegate(in cstring) s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope void delegate(in cstring) s,bool shortVersion){
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
    /// logging a message
    void logMsg(in cstring m){
        log.info(m);
    }
    /// adds a task to the scheduler queue
    void addTask(TaskI t){
        if (runLevel!=SchedulerRunLevel.Stopped){
            try{
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        dumper(s)("Executer ")(name)(", thread ")(Thread.getThis().name)(" starting task ")(t); });
                }
                if (t is null) {
                    log.warn("Executer "~name~", thread "~Thread.getThis().name~" stopped");
                    return;
                }
                scheduler.subtaskActivated(t); // rm?
                t.execute(true);
                scheduler.subtaskDeactivated(t); // rm?
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){ // task retain release is ok???
                        dumper(s)("Thread ")(Thread.getThis().name)(" finished task ")(t); });
                }
            }
            catch(Exception e) {
                log.error("exception in main thread ");
                sout(e);
                soutStream.flush();
                runLevel=SchedulerRunLevel.Stopped;
            }
        }
    }
    // alias addTask addTask0;
    void addTask0(TaskI t){
        addTask(t);
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
    @property ExecuterI executer() { return this; }
    /// returns the executer for this task
    @property void executer(ExecuterI e) {
        throw new ParaException("cannot set executer of ImmediateExecuter",__FILE__,__LINE__);
    }
    /// logger for task/scheduling messages
    @property Logger logger() { return log; }
    /// yields the current fiber if the scheduler is not sequential
    void yield() { }
    /// yields the current fiber if the scheduler is not sequential
    void maybeYield() { }
    /// number of simple tasks wanted
    @property int nSimpleTasksWanted(){
        return 1;
    }
    /// number of tasks (unknown if simple or not) wanted
    @property int nTaskWanted(){
        return 1;
    }
    /// if there are many queued tasks (and one should try not to queue too many of them)
    @property bool manyQueued() { return true; }
    /// executer log
    @property Logger execLogger(){ return log; }
    /// group of this scheduler, this can be used to deterministically distribute work
    @property SchedGroupI schedGroup(){ return _schedGroup; }
    
    // schedGroupI
    /// activate all possible schedulers in the current group
    void activateAll() { }
    /// returns the currently active schedulers
    @property TaskSchedulerI[] activeScheds() {
        return _activeSchedulers;
    }
    /// logger for the group
    @property Logger groupLogger() {
        return log;
    }
    /// global root task (should submit to the least used scheduler)
    @property TaskI gRootTask() {
        return rootTask();
    }
    /// root task for things that should ideally be executed only if executers are idle
    @property TaskI onStarvingTask(){
        return rootTask();
    }
}


class PExecuter:ExecuterI,SchedGroupI{
    /// number of processors (used as hint for the number of tasks)
    int nproc;
    /// worker threads
    Thread[] workers;
    /// logger for problems/info
    Logger log;
    /// root task
    TaskSchedulerI[1] _scheduler;
    /// name of the executer
    string _name;
    /// name accessor
    @property string name(){
        return _name;
    }
    /// logs a message
    void logMsg(in cstring m){
        log.info(m);
    }
    @property TaskSchedulerI scheduler(){ return _scheduler[0]; }
    /// creates a new executer
    this(string name,TaskSchedulerI scheduler=null,int nproc=-1,string loggerPath="blip.parallel.smp.exec"){
        this._name=name;
        this._scheduler[0]=scheduler;
        if (scheduler is null) {
            this._scheduler[0]=new PriQTaskScheduler(this.name~"sched");
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
            workers[i].name(name~"-worker-"~ctfe_i2s(i));
            workers[i].start();
        }
    }
    /// the job of the worker threads
    void workThreadJob(){
        sinkTogether(&logMsg,delegate void(scope CharSink s){
            dumper(s)("Work thread ")(Thread.getThis().name)(" started");
        });
        scope(exit){
            sinkTogether(&logMsg,delegate void(scope CharSink s){
                dumper(s)("Work thread ")(Thread.getThis().name)(" stopped");
            });
        }
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" starting task ")(t);
                    });
                }
                if (t is null) return;
                t.execute(false);
                scheduler.subtaskDeactivated(t);
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(scope CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" finished task ")(t.taskName);
                    });
                }
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                sout(e);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
    }
    /// description (for debugging)
    /// non threadsafe
    string toString(){
        return collectIAppender(cast(OutWriter)&desc);
    }
    /// description (for debugging)
    void desc(scope CharSink s){ desc(s,false); }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    void desc(scope CharSink s,bool shortVersion){
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
    @property int nSimpleTasksWanted(){
        return nproc;
    }
    /// number of tasks (unknown if simple or not) wanted
    @property int nTaskWanted(){
        return min(2,nproc);
    }
    /// logger for task execution messages
    @property Logger execLogger(){
        return log;
    }
    
    /// group of this executer, can be used for deterministic task distribution
    @property SchedGroupI schedGroup(){
        return this;
    }
    // schedGroupI
    /// activate all possible schedulers in the current group
    void activateAll() { }
    /// returns the currently active schedulers
    @property TaskSchedulerI[] activeScheds() {
        return _scheduler;
    }
    /// logger for the group
    @property Logger groupLogger() {
        return log;
    }
    /// global root task (should submit to the least used scheduler)
    @property TaskI gRootTask() {
        return scheduler.rootTask();
    }
    /// root task for things that should ideally be executed only if executers are idle
    @property TaskI onStarvingTask(){
        return scheduler.rootTask();
    }
    
}

