/// test of the c libev bindings taken from the unittest of the c bindings
/// of the one written by Leandro Lucarella (2008) and available at
/// http://git.llucax.com.ar/w/software/ev.d.git and placed under BOLA license
/// <http://auriga.wearlab.de/~alb/bola/> which is compatible with the apache license 2.0 used in
/// this project.
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
module testLibev;
import blip.bindings.ev.Libev;
import blip.io.Console;
import stdlib = blip.stdc.stdlib;
import unistd = tango.stdc.posix.unistd;
import blip.stdc.stringz;
import blip.stdc.string:strlen;
import signal=tango.stdc.posix.signal;
import fcntl = tango.stdc.posix.fcntl;
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

void aassert(bool v,long line){
    if (!v){
        throw new Exception("aassert failed",__FILE__,line);
    }
}

extern (C) static void cbprepare(ev_loop_t* loop, ev_prepare* w, int revents)
{
    sout("ev_prepare\n");
    aassert (!prepare_done,__LINE__);
    aassert (!check_done,__LINE__);
    aassert (!idle_done,__LINE__);
    aassert (!timer_done,__LINE__);
    aassert (!io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    prepare_done = true;
    ev_prepare_stop(loop, w);
}
extern (C) static void cbcheck(ev_loop_t* loop, ev_check* w, int revents)
{
    sout("ev_check\n");
    aassert (prepare_done,__LINE__);
    aassert (!check_done,__LINE__);
    aassert (!idle_done,__LINE__);
    aassert (!timer_done,__LINE__);
    aassert (!io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    check_done = true;
    ev_check_stop(loop, w);
}
extern (C) static void cbidle(ev_loop_t* loop, ev_idle* w, int revents)
{
    sout("ev_idle\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (!idle_done,__LINE__);
    aassert (!timer_done,__LINE__);
    aassert (!io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    idle_done = true;
    ev_idle_stop(loop, w);
}
extern (C) static void cbtimer(ev_loop_t* loop, ev_timer* w,
        int revents)
{
    sout("ev_timer\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (!timer_done,__LINE__);
    aassert (!io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    timer_done = true;
    ev_timer_stop(loop, w);
    sout("\tfiring ev_io\n");
    sout("\t\topening pipe for writing...\n");
    int pipe_fd = *cast (int*) w.data;
    sout("\t\twriting '")(TEST_TEXT)("' to pipe...\n");
    long n = unistd.write(pipe_fd, cast (void*) TEST_TEXT,
                          cast(int)TEST_TEXT.length);
    aassert (n == TEST_TEXT.length,__LINE__);
}
extern (C) static void cbio(ev_loop_t* loop, ev_io* w, int revents)
{
    sout("ev_io\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (!io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    io_done = true;
    ev_io_stop(loop, w);
    char[TEST_TEXT.length] buffer;
    sout("\treading ")(buffer.length)(" bytes from pipe...");
    long n = unistd.read(w.fd, cast (void*) buffer, buffer.length);
    aassert (n == TEST_TEXT.length,__LINE__);
    aassert (buffer.dup == TEST_TEXT.dup,__LINE__);
    sout("\tread '")(buffer)("'\n");
    sout("\tfiring ev_stat\n");
    sout("\t\topening file '")(STAT_FILE)("'\n");
    int fd = fcntl.open(toStringz(STAT_FILE),
            fcntl.O_WRONLY | fcntl.O_TRUNC | fcntl.O_CREAT);
    aassert (fd != -1,__LINE__);
    sout("\t\tfd: ")(fd)("\n");
    n = unistd.write(fd, cast (void*) TEST_TEXT,
                     TEST_TEXT.length);
    aassert (n == TEST_TEXT.length,__LINE__);
    unistd.close(fd);
}
extern (C) static void cbstat(ev_loop_t* loop, ev_stat* w, int revents)
{
    sout("ev_stat\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (!stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    stat_done = true;
    ev_stat_stop(loop, w);
    static void print_stat(ev_statdata* s)
    {
        sout("\t\t\tinode: ")(s.st_ino)("\n");
        sout("\t\t\tmode: ")(s.st_mode)("\n");
        sout("\t\t\tlinks: ")(s.st_nlink)("\n");
        sout("\t\t\tuid: ")(s.st_uid)("\n");
        sout("\t\t\tgid: ")(s.st_gid)("\n");
        sout("\t\t\tsize: ")(s.st_size)("\n");
        sout("\t\t\tatime: ")(s.st_atime)("\n");
        sout("\t\t\tmtime: ")(s.st_mtime)("\n");
        sout("\t\t\tctime: ")(s.st_ctime)("\n");
    }
    if (w.attr.st_nlink)
    {
        sout("\tfile '")(w.path[0..strlen(w.path)])("' changed\n");
        sout("\t\tprevios state:\n");
        print_stat(&w.prev);
        sout("\t\tcurrent state:\n");
        print_stat(&w.attr);
    }
    else
    {
        sout("\tfile '")(w.path[0..strlen(w.path)])("' does not exist!\n");
        sout("\t\tprevios state:\n");
        print_stat(&w.prev);
    }
    sout("\tfiring ev_fork...\n");
    sout("\t\tforking...\n");
    auto pid = unistd.fork();
    assert (pid != -1);
    if (pid)
    {
        child_pid = pid;
        sout("\t\tev_stat: in parent, child pid: ")(pid)("\n");
    }
    else
    {
        sout("\t\tev_stat: in child, calling "
             "ev_default_fork...\n");
        ev_loop_fork(ev_default_loop());
    }
}
extern (C) static void cbchild(ev_loop_t* loop, ev_child* w, int revents)
{
    sout("ev_child\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
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
    sout("\tthe child with pid ")(w.rpid)(" exited with status ")(w.rstatus)("\n");
    aassert (child_pid == w.rpid,__LINE__);
    if (WIFEXITED(w.rstatus))
        sout("\tchild exited normally with code ")
                (WEXITSTATUS(w.rstatus))("\n");
    if (WIFSIGNALED(w.rstatus))
    {
        sout("\tchild exited with signal ")
                (WTERMSIG(w.rstatus))("\n");
        if (WCOREDUMP(w.rstatus))
            sout("\tchild produced a core dump\n");
    }
    aassert (WIFEXITED(w.rstatus) && WEXITSTATUS(w.rstatus) == 5,__LINE__);
    sout("\tfiring ev_signal\n");
    sout("\t\tsending signal 2 (SIGINT)\n");
    signal.kill(unistd.getpid(), SIGINT);
}
extern (C) static void cbfork(ev_loop_t* loop, ev_fork* w, int revents)
{
    sout("ev_fork\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (stat_done,__LINE__);
    aassert (!child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    ev_fork_stop(loop, w);
    sout("\texiting the child program with return "
            "code 5\n");
    stdlib.exit(5);
}
extern (C) static void cbsignal(ev_loop_t* loop, ev_signal* w,
        int revents)
{
    sout("ev_signal\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (stat_done,__LINE__);
    aassert (child_done,__LINE__);
    aassert (!signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    signal_done = true;
    ev_signal_stop(loop, w);
    sout("\tfiring embeded ev_io...\n");
    sout("\t\topening pipe for writing...\n");
    int pipe_fd = *cast(int*)w.data;
    sout("\t\twriting '%s' to pipe...")(TEST_TEXT)("\n");
    long n = unistd.write(pipe_fd, cast(void*)TEST_TEXT,
            TEST_TEXT.length);
    aassert (n == TEST_TEXT.length,__LINE__);
}
extern (C) static void ecbio(ev_loop_t* loop, ev_io* w, int revents)
{
    sout("embeded ev_io\n");
    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (stat_done,__LINE__);
    aassert (child_done,__LINE__);
    aassert (signal_done,__LINE__);
    aassert (!eio_done,__LINE__);
    eio_done = true;
    //ev_io_stop(loop, w);
    char[TEST_TEXT.length] buffer;
    sout("\treading ")(buffer.length)(" bytes from pipe...\n");
    long n = unistd.read(w.fd, cast (void*) buffer, buffer.length);
    aassert (n == TEST_TEXT.length,__LINE__);
    aassert (buffer.dup == TEST_TEXT.dup,__LINE__);
    sout("\tread '")(buffer)("'\n");
    sout("\tstoping the loop\n");
    //    ev_break(loop, EV_BREAK.ONE);
    ev_break(ev_default_loop(), EV_BREAK.ALL);
    sout("\tstopped the loop\n");
}
extern (C) static void cbembed(ev_loop_t* loop, ev_embed* w, int revents)
{
    sout("ev_embed\n");
    sout("\tsweeping embeded loop...\n");
    ev_embed_sweep(w.other, w);
    // ev_embed_stop(loop, w);
}

void main(){
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
        sout("Initializing embeded loop\n");
        ev_embed_init(&wembed, &cbembed, eloop);
        ev_embed_start(loop, &wembed);
    }
    else
    {
        sout("No embeded loop, using the default\n");
        eloop = loop;
    }

    int[2] epipe;
    {
        int ret = unistd.pipe(epipe.ptr);
        aassert (ret == 0,__LINE__);
    }
    ev_io_init(&ewio, &ecbio, epipe[0], EV_READ);
    ev_io_start(eloop, &ewio);

    int[2] pipe;
    {
        int ret = unistd.pipe(pipe.ptr);
        aassert (ret == 0,__LINE__);
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

    ev_stat_init(&wstat, &cbstat, toStringz(STAT_FILE), 0 /* auto */);
    ev_stat_start(loop, &wstat);

    ev_idle_init(&widle, &cbidle);
    ev_idle_start(loop, &widle);

    ev_prepare_init(&wprepare, &cbprepare);
    ev_prepare_start(loop, &wprepare);

    ev_check_init(&wcheck, &cbcheck);
    ev_check_start(loop, &wcheck);

    ev_fork_init(&wfork, &cbfork);
    ev_fork_start(loop, &wfork);

    ev_run(loop, 0);

    aassert (prepare_done,__LINE__);
    aassert (check_done,__LINE__);
    aassert (idle_done,__LINE__);
    aassert (timer_done,__LINE__);
    aassert (io_done,__LINE__);
    aassert (stat_done,__LINE__);
    aassert (child_done,__LINE__);
    aassert (signal_done,__LINE__);
    aassert (eio_done,__LINE__);

    sout("done!\n");
}
