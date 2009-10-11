module blip.parallel.mpi;
import blip.serialization.Serialization;
import gobo.mpi.mpi;
public import gobo.mpi.mpi: MPI_Op, MPI_MAX, MPI_MIN, MPI_SUM, MPI_PROD, MPI_LAND, MPI_BAND, MPI_LOR,
    MPI_BOR, MPI_LXOR, MPI_BXOR, MPI_MAXLOC, MPI_MINLOC, MPI_REPLACE;

//PUBLIC :: mp_bcast, mp_sum, mp_max, mp_maxloc, mp_minloc, mp_min, mp_sync
//PUBLIC :: mp_gather, mp_scatter, mp_alltoall, mp_sendrecv, mp_allgather

interface Channel{
    void send(double[]);
    void send(int[]);
    void send(ubyte[]);
    void recv(double[]);
    void recv(int[]);
    void recv(ubyte[]);
    void sendStr(char[]);
    void recvStr(char[]);
    Serializer serializer();
    Unserializer unserializer();
    void close();
}

interface LinearComm{
    Channel opIndex(int rank);
    void bcast(ref double,int);
    void bcast(ref double[],int);
    void bcast(ref int,int);
    void bcast(ref void[],int);
    void bcast(ref ubyte,int);
    void bcast(ref ubyte[],int);
    void reduce(ref double,int,MPI_Op);
    void reduce(ref double[],int,MPI_Op);
    void reduce(ref int,int,MPI_Op);
    void reduce(ref int[],int,MPI_Op);
    void reduce(ref ubyte,int);
    void reduce(ref ubyte[],int);
    
}

