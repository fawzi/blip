/// Mpi environment
/// a mpiWorld static constant is available, if mpi is available it uses it, otherwise
/// SingleNode is used. The interface exposed is the same.
module blip.parallel.mpi.Mpi;
version(mpi)
{
    public import blip.parallel.mpi.MpiModels;
    import blip.serialization.Serialization;
    import blip.parallel.smp.WorkManager;
    import gobo.mpi.mpi;
    import blip.io.IOArray;
    import blip.container.Deque;
    import blip.BasicModels;
    import blip.sync.UniqueNumber;

    template MPI_DatatypeForType(T){
        static if (is(T==ubyte)){
            alias MPI_BYTE MPI_DatatypeForType;
        } else static if (is(T==char)){
            alias MPI_CHAR MPI_DatatypeForType;
        } else static if (is(T==short)){
            alias MPI_SHORT MPI_DatatypeForType;
        } else static if (is(T==int)){
            alias MPI_INT MPI_DatatypeForType;
        } else static if (is(T==c_long)){
            alias MPI_LONG MPI_DatatypeForType;
        } else static if (is(T==float)){
            alias MPI_FLOAT MPI_DatatypeForType;
        } else static if (is(T==double)){
            alias MPI_DOUBLE MPI_DatatypeForType;
        } else static if (is(T==real)){
            alias MPI_LONG_DOUBLE MPI_DatatypeForType; // correct???
        } else static if (is(T==byte)){
            alias MPI_SIGNED_CHAR MPI_DatatypeForType;
        } else static if (is(T==ushort)){
            alias MPI_UNSIGNED_SHORT MPI_DatatypeForType;
        } else static if (is(T==c_ulong)){
            alias MPI_UNSIGNED_LONG MPI_DatatypeForType;
        } else static if (is(T==uint)){
            alias MPI_UNSIGNED MPI_DatatypeForType;
        } else static if (is(T==c_ulong)){
            alias MPI_UNSIGNED_LONG MPI_DatatypeForType;
        } else static if (is(T==c_ulong)){
            alias MPI_UNSIGNED_LONG MPI_DatatypeForType;
        } else static if (is(T==long)){
            alias MPI_LONG_LONG MPI_DatatypeForType;
        } else static if (is(T==ulong)){
            alias MPI_UNSIGNED_LONG_LONG MPI_DatatypeForType;
        } else static if (is(T==cfloat)){
            alias MPI_COMPLEX MPI_DatatypeForType; // correct? (fortran binding)
        } else static if (is(T==cdouble)){
            alias MPI_DOUBLE_COMPLEX MPI_DatatypeForType;
        } else static if (is(T==ifloat)){
            alias MPI_FLOAT MPI_DatatypeForType;
        } else static if (is(T==cdouble)){
            alias MPI_DOUBLE MPI_DatatypeForType;
        } else {
            static assert(0,"unsupported type "~T.stringof);
        }
    }

    struct SerializedMessage{
        int tag;
        ubyte[] msg;
        static SerializedMessage opCall(int tag,ubyte[] msg){
            SerializedMessage res;
            res.tag=tag;
            res.msg=msg;
            return res;
        }
    }

    class MpiSerializer:SBinSerializer{
        static MpiSerializer freeList;
        MpiSerializer next;
        int tag;
        SerializedMessage msg;
        Channel target;
        bool localBuf;
        static MpiSerializer opCall(Channel target,int tag,ubyte[] buf=null){
            auto newS=popFrom(freeList);
            if (newS is null){
                IOArray arr;
                if (buf.length>0){
                    arr=new IOArray(buf,0,512);
                    localBuf=true;
                } else {
                    arr=new IOArray(512,512);
                    localBuf=false;
                }
                newS=new MpiSerializer(arr);
            } else {
                if (buf.length>0){
                    auto arr=cast(IOArray)((cast(BinaryHandlers!())handlers).writer);
                    arr.assign(buf,0,512);
                }
            }
            return newS;
        }
        void giveBack(){
            insertAt(freeList,this);
        }
        this(size_t capacity=512,size_t grow=512){
            super(new IOArray(capacity,grow));
        }
        void writeStartRoot() {
            super.writeStartRoot();
            assert(msg.tag!=AnyTag);
            assert(target!is null);
            msg.tag=tag;
        }
        void writeEndRoot() {
            super.writeEndRoot();
            assert(msg.tag==tag);
        }
        void close(){
            auto arr=cast(IOArray)((cast(BinaryHandlers!())handlers).writer);
            msg.msg=arr.slice;
            Task("MpiSerializerClose",{
                target.send(msg.msg,msg.tag);
            }).autorelease.executeNow(target.sendTask);
            arr.assign(null,0);
            if (handleMsg!is null){
                if (handleMsg(msg)){
                    clearMsg();
                }
            }
            super.close();
            giveBack();
        }
        void useBuf(ubyte[] buf){
            auto arr=cast(IOArray)((cast(BinaryHandlers!())handlers).writer);
            arr.assign(buf,0,512);
        }
        void clearMsg(){
            msg.tag=AnyTag;
            msg.msg=null;
        }
    }

    class MpiUnserializer:SBinUnserializer{
        static MpiUnserializer freeList;
        SerializedMessage msg;
        static MpiUnserializer opCall(SerializedMessage msg){
            auto newS=popFrom(freeList);
            if (newS is null){
                newS=new MpiSerializer(msg);
            }
            return newS;
        }
        void giveBack(){
            insertAt(freeList,this);
        }
        this(SerializedMessage msg){
            this.msg=msg;
            super(new IOArray(msg.msg,msg.msg.length));
        }
        void readStartRoot() {
            assert(msg.tag!=AnyTag);
            super.readStartRoot();
        }
        void readEndRoot() {
            super.readEndRoot();
            assert(res.tag!=AnyTag);
        }
        void close(){
            msg.msg=Variant.init;
            msg.tag=AnyTag;
            auto tmp=arr.assign;
            arr.assign(null,0);
            //delete tmp;
            giveBack();
        }
    
    }

    /// mpi error
    class MpiException:Exception{
        this(char[] msg,char[] file, long line){
            super(msg,file,line);
        }
    }

    /// channel within a process
    /// this channel could allow reading messages out of order, but to have the same
    /// behaviour as other channels it does not.
    /// When created it sends to itself, but one can easily build interconnected channels by setting
    /// their recevingChannel attribute
    class MpiChannel:Channel{
        TaskI _recvTask;
        TaskI _sendTask;
        int otherRank;
        MpiLinearComm comm;
    
        TaskI sendTask(){ return _sendTask; }
        TaskI recvTask(){ return _recvTask; }
        this(MpiLinearComm comm,int otherRank, TaskI sendTask=null,TaskI recvTask=null){
            this.comm=comm;
            this.otherRank=otherRank;
            _sendTask=sendTask;
            _recvTask=recvTask;
            if (_sendTask is null){
                _sendTask=new SequentialTask("MpiChannelSeqSendTask",defaultTask);
            }
            if (_recvTask is null){
                _recvTask=new SequentialTask("MpiChannelSeqRecvTask",defaultTask);
            }
        }
        MpiSerializer sendTag(int tag=0,ubyte[] buf=null){
            return MpiSerializer(this,tag,buf);
        }
        MpiUnserializer recvTag(ref int tag,ubyte[] buf=null){
            MPI_Status status;
            if (MPI_Probe(otherRank, tag, comm.comm, &status)!=MPI_SUCCESS){
                throw new MpiException("MPI_Probe failed",__FILE__,__LINE__);
            }
            tag=status.tag;
            int count;
            if (MPI_Get_count(&status, MPI_DatatypeForType!(ubyte), count)!=MPI_SUCCESS){
                throw new MpiException("MPI_Get_count failed",__FILE__,__LINE__);
            }
            buf.length=count;
            recv(buf,tag);
            return MpiUnserializer(SerializedMessage(status.tag,buf));
        }
        void send(T)(T valOut,int tag=0){
            static if(is(T U:U[])){
                int count=valOut.length;
                void * buf=valOut.ptr;
                auto dataType=MPI_DatatypeForType!(U);
            } else {
                int count=1;
                void * buf=&valOut;
                auto dataType=MPI_DatatypeForType!(T);
            }
        
            if (MPI_Send(buf, count, dataType, otherRank, tag, comm.comm)!=MPI_SUCCESS){
                throw new MpiException("MPI_Send failed",__FILE__,__LINE__);
            }
        }
        int recv(T)(out T valIn, int tag=0){
            static if(is(T U:U[])){
                int count=valIn.length;
                void * buf=valIn.ptr;
                auto dataType=MPI_DatatypeForType!(U);
            } else {
                int count=1;
                void * buf=&valIn;
                auto dataType=MPI_DatatypeForType!(T);
            }
        
            MPI_Status status;
            if (MPI_Recv(buf, count, dataType, otherRank, tag, comm.comm,&status)!=MPI_SUCCESS){
                throw new MpiException("MPI_Send failed",__FILE__,__LINE__);
            }
        }
        void sendStr(char[] s, int tag=0){
            send(s,tag);
        }
        void recvStr(ref char[] s,int tag=0){
            MPI_Status status;
            if (MPI_Probe(otherRank, tag, comm.comm, &status)!=MPI_SUCCESS){
                throw new MpiException("MPI_Probe failed",__FILE__,__LINE__);
            }
            int count;
            if (MPI_Get_count(&status, MPI_DatatypeForType!(char), count)!=MPI_SUCCESS){
                throw new MpiException("MPI_Get_count failed",__FILE__,__LINE__);
            }
            s.length=count;
            recv(s,tag);
        }
        void close(){ }
    
        void sendrecv(T)(T sendV,ref T recvV,Channel recvChannel){
            if (recvChannel is this){
                assert(data.length==0);
                recvV=sendV;
            } else {
                recvChannel.send(sendV);
                recvChannel.recv(recvV);
            }
        }
    
        FormatOut desc(FormatOut s){
            s("{<MPIChannel@")(cast(void*)this)(">").newline;
            s("  otherRank:")(otherRank)(",").newline;
            s("  comm:MpiLinearComm@")(cast(void*)comm)(">").newline;
            s("}");
        }
    }

    class MpiCart(int dimG):Cart!(dimG){
        int[dimG] _dims;
        int[dimG] _myPos;
        LinearComm _baseComm;
        this(MpiLinearComm baseComm){
            _dims[]=1;
            _zeros[]=0;
            _baseComm=baseComm;
            int MPI_Cart_coords(MPI_Comm comm, int rank, int maxdims, int *coords);
            int MPI_Cart_create(MPI_Comm old_comm, int ndims, int *dims,
                                               int *periods, int reorder, MPI_Comm *comm_cart);
            int MPI_Cart_get(MPI_Comm comm, int maxdims, int *dims,
                                            int *periods, int *coords);
            int MPI_Cart_map(MPI_Comm comm, int ndims, int *dims,
                                            int *periods, int *newrank);
            int MPI_Cart_rank(MPI_Comm comm, int *coords, int *rank);
            int MPI_Cart_shift(MPI_Comm comm, int direction, int disp,
                                              int *rank_source, int *rank_dest);
        
        }
        int[] dims(){
            return _dims;
        }
        Channel opIndex(int[dimG] pos){
            assert(pos==_zeros,"invalid index");
            return _baseComm[0];
        }
        LinearComm baseComm(){
            return _baseComm;
        }
        int toBaseIdx(int[dimG] pos){
            assert(pos==_zeros,"invalid index");
            return 0;
        }
        int[] fromBaseIdx(int rank,int[] res=null){
            res.length=3;
            if (MPI_Cart_coords(comm, rank, 3, res.ptr)!=MPI_SUCCESS){
                throw new MpiException("MPI_Cart_coords failure",__FILE__,__LINE__);
            }
        
        }
    }

    /// a linear communicator for a single process
    /// supports only 1 channel, could be extdended to multi channel, but I don't need it at the moment
    class MpiLinearComm:LinearComm,BasicObjectI{
        int _myRank;
        MpiChannel[] channels;
        UniqueNumber!(int) counter;
        MPI_Comm comm;
        char[] _name;
    
        static class HandlerServer{
            MpiLinearComm comm;
            ChannelHandler handler;
            int tag;
            this(MpiLinearComm comm,ChannelHandler handler, int tag){
                this.comm=comm;
                this.handler=handler;
                this.tag=tag;
            }
            void run(){
                try{
                    while(1){
                        MPI_Status status;
                        if (MPI_Probe(MPI_ANY_SOURCE,tag, comm.comm,&status)!=MPI_SUCCESS){
                            throw new MpiException("Mpi probe failed",__FILE__,__LINE__);
                        }
                        handler(status.tag,comm[status.source]);
                    }
                } catch (Exception e){
                    synchronized(Stderr){
                        Stderr("Error in mpi handler for comm ")(comm.name)(" tag:")(tag).newline;
                        e.desc(delegate void(char[]c){
                            Stderr(c);
                        } );
                    }
                }
            }
        }
    
        HandlerServer[int] handlers;
    
        this(){
            this(MPI_COMM_WORLD,"world");
        }
        this(MPI_Comm comm,char[] name=""){
            this.comm=comm;
            _name=name;
            int dim;
            if (MPI_Comm_size(comm, &dim)!=MPI_SUCCESS){
                throw new MpiException("could not get size of communicator",__FILE__,__LINE__);
            }
            if (MPI_Comm_rank(comm, &_myRank)!=MPI_SUCCESS){
                throw new MpiException("could not get rank of communicator",__FILE__,__LINE__);
            }
            counter=UniqueNumber!(int)(10);
            channels=new MPIChannel[](dim);
        }
        char[] name(){
            return _name;
        }
        void name(char[] n){
            _name=n;
        }
        int dim(){
            return channels.length;
        }
        int myRank(){
            return _myRank;
        }
        MpiChannel opIndex(int rank){
            auto res=channels[rank];
            if (res is null){
                synchronized(this){
                    volatile res=channels[rank];
                    if (res is null){
                        res=new MpiChannel(this,rank);
                        channels[rank]=res;
                    }
                }
            }
            return res;
        }
        MpiLinearComm split(int color,int newRank){
            MPI_Comm newComm;
            if (MPI_Comm_split(comm, color, newRank, &newComm)!=MPI_SUCCESS){
                throw new MpiException("split failed",__FILE__,__LINE__);
            }
            return new MpiLinearComm(newComm);
        }
        Cart!(2) mkCart(int[2] dims,int[2] periodic,bool reorder){
            MPI_Comm newComm;
            if (MPI_Cart_create(comm, 2, dims.ptr,
                    periodic.ptr, (reorder?1:0), &newComm)!=MPI_SUCCESS)
            {
                throw new MpiException("cart create failed",__FILE__,__LINE__);
            }
            return new MPICart!(2)(this,newComm);
        }
        Cart!(3) mkCart(int[3] dims,int[3] periodic,bool reorder){
            MPI_Comm newComm;
            if (MPI_Cart_create(comm, 3, dims.ptr,
                    periodic.ptr, (reorder?1:0), &newComm)!=MPI_SUCCESS)
            {
                throw new MpiException("cart create failed",__FILE__,__LINE__);
            }
            return new MPICart!(3)(this,newComm);
        }
        Cart!(4) mkCart(int[4] dims,int[4] periodic,bool reorder){
            MPI_Comm newComm;
            if (MPI_Cart_create(comm, 4, dims.ptr,
                    periodic.ptr, (reorder?1:0), &newComm)!=MPI_SUCCESS)
            {
                throw new MpiException("cart create failed",__FILE__,__LINE__);
            }
            return new MPICart!(4)(this,newComm);
        }
    
        int nextTag(){
            return counter.next();
        }
    
        void bcast(T)(ref T val,int root,int tag=0){
            if (_dim<=1) return;
            static if(is(T U:U[])){
                int count=val.length;
                void * buf=val.ptr;
                auto dataType=MPI_DatatypeForType!(U);
            } else {
                int count=1;
                void * buf=&val;
                auto dataType=MPI_DatatypeForType!(T);
            }
            if (MPI_Bcast(buf, count, dataType, root, comm)!=MPI_SUCCESS){
                throw new MpiException("MPI_Bcast failed",__FILE__,__LINE__);
            }
        }
    
        void reduce(T)(T valOut, ref T valIn, int root,MPI_Op op,int tag=0){
            static if(is(T U:U[])){
                int count=valOut.length;
                assert(valIn.length==count,"in and out nned to have the same size");
                void * bufOut=valOut.ptr;
                void * bufIn=valIn.ptr;
                auto dataType=MPI_DatatypeForType!(U);
            } else {
                int count=1;
                void * bufOut=&valOut;
                void * bufIn=&valIn;
                auto dataType=MPI_DatatypeForType!(T);
            }
            if (MPI_Reduce ( bufOut, bufIn, count, dataType, op, root, comm )!=MPI_SUCCESS){
                throw new MpiException("MPI_Reduce failed",__FILE__,__LINE__);
            }
        }

        void allReduce(T)(T valOut, ref T valIn,MPI_Op op,int tag=0){
            static if(is(T U:U[])){
                int count=valOut.length;
                assert(valIn.length==count,"in and out nned to have the same size");
                void * bufOut=valOut.ptr;
                void * bufIn=valIn.ptr;
                auto dataType=MPI_DatatypeForType!(U);
            } else {
                int count=1;
                void * bufOut=&valOut;
                void * bufIn=&valIn;
                auto dataType=MPI_DatatypeForType!(T);
            }
            if (MPI_Allreduce ( bufOut, bufIn, count, dataType, op, comm )!=MPI_SUCCESS){
                throw new MpiException("MPI_Allreduce failed",__FILE__,__LINE__);
            }
        }
    
        void gather(T)(T[] dataOut,T[] dataIn,int root,int tag=0){
            assert(0<=root && root<dim,"invalid root");
            if (dim==1){
                dataIn[0..dataOut.length]=dataOut;
                return;
            }
            if (MPI_Gather(dataOut.ptr, dataOut.length, MPI_DatatypeForType!(T),
                        dataIn.ptr, dataIn.length, MPI_DatatypeForType!(T),
                        root, comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Gather failed",__FILE__,__LINE__);
            }
        }
        void gather(T)(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0){
            assert(inCounts.length==dim,"invalid inCounts length");
            assert(inStarts.length==dim,"invalid inStarts length");
            assert(0<=root && root<dim,"invalid root");
            if (dim==1){
                dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
                return;
            }
            if (MPI_Gatherv(dataOut.ptr, dataOut.length, MPI_DatatypeForType!(T),
                dataIn.ptr, inCounts.ptr, inStarts.ptr,
                MPI_DatatypeForType!(T), root, comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Gatherv failed",__FILE__,__LINE__);
            }
        }
        void allGather(T)(T[] dataOut,T[] dataIn,int tag=0){
            assert(0<=root && root<dim,"invalid root");
            if (dim==1){
                dataIn[0..dataOut.length]=dataOut;
                return;
            }
            if (MPI_Allgather(dataOut.ptr, dataOut.length, MPI_DatatypeForType!(T),
                        dataIn.ptr, dataIn.length, MPI_DatatypeForType!(T),
                        comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Gather failed",__FILE__,__LINE__);
            }
        }
        void allGather(T)(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0){
            assert(inCounts.length==dim,"invalid inCounts length");
            assert(inStarts.length==dim,"invalid inStarts length");
            assert(0<=root && root<dim,"invalid root");
            if (dim==1){
                dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
                return;
            }
            if (MPI_Allgatherv(dataOut.ptr, dataOut.length, MPI_DatatypeForType!(T),
                dataIn.ptr, inCounts.ptr, inStarts.ptr,
                MPI_DatatypeForType!(T), comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Gatherv failed",__FILE__,__LINE__);
            }
        }

        void scatter(T)(T[] dataOut,T[] dataIn,int root,int tag=0){
            assert(dataOut.length%dim==0);
            if (dim==1){
                dataIn[]=dataOut;
                return;
            }
            if (MPI_Scatter(dataOut.ptr, dataOut.length/dim, MPI_DatatypeForType!(T),
                            dataIn.ptr, dataIn.length, MPI_DatatypeForType!(T),
                            root, comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Scatter failed",__FILE__,__LINE__);
            }
        }
        void scatter(T)(T[] dataOut,int[] outCounts, int[] outStarts, T[] dataIn,int root,int tag=0){
            assert(outCounts.length==dim,"invalid outCounts length");
            assert(outStarts.length==dim,"invalid outStarts length");
            assert(0<=root && root<dim,"invalid root");
            if (dim==1){
                dataIn[]=dataOut[outStarts[0]..outStarts[0]+outCounts[0]];
                return;
            }
            if (MPI_Scatterv(dataOut.ptr, outCounts.ptr, outStarts,
                             MPI_DatatypeForType!(T), dataIn.ptr, dataIn.length,
                             MPI_DatatypeForType!(T), root, comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Scatterv failed",__FILE__,__LINE__);
            }
        }
        void allScatter(T)(T[] dataOut,T[] dataIn,int tag=0){
            assert(dataOut.length%dim==0);
            if (dim==1){
                dataIn[]=dataOut;
                return;
            }
            if (MPI_Scatter(dataOut.ptr, dataOut.length/dim, MPI_DatatypeForType!(T),
                            dataIn.ptr, dataIn.length, MPI_DatatypeForType!(T),
                            comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Scatter failed",__FILE__,__LINE__);
            }
        }
        void allScatter(T)(T[] dataOut,int[] outCounts, int[] outStarts, T[] dataIn,int tag=0){
            assert(outCounts.length==dim,"invalid outCounts length");
            assert(outStarts.length==dim,"invalid outStarts length");
            if (dim==1){
                dataIn[]=dataOut[outStarts[0]..outStarts[0]+outCounts[0]];
                return;
            }
            if (MPI_Scatterv(dataOut.ptr, outCounts.ptr, outStarts,
                             MPI_DatatypeForType!(T), dataIn.ptr, dataIn.length,
                             MPI_DatatypeForType!(T), comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Scatterv failed",__FILE__,__LINE__);
            }
        }
    
        void reduceScatter(T)(T[]outData,T[]inData,MPI_Op op){
            assert(outData.length==inData.length*dim,"invalid lengths");
            if (dim==1){
                inData[0..outData.length]=outData;
                return;
            }
            static if(is(typeof(&MPI_Reduce_scatter_block))){
                if (MPI_Reduce_scatter_block(outData.ptr, inData.ptr, inData.length, 
                        MPI_DatatypeForType!(T), op, comm)!=MPI_SUCCESS)
                {
                    throw new MpiException("MPI_Reduce_scatter_block failed",__FILE__,__LINE__);
                }
            } else {
                scope inCounts=new int[](dim);
                inCounts[]=inData.length;
                if (MPI_Reduce_scatter(outData.ptr, inData.ptr, inCounts.ptr,
                                           MPI_DatatypeForType!(T), op, comm)!=MPI_SUCCESS)
                {
                    throw new MpiException("MPI_Reduce_scatter (block) failed",__FILE__,__LINE__);
                }
            }
        }
        void reduceScatter(T)(T[]outData,T[]inData,int[]inCounts,MPI_Op op)
        in{
            assert(outData.length==inData.length*dim,"invalid lengths");
            assert(inCounts[myRank]==inData.length,"invalid inData length");
            size_t sum=0;
            foreach (i;inCounts) sum+=i;
            assert(outData.length==sum,"inconsistent inCounts and outData length");
        }
        body{
            if (dim==1){
                assert(inCounts[0]==outData.length && inCounts[0]==inData.length,"incorrect lengths");
                inData[0..outData.lengths]=outData;
                return;
            }
            if (MPI_Reduce_scatter(outData.ptr, inData.ptr, inCounts.ptr,
                                       MPI_DatatypeForType!(T), op, comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Reduce_scatter failed",__FILE__,__LINE__);
            }
        }

        void alltoall(T)(T[] dataOut,T[] dataIn,int tag=0){
            assert(dataOut.length%dim==0,"invalid dataOut length");
            assert(dataIn.length%dim==0,"invalid dataIn length");
            if (dim==1){
                dataIn[0..dataOut.length]=dataIn;
                return;
            }
            if (MPI_Alltoall(dataOut.ptr, dataOut.length/dim, MPI_DatatypeForType!(T),
                             dataIn.ptr, dataIn.length/dim, MPI_DatatypeForType!(T),comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Alltoall failed",__FILE__,__LINE__);
            }
        }
        void alltoall(T)(T[] dataOut,int[] outCounts,int[] outStarts,
            T[] dataIn,int[] inCounts, int[] inStarts,int tag=0)
        in {
            assert(outCounts.length==dim,"invalid outCounts length");
            assert(outStarts.length==dim,"invalid outStarts length");
            assert(inCounts.length==dim,"invalid inCounts length");
            assert(inStarts.length==dim,"invalid inStarts length");
            assert(dataIn.length>inStarts[$]+inCounts[$]);
            for (int irank=1;irank<dim;++irank){
                assert(inStarts[irank]>=inStarts[irank-1]+inCounts[irank-1]);
            }
            assert(dataOut.length>outStarts[$]+outCounts[$]);
            for (int irank=1;irank<dim;++irank){
                assert(outStarts[irank]>=outStarts[irank-1]+outCounts[irank-1]);
            }
        }
        body {
            if (dim==1){
                dataIn[inStarts[0]..inStarts[0]+dataOut.length]=outData;
                return;
            }
            if (MPI_Alltoallv(dataOut.ptr, outCounts.ptr, outStarts.ptr,
                              MPI_DatatypeForType!(T), dataIn.ptr, inCounts.ptr,
                              inStarts.ptr, MPI_DatatypeForType!(T),comm)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Alltoallv failed",__FILE__,__LINE__);
            }
        }
    
        void barrier(){
            if (MPI_Barrier(comm)!=MPI_SUCCESS){
                throw new MpiException("MPI_Barrier failed",__FILE__,__LINE__);
            }
        }
    
        void registerHandler(ChannelHandler handler,int tag){
            serv=new HandlerServer(this,handler,tag);
            if ((tag in handlers)is null){
                throw new MpiException("handler already present for tag "~to!(char[])(tag),
                    __FILE__,__LINE__);
            }
            handlers[tag]=serv;
            t=new Thread(&serv.run);
            t.isDaemon=true;
            t.start();
        }
    
    }

    static LinearComm mpiWorld;
    static this(){
        mpiWorld=new MpiLinearComm();
    }

} else { // no mpi
    public import blip.parallel.mpi.MpiModels;
    import blip.parallel.mpi.SingleNode;
    
    static LinearComm mpiWorld;
    static this(){
        mpiWorld=new SNLinearComm();
    }
}