/// tskas that can be transferred from a processor to another
module blip.parallel.TransferrableTasks;
import tango.io.protocol.model.IWriter;
import tango.io.protocol.model.IReader;
import blip.parallel.Models;

// task register
class TTaskRegister{
    this() { }
    // char[TransferrableTaskSet] id2Task;
    // char[TransferrableTaskSet[]] kind2Tasks;
    // void registerTask(TransferrableTaskSet task);
    // void unregisterTask(TransferrableTaskSet task);
    // TransferrableTaskSet getTask(char[]kind,char[]name);
    // TransferrableTaskSet getTask(char[]id);
    // TTaskSetIter getTaskOfKind(char[]kind); // copy?
    // TransferrableTaskSet getLargestTaskOfKind(char[]kind);
    // TTaskSetIter getAllTasks();
}

struct TransferCost{
    float transferSize; // this might include also transfer of extra data done by the task
    float sizeWorkRatio;
}

/// tasks that can be transferred between computers
interface TransferrableTaskSet:IWritable,IReadable{
    /// kind of the task
    char[] taskKind();
    /// task name locally unique
    char[] taskName();
    /// gobally unique
    char[] taskId();
    /// work remaining
    float restWork();
    /// units of work (taskName is probably a good choice if you don't know the unit)
    char[] workUnit();
    /// minimum reasonable transfer amount
    float minTransferAmount();
    /// expected transfer cost 
    TransferCost transferCost(float amount=0.5f);
    /// writes a task set to the given channel (tries to dump the given fraction of tasks)
    /// a negative amount means a ratio. Returns the actual amount transferred
    float tansferTasks(IWriter channel,float amount=-0.5f,bool roundDown=true);
    /// if the task can checkpoint (i.e. dump its value, read it back, even on another process,
    /// and continue)
    bool canCheckpoint();
    /// if the task can be restarted from scratch or a previous dump
    /// (i.e. partial results can be safely discarded and recovered)
    bool canRestart();
}
