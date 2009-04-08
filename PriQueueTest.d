module PriQueueTest;
import blip.parallel.BasicTasks;
import blip.parallel.PriQueue;
import tango.io.Stdout;

void main(){
    PriQueue!(Task) queue=new PriQueue!(Task)();
    queue.insert(10,new Task("bla1", delegate(){Stdout("task1").newline;}));
    queue.desc(Stdout("xx1")).newline;
    auto t=queue.popNext();
    queue.desc(Stdout("xx2")).newline;
    queue.insert(12,new Task("bla2", delegate(){Stdout("task2").newline;}));
    queue.desc(Stdout("xx3")).newline;
    queue.insert(10,t);
    queue.desc(Stdout("xx4")).newline;
    queue.insert(12,t);
    queue.desc(Stdout("xx5")).newline;
    auto t2=queue.popNext();
    queue.desc(Stdout("xx5.1")).newline;
    queue.insert(20,t);    
    queue.desc(Stdout("xx6")).newline;
    queue.insert(0,t);    
    queue.desc(Stdout("xx7")).newline;
    Stdout("done").newline;
}
