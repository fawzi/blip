/// a simple event handler that supports delegates and tasks
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
module blip.bindings.ev.EventHandler;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.container.Pool;
import blip.container.Cache;
import blip.bindings.ev.Libev;
import blip.bindings.ev.DLibev;
import blip.core.Traits;
import blip.util.TemplateFu;
import blip.parallel.smp.SmpModels;
import blip.serialization.Serialization;
version(TrackEvents){
    import blip.io.Console;
}
import blip.Comp;

/// structure that performs simple (but flexible) callbacks
struct EventHandler{
    TaskI task; // this allow nicer errors than inlineAction... but adds some dependencies...
    void delegate() inlineAction;
    void delegate(bool) inlineActionTout;
    void delegate(ev_loop_t*,GenericWatcher,EventHandler*) callback;
    PoolI!(EventHandler*) pool;
    int delayLevel;
    
    mixin(descSome("blip.ev.EventHandler","task|delayLevel|inlineAction|inlineActionTout|callback"));
    
    /// the default callback: stops the watcher, executes inlineActionTout in this thread, then
    /// inlineAction, and starts or resumes the task (if given). Finally recicles the handler and watcher
    void defaultCallbackOnce(ev_loop_t*l,GenericWatcher w,EventHandler*h){
        w.stop(l);
        if (inlineActionTout !is null){
            inlineActionTout(true);
        }
        if (inlineAction !is null){
            inlineAction();
        }
        if (task!is null){
            if (task.status>=TaskStatus.Started){
                task.resubmitDelayed(delayLevel);
            } else {
                task.submit();
            }
        }
        w.giveBack();
        giveBack();
    }
    /// the default repeating callback: executes inlineActionTout in this thread, then
    /// inlineAction, Resuming or starting a task periodically is normally wrong, as
    /// one cannot expect the task to be suspended
    void defaultCallbackRepeat(ev_loop_t*l,GenericWatcher w,EventHandler*h){
        if (inlineActionTout !is null){
            inlineActionTout(true);
        }
        if (inlineAction !is null){
            inlineAction();
        }
        if (task!is null){
            throw new Exception(collectIAppender(delegate void(CharSink s){
                dumper(s)("cannot resume or start a task periodically for task ")(task)
                    (" and watcher ")(w);
            }));
        }
    }
    void clear(){
        task=null;
        inlineAction=null;
        inlineActionTout=null;
        callback=&this.defaultCallbackOnce;
    }
    void giveBack(){
        if (pool !is null) {
            pool.giveBack(this);
        } else {
            clear();
        }
    }
    __gshared static PoolI!(EventHandler*) gPool;
    shared static this(){
        gPool=cachedPool(function EventHandler*(PoolI!(EventHandler*)p){
            auto res=new EventHandler;
            res.pool=p;
            return res;
        });
    }
    /// creates a callback that starts or resumes the task t
    static EventHandler*opCall(TaskI t, int delayLevel=int.min){
        auto res=gPool.getObj();
        if (delayLevel==int.min){
            res.delayLevel=t.delayLevel-1;
        } else {
            res.delayLevel=delayLevel;
        }
        res.task=t;
        res.callback=&res.defaultCallbackOnce;
        return res;
    }
    /// creates a callback that executes the inlineAction (in the io thread, it should be short!)
    /// then starts or resumes the task t (if given)
    static EventHandler*opCall(void delegate() inlineAction,TaskI t=null, int delayLevel=int.min,bool repeat=false,
        void delegate(bool) inlineActionTout=null){
        auto res=gPool.getObj();
        res.inlineAction=inlineAction;
        res.inlineActionTout=inlineActionTout;
        res.task=t;
        if (delayLevel==int.min && t!is null){
            res.delayLevel=t.delayLevel-1;
        } else {
            res.delayLevel=delayLevel;
        }
        if (repeat) {
            assert(t is null,"cannot use task and repeating messages");
            res.callback=&res.defaultCallbackRepeat;
        } else {
            res.callback=&res.defaultCallbackOnce;
        }
        return res;
    }
    /// ditto
    static EventHandler*opCall(void delegate(bool) inlineActionTout,TaskI t=null, int delayLevel=int.min,bool repeat=false,
        void delegate() inlineAction=null){
        return EventHandler.opCall(inlineAction,t,delayLevel,repeat,inlineActionTout);
    }
    /// creates a callback that executes the given callback passing this structure containing task and
    /// inlineAction as last argument
    static EventHandler*opCall(void delegate(ev_loop_t*,GenericWatcher,EventHandler*)callback,
        void delegate(bool) inlineActionTout=null,void delegate() inlineAction=null,TaskI task=null,
        int delayLevel=int.min)
    {
        auto res=gPool.getObj();
        res.callback=callback;
        res.inlineAction=inlineAction;
        res.inlineActionTout=inlineActionTout;
        res.task=task;
        if (delayLevel==int.min && task!is null){
            res.delayLevel=task.delayLevel-1;
        } else {
            res.delayLevel=delayLevel;
        }
        return res;
    }
    
    static extern(C) void cCallback(ev_loop_t*loop, ev_watcher *w, int revents){
        version(TrackEvents){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("event@")(cast(void*)w)(" has been fired\n");
            });
        }
        auto gWatcher=GenericWatcher(w,revents);
        auto eH=gWatcher.data!(EventHandler*)();
        if (eH.callback is null) throw new Exception("callback of event is null",__FILE__,__LINE__);
        assert(eH!is null);
        eH.callback(loop,gWatcher,eH);
    }
}

