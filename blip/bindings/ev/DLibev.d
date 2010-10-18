/// D wrapping for libenv, basically wraps all watchers into a tagged structure that
/// implements all methods (GenericWatcher), that has also a pool for quick reuse.
/// Loops are not wrapped, change ? loops are used seldomly anyway...
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
module blip.bindings.ev.DLibev;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.container.Pool;
import blip.container.Cache;
import blip.bindings.ev.Libev;
import blip.core.Traits;
import blip.util.TemplateFu;
public import blip.bindings.ev.Libev: EV_PERIODIC_ENABLED, EV_STAT_ENABLED, EV_IDLE_ENABLED, EV_FORK_ENABLED,
    EV_EMBED_ENABLED, EV_ASYNC_ENABLED, EV_WALK_ENABLED,ev_loop_t, EV_READ, EV_WRITE, ev_tstamp;
import blip.container.HashSet;
version(TrackEvents){
    import blip.io.Console;
}

/// bits for ev_default_loop and ev_loop_new
enum EVFLAG: uint{
    /// the default, not quite a mask
    AUTO       = EVFLAG_AUTO     ,
    // flag bits
    NOENV      = EVFLAG_NOENV    , /// do NOT consult environment
    FORKCHECK  = EVFLAG_FORKCHECK, /// check for a fork in each iteration
    // debugging/feature disable 
    NOINOTIFY  = EVFLAG_NOINOTIFY, /// do not attempt to use inotify
    SIGNALFD   = EVFLAG_SIGNALFD , /// attempt to use signal
}

/// method bits to be ored together
enum EVBACKEND: uint{
    SELECT  = EVBACKEND_SELECT , /// about anywhere
    POLL    = EVBACKEND_POLL   , /// !win
    EPOLL   = EVBACKEND_EPOLL  , /// linux
    KQUEUE  = EVBACKEND_KQUEUE , /// bsd
    DEVPOLL = EVBACKEND_DEVPOLL, /// solaris 8 / NYI
    PORT    = EVBACKEND_PORT   , /// solaris 10
    ALL     = EVBACKEND_ALL    , /// all backends
}

// the active watcher types (excluding none, custom, any, and superclasses watcher,watcher_list,watcher_time)
// without "ev_" at the beginning, separated by commas
char[] baseEvTypesStr(){
    char[] str="io,timer,";
    static if (EV_PERIODIC_ENABLED){
        str~="periodic,";
    }
    str~="signal,child,";
    static if (EV_STAT_ENABLED){
        str~="stat,";
    }
    static if (EV_IDLE_ENABLED){
        str~="idle,";
    }
    str~="prepare,check,";
    static if (EV_FORK_ENABLED){
        str~="fork,";
    }
    static if (EV_EMBED_ENABLED){
        str~="embed,";
    }
    static if (EV_ASYNC_ENABLED){
        str~="async,";
    }
    return str;
}

/// ev types (excluding none and custom that do not have a real type corresponding to it)
char[] evTypesStr(){
    return baseEvTypesStr()~"watcher,watcher_list,watcher_time,any_watcher";
}

/+
 inheritance graph:

    watcher
        idle
        prepare
        check
        fork
        embed
        async

        watcher_list
            io
            signal
            child
            stat

        watcher_time
            timer
            periodic
+/

char[] kindOfTypeMixin(){
    char[] res="";
    foreach(i,kStr;ctfeSplit(",",evTypesStr(),true)){
        res~=`
    `~((i!=0)?`} else `[]:""[])~`static if (is(T==ev_`~kStr~`)){
        enum { kindOfType=Kind.`~kStr~` }`;
    }
    res~=`
    } else {
        static assert(0,"incompatible type "~T.stringof);
    }`;
    return res;
}

char[] startMixin(){
    char[] res=`
    switch(kind){`;
    foreach(kStr;ctfeSplit(",",baseEvTypesStr(),true)){
        res~=`
        case Kind.`~kStr~` :
        ev_`~kStr~`_start(loop,ptr!(ev_`~kStr~`)());
        break;`;
    }
    res~=`
        case Kind.none:
        break;
        default:
        throw new Exception(collectAppender(delegate void(CharSink s){
            dumper(s)("cannot start kind ")(kind);
        }),__FILE__,__LINE__);
    }`;
    return res;
}

char[] stopMixin(){
    char[] res=`
    switch(kind){`;
    foreach(kStr;ctfeSplit(",",baseEvTypesStr(),true)){
        res~=`
        case Kind.`~kStr~` :
        ev_`~kStr~`_stop(loop,ptr!(ev_`~kStr~`)());
        break;`;
    }
    res~=`
        case Kind.custom,Kind.none:
        break;
        default:
        if ((kind&Kind.io)!=0){
            ev_io_stop(loop,ptr!(ev_io)());
        } else {
            throw new Exception(collectAppender(delegate void(CharSink s){
                dumper(s)("cannot stop kind ")(kind);
            }),__FILE__,__LINE__);
        }
    }`;
    return res;
}

char[] mixinInitAndCreate(char[]kind,char[] extraArgsDecls, char[] extraArgs){
    char[] upcaseKind=kind.dup;
    upcaseKind[0]+='A'-'a';
    char[] commaExtraArgs=((extraArgs.length>0)?",":" ")~extraArgs;
    char[] extraArgsDeclsComma=extraArgsDecls~((extraArgsDecls.length>0)?",":" ");
    char[] res=`
/// initialize a `~kind~` watcher, the callback can be either directly given, or created by passing
/// a structure pointer/class that contains an extern(C) cCallback static member
GenericWatcher `~kind~`Init(T=watcherCbF)(`~extraArgsDeclsComma~` T callback=null){
    static if (is(typeof(*T.init))){
        alias typeof(*T.init) TT;
    } else {
        alias T TT;
    }
    assert(canCastTo!(ev_`~kind~`)(kind),"cannot case content to ev_`~kind~` type");
    kind=Kind.`~kind~`;
    static if (is(T==`~kind~`CbF)){
        ev_`~kind~`_init(ptr!(ev_`~kind~`)(),callback`~commaExtraArgs~`);
    } else static if (is(T==watcherCbF)){
        ev_init!(ev_watcher*)(ptr!(ev_watcher)(),callback);
        ev_`~kind~`_set(ptr!(ev_`~kind~`)()`~commaExtraArgs~`);
    } else static if (is(typeof(&TT.cCallback)==watcherCbF)){
        ev_init!(ev_watcher*)(ptr!(ev_watcher)(),&TT.cCallback);
        ev_`~kind~`_set(ptr!(ev_`~kind~`)()`~commaExtraArgs~`);
        data!(T)(callback);
    } else static if (is(typeof(&TT.cCallback)==`~kind~`CbF)){
        ev_`~kind~`_init(ptr!(ev_`~kind~`)(),&TT.cCallback`~commaExtraArgs~`);
        data!(T)(callback);
    } else {
        static assert(0,"could not create a valid `~kind~` callback with "~TT.stringof);
    }
    return *this;
}
/// create a `~kind~` watcher, the callback can be either directly given, or created by passing
/// valid arguments for EventHandler opCall
static GenericWatcher `~kind~`Create(S...)(`~extraArgsDeclsComma~` S args){
    GenericWatcher res;
    if (gPool is null){
        res.ptr_=new ev_any_watcher;
    } else {
        res=gPool.getObj();
    }
    res.`~kind~`Init(`~extraArgs~((extraArgs.length>0)?",":" ")~`args);
    return res;
}`;
    return res;
}

struct GenericWatcher{
    enum Kind{
        none=EV_UNDEF,
        watcher=EV_READ|EV_WRITE|EV_TIMEOUT|EV_PERIODIC|EV_SIGNAL|EV_CHILD|EV_STAT|
            EV_IDLE|EV_PREPARE|EV_CHECK|EV_EMBED|EV_FORK|EV_ASYNC,
        watcher_list=EV_READ|EV_WRITE|EV_SIGNAL|EV_CHILD|EV_STAT,
        watcher_time=EV_TIMER|EV_PERIODIC,
        io=EV_READ|EV_WRITE,
        timer=EV_TIMER,
        periodic=EV_PERIODIC,
        signal=EV_SIGNAL,
        child=EV_CHILD,
        stat=EV_STAT,
        idle=EV_IDLE,
        prepare=EV_PREPARE,
        check=EV_CHECK,
        fork=EV_FORK,
        embed=EV_EMBED,
        async=EV_ASYNC,
        custom=EV_CUSTOM,
        any_watcher=EV_NONE,
    }
    void* ptr_;
    int kind;
    PoolI!(GenericWatcher) pool; // should be set only if it is based on any_watcher
    
    void desc(void delegate(char[])s){
        dumper(s)("<GenericWatcher@")(ptr_)(" kind:")(kind)(">");
    }
    
    void giveBack(){
        if (pool!is null && ptr_!is null){
            pool.giveBack(*this);
        }
        ptr_=null;
        kind=Kind.none;
    }
    equals_t opEqual(GenericWatcher w2){
        return (ptr_ is w2.ptr_);
    }
    int opCmp(GenericWatcher w2){
        return ((ptr_<w2.ptr_)?-1:((ptr_ is w2.ptr_)?0:1));
    }
    hash_t toHash(){
        union H{
            hash_t hash;
            void* ptr;
        }
        H h;
        h.ptr=ptr_;
        return h.hash;
    }
    /// returns the ad-hoc data stored in this watcher
    TP data(TP=void*)(){
        return cast(TP)ptr!(ev_watcher)().data;
    }
    /// sets the ad'hoc data stored in this watcher
    void data(TP=void*)(TP newData){
        ptr!(ev_watcher)().data=cast(void*)newData;
    }
    /// Starts (activates) the given watcher. Only active watchers will receive events. If the watcher is already active nothing will happen.
    void start(ev_loop_t* loop){
        version(TrackEvents){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("starting event@")(cast(void*)ptr_)(" on loop@")(cast(void*)loop)("\n");
            });
        }
        synchronized(activeWatchers()){
            activeWatchers().add(*this); // slow and ugly!!!
        }
        mixin(startMixin());
    }
    /// Stops the given watcher if active, and clears the pending status (whether the watcher was active or not).
    ///
    /// It is possible that stopped watchers are pending - for example, non-repeating timers are being stopped when they become pending - but calling ev_TYPE_stop ensures that the watcher is neither active nor pending. If you want to free or reuse the memory used by the watcher it is therefore a good idea to always call its stop function.
    void stop(ev_loop_t* loop){
        version(TrackEvents){
            sinkTogether(sout,delegate void(CharSink s){
                dumper(s)("stopping event@")(cast(void*)ptr_)(" on loop@")(cast(void*)loop)("\n");
            });
        }
        synchronized(activeWatchers()){
            activeWatchers().remove(*this); // slow and ugly!!!
        }
        mixin(stopMixin());
    }

    /// Returns a true value iff the watcher is active (i.e. it has been started and not yet been stopped). As long as a watcher is active you must not modify it.
    bool isActive(){
        return ev_is_active(ptr!(ev_watcher)());
    }

    /// Returns a true value iff the watcher is pending, (i.e. it has outstanding events but its callback has not yet been invoked). As long as a watcher is pending (but not active) you must not call an init function on it (but ev_TYPE_set is safe), you must not change its priority, and you must make sure the watcher is available to libev (e.g. you cannot free () it).
    bool isPending(){
        return ev_is_pending(ptr!(ev_watcher)());
    }

    /// Change the callback. You can change the callback at virtually any time (modulo threads).
    /// callback can either be a pointer to a C function, or a pointer like type that will be stored
    /// in data and a static C function into its type called cCallback that will be the callback.
    void cb(T=watcherCbF)(T callback){
        static if (is(typeof(*T.init))){
            alias typeof(*T.init) TT;
        } else {
            alias T TT;
        }
        static if (is(T==watcherCbF)){
            ev_cb_set(ptrP!(ev_watcher*)(),callback);
        } else static if (is(T == function)){
            static if (is(T U==arguments)){
                ev_cb_set(ptrP!(U[1])(),callback);
            } else {
                static assert(0,"could not extract callback for "~T.stringof);
            }
        } else static if (is(typeof(&TT.cCallback)== watcherCbF)){
            ev_set_cb!(ev_watcher*)(ptrP!(ev_watcher*)(),&TT.cCallback);
            data!(T)(callback);
        } else static if (is(typeof(&TT.cCallback)== function)){
            static if (is(typeof(&TT.cCallback) U==arguments)){
                ev_set_cb(ptrP!(U[1])(),&TT.cCallback);
            }
            data!(T)(callback);
        } else {
            static assert(0,"could not create a valid callback with "~TT.stringof);
        }
    }
    /// Returns the callback currently set on the watcher.
    T cb(T=watcherCbF)(){
        return cast(T)ev_cb(ptrP!(ev_watcher*)());
        /+static if (is(T U==arguments)){
            return ev_cb(ptrP!(U[1])());
        } else {
            static assert(0,"could not extract type for "~T.stringof);
        }+/
    }

    /// Set and query the priority of the watcher. The priority is a small integer between EV_MAXPRI (default: 2) and EV_MINPRI (default: -2). Pending watchers with higher priority will be invoked before watchers with lower priority, but priority will not keep watchers from being executed (except for ev_idle watchers).
    /// 
    /// If you need to suppress invocation when higher priority events are pending you need to look at ev_idle watchers, which provide this functionality.
    /// 
    /// You must not change the priority of a watcher as long as it is active or pending.
    /// 
    /// Setting a priority outside the range of EV_MINPRI to EV_MAXPRI is fine, as long as you do not mind that the priority value you query might or might not have been clamped to the valid range.
    /// 
    /// The default priority used by watchers when no priority has been set is always 0, which is supposed to not be too high and not be too low :).
    /// 
    /// See WATCHER PRIORITY MODELS, below, for a more thorough treatment of priorities.
    void priority(int priority){
        ev_set_priority (ptr!(ev_watcher)(), priority);
    }
    /// ditto
    int priority(){
        return ev_priority(ptr!(ev_watcher)());
    }

    static void feedFdEvent(ev_loop_t* loop, int fd, int revents){
        ev_feed_fd_event(loop,fd,revents);
    }
    static void feedSignalEvent(ev_loop_t*loop,int signum){
        ev_feed_signal_event (loop, signum);
    }
    /// returns the absolute at value of an ev_watcher_time
    ev_tstamp at(){
        return ev_periodic_at(ptr!(ev_watcher_time));
    }

    /// Invoke the watcher with the given loop and revents. Neither loop nor revents need to be valid as long as the watcher callback can deal with that fact, as both are simply passed through to the callback.
    void invoke(ev_loop_t*loop, int revents){
        ev_invoke(loop,ptr!(ev_watcher)(),revents);
    }

    /// If the watcher is pending, this function clears its pending status and returns its revents bitset (as if its callback was invoked). If the watcher isn't pending it does nothing and returns 0.
    ///
    /// Sometimes it can be useful to "poll" a watcher instead of waiting for its callback to be invoked, which can be accomplished with this function.
    int clearPending (ev_loop_t*loop){
        return ev_clear_pending(loop, ptr!(ev_watcher)());
    }
    
    /// Feeds the given event set into the event loop, as if the specified event had happened for the specified watcher (which must be a pointer to an initialised but not necessarily started event watcher). Obviously you must not free the watcher as long as it has pending events.
    /// 
    /// Stopping the watcher, letting libev invoke it, or calling ev_clear_pending will clear the pending event, even if the watcher was not started in the first place.
    /// 
    /// See also ev_feed_fd_event and ev_feed_signal_event for related functions that do not need a watcher.
    void feedEvent (ev_loop_t* loop, int revents){
        ev_feed_event(loop,ptr!(ev_watcher)(),revents);
    }

    static if (EV_ASYNC_ENABLED){
        /// sends an asynchronous signal (this should be of type async)
        void asyncSend(ev_loop_t* loop){
            ev_async_send(loop,ptr!(ev_async)());
        }
    }
    /// does a sweep of the embedded loop pointed to by this watcher (should be of type embed)
    void embedSweep(ev_loop_t*loop){
        ev_embed_sweep(loop,ptr!(ev_embed)());
    }
    /// restarts the time of periodic watcher
    void again(ev_loop_t*loop){
        switch (kind){
            case Kind.periodic:
                ev_periodic_again(loop,ptr!(ev_periodic)());
                break;
            case Kind.timer:
                ev_timer_again(loop,ptr!(ev_timer)());
                break;
            default:
                throw new Exception(collectAppender(delegate void(CharSink s){
                    dumper(s)("the kind ")(kind)(" does not support *again");
                }),__FILE__,__LINE__);
        }
    }
    /// returns the remaining time (valid only for the timer type)
    ev_tstamp timerRemaining(ev_loop_t* loop){
        return ev_timer_remaining (loop,ptr!(ev_timer)());
    }
    

    /// clears
    void clear(){
        assert(!(isPending()||isActive()),"cannot clear active or pending watcher");
        if (pool!is null){
            kind=Kind.any_watcher;
        } else {
            kind=Kind.none;
            ptr_=null;
        }
    }
    
    template kindOfType(T){
        mixin(kindOfTypeMixin());
    }
    static GenericWatcher opCall(T)(T*ptr){
        GenericWatcher res;
        res.kind=kindOfType!(T);
        res.ptr_=ptr;
        return res;
    }
    static GenericWatcher opCall(T)(T*ptr,int kind){
        GenericWatcher res;
        res.kind=kind;
        res.ptr_=ptr;
        return res;
    }
    /// if the type k can be casted to type T
    static bool canCastTo(T)(int k){
        static if(is(T==void*)){
            return true;
        } else {
            return (kindOfType!(T) & k)==k;
        }
    }
    /// returns the content as a pointer to type T
    T* ptr(T=void*)(){
        assert(canCastTo!(T)(kind),collectAppender(delegate void(CharSink s){
            dumper(s)("invalid cast of kind ")(kind)(" to ")(T.stringof);
        }));
        return cast(T*)ptr_;
    }
    TP ptrP(TP)(){
        assert(canCastTo!(typeof(*TP.init))(kind),collectAppender(delegate void(CharSink s){
            dumper(s)("invalid cast of kind ")(kind)(" to ")(TP.stringof);
        }));
        return cast(TP)ptr_;
    }
    // global pool - static methods
    static PoolI!(GenericWatcher) gPool;
    static this(){
        gPool=cachedPool( function GenericWatcher(PoolI!(GenericWatcher)p){
            GenericWatcher res;
            res.ptr_=new ev_any_watcher;
            res.pool=p;
            res.kind=Kind.any_watcher;
            return res;
        });
    }

    mixin(mixinInitAndCreate("io","int fd, int what","fd,what"));
    mixin(mixinInitAndCreate("timer","ev_tstamp after, ev_tstamp repeat","after,repeat"));
    static if (EV_PERIODIC_ENABLED){
        mixin(mixinInitAndCreate("periodic","ev_tstamp ofs, ev_tstamp ival,periodicF res","ofs,ival,periodicF"));
    }
    mixin(mixinInitAndCreate("signal","int signum","signum"));
    mixin(mixinInitAndCreate("child","int pid, int trace","pid,trace"));
    static if (EV_STAT_ENABLED){
        mixin(mixinInitAndCreate("stat","char* path, ev_tstamp interval","path,interval"));
    }
    static if (EV_IDLE_ENABLED){
        mixin(mixinInitAndCreate("idle","",""));
    }
    mixin(mixinInitAndCreate("prepare","",""));
    mixin(mixinInitAndCreate("check","",""));
    mixin(mixinInitAndCreate("embed","ev_loop_t* other","other"));
    static if (EV_FORK_ENABLED){
        mixin(mixinInitAndCreate("fork","",""));
    }
    static if (EV_ASYNC_ENABLED){
        mixin(mixinInitAndCreate("async","",""));
    }
}

/// represents an objects that takes care of an event loop and to which event watchers can be added
interface LoopHandlerI{
    /// adds and start an event watcher in this LoopHandlerI (actual adding will probably be posted to be
    /// executed in this loop). If inlineOp is given it is used as operation to execute
    /// when the event is triggered, pssing false to it if the timeout was reached
    void addWatcher(GenericWatcher w,void delegate(bool)inlineOp=null);
    /// adds an action that will be executed in the loop thread
    void addAction(void delegate()w);
    /// utility method to wait for a non repeating GenericWatcher suspending the current task
    /// returns true if the event was fired, false if a timeout was encountred
    bool waitForEvent(GenericWatcher w,void delegate(bool)inlineOp=null);
    /// returns the loop of this LoopHandlerI
    ev_loop_t*loop();
    /// returns the current time in the loop
    ev_tstamp now();
}

/// watchers that are currently active (to avoid gc collection, ugly hack)
/// could store only the underlying ev_watcher...
HashSet!(GenericWatcher) _activeWatchers;
HashSet!(GenericWatcher) activeWatchers(){
    if (_activeWatchers !is null) return _activeWatchers;
    synchronized{
        if (_activeWatchers is null)
            _activeWatchers=new HashSet!(GenericWatcher)();
    }
    return _activeWatchers;
}
