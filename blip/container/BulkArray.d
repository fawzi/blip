/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.container.BulkArray;
import tango.core.Memory;
import blip.BasicModels;
import tango.stdc.string;
import tango.core.Traits;
import blip.serialization.Serialization;
import blip.serialization.SerializationMixins;
import blip.container.AtomicSLink;
import blip.parallel.smp.WorkManager;

/// guard object to deallocate large arrays that contain inner pointers
class Guard{
    ubyte[] data;
    this(void[] data){
        this.data=cast(ubyte[])data;
    }
    this(size_t size,bool scanPtr=false){
        GC.BlkAttr attr;
        if (!scanPtr)
            attr=GC.BlkAttr.NO_SCAN;
        ubyte* mData2=cast(ubyte*)GC.malloc(size);
        if(mData2 is null) throw new Exception("malloc failed");
        data=mData2[0..size];
    }
    ~this(){
        GC.free(data.ptr);
    }
}

/// 1D array mallocated if large, with parallel looping
struct BulkArray(T){
    enum Flags{
        None=0,
        Dummy,
    }
    static size_t defaultOptimalBlockSize=100*1024/T.sizeof;
    static const BulkArrayCallocSize=100*1024;
    T* ptr, ptrEnd;
    Guard guard;
    Flags flags=Flags.Dummy;
    static const BulkArray dummy={null,null,null,Flags.Dummy};
    alias T dtype;
    
    // ---- Serialization ---
    static ClassMetaInfo metaI;
    static this(){
        synchronized{
            if (metaI is null){
                metaI=ClassMetaInfo.createForType!(BulkArray)
                    ("BulkArray!("~T.stringof~")");
                metaI.kind=TypeKind.CustomK;
            }
        }
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        T[] dArray=data;
        auto ac=s.writeArrayStart(null,dArray.length);
        FieldMetaInfo *elMetaInfoP=null;
        version(PseudoFieldMetaInfo){
            FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                getSerializationInfoForType!(T)());
            elMetaInfo.pseudo=true;
            elMetaInfoP=&elMetaInfo;
        }
        foreach (ref d;dArray){
            s.writeArrayEl(ac,{ s.field(elMetaInfoP, d); } );
        }
        s.writeArrayEnd(ac);
    }
    void unserialize(Unserializer s){
        T[] dArray;
        FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
            getSerializationInfoForType!(T)());
        elMetaInfo.pseudo=true;
        auto ac=s.readArrayStart(null);
        dArray.length=cast(size_t)ac.sizeHint();
        size_t pos=0;
        while(s.readArrayEl(ac,
            {
                if (pos==dArray.length){
                    dArray.length=GC.growLength(dArray.length+1,T.sizeof);
                }
                s.field(&elMetaInfo, dArray[pos]);
                ++pos;
            } )) {}
        dArray.length=pos;
        ptr=dArray.ptr;
        ptrEnd=ptr+dArray.length;
        guard=new Guard(dArray);
    }
    
    /// data as array
    T[] data(){
        return ptr[0..(ptrEnd-ptr)];
    }
    void data(T[] newData){
        ptr=newData.ptr;
        ptrEnd=ptr+newData.length;
    }
    static BulkArray opCall(){
        BulkArray b;
        return b;
    }
    static BulkArray opCall(size_t size,bool scanPtr=false){
        BulkArray res;
        if (size*T.sizeof>BulkArrayCallocSize){
            res.guard=new Guard(size*T.sizeof,(typeid(T).flags & 2)!=0);
            res.ptr=cast(T*)res.guard.data.ptr;
            res.ptrEnd=res.ptr+size;
        } else {
            res.data=new T[size];
        }
        res.flags=Flags.None;
        return res;
    }
    static BulkArray opCall(T[] data,Guard guard=null){
        BulkArray res;
        res.data=data;
        res.guard=guard;
        res.flags=Flags.None;
        return res;
    }
    static BulkArray opCall(T*ptr,T*ptrEnd,Guard guard=null){
        BulkArray res;
        res.ptr=ptr;
        res.ptrEnd=ptrEnd;
        assert(ptrEnd>=ptr,"invalid pointers");
        res.guard=guard;
        res.flags=Flags.None;
        return res;
    }
    /// returns the adress of element i
    T* ptrI(size_t i){
        assert(ptr+i<ptrEnd,"index out of bounds");
        return ptr+i;
    }
    /// returns element i
    DynamicArrayType!(T) opIndex(size_t i){
        assert(ptr+i<ptrEnd,"index out of bounds");
        return ptr[i];
    }
    /// assign element i
    void opIndexAssign(T val,size_t i){
        assert(ptr+i<ptrEnd,"index out of bounds");
        *(ptr+i)=val;
    }
    /// returns a slice of the array
    BulkArray opIndex(size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=length,"slicing index out of bounds");
        return BulkArray(data[i..j],guard);
    }
    /// sets a slice of the array
    void opIndexAssign(T val,size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=length,"slicing index out of bounds");
        BulkArray(data[i..j],guard)[]=val;
    }
    /// gets a slice of the array as normal array (this will get invalid when dis array is collected)
    T[] getSlice(size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=length,"slicing index out of bounds");
        return data[i..j];
    }
    void opIndexAssign(BulkArray val,size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=length,"slicing index out of bounds");
        BulkArray(data[i..j],guard)[]=val;
    }
    /// copies an bulk array
    void opSliceAssign(BulkArray b){
        if (b.length!=length) throw new Exception("different length",__FILE__,__LINE__);
        memcpy(data.ptr,b.data.ptr,length*T.sizeof);
    }
    void opSliceAssign(T val){
        foreach(ref v;pLoop())
            v=val;
    }
    /// length of the array
    size_t length(){
        return ptrEnd-ptr;
    }
    /// shallow copy of the array
    BulkArray dup(){
        BulkArray n=BulkArray(length);
        memcpy(n.data.ptr,data.ptr,length*T.sizeof);
        return n;
    }
    /// deep copy of the array
    BulkArray deepdup(){
        BulkArray n=BulkArray(length);
        static if (is(typeof(T.init.deepdup))){
            baBinaryOpStr!("*bPtr0=cast(typeof(*bPtr0))aPtr0.deepdup;",T,T)(*this,n);
        } else static if (is(typeof(T.init.dup()))) {
            baBinaryOpStr!("*bPtr0=cast(typeof(*bPtr0))aPtr0.dup;",T,T)(*this,n);
        } else {
            memcpy(n.data.ptr,data.ptr,length*T.sizeof);
        }
        return n;
    }
    // iterator/sequential loop done directly on BulkArray
    bool next(ref T* el){
        if (ptr==ptrEnd) {
            el=null;
            return false;
        }
        el=++ptr;
        return true;
    }
    int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
        for (T*aPtr=ptr;aPtr!=ptrEnd;++aPtr){
            int ret=loopBody(*aPtr);
            if (ret) return ret;
        }
    }
    int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
        T*aPtr=ptr;
        for (size_t i=ptrEnd-aPtr;i!=0;--i,++aPtr){
            int ret=loopBody(i,*aPtr);
            if (ret) return ret;
        }
    }
    /// parallel foreach loop structure
    struct PLoop{
        int res;
        T* start;
        T* end;
        size_t index;
        Slice1 *freeList1;
        Slice2 *freeList2;
        size_t optimalBlockSize;
        struct Slice1{
            PLoop *context;
            T* start;
            T* end;
            int delegate(ref DynamicArrayType!(T) v) loopBody;
            Slice1 *next;
            void exec(){
                for (T*tPtr=start;tPtr!=end;++tPtr){
                    auto res=loopBody(*tPtr);
                    if (res){
                        context.res=res;
                        return;
                    }
                }
            }
            void giveBack(){
                insertAt(context.freeList1,this);
            }
            void exec2(){
                exec();
                giveBack();
            }
        }
        struct Slice2{
            PLoop *context;
            T* start;
            T* end;
            int delegate(ref size_t index,ref DynamicArrayType!(T) v) loopBody;
            size_t index;
            Slice2 *next;
            void exec(){
                for (T*tPtr=start;tPtr!=end;++tPtr){
                    auto res=loopBody(index,*tPtr);
                    if (res){
                        context.res=res;
                        return;
                    }
                    ++index;
                }
            }
            void giveBack(){
                insertAt(context.freeList2,this);
            }
            void exec2(){
                exec();
                giveBack();
            }
        }
        static PLoop opCall(BulkArray array,size_t optimalBlockSize){
            PLoop it;
            assert(! BulkArrayIsDummy(array), "array cannot be null");
            it.start=array.ptr;
            it.end=array.ptrEnd;
            it.index=0;
            it.optimalBlockSize=optimalBlockSize;
            return it;
        }
        int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
            if (end-start>optimalBlockSize*2){
                Task("BulkArrayPLoop0",
                    delegate void(){
                        while(start-end>optimalBlockSize*3/2 && res==0){
                            auto newChunk=popFrom(freeList1);
                            if (newChunk is null){
                                newChunk=new Slice1;
                                newChunk.loopBody=loopBody;
                                newChunk.context=this;
                            }
                            newChunk.start=start;
                            start+=optimalBlockSize;
                            newChunk.end=start;
                            index+=optimalBlockSize;
                            Task("BulkArrayPLoop0sub",&newChunk.exec2).autorelease.submitYield();
                        }
                        if (res==0){
                            for (T*aPtr=start;aPtr!=end;++aPtr){
                                int ret=loopBody(*aPtr);
                                if (ret) {
                                    res=ret;
                                    break; // needs to keep the context valid while sub runs might use it...
                                }
                            }
                        }
                    },TaskFlags.TaskSet).executeNow();
                return res;
            } else {
                for (T*aPtr=start;aPtr!=end;++aPtr){
                    int ret=loopBody(*aPtr);
                    if (ret) return ret;
                }
            }
            return 0;
        }
        int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
            if (end-start>optimalBlockSize*2){
                Task("BulkArrayPLoop1",
                    delegate void(){
                        while(start-end>optimalBlockSize*3/2 && res==0){
                            auto newChunk=popFrom(freeList2);
                            if (newChunk is null){
                                newChunk=new Slice2;
                                newChunk.loopBody=loopBody;
                                newChunk.context=this;
                            }
                            newChunk.start=start;
                            start+=optimalBlockSize;
                            newChunk.end=start;
                            newChunk.index=index;
                            index+=optimalBlockSize;
                            Task("BulkArrayPLoop1sub",&newChunk.exec2).autorelease.submitYield();
                        }
                        if (res==0){
                            for (T*aPtr=start;aPtr!=end;++aPtr){
                                int ret=loopBody(index,*aPtr);
                                if (ret) {
                                    res=ret;
                                    break; // needs to keep the context valid while sub runs might use it...
                                }
                                ++index;
                            }
                        }
                    }).executeNow();
                return res;
            } else {
                size_t len=end-start;
                T*aPtr=start;
                for (size_t i=0;i!=len;++i,++aPtr){
                    int ret=loopBody(i,*aPtr);
                    if (ret) return ret;
                }
            }
            return 0;
        }
    }
    /// return what is needed for a sequential foreach loop on the array
    BulkArray sLoop(){
        return *this;
    }
    /// return what is needed for a parallel foreach loop on the array
    PLoop pLoop(size_t optimalBlockSize=defaultOptimalBlockSize){
        return PLoop(*this,optimalBlockSize);
    }
    /// implement an FIterator compliant interface on T*
    final class FIteratorP:FIteratorI!(DynamicArrayType!(T)*){
        BulkArray it;
        bool parallel;
        size_t optimalChunkSize;
        this(BulkArray array){
            it=array;
            parallel=false;
            optimalChunkSize=defaultOptimalBlockSize;
        }
        bool next(ref DynamicArrayType!(T)* el){
            return it.next(el);
        }
        int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
            if (parallel){
                return it.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                return it.sLoop().opApply(loopBody);
            }
        }
        int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
            if (parallel){
                return it.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                return it.sLoop().opApply(loopBody);
            }
        }
        FIteratorP parallelLoop(size_t myOptimalChunkSize){
            optimalChunkSize=myOptimalChunkSize;
            parallel=true;
            return this;
        }
        FIteratorP parallelLoop(){
            parallel=true;
            return this;
        }
    }
}

/// tests if b is a dummy array
static bool BulkArrayIsDummy(T)(BulkArray!(T) b){
    return (b.flags & BulkArray!(T).Flags.Dummy)!=0;
}

void baUnaryOpStr(char[] opStr,T)(BulkArray!(T) a){
    for (aPtr0=a.ptr;aPtr0!=ptrEnd;++aPtr0){
        mixin(opStr);
    }
}

void baBinaryOpStr(char[] opStr,T,U)(BulkArray!(T) a,BulkArray!(U) b){
    assert(a.length==b.length,"binaryOpStr only on equally sized arrays");
    U * bPtr0=b.ptr;
    T* aPtrEnd=a.ptrEnd;
    for (T *aPtr0=a.ptr;aPtr0!=aPtrEnd;++aPtr0,++bPtr0){
        mixin(opStr);
    }
}

