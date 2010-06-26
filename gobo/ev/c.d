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

module gobo.ev.c;

private alias char[] string;
extern (C):
align (4):

enum: uint
{
    EV_UNDEF    = 0xFFFFFFFFL, // guaranteed to be invalid
    EV_NONE     =       0x00L, // no events
    EV_READ     =       0x01L, // ev_io detected read will not block
    EV_WRITE    =       0x02L, // ev_io detected write will not block
    EV_IOFDSET  =       0x80L, // internal use only
    EV_TIMEOUT  = 0x00000100L, // timer timed out
    EV_PERIODIC = 0x00000200L, // periodic timer timed out
    EV_SIGNAL   = 0x00000400L, // signal was received
    EV_CHILD    = 0x00000800L, // child/pid had status change
    EV_STAT     = 0x00001000L, // stat data changed
    EV_IDLE     = 0x00002000L, // event loop is idling
    EV_PREPARE  = 0x00004000L, // event loop about to poll
    EV_CHECK    = 0x00008000L, // event loop finished poll
    EV_EMBED    = 0x00010000L, // embedded event loop needs sweep
    EV_FORK     = 0x00020000L, // event loop resumed in child
    EV_ERROR    = 0x80000000L, // sent when an error occurs
}

enum: uint
{
    // bits for ev_default_loop and ev_loop_new
    // the default
    EVFLAG_AUTO       = 0x00000000UL, // not quite a mask
    // flag bits
    EVFLAG_NOENV      = 0x01000000UL, // do NOT consult environment
    EVFLAG_FORKCHECK  = 0x02000000UL, // check for a fork in each iteration
    // method bits to be ored together
    EVBACKEND_SELECT  = 0x00000001UL, // about anywhere
    EVBACKEND_POLL    = 0x00000002UL, // !win
    EVBACKEND_EPOLL   = 0x00000004UL, // linux
    EVBACKEND_KQUEUE  = 0x00000008UL, // bsd
    EVBACKEND_DEVPOLL = 0x00000010UL, // solaris 8 / NYI
    EVBACKEND_PORT    = 0x00000020UL, // solaris 10
}

enum
{
    EVLOOP_NONBLOCK = 1, // do not block/wait
    EVLOOP_ONESHOT  = 2, // block *once* only
}

enum
{
    EVUNLOOP_CANCEL = 0, // undo unloop
    EVUNLOOP_ONE    = 1, // unloop once
    EVUNLOOP_ALL    = 2, // unloop all loops
}

version (EV_ENABLE_SELECT)
{
}
else
{
    version = EV_PERIODIC_ENABLE;
    version = EV_STAT_ENABLE;
    version = EV_IDLE_ENABLE;
    version = EV_FORK_ENABLE;
    version = EV_EMBED_ENABLE;
}

alias double ev_tstamp;

struct ev_loop_t;

template EV_COMMON()
{
    void* data;
}

template EV_CB_DECLARE(TYPE)
{
    void function (ev_loop_t*, TYPE*, int) cb;
}

template EV_WATCHER(TYPE)
{
    int active;                 // private
    int pending;                // private
    int priority;               // private
    mixin EV_COMMON;            // rw
    mixin EV_CB_DECLARE!(TYPE); // private
}

template EV_WATCHER_LIST(TYPE)
{
    mixin EV_WATCHER!(TYPE);
    ev_watcher_list* next;      // private
}

template EV_WATCHER_TIME(TYPE)
{
    mixin EV_WATCHER!(TYPE);
    ev_tstamp at;               // private
}

struct ev_watcher
{
    mixin EV_WATCHER!(ev_watcher);
}

struct ev_watcher_list
{
    mixin EV_WATCHER_LIST!(ev_watcher_list);
}

struct ev_watcher_time
{
    mixin EV_WATCHER_TIME!(ev_watcher_time);
}

struct ev_io
{
    mixin EV_WATCHER_LIST!(ev_io);
    int fd;     // ro
    int events; // ro
}

struct ev_timer
{
    mixin EV_WATCHER_TIME!(ev_timer);
    ev_tstamp repeat; // rw
}

version (EV_PERIODIC_ENABLE)
{
    struct ev_periodic
    {
        mixin EV_WATCHER_TIME!(ev_periodic);
        ev_tstamp offset;                     // rw
        ev_tstamp interval;                   // rw
        ev_tstamp function(ev_periodic *w,
                ev_tstamp now) reschedule_cb; // rw
    }
}

struct ev_signal
{
    mixin EV_WATCHER_LIST!(ev_signal);
    int signum; // ro
}

struct ev_child
{
    mixin EV_WATCHER_LIST!(ev_child);
    int flags;   // private
    int pid;     // ro
    int rpid;    // rw, holds the received pid
    int rstatus; // rw, holds the exit status, use the
    // macros from sys/wait.h
}

version (EV_STAT_ENABLE)
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

    struct ev_stat
    {
        mixin EV_WATCHER_LIST!(ev_stat);

        ev_timer timer;     // private
        ev_tstamp interval; // ro
        char *path;   // ro
        ev_statdata prev;   // ro
        ev_statdata attr;   // ro
        int wd; // wd for inotify, fd for kqueue
    }
}

version (EV_IDLE_ENABLE)
{
    struct ev_idle
    {
        mixin EV_WATCHER!(ev_idle);
    }
}

struct ev_prepare
{
    mixin EV_WATCHER!(ev_prepare);
}

struct ev_check
{
    mixin EV_WATCHER!(ev_check);
}

version (EV_FORK_ENABLE)
{
    struct ev_fork
    {
        mixin EV_WATCHER!(ev_fork);
    }
}

version (EV_EMBED_ENABLE)
{
    struct ev_embed
    {
        mixin EV_WATCHER!(ev_embed);
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

int ev_version_major();
int ev_version_minor();

uint ev_supported_backends();
uint ev_recommended_backends();
uint ev_embeddable_backends();

ev_tstamp ev_time();
void ev_sleep(ev_tstamp delay); // sleep for a while

// Sets the allocation function to use, works like realloc.
// It is used to allocate and free memory.
// If it returns zero when memory needs to be allocated, the library
// might abort
// or take some potentially destructive action.
// The default is your system realloc function.
void ev_set_allocator(void* function(void* ptr, int size));

// set the callback function to call on a
// retryable syscall error
// (such as failed select, poll, epoll_wait)
void ev_set_syserr_cb(void function(char* msg));

extern ev_loop_t* ev_default_loop_ptr;

ev_loop_t* ev_default_loop_init(uint flags);

// create and destroy alternative loops that don't handle signals
ev_loop_t* ev_loop_new(uint flags);
void ev_loop_destroy(ev_loop_t*);
void ev_loop_fork(ev_loop_t*);

ev_tstamp ev_now(ev_loop_t*);
void ev_default_destroy();
void ev_default_fork();
uint ev_backend(ev_loop_t*);
uint ev_loop_count(ev_loop_t*);
void ev_loop(ev_loop_t*, int flags);
void ev_unloop(ev_loop_t*, int);
void ev_set_io_collect_interval(ev_loop_t*, ev_tstamp interval);
void ev_set_timeout_collect_interval(ev_loop_t*, ev_tstamp interval);
void ev_ref(ev_loop_t*);
void ev_unref(ev_loop_t*);
void ev_once(ev_loop_t*, int fd, int events, ev_tstamp timeout,
        void function(int revents, void* arg), void* arg);

void ev_feed_event(ev_loop_t*, void *w, int revents);
void ev_feed_fd_event(ev_loop_t*, int fd, int revents);
void ev_feed_signal_event (ev_loop_t*, int signum);
void ev_invoke(ev_loop_t*, void *w, int revents);
int  ev_clear_pending(ev_loop_t*, void *w);

void ev_io_start(ev_loop_t*, ev_io *w);
void ev_io_stop(ev_loop_t*, ev_io *w);

void ev_timer_start(ev_loop_t*, ev_timer *w);
void ev_timer_stop(ev_loop_t*, ev_timer *w);
void ev_timer_again(ev_loop_t*, ev_timer *w);

version (EV_PERIODIC_ENABLE)
{
    void ev_periodic_start(ev_loop_t*, ev_periodic *w);
    void ev_periodic_stop(ev_loop_t*, ev_periodic *w);
    void ev_periodic_again(ev_loop_t*, ev_periodic *w);
}

void ev_signal_start(ev_loop_t*, ev_signal *w);
void ev_signal_stop(ev_loop_t*, ev_signal *w);

/* only supported in the default loop */
void ev_child_start(ev_loop_t*, ev_child *w);
void ev_child_stop(ev_loop_t*, ev_child *w);

version (EV_STAT_ENABLE)
{
    void ev_stat_start(ev_loop_t*, ev_stat *w);
    void ev_stat_stop(ev_loop_t*, ev_stat *w);
    void ev_stat_stat(ev_loop_t*, ev_stat *w);
}

version (EV_IDLE_ENABLE)
{
    void ev_idle_start(ev_loop_t*, ev_idle *w);
    void ev_idle_stop(ev_loop_t*, ev_idle *w);
}

void ev_prepare_start(ev_loop_t*, ev_prepare *w);
void ev_prepare_stop(ev_loop_t*, ev_prepare *w);

void ev_check_start(ev_loop_t*, ev_check *w);
void ev_check_stop(ev_loop_t*, ev_check *w);

version (EV_FORK_ENABLE)
{
    void ev_fork_start(ev_loop_t*, ev_fork *w);
    void ev_fork_stop(ev_loop_t*, ev_fork *w);
}

version (EV_EMBED_ENABLE)
{
    // only supported when loop to be embedded is in fact embeddable
    void ev_embed_start(ev_loop_t*, ev_embed *w);
    void ev_embed_stop(ev_loop_t*, ev_embed *w);
    void ev_embed_sweep(ev_loop_t*, ev_embed *w);
}

bool ev_is_pending(TYPE)(TYPE* w)
{
    return cast (bool) w.pending;
}

bool ev_is_active(TYPE)(TYPE* w)
{
    return cast (bool) w.active;
}

int ev_priority(TYPE)(TYPE* w)
{
    return cast (bool) w.priority;
}

void function(ev_loop_t*, TYPE*, int) ev_cb(TYPE)(TYPE* w)
{
    return w.cb;
}

void ev_set_priority(TYPE)(TYPE* w, int pri)
{
    w.priority = pri;
}

void ev_set_cb(TYPE)(TYPE* w,
        void function(ev_loop_t*, TYPE*, int) cb)
{
    w.cb = cb;
}

void ev_init(TYPE)(TYPE* w,
        void function(ev_loop_t*, TYPE*, int) cb)
{
    w.active = 0;
    w.pending = 0;
    w.priority = 0;
    ev_set_cb(w, cb);
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

void ev_periodic_set(ev_periodic* w, ev_tstamp ofs, ev_tstamp ival,
        ev_tstamp function(ev_periodic *w, ev_tstamp now) res)
{
    w.offset = ofs;
    w.interval = ival;
    w.reschedule_cb = res;
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

void ev_stat_set(ev_stat* w, char* path, ev_tstamp interval)
{
    w.path = path;
    w.interval = interval;
    w.wd = -2;
}

void ev_idle_set(ev_idle* w)
{
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

void ev_fork_set(ev_fork* w)
{
}

void ev_io_init(ev_io* w, void function(ev_loop_t*, ev_io*, int) cb, int fd,
        int events)
{
    ev_init(w, cb);
    ev_io_set(w, fd, events);
}

void ev_timer_init(ev_timer* w, void function(ev_loop_t*, ev_timer*, int) cb,
        ev_tstamp after, ev_tstamp repeat)
{
    ev_init(w, cb);
    ev_timer_set(w, after, repeat);
}

void ev_periodic_init(ev_periodic* w,
        void function(ev_loop_t*, ev_periodic*, int) cb,
        ev_tstamp ofs, ev_tstamp ival,
        ev_tstamp function(ev_periodic *w, ev_tstamp now) res)
{
    ev_init(w, cb);
    ev_periodic_set(w, ofs, ival, res);
}

void ev_signal_init(ev_signal* w, void function(ev_loop_t*, ev_signal*, int) cb,
        int signum)
{
    ev_init(w, cb);
    ev_signal_set(w, signum);
}

void ev_child_init(ev_child* w, void function(ev_loop_t*, ev_child*, int) cb,
        int pid, int trace)
{
    ev_init(w, cb);
    ev_child_set(w, pid, trace);
}

void ev_stat_init(ev_stat* w, void function(ev_loop_t*, ev_stat*, int) cb,
        char* path, ev_tstamp interval)
{
    ev_init(w, cb);
    ev_stat_set(w, path, interval);
}

void ev_idle_init(ev_idle* w, void function(ev_loop_t*, ev_idle*, int) cb)
{
    ev_init(w, cb);
    ev_idle_set(w);
}

void ev_prepare_init(ev_prepare* w,
        void function(ev_loop_t*, ev_prepare*, int) cb)
{
    ev_init(w, cb);
    ev_prepare_set(w);
}

void ev_check_init(ev_check* w, void function(ev_loop_t*, ev_check*, int) cb)
{
    ev_init(w, cb);
    ev_check_set(w);
}

void ev_embed_init(ev_embed* w, void function(ev_loop_t*, ev_embed*, int) cb,
        ev_loop_t* other)
{
    ev_init(w, cb);
    ev_embed_set(w, other);
}

void ev_fork_init(ev_fork* w, void function(ev_loop_t*, ev_fork*, int) cb)
{
    ev_init(w, cb);
    ev_fork_set(w);
}

ev_loop_t* ev_default_loop(uint flags = EVFLAG_AUTO)
{
    if (!ev_default_loop_ptr)
        ev_default_loop_init(flags);
    return ev_default_loop_ptr;
}

version (UnitTest):
version (Tango){} else { // to do: convert
extern (D):
import blip.io.Console;
import stdlib = blip.stdc.stdlib;
import str = blip.stdc.string;
import unix = std.c.unix.unix;
import proc = std.c.process;
enum { SIGINT = 2 }
const STAT_FILE = "/tmp/libev-stat-test-file";
const TEST_TEXT = "hello";
bool prepare_done = false;
bool check_done = false;
bool idle_done = false;
bool timer_done = false;
bool io_done = false;
bool stat_done = false;
bool child_done = false;
bool signal_done = false;
bool eio_done = false;
int child_pid = -1;
unittest
{
    stdio.writefln("Unittesting...");
    extern (C) static void cbprepare(ev_loop_t* loop, ev_prepare* w, int revents)
    {
        stdio.writefln("ev_prepare");
        assert (!prepare_done);
        assert (!check_done);
        assert (!idle_done);
        assert (!timer_done);
        assert (!io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        prepare_done = true;
        ev_prepare_stop(loop, w);
    }
    extern (C) static void cbcheck(ev_loop_t* loop, ev_check* w, int revents)
    {
        stdio.writefln("ev_check");
        assert (prepare_done);
        assert (!check_done);
        assert (!idle_done);
        assert (!timer_done);
        assert (!io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        check_done = true;
        ev_check_stop(loop, w);
    }
    extern (C) static void cbidle(ev_loop_t* loop, ev_idle* w, int revents)
    {
        stdio.writefln("ev_idle");
        assert (prepare_done);
        assert (check_done);
        assert (!idle_done);
        assert (!timer_done);
        assert (!io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        idle_done = true;
        ev_idle_stop(loop, w);
    }
    extern (C) static void cbtimer(ev_loop_t* loop, ev_timer* w,
            int revents)
    {
        stdio.writefln("ev_timer");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (!timer_done);
        assert (!io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        timer_done = true;
        ev_timer_stop(loop, w);
        stdio.writefln("\tfiring ev_io");
        stdio.writefln("\t\topening pipe for writing...");
        int pipe_fd = *cast (int*) w.data;
        stdio.writefln("\t\twriting '%s' to pipe...", TEST_TEXT);
        int n = unix.write(pipe_fd, cast (void*) TEST_TEXT,
                TEST_TEXT.length);
        assert (n == TEST_TEXT.length);
    }
    extern (C) static void cbio(ev_loop_t* loop, ev_io* w, int revents)
    {
        stdio.writefln("ev_io");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (!io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        io_done = true;
        ev_io_stop(loop, w);
        char[TEST_TEXT.length] buffer;
        stdio.writefln("\treading %d bytes from pipe...",
                buffer.length);
        int n = unix.read(w.fd, cast (void*) buffer, buffer.length);
        assert (n == TEST_TEXT.length);
        assert (buffer.dup == TEST_TEXT.dup);
        stdio.writefln("\tread '%s'", buffer);
        stdio.writefln("\tfiring ev_stat");
        stdio.writefln("\t\topening file '%s'", STAT_FILE);
        int fd = unix.open(str.toStringz(STAT_FILE),
                unix.O_WRONLY | unix.O_TRUNC | unix.O_CREAT);
        assert (fd != -1);
        stdio.writefln("\t\tfd: %d", fd);
        n = unix.write(fd, cast (void*) TEST_TEXT,
                TEST_TEXT.length);
        assert (n == TEST_TEXT.length);
        unix.close(fd);
    }
    extern (C) static void cbstat(ev_loop_t* loop, ev_stat* w, int revents)
    {
        stdio.writefln("ev_stat");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (io_done);
        assert (!stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        stat_done = true;
        ev_stat_stop(loop, w);
        static void print_stat(ev_statdata* s)
        {
            stdio.writefln("\t\t\tinode: ", s.st_ino);
            stdio.writefln("\t\t\tmode: ", s.st_mode);
            stdio.writefln("\t\t\tlinks: ", s.st_nlink);
            stdio.writefln("\t\t\tuid: ", s.st_uid);
            stdio.writefln("\t\t\tgid: ", s.st_gid);
            stdio.writefln("\t\t\tsize: ", s.st_size);
            stdio.writefln("\t\t\tatime: ", s.st_atime);
            stdio.writefln("\t\t\tmtime: ", s.st_mtime);
            stdio.writefln("\t\t\tctime: ", s.st_ctime);
        }
        if (w.attr.st_nlink)
        {
            stdio.writefln("\tfile '%s' changed", str.toString(w.path));
            stdio.writefln("\t\tprevios state:");
            print_stat(&w.prev);
            stdio.writefln("\t\tcurrent state:");
            print_stat(&w.attr);
        }
        else
        {
            stdio.writefln("\tfile '%s' does not exist!",
                    str.toString(w.path));
            stdio.writefln("\t\tprevios state:");
            print_stat(&w.prev);
        }
        stdio.writefln("\tfiring ev_fork...");
        stdio.writefln("\t\tforking...");
        auto pid = unix.fork();
        assert (pid != -1);
        if (pid)
        {
            child_pid = pid;
            stdio.writefln("\t\tev_stat: in parent, child pid: ", pid);
        }
        else
        {
            stdio.writefln("\t\tev_stat: in child, calling "
                    "ev_default_fork...");
            ev_default_fork();
        }
    }
    extern (C) static void cbchild(ev_loop_t* loop, ev_child* w, int revents)
    {
        stdio.writefln("ev_child");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (io_done);
        assert (stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        child_done = true;
        ev_child_stop(loop, w);
        static ubyte WEXITSTATUS(int s)
        {
            return cast(ubyte)((s & 0xff00) >> 8);
        }
        static ubyte WTERMSIG(int s)
        {
            return cast(ubyte)(s & 0x7f);
        }
        static bool WIFEXITED(int s)
        {
            return WTERMSIG(s) == 0;
        }
        static bool WIFSIGNALED(int s)
        {
            return cast(byte)(((s & 0x7f) + 1) >> 1) > 0;
        }
        static bool WCOREDUMP(int s)
        {
            return cast(bool)(s & 0x80);
        }
        stdio.writefln("\tthe child with pid %d exited with status "
                "%d", w.rpid, w.rstatus);
        assert (child_pid == w.rpid);
        if (WIFEXITED(w.rstatus))
            stdio.writefln("\tchild exited normally with code ",
                    WEXITSTATUS(w.rstatus));
        if (WIFSIGNALED(w.rstatus))
        {
            stdio.writefln("\tchild exited with signal ",
                    WTERMSIG(w.rstatus));
            if (WCOREDUMP(w.rstatus))
                stdio.writefln("\tchild produced a core dump");
        }
        assert (WIFEXITED(w.rstatus) && WEXITSTATUS(w.rstatus) == 5);
        stdio.writefln("\tfiring ev_signal");
        stdio.writefln("\t\tsending signal 2 (SIGINT)");
        unix.kill(proc.getpid(), SIGINT);
    }
    extern (C) static void cbfork(ev_loop_t* loop, ev_fork* w, int revents)
    {
        stdio.writefln("ev_fork");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (io_done);
        assert (stat_done);
        assert (!child_done);
        assert (!signal_done);
        assert (!eio_done);
        ev_fork_stop(loop, w);
        stdio.writefln("\texiting the child program with return "
                "code 5");
        stdlib.exit(5);
    }
    extern (C) static void cbsignal(ev_loop_t* loop, ev_signal* w,
            int revents)
    {
        stdio.writefln("ev_signal");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (io_done);
        assert (stat_done);
        assert (child_done);
        assert (!signal_done);
        assert (!eio_done);
        signal_done = true;
        ev_signal_stop(loop, w);
        stdio.writefln("\tfiring embeded ev_io...");
        stdio.writefln("\t\topening pipe for writing...");
        int pipe_fd = *cast(int*)w.data;
        stdio.writefln("\t\twriting '%s' to pipe...", TEST_TEXT);
        int n = unix.write(pipe_fd, cast(void*)TEST_TEXT,
                TEST_TEXT.length);
        assert (n == TEST_TEXT.length);
    }
    extern (C) static void ecbio(ev_loop_t* loop, ev_io* w, int revents)
    {
        stdio.writefln("embeded ev_io");
        assert (prepare_done);
        assert (check_done);
        assert (idle_done);
        assert (timer_done);
        assert (io_done);
        assert (stat_done);
        assert (child_done);
        assert (signal_done);
        assert (!eio_done);
        eio_done = true;
        //ev_io_stop(loop, w);
        char[TEST_TEXT.length] buffer;
        stdio.writefln("\treading %d bytes from pipe...",
                buffer.length);
        int n = unix.read(w.fd, cast (void*) buffer, buffer.length);
        assert (n == TEST_TEXT.length);
        assert (buffer.dup == TEST_TEXT.dup);
        stdio.writefln("\tread '%s'", buffer);
        stdio.writefln("\tstoping the loop");
        ev_unloop(loop, EVUNLOOP_ONE);
    }
    extern (C) static void cbembed(ev_loop_t* loop, ev_embed* w, int revents)
    {
        stdio.writefln("ev_embed");
        stdio.writefln("\tsweeping embeded loop...");
        ev_embed_sweep(w.other, w);
        //ev_embed_stop(loop, w);
    }

    auto loop = ev_default_loop(0);

    ev_io wio;
    ev_io ewio;
    ev_timer wtimer;
    ev_signal wsignal;
    ev_child wchild;
    ev_stat wstat;
    ev_idle widle;
    ev_prepare wprepare;
    ev_check wcheck;
    ev_fork wfork;
    ev_embed wembed;

    ev_loop_t* eloop = ev_embeddable_backends() & ev_recommended_backends()
        ? ev_loop_new(ev_embeddable_backends () &
                ev_recommended_backends ())
        : null;

    if (eloop)
    {
        stdio.writefln("Initializing embeded loop");
        ev_embed_init(&wembed, &cbembed, eloop);
        ev_embed_start(loop, &wembed);
    }
    else
    {
        stdio.writefln("No embeded loop, using the default");
        eloop = loop;
    }

    int[2] epipe;
    {
        int ret = unix.pipe(epipe);
        assert (ret == 0);
    }
    ev_io_init(&ewio, &ecbio, epipe[0], EV_READ);
    ev_io_start(eloop, &ewio);

    int[2] pipe;
    {
        int ret = unix.pipe(pipe);
        assert (ret == 0);
    }

    ev_io_init(&wio, &cbio, pipe[0], EV_READ);
    ev_io_start(loop, &wio);

    ev_timer_init(&wtimer, &cbtimer, 1.5, 0.);
    wtimer.data = &pipe[1]; // write fd
    ev_timer_start(loop, &wtimer);

    ev_signal_init(&wsignal, &cbsignal, SIGINT);
    wsignal.data = &epipe[1]; // write fd
    ev_signal_start(loop, &wsignal);

    ev_child_init(&wchild, &cbchild, 0 /* trace any PID */, 0 /* death */);
    ev_child_start(loop, &wchild);

    ev_stat_init(&wstat, &cbstat, str.toStringz(STAT_FILE), 0 /* auto */);
    ev_stat_start(loop, &wstat);

    ev_idle_init(&widle, &cbidle);
    ev_idle_start(loop, &widle);

    ev_prepare_init(&wprepare, &cbprepare);
    ev_prepare_start(loop, &wprepare);

    ev_check_init(&wcheck, &cbcheck);
    ev_check_start(loop, &wcheck);

    ev_fork_init(&wfork, &cbfork);
    ev_fork_start(loop, &wfork);

    ev_loop(loop, 0);

    assert (prepare_done);
    assert (check_done);
    assert (idle_done);
    assert (timer_done);
    assert (io_done);
    assert (stat_done);
    assert (child_done);
    assert (signal_done);
    assert (eio_done);

    stdio.writefln("Unittesting done!");

}
}
