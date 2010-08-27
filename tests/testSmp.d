/// some tests of the smp parallelization, some checks are done automatically, but a full check
/// requires manual check of the generated log
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
module testSmp;
import blip.io.Console;
import blip.parallel.smp.WorkManager;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.core.Thread;
import blip.parallel.smp.DataFlowVar;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }
import blip.io.Console;

class STask{
    static gVal=0;
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
        Task.yield();
        Task(name~"_sub2",&((new STask(name~"_sub2",0.5,&submit1)).writeOutSN)).submit();
        Task.maybeYield();
        Task(name~"_sub3",&((new STask(name~"_sub3",0.5)).writeOutSN)).submit();
    }
    void immediateWakeUp(){
        auto tAtt=taskAtt.val;
        tAtt.delay({
            sout(name~" delayed!\n");
            tAtt.resubmitDelayed(tAtt.delayLevel-1);
        });
        sout(name~" waked!\n");
    }
    void lateWakeUp(){
        auto tAtt=taskAtt.val;
        auto resub=resubmitter(tAtt,tAtt.delayLevel);
        sout(collectAppender(delegate void(CharSink s){
            s("resub:"); writeOut(s,resub);
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
    
    void updateG(){
        if(gVal!=0) assert(0);
        gVal+=1;
        writeOutSN();
        if(gVal!=1) assert(0);
        gVal-=1;
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
    Task("testOnFinish1Seq",&((new STask("singleTask")).updateG))
        .appendOnFinish({sout("Run onFinish of testOnFinish1\n");}).autorelease().submit(sequentialTask);
    {
        auto t=new STask("subShort",2.0);
        t.op=&t.submit1;
        auto tt=Task("testOnFinish2",&t.updateG);
        tt.appendOnFinish({sout("Run onFinish of testOnFinish2\n");});
        tt.autorelease.submit(sequentialTask);
    }
    {
        auto t=new STask("subLong",0.1);
        t.op=&t.submit1;
        auto tt=Task("testOnFinish3Seq",&t.updateG);
        tt.appendOnFinish({sout("Run onFinish of testOnFinish3\n");});
        tt.submit(sequentialTask);
    }
    {
        auto t=new STask("subShort",2.0);
        t.op=&t.submit3;
        auto tt=Task("testOnFinish4Seq",&t.updateG)
            .appendOnFinish(delegate void(){sout("Run onFinish of testOnFinish4\n");});
        tt.autorelease.submit(sequentialTask);
    }
    {
        auto t=new STask("singleTaskDelayShort");
        t.op=&t.immediateWakeUp;
        Task("testDelay1Seq",&t.updateG)
            .appendOnFinish(delegate void(){sout("Run onFinish of testDelay1\n");}).autorelease.submit(sequentialTask);
    }
    {
        auto t=new STask("singleTaskDelayLong");
        t.op=&t.lateWakeUp;
        Task("testDelay2Seq",&t.updateG)
            .appendOnFinish(delegate void(){sout("Run onFinish of testDelay2\n");}).autorelease.submit(sequentialTask);
    }
    Task("testExecuteNow1Seq",&((new STask("singleTask_testExecuteNow1Seq")).updateG))
        .appendOnFinish(delegate void(){sout("Run onFinish of testExecuteNow1\n");}).executeNow(sequentialTask);
    {
        auto t=new STask("subShort_testExecuteNow2Seq");
        t.op=&t.submit3;
        auto tt=Task("testExecuteNow2Seq",&t.updateG)
            .appendOnFinish(delegate void(){sout("Run onFinish of testExecuteNow2\n");});
        tt.executeNow(sequentialTask);
    }
}

class DataFlowTest{
    DataFlow!(int) var1;
    DataFlow!(int) var2;
    this(){
    }
    Task testerTask(){
        return Task("DataFlowTestTask",&doTests);
    }
    
    void read1(){
        sout(collectAppender(delegate void(CharSink s){
            s("var1 has value:"); writeOut(s,var1()); s("\n");
        }));
    }
    void read2(){
        sout(collectAppender(delegate void(CharSink s){
            s("var2 has value:"); writeOut(s,var2()); s("\n");
        }));
    }
    void write1(){
        var1=4;
        sout("set var1=4\n");
    }
    void read1Write2(){
        var2=var1();
        sout("set var2 to var1 value\n");
    }
    void doTests(){
        Task("read1_1",    &read1      ).autorelease.submit();
        Task("read1Write2",&read1Write2).autorelease.submit();
        Task("read1_2",    &read1      ).autorelease.submit();
        Task("read2_1",    &read2      ).autorelease.submit();
        Thread.sleep(0.5);
        Task("write1_1",   &write1     ).autorelease.submit();
        Task("write1_2",   &write1     ).autorelease.submit();
    }
}

void testDataFlow(){
    auto t=new DataFlowTest();
    Task("dataFlowTests",&t.doTests).appendOnFinish(delegate void(){
        sout("finished dataFlowTests\n");
    }).executeNow(defaultTask);
}

void tests(){
    sout("testOnFinish\n");
    testOnFinish();
    sout("testDelay\n");
    testDelay();
    sout("testExecuteNow\n");
    testExecuteNow();
    sout("testSequential\n");
    testSequential();
    sout("testDataFlow\n");
    testDataFlow();
    sout("shoud be done\n");
    Thread.sleep(8.0);
    sout("done\n");
}

void main(){
    tests();
}