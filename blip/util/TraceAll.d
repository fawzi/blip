/// simple module to get the stacktrace of all threads
module blip.util.TraceAll;
import blip.t.core.Thread;
import blip.t.core.stacktrace.StackTrace;
import blip.sync.Atomic;
import blip.io.Console;
import blip.t.stdc.stdlib;
version(Posix){
    import tango.stdc.posix.signal;
    version(NewTango) {} else {
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
            bool waitFor(bool delegate() check){
                for(int i=0;i<1000;++i){
                    for(int j=0;i<1000;++i){
                        volatile auto tLevel=traceLevel;
                        if (check()) return true;
                        Thread.yield();
                    }
                    if (check()) return true;
                    Thread.sleep(0.01);
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
                                            serr("a thread did not respond\n");
                                            Thread.sleep(0.1);
                                        } else {
                                            waitFor(delegate bool(){ volatile auto tLevel=traceLevel; return tLevel==3; });
                                            if (traceLevel!=3){
                                                serr("a thread trace failed\n");
                                                abortLevel=5;
                                                return;
                                            }
                                        }
                                    } else {
                                        tAtt=null;
                                        if (!atomicCASB(traceLevel,0,3)){
                                            serr("invalid traceLevel on master reset\n");
                                            exit(1);
                                        }
                                        readBarrier();
                                        trace.writeOut(serr.call);
                                    }
                                }
                            }
                        }
                    }
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
                                atomicCASB(traceLevel,1,2);
                                return;
                            }
                            trace.trace();
                            writeBarrier();
                            if (!atomicCASB(traceLevel,3,2)){
                                serr("trace collision\n");
                            }
                            return;
                        } else {
                            serr("double signaling in trace\n");
                        }
                    }
                default:
                    exit(2);
                    return;
                }
            }
        }
        static TraceAll tracer;
        static this(){
            tracer=new TraceAll();
            version(NewTango) {} else {
                setthread_abortHandler(function void(int i){ tracer.abort(); });
            }
        }
    }
}
