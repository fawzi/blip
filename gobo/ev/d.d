/+
 + D Programming Language "bindings" to libev
 + <http://software.schmorp.de/pkg/libev.html>
 +
 + Written by Leandro Lucarella (2008).
 +
 + Placed under BOLA license <http://auriga.wearlab.de/~alb/bola/> which is
 + basically public domain.
 +
 +/

module gobo.ev.d;

import gobo.ev.c;
import blip.io.Console;
import blip.t.stdc.stringz;
private alias char[] string;

enum: uint
{
    UNDEF    = EV_UNDEF,
    NONE     = EV_NONE,
    READ     = EV_READ,
    WRITE    = EV_WRITE,
    IOFDSET  = EV_IOFDSET,
    TIMEOUT  = EV_TIMEOUT,
    PERIODIC = EV_PERIODIC,
    SIGNAL   = EV_SIGNAL,
    CHILD    = EV_CHILD,
    STAT     = EV_STAT,
    IDLE     = EV_IDLE,
    PREPARE  = EV_PREPARE,
    CHECK    = EV_CHECK,
    EMBED    = EV_EMBED,
    FORK     = EV_FORK,
    ERROR    = EV_ERROR,
}

enum: uint
{
    AUTO       = EVFLAG_AUTO,
    NOENV      = EVFLAG_NOENV,
    FORKCHECK  = EVFLAG_FORKCHECK,
    SELECT     = EVBACKEND_SELECT,
    POLL       = EVBACKEND_POLL,
    EPOLL      = EVBACKEND_EPOLL,
    KQUEUE     = EVBACKEND_KQUEUE,
    DEVPOLL    = EVBACKEND_DEVPOLL,
    PORT       = EVBACKEND_PORT,
}

enum
{
    NONBLOCK = EVLOOP_NONBLOCK,
    ONESHOT  = EVLOOP_ONESHOT,
}

enum Unloop
{
    CANCEL = EVUNLOOP_CANCEL,
    ONE    = EVUNLOOP_ONE,
    ALL    = EVUNLOOP_ALL,
}

alias ev_tstamp tstamp;

alias ev_statdata statdata;

int version_major()
{
    return ev_version_major();
}

int version_minor()
{
    return ev_version_minor();
}

uint supported_backends()
{
    return ev_supported_backends();
}

uint recommended_backends()
{
    return ev_recommended_backends();
}

uint embeddable_backends()
{
    return ev_embeddable_backends();
}

tstamp time()
{
    return ev_time();
}

void sleep(tstamp delay)
{
    void ev_sleep(tstamp delay);
}

private extern(C) void* allocator_thunk(alias Fn)(void* ptr, int size)
{
    return Fn(ptr, size);
}

// Fn is void* function(void* ptr, int size)
void set_allocator(alias Fn)()
{
    ev_set_allocator(&allocator_thunk!(Fn));
}

debug (ev_d_set_allocator)
{
    unittest
    {
        static void* alloc(void* ptr, int size)
        {
            sout("alloc(")(ptr)(", ")(size)(")\n");
            return null;
        }
        set_allocator!(alloc)();
        gobo.ev.d.loop;
    }
}

private extern(C) void syserr_thunk(alias Fn)(char* msg)
{
    char[] m = msg[0..strlen(msg)];
    Fn(m);
}

// Fn is void function(string msg)
void set_syserr_cb(alias Fn)()
{
    ev_set_syserr_cb(&syserr_thunk!(Fn));
}

unittest
{
    static void syserr(string msg)
    {
    }
    set_syserr_cb!(syserr)();
}


private alias extern (C) void function(int, void*) once_callback_t;

interface ILoop
{

    alias void delegate(ILoop, int, int) OnceCallback;

    ev_loop_t* ptr();

    void fork();

    tstamp now();

    uint backend();

    uint count();

    void loop(int flags = 0);

    void unloop(Unloop how = Unloop.ONE);

    void ioCollectInterval(tstamp interval);

    void timeoutCollectInterval(tstamp interval);

    void addref();

    void unref();

    void once(int fd, int events, tstamp timeout,
            once_callback_t cb, void* arg = null);

    void once(int fd, int events, tstamp timeout, OnceCallback cb);

    void once(int fd, int events, OnceCallback cb);

    void once(tstamp timeout, OnceCallback cb);

    void feedFdEvent(int fd, int revents);

    void feedSignalEvent(int signum);

}

private struct OnceData
{
    ILoop loop;
    int fd;
    ILoop.OnceCallback cb;
}

private extern(C) void once_thunk(int revents, void* arg)
{
    auto d = cast (OnceData*) arg;
    d.cb(d.loop, d.fd, revents);
}

template MLoop()
{

    ev_loop_t* ptr()
    {
        return _ptr;
    }

    tstamp now()
    {
        return ev_now(ptr);
    }

    uint backend()
    {
        return ev_backend(ptr);
    }

    uint count()
    {
        return ev_loop_count(ptr);
    }

    void loop(int flags = 0)
    {
        ev_loop(ptr, flags);
    }

    void unloop(Unloop how = Unloop.ONE)
    {
        ev_unloop(ptr, how);
    }

    void ioCollectInterval(tstamp interval)
    {
        ev_set_io_collect_interval(ptr, interval);
    }

    void timeoutCollectInterval(tstamp interval)
    {
        ev_set_timeout_collect_interval(ptr, interval);
    }

    void addref()
    {
        ev_ref(ptr);
    }

    void unref()
    {
        ev_unref(ptr);
    }

    void once(int fd, int events, tstamp timeout,
            once_callback_t cb, void* arg = null)
    {
        ev_once(ptr, fd, events, timeout, cb, arg);
    }

    void once(int fd, int events, tstamp timeout, OnceCallback cb)
    {
        auto d = new OnceData;
        d.cb = cb;
        d.fd = fd;
        d.loop = this;
        once(fd, events, timeout, &once_thunk, d);
    }

    void once(int fd, int events, OnceCallback cb)
    {
        once(fd, events, -1.0, cb);
    }

    void once(tstamp timeout, OnceCallback cb)
    {
        once(-1, NONE, timeout, cb);
    }

    void feedFdEvent(int fd, int revents)
    {
        return ev_feed_fd_event(ptr, fd, revents);
    }

    void feedSignalEvent(int signum)
    {
        return ev_feed_signal_event(ptr, signum);
    }

    private ev_loop_t* _ptr;

}

class Loop: ILoop
{

    mixin MLoop;

    this(uint flags = AUTO)
    {
        _ptr = ev_loop_new(flags);
    }

    ~this()
    {
        ev_loop_destroy(ptr);
    }

    void fork()
    {
        ev_loop_fork(ptr);
    }

    unittest
    {
        auto loop = new Loop;
        assert (loop.count == 0);
        loop.fork;
    }

}

private class DefaultLoop: ILoop
{

    mixin MLoop;

    this(uint flags = AUTO)
    {
        _ptr = ev_default_loop(flags);
    }

    ~this()
    {
        ev_default_destroy();
    }

    void fork()
    {
        ev_default_fork();
    }

    void destroy()
    {
        delete gobo.ev.d._loop;
        gobo.ev.d._loop = null;
    }

    unittest
    {
        debug (ev_d_DefaultLoop) sout("BEGIN UNITTEST\n");
        auto loop = new DefaultLoop;
        debug (ev_d_DefaultLoop) sout("loop.count = ")(loop.count)("\n");
        loop.fork;
        class C
        {
            void ev(ILoop loop, int fd, int revents)
            {
                debug (ev_d_DefaultLoop)
                {
                    sout("ev\n");
                    if (revents & READ) sout("\tREAD\n");
                    if (revents & TIMEOUT) sout("\tTIMEOUT\n");
                }
            }
        }
        C c = new C;
        loop.once(0, READ, 2.0, &c.ev);
        loop.loop(ONESHOT);
        debug (ev_d_DefaultLoop) sout("END UNITTEST\n");
    }

}

private DefaultLoop _loop;

DefaultLoop loop(uint flags = AUTO)
{
    if (!_loop) _loop = new DefaultLoop(flags);
    return _loop;
}

interface IWatcher
{

    void start();

    void stop();

    bool pending();

    bool active();

    int priority();

    void priority(int);

    ILoop loop();

    void loop(ILoop);

    void feed(int revents);

}

enum: bool
{
    RO = false,
    RW = true,
}

string property(string type, string proxy, string name, bool access = RW)()
{
    string s = "\n\t" ~ type ~ " " ~ name ~ "() {\n"
        "\t\treturn cast (" ~ type ~ ") " ~ proxy ~ "." ~ name ~ ";\n"
        "\t}\n";
    if (access == RW)
    {
        s ~= "\n\tvoid " ~ name ~ "(" ~ type ~ " " ~ name ~ ") {\n"
            "\t\t" ~ proxy ~ "." ~ name ~ " =  cast (" ~ type ~ ") " ~ name ~ ";\n"
            "\t}\n";
    }
    return s;
}

string wproperty(string type, string name, bool access = RW)()
{
    debug (ev_d_property)
        pragma(msg, "" ~ property!(type, "ptr", name, access));
    return property!(type, "ptr", name, access);
}

string dproperty(string type, string name, bool access = RW)()
{
    debug (ev_d_property)
        pragma(msg, "" ~ property!(type, "data", name, access));
    return property!(type, "data", name, access);
}

template MWatcher(DWatcher, CWatcher, alias StartFunc, alias StopFunc,
        bool DefineData = true)
{

    static if (DefineData) private struct WatcherData
    {
        Callback cb;
        DWatcher watcher;
    }

    alias void delegate(DWatcher, int revents) Callback;

    private extern(C) static void watcher_thunk(ev_loop_t* loop,
            CWatcher* watcher, int revents)
    {
        auto d = cast (WatcherData*) watcher.data;
        d.cb(d.watcher, revents);
    }

    private void init(ILoop loop, Callback cb)
    {
        ev_init(ptr, &watcher_thunk);
        auto d = new WatcherData;
        d.watcher = this;
        ptr.data = d;
        this.cb = cb;
        this.loop = loop;
    }

    ~this()
    {
        if (active) stop;
    }

    bool pending()
    {
        return ev_is_pending(ptr);
    }

    bool active()
    {
        return ev_is_active(ptr);
    }

    int priority()
    {
        return ev_priority(ptr);
    }

    void priority(int prio)
    {
        ev_set_priority(ptr, prio);
    }

    CWatcher* ptr()
    {
        return &_ptr;
    }

    ILoop loop()
    {
        return _loop;
    }

    void loop(ILoop loop)
    {
        bool a = active;
        if (a) stop;
        _loop = loop;
        if (a) start;
    }

    private ILoop _loop;

    private CWatcher _ptr;

    void start()
    {
        StartFunc(loop.ptr, ptr);
    }

    void stop()
    {
        StopFunc(loop.ptr, ptr);
    }

    void feed(int revents)
    {
        ev_feed_event(loop.ptr, ptr, revents);
    }

    private mixin (wproperty!("WatcherData*", "data"));

    mixin (dproperty!("Callback", "cb"));

}

class Io: IWatcher
{

    mixin MWatcher!(Io, ev_io, ev_io_start, ev_io_stop);

    this(int fd, int events, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_io_set(ptr, fd, events);
    }

    mixin (wproperty!("int", "fd", RO));

    mixin (wproperty!("int", "events", RO));

    debug (ev_d_Io)
    {
        import std.stdio;
    }
//    import std.c.unix.unix;
    unittest
    {
        auto w = new Io(0, READ, (Io w, int revents)
        {
            debug (ev_d_Io)
                sout("io callback: revents=")(revents)("\n");
            char[4096] buff;
            int r = read(w.fd, buff.ptr, buff.length);
            debug (ev_d_Io)
                sout("\tread ")(r)(" bytes:")(buff)("\n");
            w.loop.unloop;
        });
        gobo.ev.d.loop.loop;
    }

}

interface ITimer: IWatcher
{

    void again();

}

template MTimer(alias AgainFunc)
{

    void again()
    {
        AgainFunc(loop.ptr, ptr);
    }

}

class Timer: ITimer
{

    mixin MWatcher!(Timer, ev_timer, ev_timer_start, ev_timer_stop);

    mixin MTimer!(ev_timer_again);

    this(tstamp after, tstamp repeat, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_timer_set(ptr, after, repeat);
    }

    this(tstamp after, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        this(after, 0.0, cb, loop);
    }

    mixin (wproperty!("tstamp", "repeat"));

    unittest
    {
        auto w = new Timer(1.0, (Timer w, int revents)
        {
            debug (ev_d_Timer)
                sout("timeout callback: revents=")(revents);
            w.loop.unloop;
        });
        gobo.ev.d.loop.loop;
    }

}

class Periodic: ITimer
{

    mixin MWatcher!(Periodic, ev_periodic, ev_periodic_start,
            ev_periodic_stop, false);

    mixin MTimer!(ev_periodic_again);

    alias tstamp delegate(Periodic, tstamp) RescheduleCallback;

    private struct WatcherData
    {
        void delegate(Periodic, int) cb;
        RescheduleCallback reschedulecb;
        Periodic watcher;
    }

    private extern(C) static tstamp reschedule_thunk(ev_periodic* watcher,
            tstamp now)
    {
        auto d = cast (WatcherData*) watcher.data;
        return d.reschedulecb(d.watcher, now);
    }

    this(tstamp at, tstamp interval, RescheduleCallback reschedulecb,
            Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_periodic_set(ptr, at, interval, null);
        this.reschedulecb = reschedulecb;
    }

    void reschedulecb(RescheduleCallback reschedulecb)
    {
        if (reschedulecb is null) {
            ptr.reschedule_cb = null;
            data.reschedulecb = null;
        }
        else {
            ptr.reschedule_cb = &reschedule_thunk;
            data.reschedulecb = reschedulecb;
        }
    }

    mixin (dproperty!("RescheduleCallback", "reschedulecb", RO));

    mixin (wproperty!("tstamp", "offset"));

    mixin (wproperty!("tstamp", "interval"));

    mixin (wproperty!("tstamp", "at", RO));

}

class At: Periodic
{

    this(tstamp time, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        super(time, 0.0, null, cb, loop);
    }

}

class Cron: Periodic
{

    this(tstamp offset, tstamp interval, Callback cb,
            ILoop loop = gobo.ev.d.loop)
    in {
        assert (interval > 0);
    }
    body {
        super(offset, interval, null, cb, loop);
    }

}

class ManualCron: Periodic
{
    this(RescheduleCallback reschedulecb, Callback cb,
            ILoop loop = gobo.ev.d.loop)
    {
        super(0.0, 0.0, reschedulecb, cb, loop);
    }
}

class Signal: IWatcher
{

    mixin MWatcher!(Signal, ev_signal, ev_signal_start, ev_signal_stop);

    this(int signum, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_signal_set(ptr, signum);
    }

    mixin (wproperty!("int", "signum", RO));

}

class Child: IWatcher
{

    mixin MWatcher!(Child, ev_child, ev_child_start, ev_child_stop);

    this(int pid, bool trace, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_child_set(ptr, pid, trace);
    }

    this(int pid, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        this(pid, 0, cb, loop);
    }

    this(Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        this(0, 0, cb, loop);
    }

    mixin (wproperty!("int", "pid", RO));

    mixin (wproperty!("int", "rpid"));

    mixin (wproperty!("int", "rstatus"));

}

class Stat: IWatcher
{

    mixin MWatcher!(Stat, ev_stat, ev_stat_start, ev_stat_stop);

    this(string path, tstamp interval, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_stat_set(ptr, toStringz(path.dup), interval);
    }

    this(string path, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        this(path, 0.0, cb, loop);
    }

    void stat()
    {
        ev_stat_stat(loop.ptr, ptr);
    }

    mixin (wproperty!("statdata", "attr", RO));

    mixin (wproperty!("statdata", "prev", RO));

    mixin (wproperty!("tstamp", "interval", RO));

    /+
    void path(string path)
    {
        ptr.path = toStringz(path.dup);
    }
    +/

    string path()
    {
        return fromStringz(ptr.path).dup;
    }

}

class Idle: IWatcher
{

    mixin MWatcher!(Idle, ev_idle, ev_idle_start, ev_idle_stop);

    this(Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_idle_set(ptr);
    }

}

class Prepare: IWatcher
{

    mixin MWatcher!(Prepare, ev_prepare, ev_prepare_start, ev_prepare_stop);

    this(Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_prepare_set(ptr);
    }

}

class Check: IWatcher
{

    mixin MWatcher!(Check, ev_check, ev_check_start, ev_check_stop);

    this(Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_check_set(ptr);
    }

}

class Embed: IWatcher
{

    mixin MWatcher!(Embed, ev_embed, ev_embed_start, ev_embed_stop, false);

    private struct WatcherData
    {
        void delegate(Embed, int) cb;
        ILoop other;
        Embed watcher;
    }

    this(ILoop embeddedloop, Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_embed_set(ptr, embeddedloop.ptr);
        this.other = embeddedloop;
    }

    void sweep()
    {
        ev_embed_sweep(loop.ptr, ptr);
    }

    void other(ILoop other)
    {
        data.other = other;
        ev_embed_set(ptr, other.ptr);
    }

    mixin (dproperty!("ILoop", "other", RO));

}

class Fork: IWatcher
{

    mixin MWatcher!(Fork, ev_fork, ev_fork_start, ev_fork_stop);

    this(Callback cb, ILoop loop = gobo.ev.d.loop)
    {
        init(loop, cb);
        ev_fork_set(ptr);
    }

}

