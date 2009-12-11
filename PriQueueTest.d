module PriQueueTest;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.PriQueue;
import blip.io.Console;

void main(){
    PriQueue!(Task) queue=new PriQueue!(Task)();
    queue.insert(10,new Task("bla1", delegate(){ sout("task1\n");}));
    writeOut(sout("xx1").call,queue); sout("\n");
    auto t=queue.popNext();
    writeOut(sout("xx2").call,queue); sout("\n");
    queue.insert(12,new Task("bla2", delegate(){ sout("task2\n");}));
    writeOut(sout("xx3").call,queue); sout("\n");
    queue.insert(10,t);
    writeOut(sout("xx4").call,queue); sout("\n");
    queue.insert(12,t);
    writeOut(sout("xx5").call,queue); sout("\n");
    auto t2=queue.popNext();
    writeOut(sout("xx5.1").call,queue); sout("\n");
    queue.insert(20,t);    
    writeOut(sout("xx6").call,queue); sout("\n");
    queue.insert(0,t);    
    writeOut(sout("xx7").call,queue); sout("\n");
    sout("done\n");
}
