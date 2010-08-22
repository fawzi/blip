/// D Programming Language "bindings" to libev <http://software.schmorp.de/pkg/libev.html>
///
/// This re-port of the C header, very slightly influenced by the
/// of the one written by Leandro Lucarella (2008) and available at
/// http://git.llucax.com.ar/w/software/ev.d.git and placed under BOLA license
/// <http://auriga.wearlab.de/~alb/bola/> which is compatible with the apache license 2.0 used in
/// this project.
///
/// Based on version libev 3.9, the new *ENABLE from 4.0 are not yet there...
///
/// author: fawzi
///
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
module gobo.ev.Libev;
import blip.stdc.signal;
private alias char[] string;
extern (C){
    //align (4):

    // only EV_MULTIPLICITY==1, EV_PROTOTYPES==1 is supported...

    version(EV_MANUAL_VERSIONS){
        version (EV_PERIODIC_ENABLE ){  enum:bool { EV_PERIODIC_ENABLED =true  }
        } else {                        enum:bool { EV_PERIODIC_ENABLED =false }}
        version (EV_STAT_ENABLE     ){  enum:bool { EV_STAT_ENABLED     =true  }
        } else {                        enum:bool { EV_STAT_ENABLED     =false }}
        version (EV_IDLE_ENABLE     ){  enum:bool { EV_IDLE_ENABLED     =true  }
        } else {                        enum:bool { EV_IDLE_ENABLED     =false }}
        version (EV_FORK_ENABLE     ){  enum:bool { EV_FORK_ENABLED     =true  }
        } else {                        enum:bool { EV_FORK_ENABLED     =false }}
        version (EV_EMBED_ENABLE    ){  enum:bool { EV_EMBED_ENABLED    =true  }
        } else {                        enum:bool { EV_EMBED_ENABLED    =false }}
        version (EV_ASYNC_ENABLE    ){  enum:bool { EV_ASYNC_ENABLED    =true  }
        } else {                        enum:bool { EV_ASYNC_ENABLED    =false }}
        version (EV_WALK_ENABLE     ){  enum:bool { EV_WALK_ENABLED     =true  }
        } else {                        enum:bool { EV_WALK_ENABLED     =false }}
    } else version (darwin){
        enum:bool {
            EV_PERIODIC_ENABLED=true,
            EV_STAT_ENABLED=true,
            EV_IDLE_ENABLED=true,
            EV_FORK_ENABLED=true,
            EV_EMBED_ENABLED=true,
            EV_ASYNC_ENABLED=true,
            EV_WALK_ENABLED=false,
        }
    } else version (linux){
        enum:bool {
            EV_PERIODIC_ENABLED=true,
            EV_STAT_ENABLED=true,
            EV_IDLE_ENABLED=true,
            EV_FORK_ENABLED=true,
            EV_EMBED_ENABLED=true,
            EV_ASYNC_ENABLED=true,
            EV_WALK_ENABLED=false,
        }
    } else {
        static assert(0,"system not supported, set the EV_*_ENABLED");
    }
    alias sig_atomic_t EV_ATOMIC_T;

    enum: int
    {
        EV_UNDEF    = 0xFFFFFFFF, // guaranteed to be invalid
        EV_NONE     =       0x00, // no events
        EV_READ     =       0x01, // ev_io detected read will not block
        EV_WRITE    =       0x02, // ev_io detected write will not block
        EV_IO       = EV_READ|EV_WRITE,
        EV_IOFDSET  =       0x80, // internal use only
        EV_TIMEOUT  = 0x00000100, // timer timed out
        EV_TIMER    = EV_TIMEOUT,
        EV_PERIODIC = 0x00000200, // periodic timer timed out
        EV_SIGNAL   = 0x00000400, // signal was received
        EV_CHILD    = 0x00000800, // child/pid had status change
        EV_STAT     = 0x00001000, // stat data changed
        EV_IDLE     = 0x00002000, // event loop is idling
        EV_PREPARE  = 0x00004000, // event loop about to poll
        EV_CHECK    = 0x00008000, // event loop finished poll
        EV_EMBED    = 0x00010000, // embedded event loop needs sweep
        EV_FORK     = 0x00020000, // event loop resumed in child
        EV_ASYNC    = 0x00040000, // async intra-loop signal */
        EV_CUSTOM   = 0x01000000, // for use by user code */
        EV_ERROR    = 0x80000000, // sent when an error occurs
    }

    alias double ev_tstamp;

    struct ev_loop_t;
}

template callBackF(TP){
    extern(C) alias void function(ev_loop_t*, TP, int) callBackF;
}

template EV_COMMON()
{
    void* data;
}

template EV_CB_DECLARE(TP)
{
    callBackF!(TP) cb;
}

enum:int { // this is on osx, amke it platform dependent??
    EV_MINPRI= -2,
    EV_MAXPRI= +2,
}

template EV_WATCHER(TP)
{
    int active;                 // private
    int pending;                // private
    static if(EV_MINPRI!=EV_MAXPRI) int priority;               // private
    void* data; // common
    callBackF!(TP) cb; // declare
}

template EV_WATCHER_LIST(TP)
{
    mixin EV_WATCHER!(TP);
    ev_watcher_list* next;      // private
}

template EV_WATCHER_TIME(TP)
{
    mixin EV_WATCHER!(TP);
    ev_tstamp at;               // private
}

extern(C){
    struct ev_watcher
    {
        mixin EV_WATCHER!(ev_watcher*);
    }

    struct ev_watcher_list
    {
        mixin EV_WATCHER_LIST!(ev_watcher_list*);
    }

    struct ev_watcher_time
    {
        mixin EV_WATCHER_TIME!(ev_watcher_time*);
    }

    /** invoked when fd is either EV_READable or EV_WRITEable */
    /** revent EV_READ, EV_WRITE */
    struct ev_io
    {
        mixin EV_WATCHER_LIST!(ev_io*);
        int fd;     // ro
        int events; // ro
    }

    /** invoked after a specific time, repeatable (based on monotonic clock) */
    /** revent EV_TIMEOUT */
    struct ev_timer
    {
        mixin EV_WATCHER_TIME!(ev_timer*);
        ev_tstamp repeat; // rw
    }

    static if (EV_PERIODIC_ENABLED){
        alias ev_tstamp function(ev_periodic *w,ev_tstamp now) periodicF;
        /** invoked at some specific time, possibly repeating at regular intervals (based on UTC) */
        /** revent EV_PERIODIC */
        struct ev_periodic
        {
            mixin EV_WATCHER_TIME!(ev_periodic*);
            ev_tstamp offset;                     // rw
            ev_tstamp interval;                   // rw
            periodicF reschedule_cb; // rw
        }
    }

    /* invoked when the given signal has been received */
    /* revent EV_SIGNAL */
    struct ev_signal
    {
        mixin EV_WATCHER_LIST!(ev_signal*);
        int signum; // ro
    }

    /** invoked when sigchld is received and waitpid indicates the given pid */
    /** revent EV_CHILD */
    /** does not support priorities */
    struct ev_child
    {
        mixin EV_WATCHER_LIST!(ev_child*);
        int flags;   // private
        int pid;     // ro
        int rpid;    // rw, holds the received pid
        int rstatus; // rw, holds the exit status, use the
        // macros from sys/wait.h
    }

    static if (EV_STAT_ENABLED)
    {

        version (Windows) // alias _stati64 ev_statdata;
        {
            pragma (msg, "ev_stat not supported in windows "
                    "because I don't know the "
                    "layout of _stati64");
            static assert(0);
            // Maybe this should work?
            //static import stat = std.c.windows.stat;
            //alias stat.struct_stat ev_statdata;
        }
        else // It should be POSIX
        {
            static import stat = tango.stdc.posix.sys.stat;
            alias stat.stat_t ev_statdata;
        }

        /** invoked each time the stat data changes for a given path */
        /** revent EV_STAT */
        struct ev_stat
        {
            mixin EV_WATCHER_LIST!(ev_stat*);

            ev_timer timer;     // private
            ev_tstamp interval; // ro
            char *path;   // ro
            ev_statdata prev;   // ro
            ev_statdata attr;   // ro
            int wd; // wd for inotify, fd for kqueue
        }
    }

    static if (EV_IDLE_ENABLED)
    {
        /** invoked when the nothing else needs to be done, keeps the process from blocking */
        /** revent EV_IDLE */
        struct ev_idle
        {
            mixin EV_WATCHER!(ev_idle*);
        }
    }

    /** invoked for each run of the mainloop, just before the blocking call */
    /** you can still change events in any way you like */
    /** revent EV_PREPARE */
    struct ev_prepare
    {
        mixin EV_WATCHER!(ev_prepare*);
    }

    /** invoked for each run of the mainloop, just after the blocking call */
    /** revent EV_CHECK */
    struct ev_check
    {
        mixin EV_WATCHER!(ev_check*);
    }

    static if (EV_FORK_ENABLED)
    {
        /** the callback gets invoked before check in the child process when a fork was detected */
        struct ev_fork
        {
            mixin EV_WATCHER!(ev_fork*);
        }
    }

    static if (EV_EMBED_ENABLED)
    {
        /** used to embed an event loop inside another */
        /** the callback gets invoked when the event loop has handled events, and can be 0 */
        struct ev_embed
        {
            mixin EV_WATCHER!(ev_embed*);
            ev_loop_t* other;     // ro
            ev_io io;             // private
            ev_prepare prepare;   // private
            ev_check check;       // unused
            ev_timer timer;       // unused
            ev_periodic periodic; // unused
            ev_idle idle;         // unused
            ev_fork fork;         // unused
        }
    }

    static if (EV_ASYNC_ENABLED){
        /* invoked when somebody calls ev_async_send on the watcher */
        /* revent EV_ASYNC */
        struct ev_async
        {
          mixin EV_WATCHER!(ev_async*);

          EV_ATOMIC_T sent; /* private */
        }
    }

    union ev_any_watcher
    {
        ev_watcher w;
        ev_watcher_list wl;
    
        ev_io io;
        ev_timer timer;
        ev_periodic periodic;
        ev_signal signal;
        ev_child child;
        static if (EV_STAT_ENABLED){
            ev_stat stat;
        }
        static if (EV_IDLE_ENABLED){
            ev_idle idle;
        }
        ev_prepare prepare;
        ev_check check;
        static if (EV_FORK_ENABLED){
            ev_fork fork;
        }
        static if (EV_EMBED_ENABLED){
            ev_embed embed;
        }
        static if (EV_ASYNC_ENABLED){
            ev_async async;
        }
    }


    enum: uint
    {
        // bits for ev_default_loop and ev_loop_new
        // the default
        EVFLAG_AUTO       = 0x00000000, // not quite a mask
        // flag bits
        EVFLAG_NOENV      = 0x01000000, // do NOT consult environment
        EVFLAG_FORKCHECK  = 0x02000000, // check for a fork in each iteration
        /* debugging/feature disable */
        EVFLAG_NOINOTIFY  = 0x00100000, /* do not attempt to use inotify */
        EVFLAG_SIGNALFD   = 0x00200000, /* attempt to use signalfd */
        // method bits to be ored together
        EVBACKEND_SELECT  = 0x00000001, // about anywhere
        EVBACKEND_POLL    = 0x00000002, // !win
        EVBACKEND_EPOLL   = 0x00000004, // linux
        EVBACKEND_KQUEUE  = 0x00000008, // bsd
        EVBACKEND_DEVPOLL = 0x00000010, // solaris 8 / NYI
        EVBACKEND_PORT    = 0x00000020, // solaris 10
        EVBACKEND_ALL     = 0x0000003F,
    }

    int ev_version_major();
    int ev_version_minor();

    uint ev_supported_backends();
    uint ev_recommended_backends();
    uint ev_embeddable_backends();

    ev_tstamp ev_time();
    void ev_sleep(ev_tstamp delay); // sleep for a while

    alias void* function(void* ptr, int size) allocF;
    // Sets the allocation function to use, works like realloc.
    // It is used to allocate and free memory.
    // If it returns zero when memory needs to be allocated, the library
    // might abort
    // or take some potentially destructive action.
    // The default is your system realloc function.
    void ev_set_allocator(allocF);

    alias void function(char* msg) errF;
    // set the callback function to call on a
    // retryable syscall error
    // (such as failed select, poll, epoll_wait)
    void ev_set_syserr_cb(errF);

    extern ev_loop_t* ev_default_loop_ptr;
    ev_loop_t* ev_default_loop_init(uint flags);

}

alias extern(C) void function(ev_loop_t*,ev_watcher*, int) watcherCbF;

// d functions
ev_loop_t*ev_default_loop_uc()
{
  return ev_default_loop_ptr;
}
/* the default loop is the only one that handles signals and child watchers */
/* you can call this as often as you like */
ev_loop_t*ev_default_loop (uint flags)
{
  ev_loop_t*loop = ev_default_loop_uc ();
  if (loop is null)
        loop = ev_default_loop_init (flags);
  return loop;
}

extern(C){
    // create and destroy alternative loops that don't handle signals
    ev_loop_t* ev_loop_new(uint flags);
    void ev_loop_destroy(ev_loop_t*);
    void ev_loop_fork(ev_loop_t*);

    /* time w.r.t. timers and the eventloop, updated after each poll */
    ev_tstamp ev_now(ev_loop_t*);
    int ev_is_default_loop(ev_loop_t* loop){
        return loop is ev_default_loop_ptr;
    }
    void ev_default_destroy();/* destroy the default loop */
    /* this needs to be called after fork, to duplicate the default loop */
    /* if you create alternative loops you have to call ev_loop_fork on them */
    /* you can call it in either the parent or the child */
    /* you can actually call it at any time, anywhere :) */
    void ev_default_fork();
    uint ev_backend(ev_loop_t*);
    void ev_now_update(ev_loop_t*); /* update event loop time */

    static if (EV_WALK_ENABLED){
        /* walk (almost) all watchers in the loop of a given type, invoking the */
        /* callback on every such watcher. The callback might stop the watcher, */
        /* but do nothing else with the loop */
        void ev_walk (ev_loop_t* loop, int types, void function(ev_loop_t* loop, int type, void *w));
    }

    enum
    {
        EVLOOP_NONBLOCK = 1, // do not block/wait
        EVLOOP_ONESHOT  = 2, // block *once* only
        EVUNLOOP_CANCEL = 0, // undo unloop
        EVUNLOOP_ONE    = 1, // unloop once
        EVUNLOOP_ALL    = 2, // unloop all loops
    }

    void ev_loop(ev_loop_t*, int flags);
    void ev_unloop(ev_loop_t*, int); /* set to 1 to break out of event loop, set to 2 to break out of all event loops */

    /*
     * ref/unref can be used to add or remove a refcount on the mainloop. every watcher
     * keeps one reference. if you have a long-running watcher you never unregister that
     * should not keep ev_loop from running, unref() after starting, and ref() before stopping.
     */
    void ev_ref(ev_loop_t*);
    void ev_unref(ev_loop_t*);
    alias extern(C) void function(int revents, void* arg) onceF;
    void ev_once(ev_loop_t*, int fd, int events, ev_tstamp timeout,onceF, void* arg);
}

/* these may evaluate ev multiple times, and the other arguments at most once */
/* either use ev_init + ev_TYPE_set, or the ev_TYPE_init macro, below, to first initialise a watcher */
void ev_init(TP)(TP w, callBackF!(TP) cb)
{
    w.active = 0;
    w.pending = 0;
    w.priority = 0;
    ev_set_cb!(TP)(w, cb);
}

void ev_io_set(ev_io* w, int fd, int events)
{
    w.fd = fd;
    w.events = events | EV_IOFDSET;
}

void ev_timer_set(ev_timer* w, ev_tstamp after, ev_tstamp repeat)
{
    w.at = after;
    w.repeat = repeat;
}

static if (EV_PERIODIC_ENABLED){
    void ev_periodic_set(ev_periodic* w, ev_tstamp ofs, ev_tstamp ival,periodicF res)
    {
        w.offset = ofs;
        w.interval = ival;
        w.reschedule_cb = res;
    }
}

void ev_signal_set(ev_signal* w, int signum)
{
    w.signum = signum;
}

void ev_child_set(ev_child* w, int pid, int trace)
{
    w.pid = pid;
    w.flags = !!trace;
}

static if (EV_STAT_ENABLED){
    void ev_stat_set(ev_stat* w, char* path, ev_tstamp interval)
    {
        w.path = path;
        w.interval = interval;
        w.wd = -2;
    }
}

static if (EV_IDLE_ENABLED){
    void ev_idle_set(ev_idle* w)
    {
    }
}
void ev_prepare_set(ev_prepare* w)
{
}

void ev_check_set(ev_check* w)
{
}

void ev_embed_set(ev_embed* w, ev_loop_t* other)
{
    w.other = other;
}

static if (EV_FORK_ENABLED){
    void ev_fork_set(ev_fork* w)
    {
    }
}

static if (EV_ASYNC_ENABLED){
    extern(D) void ev_async_set(ev_async* w)
    {
        w.sent=0;
    }
}

alias callBackF!(ev_io*) ioCbF;
void ev_io_init(ev_io* w, ioCbF cb, int fd,int events)
{
    ev_init!(ev_io*)(w, cb);
    ev_io_set(w, fd, events);
}

alias callBackF!(ev_timer*) timerCbF;
void ev_timer_init(ev_timer* w, timerCbF cb, ev_tstamp after, ev_tstamp repeat)
{
    ev_init!(ev_timer*)(w, cb);
    ev_timer_set(w, after, repeat);
}

static if (EV_PERIODIC_ENABLED){
    alias callBackF!(ev_periodic*) periodicCbF;
    void ev_periodic_init(ev_periodic* w, periodicCbF cb,
            ev_tstamp ofs, ev_tstamp ival,
            periodicF res)
    {
        ev_init!(ev_periodic*)(w, cb);
        ev_periodic_set(w, ofs, ival, res);
    }
}
alias callBackF!(ev_signal*) signalCbF;
void ev_signal_init(ev_signal* w, signalCbF cb,
        int signum)
{
    ev_init!(ev_signal*)(w, cb);
    ev_signal_set(w, signum);
}
alias callBackF!(ev_child*) childCbF;
void ev_child_init(ev_child* w, childCbF cb,
        int pid, int trace)
{
    ev_init!(ev_child*)(w, cb);
    ev_child_set(w, pid, trace);
}

static if (EV_STAT_ENABLED){
    alias callBackF!(ev_stat*) statCbF;
    void ev_stat_init(ev_stat* w, statCbF cb,
            char* path, ev_tstamp interval)
    {
        ev_init!(ev_stat*)(w, cb);
        ev_stat_set(w, path, interval);
    }
}

static if (EV_IDLE_ENABLED){
    alias callBackF!(ev_idle*) idleCbF;
    void ev_idle_init(ev_idle* w, idleCbF cb)
    {
        ev_init!(ev_idle*)(w, cb);
        ev_idle_set(w);
    }
}
alias callBackF!(ev_prepare*) prepareCbF;
void ev_prepare_init(ev_prepare* w, prepareCbF cb)
{
    ev_init!(ev_prepare*)(w, cb);
    ev_prepare_set(w);
}

alias callBackF!(ev_check*) checkCbF;
void ev_check_init(ev_check* w, checkCbF cb)
{
    ev_init!(ev_check*)(w, cb);
    ev_check_set(w);
}

alias callBackF!(ev_embed*) embedCbF;
void ev_embed_init(ev_embed* w, embedCbF cb,
        ev_loop_t* other)
{
    ev_init!(ev_embed*)(w, cb);
    ev_embed_set(w, other);
}

static if (EV_FORK_ENABLED){
    alias callBackF!(ev_fork*) forkCbF;
    void ev_fork_init(ev_fork* w, forkCbF cb)
    {
        ev_init!(ev_fork*)(w, cb);
        ev_fork_set(w);
    }
}
static if (EV_ASYNC_ENABLED){
    alias callBackF!(ev_async*) asyncCbF;
    void ev_fork_init(ev_async* w, asyncCbF cb){
        ev_init!(ev_async*)(w, cb);
        ev_async_set(w);
    }
}

bool ev_is_pending(TYPE)(TYPE* w){
    return cast (bool) w.pending;
}

bool ev_is_active(TYPE)(TYPE* w){
    return cast (bool) w.active;
}

callBackF!(TP) ev_cb(TP)(TP w){
    return w.cb;
}

int ev_priority(TYPE)(TYPE* w)
{
    static if (EV_MINPRI != EV_MAXPRI){
        return cast (bool) w.priority;
    } else {
        return EV_MINPRI;
    }
}
void ev_set_priority(TYPE)(TYPE* w, int pri)
{
    static if (EV_MINPRI != EV_MAXPRI){
        w.priority = pri;
    } else {
    }
}

ev_tstamp ev_periodic_at(T)(T* w){
    return w.at;
}

void ev_set_cb(TP)(TP w, callBackF!(TP) cb){
    w.cb = cb;
}

extern(C){
    void ev_feed_event(ev_loop_t*, void *w, int revents);
    void ev_feed_fd_event(ev_loop_t*, int fd, int revents);
    void ev_feed_signal_event (ev_loop_t*, int signum);
    void ev_invoke(ev_loop_t*, void *w, int revents);
    int  ev_clear_pending(ev_loop_t*, void *w);

    void ev_io_start(ev_loop_t*, ev_io *w);
    void ev_io_stop(ev_loop_t*, ev_io *w);

    void ev_timer_start(ev_loop_t*, ev_timer *w);
    void ev_timer_stop(ev_loop_t*, ev_timer *w);
    /* stops if active and no repeat, restarts if active and repeating, starts if inactive and repeating */
    void ev_timer_again(ev_loop_t*, ev_timer *w);
    /* return remaining time */
    ev_tstamp ev_timer_remaining (ev_loop_t*, ev_timer *w);

    static if (EV_PERIODIC_ENABLED){
        void ev_periodic_start(ev_loop_t*, ev_periodic *w);
        void ev_periodic_stop(ev_loop_t*, ev_periodic *w);
        void ev_periodic_again(ev_loop_t*, ev_periodic *w);
    }

    /* only supported in the default loop */
    void ev_signal_start(ev_loop_t*, ev_signal *w);
    void ev_signal_stop(ev_loop_t*, ev_signal *w);

    /* only supported in the default loop */
    void ev_child_start(ev_loop_t*, ev_child *w);
    void ev_child_stop(ev_loop_t*, ev_child *w);

    static if (EV_STAT_ENABLED){
        void ev_stat_start(ev_loop_t*, ev_stat *w);
        void ev_stat_stop(ev_loop_t*, ev_stat *w);
        void ev_stat_stat(ev_loop_t*, ev_stat *w);
    }

    static if (EV_IDLE_ENABLED){
        void ev_idle_start(ev_loop_t*, ev_idle *w);
        void ev_idle_stop(ev_loop_t*, ev_idle *w);
    }

    void ev_prepare_start(ev_loop_t*, ev_prepare *w);
    void ev_prepare_stop(ev_loop_t*, ev_prepare *w);

    void ev_check_start(ev_loop_t*, ev_check *w);
    void ev_check_stop(ev_loop_t*, ev_check *w);

    static if (EV_FORK_ENABLED){
        void ev_fork_start(ev_loop_t*, ev_fork *w);
        void ev_fork_stop(ev_loop_t*, ev_fork *w);
    }

    static if (EV_EMBED_ENABLED)
    {
        // only supported when loop to be embedded is in fact embeddable
        void ev_embed_start(ev_loop_t*, ev_embed *w);
        void ev_embed_stop(ev_loop_t*, ev_embed *w);
        void ev_embed_sweep(ev_loop_t*, ev_embed *w);
    }
    static if (EV_ASYNC_ENABLED){
        void ev_async_start(ev_loop_t*, ev_async *w);
        void ev_async_stop(ev_loop_t*, ev_async *w);
        void ev_async_send(ev_loop_t*, ev_async *w);
    }
}
