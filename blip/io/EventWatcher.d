/// a module that sets up a libenv based thread that can be used to watch out several events
/// (see DLibev for a list)
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
module blip.io.EventWatcher;
import blip.io.BasicIO;
import blip.io.Console;
import blip.container.GrowableArray;
import blip.container.Deque;
import blip.bindings.ev.DLibev;
import blip.bindings.ev.Libev;
import blip.bindings.ev.EventHandler;
import blip.core.Traits;
import blip.core.Thread;
import blip.parallel.smp.WorkManager;
import blip.core.sync.Semaphore;
import blip.container.HashSet;
import blip.container.Pool;
import blip.container.Cache;
import blip.util.RefCount;
public import blip.bindings.ev.DLibev: GenericWatcher, LoopHandlerI, ev_tstamp;

/// helper struct to wait for an action in an event loop
struct WaitLoopOp{
    TaskI task;
    int delayLevel;
    Semaphore sem;
    void delegate() op;
    void doOp(){
        if (op!is null){ op(); }
        if (task!is null){
            if (task.status>=TaskStatus.Started){
                task.resubmitDelayed(delayLevel);
            } else {
                task.submit();
            }
        }
        if (sem!is null){
            sem.notify();
        }
    }
    void waitLoopOp(void delegate() op,void delegate(void delegate())submitter){
        auto tAtt=taskAtt.val;
        this.op=op;
        if (tAtt !is null && tAtt.mightYield){
            task=tAtt;
            delayLevel=tAtt.delayLevel;
            tAtt.delay(delegate void(){
                submitter(&this.doOp);
            });
        } else {
            assert(tAtt is null || (cast(RootTask)tAtt) is null,"dangerous wait");
            sem=new Semaphore();
            submitter(&this.doOp);
            sem.wait();
        }
    }
}
/// helper method to wait for the execution of the action op that should be executed
/// asynchronously after being submitted with the submitter delegate
void waitLoopOp(void delegate() op,void delegate(void delegate())submitter){
    WaitLoopOp wOp;
    wOp.waitLoopOp(op,submitter);
}
/// this creates a watcher thread that watches for events, and notifies 
class EventWatcher:LoopHandlerI{
    enum Flags{
        None=0,
        DestroyLoop=1,
        LoopRunning=2,
    }
    static assert(EV_ASYNC_ENABLED,"ev_async is needed for proper functioning"); // builds a version that uses a periodic instead?
    Deque!(GenericWatcher) watchersToAdd;
    Deque!(void delegate()) actionsToDo;
    ev_loop_t*loop_;
    ev_async _asyncWatcher;
    Thread loopThread;
    Flags flags;
    
    ev_loop_t *loop(){
        return loop_;
    }
    
    static extern(C) void checkMoreWatchers(ev_loop_t* loop, ev_watcher *w,int relf){
        auto eW= cast(EventWatcher)w.data;
        eW.watchersToAdd.filterInPlace(delegate bool(GenericWatcher gw){
            gw.start(loop);
            return false;
        });
        eW.actionsToDo.filterInPlace(delegate bool(void delegate() a){
            a();
            return false;
        });
    }
    
    GenericWatcher asyncWatcher(){
        return GenericWatcher(&_asyncWatcher,GenericWatcher.Kind.async);
    }
    
    this(ev_loop_t* loop,Flags f){
        this.flags=f;
        this.loop_=loop;
        this.watchersToAdd=new Deque!(GenericWatcher)();
        this.actionsToDo=new Deque!(void delegate())();
        this.asyncWatcher.asyncInit(&checkMoreWatchers);
        this.asyncWatcher.data(this);
        this.asyncWatcher.start(this.loop);
    }
    
    this(bool useMainLoop=true){
        if (useMainLoop){
            this(ev_default_loop (EVFLAG.AUTO),Flags.None);
        } else {
            this(ev_loop_new(EVFLAG.AUTO),Flags.DestroyLoop);
        }
    }
    
    ~this(){
        if (loopThread is null && loop && (flags&Flags.DestroyLoop)!=0){
            ev_loop_destroy(loop);
        }
    }
    
    void notifyAdd(){
        asyncWatcher.asyncSend(loop);
    }

    void addWatcher(GenericWatcher w,void delegate(bool)inlineOp=null){
        version(TrackEvents){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("queuing event@")(w.ptr_)(" for addition\n");
            });
        }
        if (inlineOp !is null){
            assert(w.cb() is null && w.data() is null,"callback and data should be null as they will be overridden");
            w.cb(EventHandler(inlineOp));
        }
        watchersToAdd.pushBack(w);
        notifyAdd();
    }
    
    void addAction(void delegate()w){
        actionsToDo.pushBack(w);
        notifyAdd();
    }
    
    void threadTask(){
        try{
            synchronized(this){
                flags |=Flags.LoopRunning;
            }
        
            if (taskAtt.val is null || taskAtt.val is noTask){
                // allow spawn from this task into the default work manager
                taskAtt.val=defaultTask;
            }
            // start async communicator (for multithread communication)
            asyncWatcher.start(loop);

            // now wait for events to arrive
            ev_loop (loop, 0);

            synchronized(this){
                flags = flags & (~Flags.LoopRunning);
            }
        } catch (Exception e){
            sinkTogether(serr,delegate void(CharSink s){
                dumper(s)("EventWatcher thread crashed with Exception:")(e)("\n");
            });
        }
    }
    
    /// starts the watcher thread
    void startThread(){
        synchronized(this){
            if(loopThread !is null || ((flags&Flags.LoopRunning)!=0)){
                throw new Exception("a thread is already running the loop",__FILE__,__LINE__);
            }
            flags|=Flags.LoopRunning;
            loopThread=new Thread(&this.threadTask);
        }
        loopThread.start();
    }
    
    /// stops the current event loop (if running), should not be called concurrently by several threads
    bool stopLoop(){
        bool shouldStop=false;
        synchronized(this){
            if (flags&Flags.LoopRunning){
                shouldStop=true;
            }
        }
        Semaphore sem;
        auto tAtt=taskAtt.val;
        void stopOldLoop(){
            ev_unloop(loop,EVUNLOOP_ALL);
            if (sem){
                sem.notify();
            } else {
                tAtt.resubmitDelayed(tAtt.delayLevel-1);
            }
        }
        if (shouldStop){
            if (tAtt !is null && tAtt.mightYield){
                tAtt.delay({
                    addAction(&stopOldLoop);
                });
            } else {
                sem=new Semaphore();
                addAction(&stopOldLoop);
                sem.wait();
            }
            return true;
        }
        synchronized(this){
            assert((flags&Flags.LoopRunning)==0,"stopping of running thread failed");
        }
        return false;
    }
    /// stops the current event loop, and if startNow immediately re-starts it here
    /// is not thradsafe if you do several moveLoopHere concurrently
    void moveLoopHere(){
        stopLoop();
        threadTask();
    }
    /// sleeps a task for at least the requested amount of seconds
    static void sleepTask(double time){
        auto tAtt=taskAtt.val;
        if (tAtt!is null && tAtt.mightYield()){
            auto w=GenericWatcher.timerCreate(time,0.0,EventHandler(tAtt,tAtt.delayLevel));
            tAtt.delay(delegate void(){
                noToutWatcher.addWatcher(w);
            });
        } else {
            Thread.sleep(time);
        }
    }
    
    bool waitForEvent(GenericWatcher w,void delegate(bool)action=null){
        auto tAtt=taskAtt.val;
        assert(w.cb() is null,"callback should not be set, as it will be overridden");
        assert(w.data() is null,"data should not be set, as it will be overridden");
        if (tAtt!is null && tAtt.mightYield()){
            w.cb(EventHandler(action,tAtt,tAtt.delayLevel));
            tAtt.delay(delegate void(){
                noToutWatcher.addWatcher(w);
            });
        } else {
            if (tAtt !is null && (cast(RootTask)tAtt)is null){
                throw new Exception("dangerous wait in non yieldable task "~tAtt.taskName,__FILE__,__LINE__);
            }
            auto sem=new Semaphore();
            w.cb(EventHandler(&sem.notify));
            sem.wait();
        }
        return true;
    }
    /// returns the current time
    /// this seems to work correctly also from multiple threads (i.e. the update is atomic).
    /// Should it fail one should probably switch to ev_time()
    final ev_tstamp now(){
        return ev_now(loop);
    }
}

/// A class that handles all events that share a timeout time
class TimeoutManager:LoopHandlerI{
    ev_tstamp timeout;
    LoopHandlerI watcher;
    GenericWatcher timer;
    /// structure for events with a timeout
    struct TimedEvent{
        GenericWatcher event;
        void delegate(bool) eventOp;
        TimeoutManager timeoutManager;
        TimedEvent * prev;
        TimedEvent * next;
        PoolI!(TimedEvent*) pool;
        ev_tstamp endTime;
        TaskI task;
        int delayLevel;
        enum Status:int{
            NotStarted, Submitted, Started, Exec, TimedOut
        }
        int status=Status.NotStarted;

        equals_t opEquals(ref TimedEvent t2){
            return &t2 is this;
        }
        int opCmp(ref TimedEvent t2){
            if (endTime<t2.endTime){
                return -1;
            } else if (endTime==t2.endTime){
                return ((&t2 is this)?0:((this < &t2)?-1:1)); 
            } else {
                return 1;
            }
        }
        hash_t toHash(){
            struct Val{
                ev_tstamp t;
                TimedEvent *ptr;
            }
            Val v;
            v.t=endTime;
            v.ptr=this;
            return rt_hash_str(&v,v.sizeof);
        }
        void release0(){
            if (pool !is null){
                refCount=1;
                pool.giveBack(this);
            } else {
                delete this;
            }
        }
        mixin RefCountMixin!();
        /// internal start op to be executed in the loop thread
        void startEvent(){
            switch(status){
            case Status.Submitted:
                status=Status.Started;
                event.start(timeoutManager.loop);
                next=timeoutManager.list.next;
                prev=&timeoutManager.list;
                timeoutManager.list.next=this;
                next.prev=this;
                if (next is prev) { // the list was empty
                    timeoutManager.maybeSetTimer();
                }
                break;
            case Status.TimedOut:
                release();
                break;
            case Status.NotStarted, Status.Started, Status.Exec:
            default:
                throw new Exception("unexpcted status",__FILE__,__LINE__);
            }
        }
        /// internal timeout op to be executed in the loop thread
        void reachedTimeout(){
            switch(status){
            case Status.Submitted:
                retain();
                status=Status.TimedOut;
                break;
            case Status.Started:
                status=Status.TimedOut;
                event.stop(timeoutManager.loop);
                break;
            case Status.Exec:
                assert(false,"exec & timeout clash");
                //return;
            case Status.NotStarted,Status.TimedOut:
            default:
                throw new Exception("unexpcted status",__FILE__,__LINE__);
            }
            prev.next=next;
            next.prev=prev;
            next=this;
            prev=this;
            if (eventOp) eventOp(false);
            if (task!is null){
                if (task.status>=TaskStatus.Started){
                    task.resubmitDelayed(delayLevel);
                } else {
                    task.submit();
                }
            }
            release();
        }
        /// internal operation that executes the non timeout op, to be called in the loop thread
        void doOp(){
            switch(status){
            case Status.Started:
                status=Status.Exec;
                event.stop(timeoutManager.loop);
                break;
            case Status.NotStarted,Status.Submitted,Status.Exec,Status.TimedOut:
            default:
                throw new Exception("unexpected status",__FILE__,__LINE__);
            }
            prev.next=next;
            next.prev=prev;
            next=this;
            prev=this;
            if (eventOp) eventOp(true);
            if (task!is null){
                if (task.status>=TaskStatus.Started){
                    task.resubmitDelayed(delayLevel);
                } else {
                    task.submit();
                }
            }
            release();
        }
        /// callback executing doOp
        static extern(C) void cCallback(ev_loop_t*loop, ev_watcher *w, int revents){
            auto gWatcher=GenericWatcher(w,revents);
            auto tEv=gWatcher.data!(TimedEvent*)();
            tEv.doOp();
        }
        /// starts watching for this event
        void start(){
            retain();
            status=Status.Submitted;
            assert(event.cb() is null || event.cb() is &cCallback,"callback should not be set as it will be overridden");
            assert(event.data() is null || event.data!(typeof(this))() is this,"data should not be set as it will be overridden");
            event.cb(this);
            timeoutManager.watcher.addAction(&this.startEvent);
        }
        /// starts the event and wait for its execution or timeout
        /// returns true if no timeout did happen
        bool startAndWait(){
            auto tAtt=taskAtt.val;
            retain();
            scope(exit) {
                release();
            }
            if (tAtt !is null && tAtt.mightYield){
                assert(task is null || task is tAtt);
                task=tAtt;
                delayLevel=tAtt.delayLevel();
                tAtt.delay(&start);
            } else {
                assert(tAtt is null || (cast(RootTask)tAtt) is null,"dangerous wait");
                scope Semaphore sem=new Semaphore();
                assert(eventOp is null);
                eventOp=delegate void(bool v){
                    sem.notify(); // assumes that notify before wait is ok (normal semaphore)
                };
                start();
                sem.wait();
            }
            switch(status){
            case Status.TimedOut:
                return false;
            case Status.Exec:
                return true;
            case Status.NotStarted, Status.Submitted, Status.Started:
            default:
                throw new Exception("unexpcted status",__FILE__,__LINE__);
            }
        }
        /// internal stop op to be executed in the loop thread
        void stopEvent(){
            switch(status){
            case Status.NotStarted,Status.TimedOut:
                status=Status.TimedOut;
                break;
            case Status.Submitted,Status.Started,Status.Exec:
                reachedTimeout();
                break;
            default:
                throw new Exception("unexpected status",__FILE__,__LINE__);
            }
        }
        /// stops the current event
        void stop(){
            if (status==Status.TimedOut || status==Status.Exec) return;
            timeoutManager.watcher.addAction(&this.stopEvent);
        }
        /// clears the event for reuse
        void clear(){
            if (event.ptr() is null) event.giveBack();
            eventOp=null;
            timeoutManager=null;
            prev=this;
            next=this;
            endTime=0;
            task=null;
            delayLevel=0;
            status=Status.NotStarted;
        }
        static PoolI!(TimedEvent*) gPool;
        static this(){
            gPool=cachedPool(function TimedEvent*(PoolI!(TimedEvent*)p){
                auto res=new TimedEvent;
                res.pool=p;
                return res;
            });
        }
        static TimedEvent*opCall(TimeoutManager t,GenericWatcher w,void delegate(bool)op){
            auto res=gPool.getObj();
            res.timeoutManager=t;
            res.event=w;
            res.eventOp=op;
            res.endTime=res.timeoutManager.now+res.timeoutManager.timeout;
            return res;
        }
    }
    TimedEvent list;
    
    static extern(C) void cCallback(ev_loop_t*loop, ev_watcher *w, int revents){
        auto gWatcher=GenericWatcher(w,revents);
        auto tm=gWatcher.data!(TimeoutManager)();
        tm.doTimeout();
    }

    /// internal timer start
    void maybeSetTimer(){
        ev_tstamp amount=timeout;
        if (list.prev is &list){
            throw new Exception("list should not be empty in maybeSetTimer",__FILE__,__LINE__);
        }
        amount=max(list.prev.endTime-ev_now(watcher.loop),0.000000001);
        if (timer.ptr() is null){
            timer=GenericWatcher.timerCreate(0,0,this);
        }
        timer.ptr!(ev_timer)().repeat=amount;
        timer.again(loop);
    }
    /// internal timeout check, should be called in the loop thread
    void doTimeout(){
        TimedEvent *pos=list.prev;
        TimedEvent *end=&list;
        auto now=ev_now(loop);
        while (pos!is end && pos.endTime<now){
            auto nextPos=pos.prev;
            pos.reachedTimeout();
            pos=nextPos;
        }
        if (list.prev is &list){
            timer.stop(loop);
        } else{
            ev_tstamp amount=max(list.prev.endTime-ev_now(watcher.loop),0.000000001);
            timer.ptr!(ev_timer)().repeat=amount;
            timer.again(loop);
        }
    }
    
    // LoopHandlerI
    
    void addWatcher(GenericWatcher w,void delegate(bool)inlineOp=null){
        if (inlineOp!is null){
            auto t=TimedEvent(this,w,inlineOp);
            return t.start();
        } else {
            watcher.addWatcher(w,inlineOp);
        }
    }
    void addAction(void delegate()w){
        watcher.addAction(w);
    }
    ev_loop_t*loop(){
        return watcher.loop();
    }
    /// waits for the event w or the timeout whichever comes first
    bool waitForEvent(GenericWatcher w,void delegate(bool)inlineOp=null){
        auto t=TimedEvent(this,w,inlineOp);
        return t.startAndWait();
    }
    final ev_tstamp now(){
        return watcher.now();
    }
    void stopAction(){
        TimedEvent *pos=list.prev;
        TimedEvent *end=&list;
        size_t iPos=0;
        while (pos!is end){
            ++iPos;
        }
        iPos=iPos*2;
        pos=list.prev;
        while (pos!is end && iPos!=0){
            auto nextPos=pos.prev;
            pos.reachedTimeout();
            pos=nextPos;
            --iPos;
        }
        while (pos!is end){
            auto l=loop();
            auto nextPos=pos.prev;
            pos.event.stop(l);
            pos.prev.next=pos.next;
            pos.next.prev=pos.prev;
            pos.next=pos;
            pos.prev=pos;
            pos=nextPos;
        }
        timer.stop(loop);
        timer.giveBack();
    }
    this(LoopHandlerI lh,ev_tstamp timeout){
        this.watcher=lh;
        this.timeout=timeout;
        list.next=&list;
        list.prev=&list;
    }
    /// stops the TimeoutManager
    void stop(){
        waitLoopOp(&this.stopAction,&this.addAction);
        assert(timer.ptr() is null);
    }
    ~this(){
        assert(timer.ptr() is null,"TimeoutManager should not be collected before being stopped");
    }
}
/// default watcher without timeout
EventWatcher noToutWatcher;
/// a watcher with a timeout of few seconds
TimeoutManager sToutWatcher;
/// default watcher
LoopHandlerI defaultWatcher;
static this(){
    noToutWatcher=new EventWatcher(true);
    noToutWatcher.startThread();
    sToutWatcher=new TimeoutManager(noToutWatcher,10.0);
    defaultWatcher=noToutWatcher;
}
