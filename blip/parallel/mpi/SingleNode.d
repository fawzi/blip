/// an environment on a single computer (single process)
/// at the moment just 1 channel
///
/// to do: at the moment to override a function of an interface with a template you need quite some
/// contortions, those should be removed when not needed anymore.
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
module blip.parallel.mpi.SingleNode;
import blip.parallel.mpi.MpiModels;
import blip.serialization.Serialization;
import blip.parallel.smp.WorkManager;
import blip.BasicModels;
import blip.container.Deque;
import blip.sync.UniqueNumber;
import blip.io.IOArray;
import blip.serialization.Handlers;
import blip.math.random.Random;
import blip.core.Variant;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.io.StreamConverters;

// duplication of serializer/unserilizer with blip.parallel.Mpi ugly, should probably be abstracted away
struct SNMessage{
    int tag;
    Variant msg;
    static SNMessage opCall(int tag,Variant msg){
        SNMessage res;
        res.tag=tag;
        res.msg=msg;
        return res;
    }
    mixin(serializeSome("","tag"));
}

class SNSerializer:SBinSerializer{
    int tag;
    SNMessage res;
    SNChannel target;
    LocalGrowableArray!(ubyte) content;
    static SNSerializer opCall(){
        return new SNSerializer();
    }
    this(ubyte[] buf=null,bool local=false){
        content=lGrowableArray!(ubyte)(buf,0,GASharing.GlobalNoFree);
        super(&content.appendVoid);
        tag=AnyTag;
        res.tag=AnyTag;
    }
    void writeStartRoot() {
        super.writeStartRoot();
        assert(res.tag==AnyTag);
        assert(tag!=AnyTag);
        assert(target!is null);
        res.tag=tag;
    }
    void writeEndRoot() {
        super.writeEndRoot();
        assert(res.tag==tag);
    }
    void close() {
        super.close();
        assert(res.tag==tag);
        assert(target!is null);
        res.msg=Variant(content.takeData());
        target.data.append(res);
        res.msg=Variant.init;
        res.tag=AnyTag;
        tag=AnyTag;
    }
}

class SNUnserializer:SBinUnserializer{
    SNMessage msg;
    static SNUnserializer opCall(){
        return new SNUnserializer();
    }
    this(){
        super(toReaderT!(void)(new IOArray(0,0)));
        msg.tag=AnyTag;
    }
    void readStartRoot() {
        assert(msg.tag!=AnyTag);
        auto arr=cast(IOArray)((cast(BinaryReadHandlers!())handlers).reader);
        auto m=msg.msg.get!(ubyte[])();
        arr.assign(m,m.length);
        super.readStartRoot();
    }
    void readEndRoot() {
        super.readEndRoot();
        assert(msg.tag!=AnyTag);
    }
    void close(){
        msg.msg=Variant.init;
        msg.tag=AnyTag;
        auto arr=cast(IOArray)((cast(BinaryReadHandlers!())handlers).reader);
        auto tmp=arr.assign;
        arr.assign(null,0);
        delete tmp; // avoid?
    }
}

/// channel within a process
/// this channel could allow reading messages out of order, but to have the same
/// behaviour as other channels it does not.
/// When created it sends to itself, but one can easily build interconnected channels by setting
/// their recevingChannel attribute
class SNChannel:Channel,BasicObjectI{
    TaskI _sendTask;
    TaskI _recvTask;
    Random rand;

    struct HandlerAction{
        int tag;
        ChannelHandler handler;
        void delegate() action;
        static HandlerAction opCall(int tag,void delegate() action){
            HandlerAction res;
            res.tag=tag;
            res.action=action;
            return res;
        }
        static HandlerAction opCall(int tag,ChannelHandler handler){
            HandlerAction res;
            res.tag=tag;
            res.handler=handler;
            return res;
        }
        void handle(Channel c,int tagN){
            assert(tagN==tag || tag==AnyTag);
            if (action!is null){
                action();
            }
            if (handler!is null){
                handler(c,tagN);
            }
        }
    }
    Deque!(SNMessage) data;
    Deque!(HandlerAction) localHandlers;
    ChannelHandler[int] handlers;
    ChannelHandler gHandler;
    SNChannel recevingChannel;
    ChannelHandler delegate(int tag) checkGHandlers;
    
    this(TaskI sendTask=null,TaskI recvTask=null){
        _sendTask=sendTask;
        if (_sendTask is null){
            _sendTask=new SequentialTask("SNChannelSendSeqTask",defaultTask);
        }
        _recvTask=recvTask;
        if (_recvTask is null){
            _recvTask=new SequentialTask("SNChannelRecvSeqTask",defaultTask);
        }
        data=new Deque!(SNMessage)(1);
        recevingChannel=this;
        rand=new Random();
    }
    TaskI sendTask(){
        return _sendTask;
    }
    TaskI recvTask(){
        return _recvTask;
    }
    
    Serializer sendTag(int tag=0,ubyte[] buf=null){
        auto _serializer=new SNSerializer();
        _serializer.tag=tag;
        _serializer.target=recevingChannel;
        return _serializer;
    }
    template sendT(T){
        void send(T v,int tag=0){
            recevingChannel.data.append(SNMessage(tag,Variant(v)));
            recevingChannel.notify();
        }
    }
    // ugly but needed at the moment...
    mixin sendT!(int[])    s1;
    mixin sendT!(double[]) s2;
    mixin sendT!(ubyte[])  s3;
    alias s1.send send;
    alias s2.send send;
    alias s3.send send;

    void handleMsg(){
        while(data.length>0){
            ChannelHandler h=null;
            if (localHandlers.length>0 && localHandlers[0].tag==AnyTag || localHandlers[0].tag==data[0].tag){
                h=&(localHandlers.popFront().handle);
            } else if(auto k=(data[0].tag in handlers)){
                h=(*k);
            } else if (gHandler !is null){
                h=gHandler;
            } else if (checkGHandlers!is null){
                h=checkGHandlers(data[0].tag);
            }
            if (h) {
                h(this,data[0].tag);
                if (rand.uniform!(bool)()) break;
            } else {
                break;
            }
        }
    }
    Unserializer recvTag(ref int tag,ubyte[] buf=null){
        bool immediate=true;
        foreach (ha;localHandlers){
            if (ha.tag==tag || ha.tag==AnyTag){
                immediate=false;
                break;
            }
        }
        if (immediate && data.length && (tag==AnyTag || data[0].tag==tag)){
            auto msg=data.popFront();
            auto unserializer=SNUnserializer();
            unserializer.msg=msg;
            tag=msg.tag;
            return unserializer;
        }
        auto tAtt=taskAtt.val;
        if (tAtt !is null && tAtt.mightYield){
            SNMessage msg;
            bool didSetM=false;
            tAtt.delay({
                synchronized(this){
                    if (immediate && data.length && (tag==AnyTag || data[0].tag==tag)){
                        msg=data.popFront();
                        didSetM=true;
                        tAtt.resubmitDelayed(tAtt.delayLevel-1);
                    } else {
                        localHandlers.append(HandlerAction(tag,resubmitter(tAtt,tAtt.delayLevel-1)));
                    }
                }
            });
            if (!didSetM){
                msg=data.popFront();
            }
            assert(msg.tag==tag||tag==AnyTag,"unexpected tag in recv");
            auto unserializer=SNUnserializer();
            unserializer.msg=msg;
            tag=msg.tag;
            return unserializer;
        } else {
            throw new Exception("delayed recv works only in Yieldable tasks",__FILE__,__LINE__);
        }
    }
    /// might be called from any task
    void notify(){
        Task("notifyCheck",&handleMsg).autorelease.submit(recvTask);
    }
    template recvT(T){
        int recv(ref T v, int tag=0){
            bool immediate=true;
            foreach (ha;localHandlers){
                if (ha.tag==tag || ha.tag==AnyTag){
                    immediate=false;
                    break;
                }
            }
            if (immediate && data.length && (tag==AnyTag || data[0].tag==tag)){
                auto msg=data.popFront();
                v=msg.msg.get!(T)();
                return msg.tag;
            }
            auto tAtt=taskAtt.val;
            if (tAtt !is null && tAtt.mightYield){
                SNMessage msg;
                bool didSetM=false;
                tAtt.delay(delegate void(){
                    synchronized(this){
                        if (immediate && data.length && (tag==AnyTag || data[0].tag==tag)){
                            msg=data.popFront();
                            didSetM=true;
                            tAtt.resubmitDelayed(tAtt.delayLevel-1);
                        } else {
                            localHandlers.append(HandlerAction(tag,resubmitter(tAtt,tAtt.delayLevel-1)));
                        }
                    }
                });
                if (!didSetM){
                    msg=data.popFront();
                }
                assert(msg.tag==tag||tag==AnyTag,"unexpected tag in recv");
                v=msg.msg.get!(T)();
                return msg.tag;
            } else {
                throw new Exception("delayed recv works only in Yieldable tasks",__FILE__,__LINE__);
            }
        }
    }
    // ugly but needed at the moment...
    mixin recvT!(int[])    r1;
    mixin recvT!(double[]) r2;
    mixin recvT!(ubyte[])  r3;
    alias r1.recv recv;
    alias r2.recv recv;
    alias r3.recv recv;
    
    void sendStr(char[] s, int tag=0){
        sendT!(char[]).send(s,tag);
    }
    int recvStr(ref char[] s,int tag=0){
        return recvT!(char[]).recv(s,tag);
    }
    void close(){
        data=null;
    }
    void registerHandler(ChannelHandler handler,int tag){
        if (tag==AnyTag){
            gHandler=handler;
        }
        handlers[tag]=handler;
        notify();
    }
    
    template sendrecvT(T){
        int sendrecv(T sendV,ref T recvV,Channel recvChannel,int sendTag=0,int recvTag=0){
            if (recvChannel is this && sendTag==recvTag && data.length==0){
                recvV=sendV;
                return recvTag;
            } else {
                recvChannel.send(sendV,sendTag);
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

    void desc(void delegate(char[]) s){
        s("{<SNChannel@"); writeOut(s,cast(void*)this); s(">\n");
        s("  queue:"); writeOut(s,data); s(",\n");
        s("  handlers:{");
        foreach(k,v;handlers){
            s("    "); writeOut(s,k); s(":"); writeOut(s,cast(void*)v.funcptr);
            s(" "); writeOut(s,cast(void*)v.ptr); s(",\n");
        }
        s("  },\n");
        s("  permanent:{");
        foreach(k,v;handlers){
            s("    "); writeOut(s,k); s(":"); writeOut(s,cast(void*)v.funcptr); s(",\n");
        }
        s("  },\n");
        
        s("  gHandler"); writeOut(s,cast(void*)gHandler.funcptr);
        s(" "); writeOut(s,cast(void*)gHandler.ptr); s(",\n");
        s("  recevingChannel:"); writeOut(s,cast(void*)recevingChannel); s("\n");
        s("}");
    }
}

class SNCart(int dimG):Cart!(dimG){
    int[dimG] _dims;
    int[dimG] _zeros;
    int[dimG] _periodic;
    LinearComm _baseComm;
    this(LinearComm baseComm,int[] dims,int[] periodic){
        _dims[]=1;
        _zeros[]=0;
        _periodic[]=1;
        _baseComm=baseComm;
    }
    int[] dims(){
        return _dims;
    }
    int[] periodic(){
        return _periodic;
    }
    int[] myPos(){
        return _zeros;
    }
    Channel opIndex(int[dimG] pos){
        return _baseComm[pos2rank(pos)];
    }
    LinearComm baseComm(){
        return _baseComm;
    }
    int pos2rank(int[dimG] pos){
        int res=0;
        int dd=1;
        foreach(i,p;pos[1..$]){
            assert(p<_dims[i],"pos out of bounds");
            res+=p*dd;
            dd*=_dims[i];
        }
        return res;
    }
    int[] rank2pos(int rank,int[dimG] pos){
        if (rank==0){
            pos[]=0;
            return pos;
        }
        int dd=1;
        foreach(i,p;_dims){
            assert(p>0,"out of bound rank for 0 sized cart");
            pos[i]=rank%p;
            rank/=p;
        }
        assert(rank==0,"out of bound rank");
        return pos;
    }
    void shift(int direction, int disp, out int rank_source, out int rank_dest){
        assert(0<=direction && direction<dimG,"direction out of bounds");
        int[dimG] p2;
        p2[]=myPos;
        p2[direction]=(p2[direction]+disp)%_dims[direction];
        if (p2[direction]<0)
            p2[direction]+=_dims[direction];
        rank_dest=pos2rank(p2);
        p2[direction]=(p2[direction]-2*disp)%_dims[direction];
        if (p2[direction]<0)
            p2[direction]+=_dims[direction];
        rank_source=pos2rank(p2);
    }
    
}

/// a linear communicator for a single process
/// supports only 1 channel, could be extdended to multi channel, but I don't need it at the moment
class SNLinearComm:LinearComm,BasicObjectI{
    SNChannel[] channels;
    UniqueNumber!(int) counter;
    char[] _name;
    int _myRank;
    
    this(char[] name=null){
        this([new SNChannel()],name);
    }
    this(SNChannel[] channels,char[]name){
        this.channels=channels;
        this._name=name;
        this._myRank=0;
        assert(channels.length==1,"only 1 channel supported at the moment");
        counter=UniqueNumber!(int)(10);
    }
    char[] name(){
        return _name;
    }
    void name(char[] n){
        _name=n;
    }
    int myRank(){
        return _myRank;
    }
    int dim(){
        return channels.length;
    }
    Channel opIndex(int rank){
        return channels[rank];
    }
    LinearComm split(int color,int newRank){
        assert(newRank==0,"only 1 process thing available");
        return this;
    }
    Cart!(2) mkCart(char[] name,int[2] dims,int[2] periodic,bool reorder){
        assert(dims==[1,1],"only 1 process thing available");
        return new SNCart!(2)(new SNLinearComm(channels,name),dims,periodic);
    }
    Cart!(3) mkCart(char[] name,int[3] dims,int[3] periodic,bool reorder){
        assert(dims==[1,1,1],"only 1 process thing available");
        return new SNCart!(3)(new SNLinearComm(channels,name),dims,periodic);
    }
    Cart!(4) mkCart(char[] name,int[4] dims,int[4] periodic,bool reorder){
        assert(dims==[1,1,1,1],"only 1 process thing available");
        return new SNCart!(4)(new SNLinearComm(channels,name),dims,periodic);
    }
    int nextTag(){
        return counter.next();
    }
    template collOp1(T){
        void bcast(ref T val,int root,int tag=0){
            assert(root==0);
        }
        void reduce(T valOut, ref T valIn, int root,MPI_Op op,int tag=0){
            assert(root==0);
            static if (is(T U:U[])){
                valIn[]=valOut;
            } else {
                valIn=valOut;
            }
        }
        void allReduce(T valOut, ref T valIn,MPI_Op op,int tag=0){
            static if (is(T U:U[])){
                valIn[]=valOut;
            } else {
                valIn=valOut;
            }
        }
    }
    template collOp2(T){
        void gather(T[] dataOut,T[] dataIn,int root,int tag=0){
            assert(0<=root && root<dim,"invalid root");
            dataIn[0..dataOut.length]=dataOut;
        }
        void gather(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int root,int tag=0){
            assert(inCounts.length==dim,"invalid inCounts length");
            assert(inStarts.length==dim,"invalid inStarts length");
            assert(0<=root && root<dim,"invalid root");
            dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
        }
        void allGather(T[] dataOut,T[] dataIn,int tag=0){
            dataIn[0..dataOut.length]=dataOut;
        }
        void allGather(T[] dataOut,T[] dataIn,int[] inStarts,int[] inCounts,int tag=0){
            assert(inCounts.length==dim,"invalid inCounts length");
            assert(inStarts.length==dim,"invalid inStarts length");
            dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
        }

        void scatter(T[] dataOut,T[] dataIn,int root,int tag=0){
            assert(root==0);
            assert(dataOut.length%dim==0);
            dataIn[]=dataOut;
        }
        void scatter(T[] dataOut,int[] outCounts, int[] outStarts, T[] dataIn,int root,int tag=0){
            assert(outCounts.length==dim,"invalid outCounts length");
            assert(outStarts.length==dim,"invalid outStarts length");
            assert(0<=root && root<dim,"invalid root");
            dataIn[]=dataOut[outStarts[0]..outStarts[0]+outCounts[0]];
        }
    
        void reduceScatter(T[]outData,T[]inData,MPI_Op op){
            assert(outData.length==inData.length*dim,"invalid lengths");
            inData[0..outData.length]=outData;
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
            assert(inCounts[0]==outData.length && inCounts[0]==inData.length,"incorrect lengths");
            inData[0..outData.length]=outData;
        }
    
        void alltoall(T[] dataOut,T[] dataIn,int tag=0){
            assert(dataOut.length%dim==0,"invalid dataOut length");
            assert(dataIn.length%dim==0,"invalid dataIn length");
            dataIn[0..dataOut.length]=dataIn;
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
            dataIn[inStarts[0]..inStarts[0]+dataOut.length]=dataOut;
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
    
    void barrier(){}
    void registerHandler(ChannelHandler handler,int tag){
        (cast(SNChannel)(this[0])).registerHandler(handler,tag);
    }
    
    void desc(void delegate(char[]) s){
        s("{<SNLinearComm> name:"); s(name); s("}");
    }
}

