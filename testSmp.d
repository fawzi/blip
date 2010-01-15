module testSmp;
import blip.io.Console;
import blip.parallel.smp.WorkManager;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.t.core.Thread;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; }
import blip.io.Console; // pippo

class STask{
    char[] name;
    double sleepTime;
    void delegate()op;
    
    void writeOutSN(){
        {
            auto tAtt=taskAtt.val;
            sout(collectAppender(delegate void(CharSink sink){
                auto s=dumper(sink);
                s(name)(" from task ")(tAtt.taskName)(" started\n");
            }));
        }
        Thread.sleep(0.5*sleepTime);
        if (op !is null){
            sout(collectAppender(delegate void(CharSink s){
                s(name); s(" executes op \n");
                s("op ptr:"); writeOut(s,cast(void*)op.ptr); s(" funcptr:"); writeOut(s,cast(void*)op.funcptr);
                s("\n");
            }));
            
            op();
        }
        Thread.sleep(0.5*sleepTime);
        {
            auto tAtt=taskAtt.val;
            sout(collectAppender(delegate void(CharSink sink){
                auto s=dumper(sink);
                s(name)(" from task ")(tAtt.taskName)(" ended\n");
            }));
        }
    }
    this(char[] name,double sleepTime=1.0,void delegate() op=null){
        this.name=name;
        this.sleepTime=sleepTime;
        this.op=op;
    }
    void submit1(){
        auto t=new STask(name~"_sub10",0.5);
        Task(name~"_sub01",&t.writeOutSN).submit();
    }
    void submit3(){
        Task(name~"_sub1",&((new STask(name~"_sub1")).writeOutSN)).submit();
        Task(name~"_sub2",&((new STask(name~"_sub2",0.5,&submit1)).writeOutSN)).submit();
        Task(name~"_sub3",&((new STask(name~"_sub3",0.5)).writeOutSN)).submit();
    }
    void immediateWakeUp(){
        auto tAtt=taskAtt.val;
        tAtt.delay({
            sout(name~" delayed!\n");
            tAtt.resubmitDelayed();
        });
        sout(name~" waked!\n");
    }
    void lateWakeUp(){
        auto tAtt=taskAtt.val;
        auto resub=&(cast(Task)tAtt).resubmitDelayed;
        sout(collectAppender(delegate void(CharSink s){
            s("resub ptr:"); writeOut(s,cast(void*)resub.ptr); s(" funcptr:"); writeOut(s,cast(void*)resub.funcptr);
            s("\n");
        }));
        auto tt=new STask(name~"_wakeUp",0.5,resub);
        tt.op=resub;
        tAtt.delay(delegate void(){
            sout(name~" delayed!\n");
            Task(name~"_wakeUp",&tt.writeOutSN).submit();
        });
        sout(name~" waked!\n");
    }
}

void testOnFinish(){
    Task("testOnFinish1",&((new STask("singleTask")).writeOutSN))
        .appendOnFinish({sout("Run onFinish of testOnFinish1\n");}).autorelease().submit();
    Thread.sleep(3.0);
    {
        auto t=new STask("subShort",2.0);
        t.op=&t.submit1;
        auto tt=Task("testOnFinish2",&t.writeOutSN);
        tt.appendOnFinish({sout("Run onFinish of testOnFinish2\n");});
        tt.submit();
        tt.wait();
    }
    {
        auto t=new STask("subLong",0.1);
        t.op=&t.submit1;
        auto tt=Task("testOnFinish3",&t.writeOutSN);
        tt.appendOnFinish({sout("Run onFinish of testOnFinish3\n");});
        tt.submit();
        tt.wait();
    }
    {
        auto t=new STask("subShort",2.0);
        t.op=&t.submit3;
        auto tt=Task("testOnFinish4",&t.writeOutSN)
            .appendOnFinish(delegate void(){sout("Run onFinish of testOnFinish4\n");});
        tt.submit();
        tt.wait();
    }
}

void testDelay(){
    {
        auto t=new STask("singleTaskDelayShort");
        t.op=&t.immediateWakeUp;
        Task("testDelay1",&t.writeOutSN)
            .appendOnFinish(delegate void(){sout("Run onFinish of testDelay1\n");}).submit().wait();
    }
    {
        auto t=new STask("singleTaskDelayLong");
        t.op=&t.lateWakeUp;
        Task("testDelay2",&t.writeOutSN)
            .appendOnFinish(delegate void(){sout("Run onFinish of testDelay2\n");}).submit().wait();
    }
}

void testExecuteNow(){
    Task("testExecuteNow1",&((new STask("singleTask")).writeOutSN))
        .appendOnFinish(delegate void(){sout("Run onFinish of testExecuteNow1\n");}).executeNow();
    {
        auto t=new STask("subShort");
        t.op=&t.submit3;
        auto tt=Task("testExecuteNow2",&t.writeOutSN)
            .appendOnFinish(delegate void(){sout("Run onFinish of testExecuteNow2\n");});
        tt.executeNow();
    }
}
void testSequential(){
    
}

void tests(){
    //sout("testOnFinish\n");
    //testOnFinish();
    sout("testDelay\n");
    testDelay();
    sout("testExecuteNow\n");
    testExecuteNow();
    sout("testSequential\n");
    testSequential();
    sout("done\n");
}

void main(){
    tests();
}