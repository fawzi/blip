/// Mpi environment
/// a mpiWorld static constant is available, if mpi is available it uses it, otherwise
/// SingleNode is used. The interface exposed is the same.
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
module blip.parallel.mpi.Mpi;

version(mpi)
{
    public import blip.parallel.mpi.MpiModels;
    import blip.serialization.Serialization;
    import blip.parallel.smp.WorkManager;
    import blip.bindings.mpi.mpi;
    import blip.io.IOArray;
    import blip.container.Deque;
    import blip.BasicModels;
    import blip.sync.UniqueNumber;
    import blip.container.AtomicSLink;
    import blip.container.GrowableArray;
    import blip.io.Console;
    import blip.io.BasicIO;
    import blip.core.Thread;
    import blip.stdc.config;
    import blip.io.StreamConverters;
    import blip.Comp;

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
        static __gshared MpiSerializer freeList;
        MpiSerializer next;
        int tag;
        LocalGrowableArray!(ubyte) msgData;
        Channel target;
        
        static MpiSerializer opCall(Channel target,int tag,ubyte[] buf=null,
            GASharing sharing=GASharing.GlobalNoFree){
            auto newS=popFrom(freeList);
            if (newS is null){
                newS=new MpiSerializer(target,tag,buf);
            } else {
                if (buf.length>0){
                    newS.msgData.assign(buf,0,sharing);
                }
                newS.tag=tag;
                newS.target=target;
                newS.next=null;
            }
            return newS;
        }
        void giveBack(){
            tag=AnyTag;
            if (msgData.sharing!=GASharing.Global){
                msgData.deallocData();
            } else {
                msgData.clearData();
            }
            insertAt(freeList,this);
        }
        this(Channel target,int tag,ubyte[] buf=null,
            GASharing sharing=GASharing.GlobalNoFree){
            auto ga=lGrowableArray(buf,0,sharing);
            super(&ga.appendVoid);
            this.msgData=ga;
            this.target=target;
            this.tag=tag;
        }
        void writeStartRoot() {
            super.writeStartRoot();
            assert(tag!=AnyTag);
            assert(target!is null);
        }
        void writeEndRoot() {
            super.writeEndRoot();
            assert(tag!=AnyTag);
            assert(target!is null);
        }
        void close(){
            Task("MpiSerializerClose",{
                target.send(msgData.data,tag);
            }).autorelease.executeNow(target.sendTask);
            super.close();
            giveBack();
        }
        void useBuf(ubyte[] buf,GASharing sharing=GASharing.GlobalNoFree){
            msgData.assign(buf,0,sharing);
        }
        void clearMsg(){
            tag=AnyTag;
            msgData.clearData();
        }
    }

    class MpiUnserializer:SBinUnserializer{
        static __gshared MpiUnserializer freeList;
        SerializedMessage msg;
        MpiUnserializer next;
        static MpiUnserializer opCall(SerializedMessage msg){
            auto newS=popFrom(freeList);
            if (newS is null){
                newS=new MpiUnserializer(msg);
            } else {
                newS.msg=msg;
                (cast(IOArray)newS.reader).assign(msg.msg);
                newS.next=null;
            }
            return newS;
        }
        void giveBack(){
            msg.tag=AnyTag;
            msg.msg=null;
            (cast(IOArray)reader).assign(null,0);
            insertAt(freeList,this);
        }
        this(SerializedMessage msg){
            this.msg=msg;
            super(toReaderT!(void)(new IOArray(msg.msg,msg.msg.length)));
        }
        void readStartRoot() {
            assert(msg.tag!=AnyTag);
            super.readStartRoot();
        }
        void readEndRoot() {
            super.readEndRoot();
            assert(msg.tag!=AnyTag);
        }
        void close(){
            giveBack();
        }
    
    }

    /// mpi error
    class MpiException:Exception{
        this(string msg,string file, long line){
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
            tag=status.MPI_TAG;
            int count;
            if (MPI_Get_count(&status, MPI_DatatypeForType!(ubyte), &count)!=MPI_SUCCESS){
                throw new MpiException("MPI_Get_count failed",__FILE__,__LINE__);
            }
            buf.length=count;
            recv(buf,tag);
            return MpiUnserializer(SerializedMessage(status.MPI_TAG,buf));
        }
        template sendT(T){
            void send(in T valOut,int tag=0){
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
        }
        // ugly but needed at the moment...
        mixin sendT!(int[])    s1;
        mixin sendT!(double[]) s2;
        mixin sendT!(ubyte[])  s3;
        alias s1.send send;
        alias s2.send send;
        alias s3.send send;
        
        template recvT(T){
            int recv(ref T valIn, int tag=0){
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
                return status.MPI_TAG;
            }
        }
        // ugly but needed at the moment...
        mixin recvT!(int[])    r1;
        mixin recvT!(double[]) r2;
        mixin recvT!(ubyte[])  r3;
        alias r1.recv recv;
        alias r2.recv recv;
        alias r3.recv recv;
        
        void sendStr(in cstring s, int tag=0){
            sendT!(cstring ).send(s,tag);
        }
        int recvStr(ref char[] s,int tag=0){
            MPI_Status status;
            if (MPI_Probe(otherRank, tag, comm.comm, &status)!=MPI_SUCCESS){
                throw new MpiException("MPI_Probe failed",__FILE__,__LINE__);
            }
            int count;
            if (MPI_Get_count(&status, MPI_DatatypeForType!(char), &count)!=MPI_SUCCESS){
                throw new MpiException("MPI_Get_count failed",__FILE__,__LINE__);
            }
            s.length=count;
            return recvT!(char[]).recv(s,tag);
        }
        void close(){ }
    
        template sendrecvT(T){
            int sendrecv(in T sendV,ref T recvV,Channel recvChannel,int sendTag=0,int recvTag=0){
                if (recvChannel is this){
                    static if(is(T U:U[])){
                        recvV[]=sendV;
                    } else {
                        recvV=sendV;
                    }
                    return MPI_SUCCESS;
                } else {
                    sendT!(T).send(sendV,sendTag);
                    return recvChannel.recv(recvV,recvTag);
                }
            }
        }
        // ugly but needed at the moment...
        mixin sendrecvT!(int[])    sr1;
        mixin sendrecvT!(double[]) sr2;
        mixin sendrecvT!(ubyte[])  sr3;
        alias sr1.sendrecv sendrecv;
        alias sr2.sendrecv sendrecv;
        alias sr3.sendrecv sendrecv;
        
        void desc(scope void delegate(in cstring) sink){
            auto s=dumper(sink);
            s("{<MpiChannel@")(cast(void*)this)(">\n");
            s("  otherRank:")(this.otherRank)(",\n");
            s("  comm:MpiLinearComm@")(cast(void*)this.comm)(">\n");
            s("}");
        }
    }

    class MpiCart(int dimG):Cart!(dimG){
        string name;
        int[dimG] _dims;
        int[dimG] _myPos;
        int[dimG] _periods;
        MpiLinearComm _baseComm;
        this(MpiLinearComm baseComm,string name,int[]dims,int[] periods,bool reorder=true){
            assert(dims.length==dimG,"invalid number of dimensions");
            assert(periods is null || periods.length==dimG,"invalid number of dimensions");
            
            MPI_Comm newComm;
            if (MPI_Cart_create(baseComm.comm,dimG,dims.ptr,
                periods.ptr,reorder,&newComm)!=MPI_SUCCESS)
            {
                throw new MpiException("creation of cart failed",__FILE__,__LINE__);
            }
            auto bComm=new MpiLinearComm(newComm,name);
            this(bComm);
        }
        
        this(MpiLinearComm baseComm){
            this._baseComm=baseComm;
            if (MPI_Cart_get(_baseComm.comm, dimG, _dims.ptr,
                _periods.ptr,_myPos.ptr)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Cart_get failed",__FILE__,__LINE__);
            }
        }
        int[] dims(){
            return _dims;
        }
        int[] myPos(){
            return _myPos;
        }
        int[] periodic(){
            return _periods;
        }
        LinearComm baseComm(){
            return _baseComm;
        }
        int pos2rank(int[dimG] pos){
            int res;
            if(MPI_Cart_rank(_baseComm.comm,pos.ptr,&res)!=MPI_SUCCESS){
                throw new MpiException("MPI_Cart_rank failed",__FILE__,__LINE__);
            }
            return res;
        }
        Channel opIndex(int[dimG] pos){
            return _baseComm[pos2rank(pos)];
        }
        int[] rank2pos(int rank,int[dimG] pos){
            if (MPI_Cart_coords(_baseComm.comm, rank, dimG, pos.ptr)!=MPI_SUCCESS){
                throw new MpiException("MPI_Cart_coords failed",__FILE__,__LINE__);
            }
            return pos;
        }
        void shift(int direction, int disp, out int rank_source, out int rank_dest){
            if (MPI_Cart_shift(_baseComm.comm, direction, disp,
                &rank_source, &rank_dest)!=MPI_SUCCESS)
            {
                throw new MpiException("MPI_Cart_shift failed",__FILE__,__LINE__);
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
        string _name;
    
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
                        handler(comm[status.MPI_SOURCE],status.MPI_TAG);
                    }
                } catch (Throwable e){
                    serr(collectIAppender(delegate void(scope CharSink s){
                        dumper(s)("Error in mpi handler for comm ")(comm.name)(" tag:")(tag)("\n");
                        e.writeOut(serr.call);
                    }));
                }
            }
        }
    
        HandlerServer[int] handlers;
    
        this(){
            this(MPI_COMM_WORLD,"world");
        }
        this(MPI_Comm comm,string name=""){
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
            channels=new MpiChannel[](dim);
        }
        string name(){
            return _name;
        }
        void name(string n){
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
                    res=channels[rank];
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
        Cart!(2) mkCart(string name,int[2] dims,int[2] periodic,bool reorder){
            return new MpiCart!(2)(this,name,dims,periodic,reorder);
        }
        Cart!(3) mkCart(string name,int[3] dims,int[3] periodic,bool reorder){
            return new MpiCart!(3)(this,name,dims,periodic,reorder);
        }
        Cart!(4) mkCart(string name,int[4] dims,int[4] periodic,bool reorder){
            return new MpiCart!(4)(this,name,dims,periodic,reorder);
        }
    
        int nextTag(){
            return counter.next();
        }
    
        template collOp1(T){
            void bcast(ref T val,int root,int tag=0){
                if (channels.length<=1) return;
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
    
            void reduce(T valOut, ref T valIn, int root,MPI_Op op,int tag=0){
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

            void allReduce(T valOut, ref T valIn,MPI_Op op,int tag=0){
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
        }
        template collOp2(T){
            void gather(T[] dataOut,T[] dataIn,int root,int tag=0){
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
            void gather(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0){
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
            void allGather(T[] dataOut,T[] dataIn,int tag=0){
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
            void allGather(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int tag=0){
                assert(inCounts.length==dim,"invalid inCounts length");
                assert(inStarts.length==dim,"invalid inStarts length");
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

            void scatter(T[] dataOut,T[] dataIn,int root,int tag=0){
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
            void scatter(T[] dataOut,int[] outCounts, int[] outStarts, T[] dataIn,int root,int tag=0){
                assert(outCounts.length==dim,"invalid outCounts length");
                assert(outStarts.length==dim,"invalid outStarts length");
                assert(0<=root && root<dim,"invalid root");
                if (dim==1){
                    dataIn[]=dataOut[outStarts[0]..outStarts[0]+outCounts[0]];
                    return;
                }
                if (MPI_Scatterv(dataOut.ptr, outCounts.ptr, outStarts.ptr,
                                 MPI_DatatypeForType!(T), dataIn.ptr, dataIn.length,
                                 MPI_DatatypeForType!(T), root, comm)!=MPI_SUCCESS)
                {
                    throw new MpiException("MPI_Scatterv failed",__FILE__,__LINE__);
                }
            }
    
            void reduceScatter(T[]outData,T[]inData,MPI_Op op){
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
            void reduceScatter(T[]outData,T[]inData,int[]inCounts,MPI_Op op)
            in{
                assert(outData.length==inData.length*dim,"invalid lengths");
                assert(inCounts[myRank]==inData.length,"invalid inData length");
                size_t sum=0;
                foreach (i;inCounts) sum+=i;
                assert(outData.length==sum,"inconsistent inCounts and outData length");
            }
            body{
                if (dim==1){
                    assert(inCounts[0]<=outData.length && inCounts[0]==inData.length,"incorrect lengths");
                    inData[0..outData.length]=outData;
                    return;
                }
                if (MPI_Reduce_scatter(outData.ptr, inData.ptr, inCounts.ptr,
                                           MPI_DatatypeForType!(T), op, comm)!=MPI_SUCCESS)
                {
                    throw new MpiException("MPI_Reduce_scatter failed",__FILE__,__LINE__);
                }
            }

            void alltoall(T[] dataOut,T[] dataIn,int tag=0){
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
            void alltoall(T[] dataOut,int[] outCounts,int[] outStarts,
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
                    dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
                    return;
                }
                if (MPI_Alltoallv(dataOut.ptr, outCounts.ptr, outStarts.ptr,
                                  MPI_DatatypeForType!(T), dataIn.ptr, inCounts.ptr,
                                  inStarts.ptr, MPI_DatatypeForType!(T),comm)!=MPI_SUCCESS)
                {
                    throw new MpiException("MPI_Alltoallv failed",__FILE__,__LINE__);
                }
            }
        }
        // ugly but needed at the moment
        mixin collOp1!(int)      cOp1;
        mixin collOp1!(int[])    cOp2;
        mixin collOp1!(double)   cOp3;
        mixin collOp1!(double[]) cOp4;
        mixin collOp1!(ubyte)    cOp5;
        mixin collOp1!(ubyte[])  cOp6;
        mixin collOp2!(int)      cOp7;
        mixin collOp2!(double)   cOp8;
        mixin collOp2!(ubyte)    cOp9;
        alias cOp1.bcast         bcast        ;
        alias cOp1.reduce        reduce       ;
        alias cOp1.allReduce     allReduce    ;
        alias cOp2.bcast         bcast        ;
        alias cOp2.reduce        reduce       ;
        alias cOp2.allReduce     allReduce    ;
        alias cOp3.bcast         bcast        ;
        alias cOp3.reduce        reduce       ;
        alias cOp3.allReduce     allReduce    ;
        alias cOp4.bcast         bcast        ;
        alias cOp4.reduce        reduce       ;
        alias cOp4.allReduce     allReduce    ;
        alias cOp5.bcast         bcast        ;
        alias cOp5.reduce        reduce       ;
        alias cOp5.allReduce     allReduce    ;
        alias cOp6.bcast         bcast        ;
        alias cOp6.reduce        reduce       ;
        alias cOp6.allReduce     allReduce    ;
        alias cOp7.gather        gather       ;
        alias cOp7.allGather     allGather    ;
        alias cOp7.scatter       scatter      ;
        alias cOp7.reduceScatter reduceScatter;
        alias cOp7.alltoall      alltoall     ;
        alias cOp8.gather        gather       ;
        alias cOp8.allGather     allGather    ;
        alias cOp8.scatter       scatter      ;
        alias cOp8.reduceScatter reduceScatter;
        alias cOp8.alltoall      alltoall     ;
        alias cOp9.gather        gather       ;
        alias cOp9.allGather     allGather    ;
        alias cOp9.scatter       scatter      ;
        alias cOp9.reduceScatter reduceScatter;
        alias cOp9.alltoall      alltoall     ;
        
        void barrier(){
            if (MPI_Barrier(comm)!=MPI_SUCCESS){
                throw new MpiException("MPI_Barrier failed",__FILE__,__LINE__);
            }
        }
    
        void registerHandler(ChannelHandler handler,int tag){
            auto serv=new HandlerServer(this,handler,tag);
            if ((tag in handlers)is null){
                throw new MpiException(collectIAppender(delegate void(scope CharSink s){
                    s("handler already present for tag "); writeOut(s,tag); }),
                    __FILE__,__LINE__);
            }
            handlers[tag]=serv;
            auto t=new Thread(&serv.run);
            t.isDaemon=true;
            t.start();
        }
    
        void desc(scope void delegate(in cstring) sink){
            desc(sink,true);
        }
        void desc(scope void delegate(in cstring) sink,bool shortDesc){
            auto s=dumper(sink);
            s("{<MpiLinearComm@")(cast(void*)this)(">\n");
            s("  name:")(this.name)(",\n");
            s("  myRank:")(this._myRank)(",\n");
            s("  dim:")(this.channels.length)(",\n");
            if (!shortDesc){
                s("  channels:[");
                foreach(i,c;channels){
                    if (i!=0) s(",");
                    s(c);
                }
                s("],\n");
            }
            s("  comm:")(cast(void*)this.comm)("\n");
            s("}");
        }
    
    }

    static __gshared LinearComm mpiWorld;
    shared static this(){
        mpiWorld=new MpiLinearComm();
    }

} else { // no mpi
    public import blip.parallel.mpi.MpiModels;
    import blip.parallel.mpi.SingleNode;
    
    static __gshared LinearComm mpiWorld;
    shared static this(){
        mpiWorld=new SNLinearComm();
    }
}
