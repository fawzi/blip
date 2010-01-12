/// condition variables, try avoid their use
/// DataFlowVar are safe, use that when possible
module blip.parallel.smp.Condition;
import blip.parallel.smp.SmpModels;
import blip.parallel.smp.BasicTasks;
import blip.t.core.Thread;

/// waits for an OS lock
/// WARNING this might deadlock if alwaysLock and the task that aquires the lock might
/// be suspended non executing
class WaitLock(T){
    T lockObj;
    bool alwaysLock;
    uint maxT;
    this(T lockObj, bool alwaysLock=false,uint maxT=100){
        this.lockObj=lockObj;
        this.alwaysLock=alwaysLock;
        this.maxT=maxT;
    }
    void wait(){ lock(); }
    void lock(){
        for (uint i=0;i<maxT;++i){
            for (int j=0;j<20;++j){
                bool lkd=lockObj.tryLock();
                if (lkd) return;
                TaskI tAtt=taskAtt.val;
                if (tAtt.mightYield()){
                    tAtt.scheduler.yield();
                } else {
                    if (! thread_needLock())
                        throw new ParaException("deadlock",__FILE__,__LINE__);
                    if (alwaysLock) {
                        lockObj.lock();
                        return;
                    }
                }
            }
            Thread.sleep(1.0);
        }
        if (alwaysLock){
            lockObj.lock();
        } else {
            throw new ParaException("failed to wait for lock",__FILE__,__LINE__);
        }
    }
    void unlock(){
        lockObj.unlock();
    }
}

class WaitCondition{
    bool delegate() cnd;
    uint maxT;
    this(bool delegate() cnd, uint maxT=100){
        this.cnd=cnd;
        this.maxT=maxT;
    }
    void wait(){ lock(); }
    void lock(){
        for (uint i=0;i<maxT;++i){
            for (int j=0;j<20;++j){
                if (cnd()) return;
                TaskI tAtt=taskAtt.val;
                if (tAtt.mightYield()){
                    tAtt.scheduler.yield();
                } else {
                    Thread.sleep(0.001);
                }
            }
            Thread.sleep(1.0);
        }
    }
    void unlock(){ }
}