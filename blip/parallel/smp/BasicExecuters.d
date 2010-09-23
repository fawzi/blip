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
import blip.math.Math;
import blip.math.random.Random;
import blip.io.Console;
import blip.util.TangoLog;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.util.TemplateFu:ctfe_i2a;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicSchedulers;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.PriQueue;
import blip.BasicModels;
import blip.parallel.smp.Numa;
import blip.container.Cache;

static this(){
    version(DetailedLog){
        Log.lookup("blip.parallel.smp.exec").level(Logger.Level.Info,true);
    } else {
        Log.lookup("blip.parallel.smp.exec").level(Logger.Level.Warn,true);
    }
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
    Cache _nnCache;
    RandomSync _rand;
    /// returns a random source for scheduling
    final RandomSync rand(){ return _rand; }
    /// name accessor
    char[] name(){
        return _name;
    }
    Cache nnCache(){
        auto tAtt=taskAtt.val;
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
    this(char[] name,char[]loggerPath="blip.parallel.smp.exec"){
        this._name=name;
        log=Log.lookup(loggerPath);
        runLevel=SchedulerRunLevel.Running;
        _rand=new RandomSync();
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
    /// logging a message
    void logMsg(char[]m){
        log.info(m);
    }
    /// adds a task to the scheduler queue
    void addTask(TaskI t){
        if (runLevel!=SchedulerRunLevel.Stopped){
            try{
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(CharSink s){
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
                    sinkTogether(&logMsg,delegate void(CharSink s){ // task retain release is ok???
                        dumper(s)("Thread ")(Thread.getThis().name)(" finished task ")(t); });
                }
            }
            catch(Exception e) {
                log.error("exception in main thread ");
                e.writeOut(sout.call);
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
    /// logs a message
    void logMsg(char[]m){
        log.info(m);
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
        sinkTogether(&logMsg,delegate void(CharSink s){
            dumper(s)("Work thread ")(Thread.getThis().name)(" started");
        });
        scope(exit){
            sinkTogether(&logMsg,delegate void(CharSink s){
                dumper(s)("Work thread ")(Thread.getThis().name)(" stopped");
            });
        }
        while(1){
            try{
                TaskI t=scheduler.nextTask();
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" starting task ")(t);
                    });
                }
                if (t is null) return;
                t.execute(false);
                scheduler.subtaskDeactivated(t);
                version(DetailedLog){
                    sinkTogether(&logMsg,delegate void(CharSink s){
                        dumper(s)("Work thread ")(Thread.getThis().name)(" finished task ")(t.taskName);
                    });
                }
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                e.writeOut(sout.call);
                soutStream.flush();
                scheduler.raiseRunlevel(SchedulerRunLevel.Stopped);
            }
        }
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

