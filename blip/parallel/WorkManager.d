/// module of the singleton (one per process) WorkManager
/// WorkManager handles the working threads and will take care of interprocess load balancing
module blip.parallel.WorkManager;
import tango.io.protocol.model.IWriter;
import tango.io.protocol.model.IReader;
import tango.core.Thread;
import tango.core.Variant:Variant;
import tango.core.sync.Mutex;
import tango.math.Math;
import tango.io.Stdout;
import tango.util.log.Log;
import tango.util.container.HashSet;
import tango.util.container.LinkedList;
import tango.io.Print;
import blip.Stringify;
import blip.parallel.NRMutex;
import blip.TemplateFu:ctfe_i2a;
// more debugging friendly
version=NonFinishedList;

/// a fiber if work manager is parallel, a simple delegate call if not
/// this allows to easily remove the depenedence of fibers in most cases
struct YieldableCall{
    void delegate() dlg;
    size_t stack_size;
    bool mightYield;
    static YieldableCall opCall(void delegate() dlg,bool mightYield=true, size_t stack_size=1024*1024){
        YieldableCall res;
        res.dlg=dlg;
        res.stack_size=stack_size;
        res.mightYield=mightYield;
        return res;
    }
    /// returns a new fiber that performs the call
    Fiber fiber(){
        return new Fiber(this.dlg,this.stack_size);
    }
}

/// a simple priority queue optimized for adding high priority tasks
/// the public interface consists of
/// - insert (insert a new element )
class PriQueue(T){
    /// stores all the elements with a given level
    class PriQLevel{
        int level;
        int start,nEl;
        T[] entries;
        PriQLevel subLevel;
        this(int level,PriQLevel subLevel=null,int capacity=10){
            this.level=level;
            this.entries=new T[max(1,capacity)];
            this.start=0;
            this.nEl=0;
            this.subLevel=subLevel;
        }
        /// adds a new element at the end of the level
        void append(T e){
            if (nEl==entries.length){
                int oldSize=entries.length;
                entries.length=3*entries.length/2+1;
                for (int i=0;i!=start;i++){
                    entries[oldSize]=entries[i];
                    entries[i]=null;
                    ++oldSize;
                    if (oldSize==entries.length) oldSize=0;
                }
            }
            entries[(start+nEl)%entries.length]=e;
            ++nEl;
        }
        /// peek the next element in the level
        T peek(){ if (nEl<1) return null; return entries[start]; }
        /// return the next element and removes it
        T pop(){
            if (nEl<1) return null;
            T res=entries[start]; entries[start]=null;
            ++start; --nEl;
            if (start==entries.length) start=0;
            return res;
        }
        /// description (for debugging)
        char[] toString(){
            return getString(desc(new Stringify()).newline);
        }
        /// description (for debugging)
        Print!(char) desc(Print!(char)s){
            s.format("<PriQLevel@{} level={} entries=[",cast(void*)this,level);
            if (nEl>entries.length){
                s("*ERROR* nEl=")(nEl);
            } else {
                for (int i=0;i<nEl;++i){
                    if (i!=0) s(", ");
                    writeDesc(entries[(start+i)%entries.length],s);
                }
            }
            s("] capacity=")(entries.length)(" >").newline;
            return s;
        }
    }
    /// pool to recycle PriQLevels
    class PriQPool{
        PriQLevel lastE;
        /// returns a PriQLevel to the pool for recycling
        void giveBack(PriQLevel l){ assert(l); l.subLevel=lastE; lastE=l; }
        /// creates a PriQLevel, if possible recycling an old one.
        /// if recycled the capacity is ignored
        PriQLevel create(int level,PriQLevel subLevel=null,int capacity=10){
            if (lastE !is null){
                PriQLevel res=lastE;
                lastE=lastE.subLevel;
                res.level=level;
                res.subLevel=subLevel;
                return res;
            }
            return new PriQLevel(level,subLevel,capacity);
        }
        /// creates the pool
        this(){
            lastE=null;
        }
        /// description (for debugging)
        char[] toString(){
            return getString(desc(new Stringify()).newline);
        }
        /// description (for debugging)
        Print!(char) desc(Print!(char)s){
            if (this is null){
                s("<PriQPool *NULL*>").newline;
            } else {
                s.format("<PriQPool@{} entries=[",cast(void*)this);
                PriQLevel el=lastE;
                while(el !is null){
                    if (el !is lastE) s(", ");
                    s.format("<PriQLevel@{}",cast(void *)el);
                    el=el.subLevel;
                }
                s("] >").newline;
            }
            return s;
        }
    }
    /// level pool
    PriQPool lPool;
    /// queue (highest level)
    PriQLevel queue;
    /// total number of entries
    int nEntries;
    /// if the queue should stop
    bool shouldStop;
    /// lock for queue modifications
    Mutex queueLock;
    /// to make the threads wait when no tasks are available
    /// use a Condition instead? (on mac I should test them, I strongly suspect they don't work);
    NRMutex zeroLock;
    /// creates a new piriority queue
    this(){
        nEntries=0;
        queue=null;
        shouldStop=false;
        queueLock=new Mutex();
        zeroLock=new NRMutex();
        zeroLock.lock();
        lPool=new PriQPool();
    }
    /// shuts down the priority queue
    void stop(){
        bool unlockZero=false;
        synchronized(queueLock){
            shouldStop=true;
            if (nEntries==0) unlockZero=true;
        }
        if (unlockZero) zeroLock.unlock;
    }
    /// adds the given task to the queue with the given level (threadsafe)
    void insert(int tLevel,T t){
        // desc(Stdout("queue pre insert:")).newline;
        synchronized(queueLock){
            PriQLevel oldL=queue,lAtt=queue;
            while (lAtt !is null && lAtt.level>tLevel) {
                oldL=lAtt;
                lAtt=lAtt.subLevel;
            }
            if (lAtt !is null && lAtt.level==tLevel){
                lAtt.append(t);
            } else {
                PriQLevel newL=lPool.create(tLevel,lAtt);
                newL.append(t);
                if (oldL is lAtt) {
                    queue=newL;
                } else {
                    oldL.subLevel=newL;
                }
            }
            ++nEntries;
            //Stdout("XXX pushed ")(t.taskName)(nEntries).newline;
            // desc(Stdout("queue post insert:")).newline;
            if (nEntries==1) zeroLock.unlock;
        }
    }
    /// remove the next task from the queue and returns it
    /// locks if no tasks are available, returns null if and only if shouldStop is true
    /// threadsafe
    T popNext(){
        bool shouldLockZero=false;
        while(1){
            if (shouldStop) return null;
            synchronized(queueLock){
                if (nEntries>0){
                    if (shouldStop) return null;
                    assert(queue !is null);
                    Task res=queue.pop();
                    assert(res!is null);
                    if (queue.nEl==0){
                        PriQLevel nT=queue.subLevel;
                        lPool.giveBack(queue);
                        queue=nT;
                    }
                    --nEntries;
                    if (nEntries==0) zeroLock.lock;
                    //Stdout("XXX popping ")(res.taskName)(nEntries).newline;
                    return res;
                } else {
                    shouldLockZero=true;
                    assert(queue is null);
                }
            }
            if (shouldLockZero) {
                zeroLock.lock;
                zeroLock.unlock;
                shouldLockZero=false;
            }
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other thread modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s){
        if (this is null){
            s("<PriQueue *NULL*>").newline;
        } else {
            s.format("<PriQueue@{} nEntries={},",cast(void*)this,nEntries).newline;
            writeDesc(lPool,s("  lPool="))(",").newline;
            if (queue is null) {
                s("  queue=*NULL*,").newline;
            } else {
                auto lAtt=queue;
                s("  queue=[");
                while(lAtt !is null){
                    writeDesc(lAtt,s("   "))(",").newline;
                    lAtt=lAtt.subLevel;
                }
                s(" ],").newline;
            }
            s("  shouldStop=")(shouldStop);
            bool qL=queueLock.tryLock();
            if (qL) queueLock.unlock();
            s(" queueLock:");
            if (qL){
                s("unlocked by others");
            } else {
                s("locked by others");
            }
            s(",").newline;
            bool zL=zeroLock.tryLock();
            if (zL) zeroLock.unlock();
            s(" zeroLock:");
            if (zL){
                s("unlocked by others");
            } else {
                s("locked by others");
            }
            s.newline;
            s(" >").newline;
        }
        return s;
    }
}


/// level of simple tasks, tasks with ths level or higher should not spawn
/// other tasks. Tasks with higher level are tasks (like communication) that
/// should be done as soon as possible, even if overlap with other tasks is
/// then needed
const int SimpleTaskLevel=int.max/2;

enum TaskSetStatus:int{
    Building=-1,
    NonStarted=0,
    Started=1,
    WaitingEnd=2,
    PostExec=3,
    Finished=4
}

Task defaultTask;

class Task{
    int level; /// priority level of the task, the higher the better
    TaskSetStatus status; /// execution status of the task
    void delegate() taskOp; /// task to execute
    bool delegate() generator; /// generator to run
    Fiber fiber; /// fiber to run
    LinkedList!(void delegate()) onFinish; /// actions to execute sequentially at the end of the task
    Task superTask; /// super task of this task
    char[] taskName; /// name of the task
    bool resubmit; /// if the task should be resubmitted
    bool holdSubtasks; /// if subtasks should be kept on hold
    Task[] holdedSubtasks; /// the subtasks on hold
    int spawnTasks; /// number of spawn tasks
    int finishedTasks; /// number of finished subtasks
    Mutex taskLock; /// lock to update task numbers and status
    WorkManager workManager; /// work manager of the current task
    bool mightSpawn; /// if the task might spawn other subtasks
    bool mightYield; /// if the task might be yielded
    NRMutex waitLock; /// lock to wait for task end
    LinkedList!(Variant) variants; /// variants to help with full closures and gc
    
    /// constructor (with single delegate)
    this(char[] name, void delegate() taskOp,bool mightSpawn=true){
        this(name,taskOp,cast(Fiber)null,cast(bool delegate())null, mightSpawn);
    }
    /// constructor with a possibly yieldable call
    this(char[] name, YieldableCall c,bool mightSpawn=true){
        version(SequentialWorkManager){
            this(name,c.dlg,cast(Fiber)null,cast(bool delegate())null, mightSpawn);
            mightYield=c.mightYield;
        } else {
            if (! c.mightYield){
                this(name,c.dlg,cast(Fiber)null,cast(bool delegate())null, mightSpawn);
            } else {
                this(name,&runFiber,c.fiber(),cast(bool delegate())null, mightSpawn);
            }
        }
    }
    /// constructor (with fiber)
    this(char[] name,Fiber fiber,bool mightSpawn=true){
        this(name,&runFiber,fiber,cast(bool delegate())null, mightSpawn);
    }
    /// constructor (with genrator)
    this(char[] name, bool delegate() generator,bool mightSpawn=true){
        this(name,&runGenerator,cast(Fiber)null,generator, mightSpawn);
    }
    /// general constructor
    this(char[] name, void delegate() taskOp,Fiber fiber,
        bool delegate() generator, bool mightSpawn=true){
        assert(taskOp !is null);
        this.level=0;
        this.taskName=name;
        this.taskOp=taskOp;
        this.fiber=fiber;
        this.generator=generator;
        this.onFinish=new LinkedList!(void delegate())();
        this.superTask=null;
        this.workManager=null;
        this.resubmit=false;
        this.holdSubtasks=false;
        this.holdedSubtasks=[];
        this.taskLock=new Mutex();
        this.status=TaskSetStatus.Building;
        this.spawnTasks=0;
        this.finishedTasks=0;
        this.mightSpawn=mightSpawn;
        this.variants=new LinkedList!(Variant)();
        this.mightYield=fiber !is null;
    }
    /// has value for tasks
    uint getHash(){
        return cast(uint)(cast(void*)this);
    }
    /// equality of tasks
    override int opEquals(Object o){ return (o is this); }
    /// executes the actual task (after all the required setup)
    void internalExe(){
        taskOp();
        assert(taskOp !is null);
    }
    /// executes the task (called by the executing thread, performs all setups)
    /// be careful overriding this (probably you should override internalExe)
    void execute(){
        if (status==TaskSetStatus.NonStarted){
            synchronized(taskLock) {
                assert(status==TaskSetStatus.NonStarted);
                status=TaskSetStatus.Started;
            }
        }
        if (status==TaskSetStatus.Started){
            {
                scope(exit){
                    taskAtt.val=defaultTask;
                }
                taskAtt.val=this;
                internalExe();
            }
            if (resubmit) {
                workManager.addTask(this);
            } else {
                startWaiting();
            }
        } else {
            assert(0,"unexpected status in excute: "~status.stringof);
        }
    }
    /// called when the main task is finished, and should start waiting for
    /// the subtasks..
    void startWaiting(){
        assert(status==TaskSetStatus.Started);
        status=TaskSetStatus.WaitingEnd;
        bool callOnFinish=false;
        synchronized(taskLock){
            if (status==TaskSetStatus.WaitingEnd && spawnTasks==finishedTasks){
                status=TaskSetStatus.PostExec;
                callOnFinish=true;
            }
        }
        if (callOnFinish){
            finishTask();
        }
    }
    /// called after the task (and all its subtasks) have finished
    /// runs onFinish, and then tells supertask, and remove task from running ones
    void finishTask()
    {
        {
            scope(exit){
                taskAtt.val=defaultTask;
            }
            taskAtt.val=this;
            assert(status==TaskSetStatus.PostExec);
            if (onFinish !is null) {
                foreach(t;onFinish){
                    t();
                }
            }
            synchronized(taskLock){
                assert(status==TaskSetStatus.PostExec);
                status=TaskSetStatus.Finished;
                if (waitLock !is null) waitLock.unlock();
            }
        }
        if (superTask !is null){
            superTask.subtaskEnded(this);
        }
        version(NonFinishedList){
            bool found;
            synchronized(workManager.nonFinishedTasksLock){
                found=workManager.nonFinishedTasks.remove(this);
            }
            assert(found);
        }
    }
    /// called when a subtasks has finished
    void subtaskEnded(Task st){
        bool callOnFinish=false;
        synchronized(taskLock){
            ++finishedTasks;
            if (status==TaskSetStatus.WaitingEnd && spawnTasks==finishedTasks){
                status=TaskSetStatus.PostExec;
                callOnFinish=true;
            }
        }
        if (callOnFinish){
            finishTask();
        }
    }
    /// called before spawning a new subtask
    void willSpawn(Task st){
        synchronized(taskLock){
            ++spawnTasks;
        }
    }
    /// operation that spawn the given task as subtask of this one
    void spawnTask(Task task){
        assert(mightSpawn,"task '"~taskName~"' tried to spawn '"~task.taskName~"' and has mightSpawn false");
        assert(task.status==TaskSetStatus.Building,"spawnTask argument should have building status");
        if (task.superTask is null) task.superTask=this;
        assert(task.superTask is this,"task '"~taskName~"' tried to spawn '"~task.taskName~"' that has different superTask");
        if (task.workManager is null) task.workManager=workManager;
        assert(task.workManager is workManager,"task '"~taskName~"' tried to spawn '"~task.taskName~"' that has different workManager");
        if (task.mightSpawn){
            task.level+=level+1;
        } else {
            task.level+=SimpleTaskLevel;
        }
        task.status=TaskSetStatus.NonStarted;
        willSpawn(task);
        if (holdSubtasks){
            holdedSubtasks~=task;
        } else {
            workManager.addTask(task);
        }
    }
    /// runs the fiber (can be used as taskOp)
    void runFiber(){
        assert(fiber !is null);
        if (fiber.state==Fiber.State.TERM){
            resubmit=false;
            return;
        }
        fiber.call;
        resubmit=(fiber.state!=Fiber.State.TERM);
    }
    /// runs the generator (can be used as taskOp)
    void runGenerator(){
        assert(generator!is null);
        resubmit=generator();
    }
    /// returns the number of variant
    uint nVariants(){
        return variants.size();
    }
    
    // ------------------------ task setup ops -----------------------
    /// adds an onFinish operation
    Task appendOnFinish(void delegate() onF) {
        assert(status==TaskSetStatus.Building,"appendOnFinish allowed only during task building"); // change?
        onFinish.append(onF);
        return this;
    }
    /// adds a variant
    Task appendVariant(Variant v) {
        assert(status==TaskSetStatus.Building,"appendVariant allowed only during task building"); // change?
        variants.append(v);
        return this;
    }
    /// changes the level of the task (before submittal)
    Task changeLevel(int dl){
        assert(status==TaskSetStatus.Building,"changeLevel allowed only during task building");
        level+=dl;
        return this;
    }
    /// holds all the tasks (can be called also when the task is running)
    Task holdSub(){
        synchronized(taskLock){ // should not be needed
            holdSubtasks=true;
        }
        return this;
    }
    /// lets the holded tasks run (can be called also when the task is running)
    Task releaseSub(){
        Task[] tToRel;
        synchronized(taskLock){ // should not be needed
            holdSubtasks=false;
            tToRel=holdedSubtasks;
            holdedSubtasks=[];
        }
        foreach(t;tToRel){
            workManager.addTask(t);
        }
        return this;
    }
    /// submits this task (with the given supertask, or with the actual task as supertask)
    Task submit(Task superTask=null){
        if (superTask !is null){
            assert(this.superTask is null || this.superTask is superTask,"superTask was already set");
            this.superTask=superTask;
        }
        if (this.superTask is null){
            if (workManager !is null){
                this.superTask=workManager.rootTask;
            } else {
                this.superTask=taskAtt.val;
            }
        }
        this.superTask.spawnTask(this);
        return this;
    }
    /// submits the current task and yields the current one (if not SequentialWorkManager)
    /// needs a Fiber or Yieldable task
    Task submitYield(Task superTask=null){
        submit(superTask);
        if ((! this.superTask.mightYield) && (cast(RootTask)this.superTask)is null){
            throw new Exception(taskName~" submitYield called with non yieldable supertask ("~this.superTask.taskName~")"); // allow?
        }
        version(SequentialWorkManager){}
        else {
            if ((cast(RootTask)this.superTask)is null)
                Fiber.yield();
        }
        return this;
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s,bool shortVersion=true){
        if (this is null){
            s("<Task *NULL*>").newline;
        } else {
            s("<")(this.classinfo.name).format("@{} '{}' status:",cast(void*)this,taskName);
            s(status.stringof);
            if (shortVersion) {
                s(" >");
                return s;
            }
            s.newline;
            fieldsDesc(s);
            s(" >").newline;
        }
        return s;
    }
    /// prints the fields (superclasses can override this an call it through super)
    Print!(char) fieldsDesc(Print!(char)s){
        s("  level=")(level)(",").newline;
        s("  taskOp:");
        if (taskOp is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  fiber:");
        if (fiber is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  generator:");
        if (generator is null)
            s("*NULL*");
        else
            s("associated");
        s(",").newline;
        s("  onFinish:[");
        bool atStart=true;
        foreach (t;onFinish){
            if (!atStart) s(", ");
            atStart=true;
            if (t is null)
                s("*NULL*");
            else
                s("associated");
        }
        s("],").newline;
        writeDesc(superTask,s("  superTask="),true)(",").newline;
        s("  resubmit:")(resubmit)(",").newline;
        s("  holdSubtasks:")(holdSubtasks)(",").newline;
        s("  holdedSubtasks:")(holdedSubtasks)(",").newline;
        s("  spawnTasks:")(spawnTasks)(",").newline;
        s("  finishedTasks:")(finishedTasks)(",").newline;
        writeDesc(workManager,s("  workManager:"),true)(",").newline;
        bool lokD=taskLock.tryLock();
        if (lokD) taskLock.unlock();
        s("  taskLock:");
        if (lokD)
            s("locked by others");
        else
            s("unlocked by others");
        s(",").newline;
        s("  mightSpawn:")(mightSpawn);
        return s;
    }
    /// waits for the task to finish
    void wait(){
        if (status!=TaskSetStatus.Finished && waitLock is null) {
            synchronized(taskLock) {
                 if (status!=TaskSetStatus.Finished && waitLock is null) {
                     waitLock=new NRMutex();
                     waitLock.lock();
                 }
            }
        }
        if (status!=TaskSetStatus.Finished) {
            waitLock.lock();
            waitLock.unlock();
        }
    }
}

/// a task that does nothing
class EmptyTask: Task{
    this(char[] name="EmptyTask", bool mightSpawn=false){
        super(name,&internalExe,mightSpawn);
    }
    override void internalExe(){ }
}

/// root pseudo task
/// is not executed itself, but is the supertask of other tasks
class RootTask: Task{
    Logger log;
    bool warnSpawn;
    this(WorkManager workManager, int level=0, char[] name="RootTask", bool warnSpawn=false){
        super(name,&execute,true);
        this.workManager=workManager;
        this.level=level;
        this.status=TaskSetStatus.Started;
        log=Log.lookup("blip.parallel."~name);
        this.warnSpawn=warnSpawn;
    }
    override void internalExe(){
        log.error("root task '"~taskName~"' should not be executed");
        assert(0,"root task '"~taskName~"' should not be executed");
    }
    override void willSpawn(Task t){
        if (warnSpawn)
            log.warn("root task '"~taskName~"' spawned task "~t.taskName);
        super.willSpawn(t);
    }
}

/// thread local data to store current task
ThreadLocal!(Task) taskAtt;

class TaskSet:Task{
    long subCost;
    /// constructor with a possibly yieldable call
    this(char[] name, YieldableCall c,bool mightSpawn=true){
        assert(c.mightYield,"TaskSet should generate tasks...");
        super(name,c,mightSpawn);
    }
    this(char[] name, bool delegate() gen) {
        super(name, gen, true);
    }

    this(char[] name, Fiber fib) {
        super(name, fib, true);
    }
    
    /// generates a subtasks (returns true if successful), does not resubmit itself
    Task generate(){
        Task res=null;
        if (status==TaskSetStatus.NonStarted){
            synchronized(taskLock) {
                assert(status==TaskSetStatus.NonStarted);
                status=TaskSetStatus.Started;
            }
        }
        if (status==TaskSetStatus.Started){
            {
                scope(exit){
                    taskAtt.val=defaultTask;
                }
                taskAtt.val=this;
                res=internalGen();
            }
        }
        return res;
    }
    /// generate a task and returns it (null if not tasks are left)
    Task internalGen(){
        Task res=null;
        bool hold=!holdSubtasks;
        if (hold) holdSub();
        int nHolded=holdedSubtasks.length;
        taskOp();
        if (nHolded<holdedSubtasks.length){
            assert(nHolded+1==holdedSubtasks.length,"generated more than one task");
            res=holdedSubtasks[$];
        }
        if (hold) releaseSub();
        if (!resubmit) {
            startWaiting();
        }
        return res;
    }
    // generate nproc subtasks
    override void internalExe(){
        int maxQueued=workManager.nproc*2;
        long maxCost=subCost+workManager.nproc;
        do{
            taskOp();
            if (!resubmit) break;
        } while (maxQueued-workManager.queue.nEntries>0 && subCost<maxCost)
    }
    override void willSpawn(Task t){
        long cost=1;
        if (t.mightSpawn) cost+=workManager.nproc/2;
        if (cast(TaskSet)t) cost+=(workManager.nproc+1)/2;
        synchronized(taskLock){
            subCost+=cost;
        }
        super.willSpawn(t);
    }
}

class WorkManager{
    /// number of processors (used as hint for the number of tasks)
    int nproc;
    /// worker threads
    Thread[] workers;
    /// register for relocatable tasks
    TTaskRegister taskRegister;
    /// queue for tasks that are locally executing
    PriQueue!(Task) queue;
    /// logger for problems/info
    Logger log;
    /// root task
    Task rootTask;
    version(NonFinishedList){
        /// nonFinishedTasks (mostly for debugging purposes)
        HashSet!(Task) nonFinishedTasks;
        /// nonFinishedTasks lock
        Mutex nonFinishedTasksLock;
    }
    /// creates a new workManager
    this(int nproc=-1){
        if (nproc<1){
            // try to figure it out
            this.nproc=2;
        } else {
            this.nproc=nproc;
        }
        nonFinishedTasksLock=new Mutex();
        nonFinishedTasks=new HashSet!(Task)();
        queue=new PriQueue!(Task)();
        taskRegister=new TTaskRegister();
        log=Log.lookup("blip.parallel");
        rootTask=new RootTask(this);
        version(SequentialWorkManager){
            workers=[];
        } else {
            workers=new Thread[this.nproc];
            for(int i=0;i<this.nproc;++i){
                workers[i]=new Thread(&(this.workThreadJob),16*8192);
                workers[i].isDaemon=true;
                workers[i].name="worker-"~ctfe_i2a(i);
                workers[i].start();
            }
        }
    }
    /// the job of the worker threads
    void workThreadJob(){
        log.info("Work thread "~Thread.getThis().name~" started");
        while(1){
            try{
                Task t=queue.popNext();
                log.info("Work thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) return;
                t.execute();
                log.info("Work thread "~Thread.getThis().name~" finished task "~t.taskName);
            }
            catch(Exception e) {
                log.error("exception in working thread ");
                Stdout(e)(" at ")(e.file)(":")(e.line).newline;
                queue.stop();
            }
        }
        log.info("Work thread ".dup~Thread.getThis().name~" stopped");
    }
    /// adds a task to be executed
    void addTask(Task t){
        assert(t.status==TaskSetStatus.NonStarted ||
            t.status==TaskSetStatus.Started,"initial");
        version(NonFinishedList){
            if (t.status==TaskSetStatus.NonStarted) {
                synchronized(nonFinishedTasksLock){
                    nonFinishedTasks.add(t);
                }
            }
        }
        log.info("task "~t.taskName~" will be added to queue");
        version (SequentialWorkManager){
            try{
                log.info("Main thread "~Thread.getThis().name~" starting task "~
                    (t is null?"*NULL*":t.taskName));
                if (t is null) return;
                t.execute();
                log.info("Main thread "~Thread.getThis().name~" finished task "~t.taskName);
            }
            catch(Exception e) {
                log.error("exception in main thread ");
                Stdout(e)(" at ")(e.file)(":")(e.line).newline;
                throw e;
            }
        } else{
            queue.insert(t.level,t);
        }
    }
    /// description (for debugging)
    /// non threadsafe
    char[] toString(){
        return getString(desc(new Stringify()).newline);
    }
    /// description (for debugging)
    /// (might not be a snapshot if other threads modify it while printing)
    /// non threadsafe
    Print!(char) desc(Print!(char)s,bool shortVersion=false){
        if (this is null){
            s("<WorkManager *NULL*>").newline;
        } else {
            s.format("<WorkManager@{}",cast(void*)this);
            if (shortVersion) {
                s(" >");
                return s;
            }
            s.newline;
            s("  nproc:")(nproc)(",").newline;
            s("  workers:")(workers)(",").newline;
            s("  taskRegister:")(taskRegister)(",").newline;
            s("  queue:")(queue)(",").newline;
            s("  log:")(log)(",").newline;
            version(NonFinishedList){
                s("  nonFinishedTasks:[").newline;
                s("    ");
                bool nonFirst=false;
                foreach (t;nonFinishedTasks){
                    if (nonFirst) { s(",").newline; nonFirst=false; }
                    writeDesc(t,s("    "),true);
                }
                s.newline;
                s("  ],").newline;
                bool lokD=nonFinishedTasksLock.tryLock();
                if (lokD) nonFinishedTasksLock.unlock();
                s("  nonFinishedTasksLock:");
                if (lokD)
                    s("locked by others");
                else
                    s("unlocked by others");
                s(",").newline;
            }
            writeDesc(rootTask,s("  rootTask:")).newline;
            s(" >").newline;
        }
        return s;
    }
}

// task register
class TTaskRegister{
    this() { }
    // char[TransferrableTaskSet] id2Task;
    // char[TransferrableTaskSet[]] kind2Tasks;
    // void registerTask(TransferrableTaskSet task);
    // void unregisterTask(TransferrableTaskSet task);
    // TransferrableTaskSet getTask(char[]kind,char[]name);
    // TransferrableTaskSet getTask(char[]id);
    // TTaskSetIter getTaskOfKind(char[]kind); // copy?
    // TransferrableTaskSet getLargestTaskOfKind(char[]kind);
    // TTaskSetIter getAllTasks();
}

struct TransferCost{
    float transferSize; // this might include also transfer of extra data done by the task
    float sizeWorkRatio;
}

/// tasks that can be transferred between computers
interface TransferrableTaskSet:IWritable,IReadable{
    /// kind of the task
    char[] taskKind();
    /// task name locally unique
    char[] taskName();
    /// gobally unique
    char[] taskId();
    /// work remaining
    float restWork();
    /// units of work (taskName is probably a good choice if you don't know the unit)
    char[] workUnit();
    /// minimum reasonable transfer amount
    float minTransferAmount();
    /// expected transfer cost 
    TransferCost transferCost(float amount=0.5f);
    /// writes a task set to the given channel (tries to dump the given fraction of tasks)
    /// a negative amount means a ratio. Returns the actual amount transferred
    float tansferTasks(IWriter channel,float amount=-0.5f,bool roundDown=true);
    /// if the task can checkpoint (i.e. dump its value, read it back, even on another process,
    /// and continue)
    bool canCheckpoint();
    /// if the task can be restarted from scratch or a previous dump
    /// (i.e. partial results can be safely discarded and recovered)
    bool canRestart();
}

WorkManager defaultWorkManager;

static this(){
    defaultWorkManager=new WorkManager();
    defaultTask=new RootTask(defaultWorkManager,0,"defaultTask",true);
    taskAtt=new ThreadLocal!(Task)(defaultTask);
}
