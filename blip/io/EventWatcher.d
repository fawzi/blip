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
import blip.parallel.smp.WorkManager;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.container.Deque;
import gobo.ev.DLibev;
import gobo.ev.Libev;
import blip.core.Traits;
import blip.core.Thread;

/// this creates a watcher thread that watches for events, and notifies 
class EventWatcher{
    enum Flags{
        None=0,
        DestroyLoop=1,
        LoopRunning=2,
    }
    static assert(EV_ASYNC_ENABLED,"ev_async is needed for proper functioning"); // buils a version that uses a periodic instead?
    Deque!(GenericWatcher) watchersToAdd;
    Deque!(void delegate()) actionsToDo;
    ev_loop_t*loop;
    ev_async _asyncWatcher;
    Thread loopThread;
    Flags flags;
    
    static extern(C) void checkMoreWatchers(ev_loop_t* loop, ev_watcher *w,int relf){
        (cast(EventWatcher)w.data).watchersToAdd.filterInPlace(delegate bool(GenericWatcher gw){
            gw.start(loop);
            return false;
        });
        (cast(EventWatcher)w.data).actionsToDo.filterInPlace(delegate bool(void delegate() a){
            a();
            return false;
        });
    }
    
    GenericWatcher asyncWatcher(){
        return GenericWatcher(&_asyncWatcher,GenericWatcher.Kind.async);
    }
    
    this(ev_loop_t* loop,Flags f){
        this.flags=f;
        this.loop=loop;
        this.watchersToAdd=new Deque!(GenericWatcher)();
        this.actionsToDo=new Deque!(void delegate())();
        this.asyncWatcher.asyncInit(&checkMoreWatchers);
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
    
    void addWatcher(GenericWatcher w){
        watchersToAdd.pushBack(w);
        notifyAdd();
    }
    
    void addAction(void delegate()w){
        actionsToDo.pushBack(w);
        notifyAdd();
    }
    
    void notifyAdd(){
        asyncWatcher.asyncSend(loop);
    }
    
    void threadTask(){
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
}

EventWatcher defaultWatcher;

static this(){
    defaultWatcher=new EventWatcher(true);
    version(NoDefaultLoopInit){} else {
        defaultWatcher.startThread();
    }
}
