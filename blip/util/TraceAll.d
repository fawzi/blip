/// simple module to get the stacktrace of all threads
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
module blip.util.TraceAll;
import blip.core.Thread;
import blip.core.stacktrace.StackTrace;
import blip.sync.Atomic;
import blip.io.Console;
import blip.stdc.stdlib;
version(Posix){
    import tango.stdc.posix.signal;
    import tango.core.Version;
    static if(Tango.Major==1) {} else {
        private alias void function(int) sHandler;
        extern (C) void setthread_abortHandler(sHandler f);
    }
    

    class TraceAll{
        int abortLevel; /// 0: normal run, 1: master established, 2: slave traces, 3: end
        int traceLevel; /// 0:no slave trace, 1: should do trace, 2: doing trace, 3: done trace
        Thread tAtt; /// slave that should report the trace
        BasicTraceInfo trace;
    
        this(){
            trace=new BasicTraceInfo();
        }
        
        void abort(){
            bool waitFor(scope bool delegate() check){
                for(int i=0;i<500;++i){
                    for(int j=0;i<100;++i){
                        volatile auto tLevel=traceLevel;
                        if (check()) return true;
                        Thread.yield();
                    }
                    if (check()) return true;
                    Thread.sleep(0.001);
                }
                return false;
            }
            Thread  myT = Thread.getThis();
            int aLevel=abortLevel;
            bool isMaster=false;
            CASLoop: while(1){
                int nLevel;
                switch(aLevel){
                case 0:
                    nLevel=atomicCAS(abortLevel,1,0);
                    if (nLevel==0) {
                        serr("\nThread ");
                        serr(myT.name);
                        serr("\n");
                        trace.trace();
                        trace.writeOut(serr.call);
                        if (!atomicCASB(abortLevel,2,1)){
                            serr("unexpected abort level on master\n");
                        }
                        synchronized(Thread.classinfo){
                            if (!atomicCASB(traceLevel,1,0)){
                                serr("invalid traceLevel on master\n");
                                exit(1);
                            }
                            foreach(t;Thread){
                                if (t!is myT){
                                    serr("\nThread ");
                                    serr(t.name);
                                    serr("\n");
                                    tAtt=null;
                                    volatile traceLevel=1;
                                    writeBarrier();
                                    tAtt=t;
                                    Thread.sleep(0.001);
                                    if( pthread_kill( t.m_addr, SIGABRT ) != 0 ){
                                        serr("could not send signal to a thread\n");
                                    }
                                    waitFor(delegate bool(){ volatile auto tLevel=traceLevel; return tLevel==3; });
                                    if (traceLevel!=3){
                                        if (atomicCASB(traceLevel,1,0)){
                                            tAtt=null;
                                            serr("a thread did not respond, race with the GC??, skipping it, but probably further tracing will fail...\n");
                                            Thread.sleep(0.1);
                                        } else {
                                            waitFor(delegate bool(){ volatile auto tLevel=traceLevel; return tLevel==3; });
                                            if (traceLevel!=3){
                                                serr("a thread trace failed, exiting\n");
                                                abortLevel=5;
                                                exit(1);
                                                return;
                                            }
                                        }
                                    } else {
                                        tAtt=null;
                                        if (!atomicCASB(traceLevel,0,3)){
                                            serr("invalid traceLevel on master reset\n");
                                            exit(1);
                                        }
                                        volatile readBarrier();
                                        trace.writeOut(serr.call);
                                    }
                                }
                            }
                        }
                    }
                    exit(10);
                    break;
                case 1: // wait
                    Thread.yield();
                    volatile aLevel=abortLevel;
                    break;
                case 2:
                    readBarrier();
                    volatile auto tAtt1=tAtt;
                    if (tAtt1 is myT){
                        if (atomicCASB(traceLevel,2,1)){
                            readBarrier();
                            volatile tAtt1=tAtt;
                            if(tAtt1!is myT){
                                serr("double signaling or interrupted tracing\n");
                                abortLevel=5;
                                exit(2);
                                //atomicCASB(traceLevel,1,2);
                                //return;
                            }
                            trace.trace();
                            writeBarrier();
                            if (!atomicCASB(traceLevel,3,2)){
                                serr("trace collision\n");
                                abortLevel=5;
                                exit(3);
                            }
                            return;
                        } else {
                            serr("double signaling in trace\n");
                            abortLevel=5;
                            exit(4);
                        }
                    }
                default:
                    exit(5);
                    return;
                }
            }
        }
        __gshared static TraceAll tracer;
        shared static this(){
            tracer=new TraceAll();
            static if (Tango.Major==1) {} else {
                setthread_abortHandler(function void(int i){ tracer.abort(); });
            }
        }
    }
}
