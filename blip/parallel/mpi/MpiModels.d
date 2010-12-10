/// represents environments of ordered and reliable computing nodes, as modeled
/// by mpi. Cannot cope with addition or removal of nodes.
/// Use this for thightly coupled calculations, use cluster distribution of them
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
module blip.parallel.mpi.MpiModels;
import blip.serialization.Serialization;
import blip.BasicModels;
import blip.parallel.smp.WorkManager;
import blip.bindings.mpi.mpi;
public import blip.bindings.mpi.mpi: MPI_Op, MPI_MAX, MPI_MIN, MPI_SUM, MPI_PROD, MPI_LAND, MPI_BAND, MPI_LOR,
    MPI_BOR, MPI_LXOR, MPI_BXOR, MPI_MAXLOC, MPI_MINLOC, MPI_REPLACE;
import blip.util.LocalMem;
import blip.container.GrowableArray;
import blip.serialization.SBinSerialization;
import blip.core.Array:sort;
import blip.Comp;

enum :int{
    AnyTag=int.max
}
//PUBLIC :: mp_bcast, mp_sum, mp_max, mp_maxloc, mp_minloc, mp_min, mp_sync
//PUBLIC :: mp_gather, mp_scatter, mp_alltoall, mp_sendrecv, 

alias void delegate(Channel,int) ChannelHandler;

/// represents a comunication channel with a task
interface Channel{
    TaskI sendTask();
    TaskI recvTask(); // remove???
    /// send might be sent while serializing or only when you send close, thus close should be sent...
    /// can be called from any task
    Serializer sendTag(int tag=0,ubyte[] buf=null);
    /// should be called from the sendTask
    void send(Const!(double[]),int tag=0);
    /// should be called from the sendTask
    void send(Const!(int[]),int tag=0);
    /// should be called from the sendTask
    void send(Const!(ubyte[]),int tag=0);
    /// should be called from the sendTask
    void sendStr(Const!(cstring),int tag=0);
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
    int[] periodic();
    int[] myPos();
    Channel opIndex(int[dimG] pos);
    LinearComm baseComm();
    int pos2rank(int[dimG] pos);
    int[] rank2pos(int rank,int[dimG] pos);
    void shift(int direction, int disp, out int rank_source, out int rank_dest);
}

/// collective operations, represents an mpi communicator, 1D
interface LinearComm:BasicObjectI{
    enum {
        maxTagMask=0x7FFF, /// smallest valid value for MPI_TAG_UB defined in the standard
    }
    string name();
    void name(string n);
    
    int dim();
    int myRank();
    Channel opIndex(int rank);
    LinearComm split(int color,int newRank);
    Cart!(2) mkCart(string name,int[2] dims,int[2] periodic, bool reorder);
    Cart!(3) mkCart(string name,int[3] dims,int[3] periodic, bool reorder);
    Cart!(4) mkCart(string name,int[4] dims,int[4] periodic, bool reorder);
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

template isBasicMpiType(T){
    enum:bool { isBasicMpiType=(is(T==double)||is(T==int)||is(T==ubyte)) }
}
template isBasicMpiArrType(T){
    enum:bool { isBasicMpiArrType=(is(T:double[])||is(T:int[])||is(T:ubyte[])) }
}

/// utility method switching to faster sends for standard types (assumed of *known* length)
/// use Channel.sendTag for unknown length objects
void mpiSendT(T)(Channel c,T val,int tag=0){
    static if (isBasicMpiArrType!(T)){
        c.send(val,tag);
    } else static if(isBasicMpiType!(T)){
        c.send([val],tag);
    } else static if (is(T==struct) && is(typeof(T.isSimpleData)) && T.isSimpleData){
        auto arr=(cast(ubyte*)&val)[0..T.sizeof];
        c.send(arr,tag);
    } else static if (is(typeof(val.serBlockSize))){
        auto bSize=serBlockSize();
        ubyte[256] _buf;
        ubyte[] buf;
        if (bSize<=_buf.length) {
            buf=_buf[0..bSize];
        } else {
            buf=new ubyte[](bSize);
        }
        auto arr=lGrowableArray(buf,0);
        scope s=new SBinSerializer(&arr.appendArr); // use cache???
        s(val);
        s.close();
        assert(arr.length>bSize,"unexpected length");
        assert(arr.ptr==buf.ptr,"unexpected storage");
        c.send(buf,tag);
        if (bSize>_buf.length) delete buf;
    } else {
        scope s=c.sendTag(tag);
        s(val);
        s.close();
    }
}
/// paired receive method using faster receive for standard types (assumed of *known* length)
/// use recvTag for unknown length objects
void mpiRecvT(T)(Channel c,ref T val,int tag=0){
    static if (isBasicMpiArrType!(T)){
        c.recv(val,tag);
    } else static if(isBasicMpiType!(T)){
        auto r=(&val)[0..1];
        c.recv(r,tag);
        assert(r.length==1 && r.ptr=&val);
    } else static if (is(T==struct) && is(typeof(T.isSimpleData)) && T.isSimpleData){
        auto arr=(cast(ubyte*)&val)[0..T.sizeof];
        c.recv(arr,tag);
        assert(r.length==T.sizeof && r.ptr=&val);
    } else static if (is(typeof(val.serBlockSize))){
        auto bSize=serBlockSize();
        ubyte[256] _buf;
        ubyte[] buf;
        if (bSize<=_buf.length) {
            buf=_buf[0..bSize];
        } else {
            buf=new ubyte[](bSize);
        }
        auto rest=buf;
        c.recv(buf,tag);
        scope s=new SBinUnserializer(delegate void(void[] dest){
            if (dest.length<=rest.length){
                dest[]=rest[0..dest.length];
                rest=rest[dest.length..$];
            } else {
                throw new Exception("unexpected read request",__FILE__,__LINE__);
            }
        });
        s(val);
        s.close();
        if (bSize>_buf.length) delete buf;
    } else {
        scope s=c.recvTag(tag);
        s(val);
        s.close();
    }
}
/// utility method for 
void mpiBcastT(T)(LinearComm para,ref T val,int target,int tag=0){
    static if (isBasicMpiType!(T)||isBasicMpiArrType!(T)){
        para.bcast(val,target,tag);
    } else static if (is(T==struct) && is(typeof(T.isSimpleData)) && T.isSimpleData){
        auto arr=(cast(ubyte*)&val)[0..T.sizeof];
        para.bcast(arr,target,tag);
    } else static if (is(typeof(val.serBlockSize))){
        size_t size=cast(size_t)val.serBlockSize;
        ubyte[256] _buf;
        ubyte[] buf;
        if (size<=_buf.length){
            buf=_buf[0..size];
        } else {
            buf=new ubyte[](size);
        }
        if (para.myRank==target){
            auto arr=lGrowableArray(_buf,0);
            auto s=new SBinSerializer(&arr.appendArr); // use cache???
            s(val);
            assert(arr.length==buf.length,"unexpected length");
            assert(cast(ubyte*)arr.ptr is buf.ptr,"unexpected storage");
        }
        para.bcast(buf,target,tag);
        auto us=new SBinUnserializer(delegate void(void[] data){
            assert(data.length<buf.length);
            data[]=buf[0..data.length];
            buf=buf[data.length..$];
        }); // use cache???
        us(val);
    } else {
        ubyte[256] _buf;
        ubyte[] buf;
        int size;
        if (para.myRank==target){
            auto arr=lGrowableArray(_buf,0,GASharing.GlobalNoFree);
            auto s=new SBinSerializer(&arr.appendVoid); // use cache???
            s(val);
            size=arr.length;
            para.bcast(size,target,tag);
            auto arrV=arr.data;
            para.bcast(arrV,target,tag);
            buf=arr.takeData;
        } else {
            para.bcast(size,target,tag);
            if (size<=_buf.length){
                buf=_buf[0..size];
            } else {
                buf=new ubyte[](size);
            }
            para.bcast(buf,target,tag);
        }
        auto buf0=buf;
        auto us=new SBinUnserializer(delegate void(void[] data){
            assert(data.length<buf.length);
            data[]=buf[0..data.length];
            buf=buf[data.length..$];
        }); // use cache???
        us(val);
        if (size>_buf.length){
            delete buf0;
        }
    }
}

void mpiAllGatherT(U,T)(LinearComm para,U valOut, T valIn,int tag=0,int[] inCounts=null){
    alias typeof(valIn[0]) ElType;
    static if (isBasicMpiArrType!(T)){
        if (inCounts.length==0){
            static if (is(U==T)){
                para.allGather(valOut,valIn,tag);
            } else {
                static assert(is(U[]==T),"unexpected valIn type "~U.stringof~" in allGatherT with valOut of type "~T.stringof);
                para.allGather((&valOut)[0..1],valIn,tag);
            }
        } else {
            int[128] buf;
            int[] inStarts;
            if (inCounts.length<=buf.length){
                inStarts=buf[0..inCounts.length];
            } else {
                inStarts=new int[](inCounts.length);
            }
            int pos=0;
            foreach(i,j;inCounts){
                inStarts[i]=pos;
                pos+=j;
            }
            static if (is(U==T)){
                para.allGather(valOut,valIn,inStarts,inCounts,tag);
            } else {
                para.allGather((&valOut)[0..1],valIn,inStarts,inCounts,tag);
            }
            if (inCounts.length>buf.length){
                delete inStarts;
            }
        }
    } else static if (is(ElType == struct) && is(typeof(ElType.isSimpleData):bool) && ElType.isSimpleData){
        if (inCounts.length==0){
            static if (is(U==T)){
                para.allGather((cast(ubyte*)valOut.ptr)[0..valOut.length*ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],tag);
            } else {
                static assert(is(U[]==T),"unexpected valIn type "~U.stringof~" in allGatherT with valOut of type "~T.stringof);
                para.allGather((cast(ubyte*)&valOut)[0..ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],tag);
            }
        } else {
            int[256] buf;
            auto lMem=LocalMem(buf);
            int[] inStarts=lMem.allocArr!(int)(inCounts.length);
            int[] inCounts2=lMem.allocArr!(int)(inCounts.length);
            foreach(i,j;inCounts){
                inCounts2[i]=j*ElType.sizeof;
            }
            int pos=0;
            foreach(i,j;inCounts2){
                inStarts[i]=pos;
                pos+=j;
            }
            static if (is(U==T)){
                para.allGather((cast(ubyte*)valOut.ptr)[0..valOut.length*ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],inStarts,inCounts2,tag);
            } else {
                // don't accept this?
                para.allGather((cast(ubyte*)&valOut)[0..ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],inStarts,inCounts2,tag);
            }
            lMem.deallocArr(inStarts);
            lMem.deallocArr(inCounts2);
        }
    } else {
        ubyte[256] buf;
        ubyte[256] buf2;
        int size;
        auto arr=lGrowableArray(buf,0,GASharing.GlobalNoFree);
        auto s=new SBinSerializer(&arr.appendVoid); // use cache???
        s(valOut);
        auto lMem=LocalMem(buf2);
        int[] inCounts2=lMem.allocArr!(int)(para.dim);
        int[1] myCount=[cast(int)arr.length];
        para.allGather(myCount,inCounts2,tag);
        int[] inStarts=lMem.allocArr!(int)(para.dim);
        int pos=0;
        foreach(i,j;inCounts2){
            inStarts[i]=pos;
            pos+=j;
        }
        auto resData=lMem.allocArr!(ubyte)(pos);
        para.allGather(arr.data,resData,inStarts,inCounts2,tag);
        auto leftData=resData;
        auto us=new SBinUnserializer(delegate void(void[] data){
            assert(data.length<=leftData.length);
            data[]=leftData[0..data.length];
            leftData=leftData[data.length..$];
        }); // use cache???
        foreach(i,ref v;valIn){
            leftData=resData[inStarts[i]..inStarts[i]+inCounts2[i]];
            us(v);
        }
        lMem.deallocArr(resData);
        lMem.deallocArr(inStarts);
        lMem.deallocArr(inCounts2);
    }
}

void mpiGatherT(U,T)(LinearComm para,U valOut, T valIn,int root,int tag=0,int[] inCounts=null){
    alias typeof(valIn[0]) ElType;
    static if (isBasicMpiArrType!(T)){
        if (inCounts.length==0){
            static if (is(U==T)){
                para.gather(valOut,valIn,root,tag);
            } else {
                static assert(is(U[]==T),"unexpected valIn type "~U.stringof~" in gatherT with valOut of type "~T.stringof);
                para.gather(valOut,(&valIn)[0..1],root,tag);
            }
        } else {
            int[128] buf;
            int[] inStarts;
            if (inCounts.length<=buf.length){
                inStarts=buf[0..inCounts.length];
            } else {
                inStarts=new int[](inCounts.length);
            }
            pos=0;
            foreach(i,j;inCounts){
                inStarts[i]=pos;
                pos+=j;
            }
            static if (is(U==T)){
                para.gather(valOut,valIn,inStarts,inCounts,root,tag);
            } else {
                para.gather((&valOut)[0..1],valIn,inStarts,inCounts,root,tag);
            }
            if (inCounts.length>buf.length){
                delete inStarts;
            }
        }
    } else static if (is(ElType == struct) && is(typeof(ElType.isSimpleData):bool) && ElType.isSimpleData){
        if (inCounts.length==0){
            static if (is(U==T)){
                para.gather((cast(ubyte*)valOut.ptr)[0..valOut.length*ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],root,tag);
            } else {
                static assert(U[]==T,"unexpected valIn type "~U.stringof~" in gatherT with valOut of type "~T.stringof);
                para.gather((cast(ubyte*)valOut.ptr)[0..valOut.length*ElType.sizeof],
                    (cast(ubyte*)&valIn)[0..ElType.sizeof],root,tag);
            }
        } else {
            int[256] buf;
            auto lMem=LocalMem(buf);
            int[] inStarts=lMem.allocArr!(int)(inCounts.length);
            int[] inCounts2=lMem.allocArr!(int)(inCounts.length);
            foreach(i,j;inCounts){
                inCounts2[i]=j*ElType.sizeof;
            }
            int pos=0;
            foreach(i,j;inCounts2){
                inStarts[i]=pos;
                pos+=j;
            }
            static if (is(U==T)){
                para.gather((cast(ubyte*)valOut.ptr)[0..valOut.length*ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],inStarts,inCounts2,root,tag);
            } else {
                // don't accept this?
                para.gather((cast(ubyte*)&valOut)[0..ElType.sizeof],
                    (cast(ubyte*)valIn.ptr)[0..valIn.length*ElType.sizeof],inStarts,inCounts2,root,tag);
            }
            lMem.deallocArr(inStarts);
            lMem.deallocArr(inCounts2);
        }
    } else {
        int[256] buf;
        int[256] buf2;
        int size;
        auto arr=lGrowableArray(buf,0,GASharing.GlobalNoFree);
        auto s=new SBinSerializer(&arr.appendArr); // use cache???
        s(valIn);
        auto lMem=LocalMem(buf2);
        int[] inCounts2=lMem.allocArr!(int)(para.dim);
        int[1] myCount=[cast(int)arr.length];
        para.gather(myCount,inCounts2,root,tag);
        if (para.myRank==target){
            int[] inStarts=lMem.allocArr!(int)(para.dim);
            int pos=0;
            foreach(i,j;inCounts2){
                inStarts[i]=pos;
                pos+=j;
            }
            resData=lMem.allocArr!(ubyte)(pos);
            para.gather(arr.data,resData,inStarts,inCounts2,root,tag);
            auto leftData=resData;
            auto us=new SBinUnserializer(delegate void(void[] data){
                assert(data.length<leftData.length);
                data[]=leftData[0..data.length];
                buf=leftData[data.length..$];
            }); // use cache???
            foreach(i,ref v;valIn){
                leftData=data[inStarts[i]..inStarts[i]+inCounts2[i]];
                us(v);
            }
            lMem.deallocArr(resData);
            lMem.deallocArr(inStarts);
        } else {
            para.gather([],arr.data,[],[],root,tag);
        }
        lMem.deallocArr(inCounts2);
    }
}

void mpiScatterT(T,U)(T dataOut,U dataOut,int root,tag=0,int[] outCounts=null){
    alias typeof(dataOut[0])ElType;
    assert(0,"to do");
}

void mpiAlltoallT(T)(T[] dataOut,T[] dataIn,int tag=0,int[]outCount=null,int[]inCount=null){
    assert(0,"to do");
}
