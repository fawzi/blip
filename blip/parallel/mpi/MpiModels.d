/// represents environments of ordered and reliable computing nodes, as modeled
/// by mpi. Cannot cope with addition or removal of nodes.
/// Use this for thightly coupled calculations, use cluster distribution of them
module blip.parallel.mpi.MpiModels;
import blip.serialization.Serialization;
import blip.BasicModels;
import blip.parallel.smp.WorkManager;
import gobo.mpi.mpi;
public import gobo.mpi.mpi: MPI_Op, MPI_MAX, MPI_MIN, MPI_SUM, MPI_PROD, MPI_LAND, MPI_BAND, MPI_LOR,
    MPI_BOR, MPI_LXOR, MPI_BXOR, MPI_MAXLOC, MPI_MINLOC, MPI_REPLACE;

enum :int{
    AnyTag=int.max
}
//PUBLIC :: mp_bcast, mp_sum, mp_max, mp_maxloc, mp_minloc, mp_min, mp_sync
//PUBLIC :: mp_gather, mp_scatter, mp_alltoall, mp_sendrecv, 

alias void delegate(Channel,int) ChannelHandler;

/// represents a comunication channel with a task
interface Channel{
    TaskI sendTask();
    TaskI recvTask();
    /// send might be sent while serializing or only when you send close, thus close should be sent...
    /// can be called from any task
    Serializer sendTag(int tag=0,ubyte[] buf=null);
    /// should be called from the sendTask
    void send(double[],int tag=0);
    /// should be called from the sendTask
    void send(int[],int tag=0);
    /// should be called from the sendTask
    void send(ubyte[],int tag=0);
    /// should be called from the sendTask
    void sendStr(char[],int tag=0);
    /// send close to the serializer to possibly reuse the unserializer
    /// can be called from any task
    Unserializer recvTag(ref int tag,ubyte[] buf=null);
    /// should be called from recvTask
    int recv(ref double[],int tag=0);
    /// should be called from recvTask
    int recv(ref int[],int tag=0);
    /// should be called from recvTask
    int recv(ref ubyte[],int tag=0);
    /// should be called from recvTask
    int recvStr(ref char[],int tag=0);
    /// closes the Unserializer, after this it might be reused, or some cleanup might be triggered
    void close();
    // void registerHandler(ChannelHandler handler,int tag=0); // allow servers only on all channels concurrently
    int sendrecv(double[],ref double[],Channel recvChannel,int sendTag=0,int recvTag=0);
    int sendrecv(int[],ref int[],Channel recvChannel,int sendTag=0,int recvTag=0);
    int sendrecv(ubyte[],ref ubyte[],Channel recvChannel,int sendTag=0,int recvTag=0);
    // probe, wait?
}

/// higher dimensional distribution of processors
interface Cart(int dimG){
    int[] dims();
    int[] myPos();
    Channel opIndex(int[dimG] pos);
    LinearComm baseComm();
    int baseIdx(int[dimG] pos);
}

/// collective operations, represents an mpi communicator, 1D
interface LinearComm:BasicObjectI{
    char[] name();
    void name(char[] n);
    
    int dim();
    int myRank();
    Channel opIndex(int rank);
    LinearComm split(int color,int newRank);
    Cart!(2) mkCart(int[2] dims,int[2] periodic, bool reorder);
    Cart!(3) mkCart(int[3] dims,int[3] periodic, bool reorder);
    Cart!(4) mkCart(int[4] dims,int[4] periodic, bool reorder);
    int nextTag();
    
    void bcast(ref double,int,int tag=0);
    void bcast(ref double[],int,int tag=0);
    void bcast(ref int,int,int tag=0);
    void bcast(ref int[],int,int tag=0);
    void bcast(ref ubyte,int,int tag=0);
    void bcast(ref ubyte[],int,int tag=0);
    void reduce(double, ref double,int,MPI_Op,int tag=0);
    void reduce(double[],ref double[],int,MPI_Op,int tag=0);
    void reduce(int,ref int,int,MPI_Op,int tag=0);
    void reduce(int[],ref int[],int,MPI_Op,int tag=0);
    void reduce(ubyte,ref ubyte,int,MPI_Op,int tag=0);
    void reduce(ubyte[],ref ubyte[],int,MPI_Op,int tag=0);
    void allReduce(double  ,ref double  ,MPI_Op,int tag=0);
    void allReduce(double[],ref double[],MPI_Op,int tag=0);
    void allReduce(int     ,ref int     ,MPI_Op,int tag=0);
    void allReduce(int[]   ,ref int[]   ,MPI_Op,int tag=0);
    void allReduce(ubyte   ,ref ubyte   ,MPI_Op,int tag=0);
    void allReduce(ubyte[] ,ref ubyte[] ,MPI_Op,int tag=0);
    
    void gather(int[] dataOut,int[] dataIn,int root,int tag=0);
    void gather(double[] dataOut,double[] dataIn,int root,int tag=0);
    void gather(ubyte[] dataOut,ubyte[] dataIn,int root,int tag=0);
    void gather(int[] dataOut,int[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0);
    void gather(double[] dataOut,double[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0);
    void gather(ubyte[] dataOut,ubyte[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0);
    void allGather(int[] dataOut,int[] dataIn,int tag=0);
    void allGather(double[] dataOut,double[] dataIn,int tag=0);
    void allGather(ubyte[] dataOut,ubyte[] dataIn,int tag=0);
    void allGather(int[] dataOut,int[] dataIn,int[] inStarts,int[] inCounts,int tag=0);
    void allGather(double[] dataOut,double[] dataIn,int[] inStarts,int[] inCounts,int tag=0);
    void allGather(ubyte[] dataOut,ubyte[] dataIn,int[] inStarts,int[] inCounts,int tag=0);
    
    void scatter(int[] dataOut,int[] dataIn,int root,int tag=0);
    void scatter(double[] dataOut,double[] dataIn,int root,int tag=0);
    void scatter(ubyte[] dataOut,ubyte[] dataIn,int root,int tag=0);
    void scatter(int[] dataOut,int[] outCounts, int[] outStarts, int[] dataIn,int root,int tag=0);
    void scatter(double[] dataOut,int[] outCounts, int[] outStarts, double[] dataIn,int root,int tag=0);
    void scatter(ubyte[] dataOut,int[] outCounts, int[] outStarts, ubyte[] dataIn,int root,int tag=0);
    void allScatter(int[] dataOut,int[] dataIn,int root,int tag=0);
    void allScatter(double[] dataOut,double[] dataIn,int root,int tag=0);
    void allScatter(ubyte[] dataOut,ubyte[] dataIn,int root,int tag=0);
    void allScatter(int[] dataOut,int[] outCounts, int[] outStarts, int[] dataIn,int root,int tag=0);
    void allScatter(double[] dataOut,int[] outCounts, int[] outStarts, double[] dataIn,int root,int tag=0);
    void allScatter(ubyte[] dataOut,int[] outCounts, int[] outStarts, ubyte[] dataIn,int root,int tag=0);
    
    void reduceScatter(int[]outData,int[]inData,MPI_Op op);
    void reduceScatter(double[]outData,double[]inData,MPI_Op op);
    void reduceScatter(ubyte[]outData,ubyte[]inData,MPI_Op op);
    void reduceScatter(int[]outData,int[]inData,int[]inCounts,MPI_Op op);
    void reduceScatter(double[]outData,double[]inData,int[]inCounts,MPI_Op op);
    void reduceScatter(ubyte[]outData,ubyte[]inData,int[]inCounts,MPI_Op op);
    
    void alltoall(int[] dataOut,int[] dataIn,int tag=0);
    void alltoall(double[] dataOut,double[] dataIn,int tag=0);
    void alltoall(ubyte[] dataOut,ubyte[] dataIn,int tag=0);
    void alltoall(int[] dataOut,int[] outCounts,int[] outStarts,int[] dataIn,int[] inCounts, int[] inStarts,int tag=0);
    void alltoall(double[] dataOut,int[] outCounts,int[] outStarts,double[] dataIn,int[] inCounts, int[] inStarts,int tag=0);
    void alltoall(ubyte[] dataOut,int[] outCounts,int[] outStarts,ubyte[] dataIn,int[] inCounts, int[] inStarts,int tag=0);
    
    void barrier();
    /// registers a server that handles all communication from any channel with the given tag
    /// this method is not so flexible (you cannot stop a "server", the only way to accept
    /// messages from everybody is a server, but it is very portable)
    void registerHandler(ChannelHandler handler,int tag);
}

