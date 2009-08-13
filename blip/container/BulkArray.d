/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.container.BulkArray;
import tango.core.Memory;

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
    static size_t defaultOptimalBlockSize=100*1024/T.sizeof;
    static const BulkArrayCallocSize=100*1024;
    T* ptr, ptrEnd;
    Guard owner;
    T[] data(){
        return ptr[0..(ptrEnd-ptr)];
    }
    void data(T[] newData){
        ptr=newData.ptr;
        ptrEnd=ptr+newData.length;
    }
    static BulkArray opCall(size_t size,bool scanPtr=false){
        BulkArray res;
        if (size*T.sizeof>BulkArrayCallocSize){
            res.guard=new Guard(size*T.sizeof);
            res.ptr=cast(T*)guard.data.ptr;
            res.ptrEnd=res.ptr+size;
        } else {
            res.data=new T[size];
        }
        return res;
    }
    static BulkArray opCall(T[] data,Guard owner=null){
        BulkArray res;
        res.data=data;
        res.owner=owner;
        return res;
    }
    static BulkArray opCall(T*ptr,T*ptrEnd,Guard owner=null){
        BulkArray res;
        res.ptr=ptr;
        res.ptrEnd=ptrEnd;
        assert(ptrEnd>=ptr,"invalid pointers");
        res.owner=owner;
        return res;
    }
    /// returns the adress of element i
    T* ptrI(size_t i){
        assert(ptr+i<ptrEnd,"index out of bounds");
        return ptr+i;
    }
    /// returns element i
    T opIndex(size_t i){
        assert(ptr+i<ptrEnd,"index out of bounds");
        return ptr+i;
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
        return BulkArray(data[i..j],owner);
    }
    /// length of the array
    size_t length(){
        return ptrEnd-ptr;
    }
    /// shallow copy of the array
    BulkArray dup(){
        BulkArray n=BulkArray(length);
        memcopy(n.data.ptr,data.ptr,length*T.sizeof);
        return n;
    }
    /// deep copy of the array
    BulkArray deepdup(){
        BulkArray n=BulkArray(length);
        static if (T.deepdup){
            baBinaryOpStr("*bPtr0=aPtr0.deepdup",T,T)(this,n);
        } else static if (is(typeof(T.init.dup()))) {
            baBinaryOpStr("bPtr0=aPtr0.dup",T,T)(this,n);
        } else {
            memcopy(n.data.ptr,data.ptr,length*T.sizeof);
        }
        return n;
    }
    // iterator/sequential loop done directly on BulkArray
    T* next(){
        if (ptr==ptrEnd) return null;
        return ++ptr;
    }
    bool atEnd(){
        return ptr==ptrEnd;
    }
    int opApply(int delegate(T* v) loopBody){
        for (T*aPtr=ptr;aPtr!=ptrEnd;++aPtr){
            int ret=loopBody(aPtr0);
            if (ret) return ret;
        }
    }
    int opApply(int delegate(size_t i,T* v) loopBody){
        T*aPtr=ptr;
        for (i=ptrEnd-aPtr;i!=0;--i,++aPtr){
            int ret=loopBody(i,aPtr0);
            if (ret) return ret;
        }
    }
    int opApply(int delegate(ref T v) loopBody){
        for (T*aPtr=ptr;aPtr!=aEnd;++aPtr){
            int ret=loopBody(*aPtr0);
            if (ret) return ret;
        }
    }
    int opApply(int delegate(size_t i,ref T v) loopBody){
        T*aPtr=ptr;
        for (i=aEnd-aPtr;i!=0;--i,++aPtr){
            int ret=loopBody(i,*aPtr0);
            if (ret) return ret;
        }
    }
    /// parallel foreach loop structure
    struct PLoop{
        BulkArray array;
        size_t optimalBlockSize;
        static PLoop opCall(BulkArray array,size_t optimalBlockSize){
            PLoop it;
            assert(array!is null, "array cannot be null");
            it.array=array;
            it.optimalBlockSize=optimalBlockSize;
            return it;
        }
        int opApply(int delegate(T* v) loopBody){
            for (T*aPtr=ptr;aPtr!=aEnd;++aPtr){
                int ret=loopBody(aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
        int opApply(int delegate(size_t i,T* v) loopBody){
            T*aPtr=ptr;
            for (i=aEnd-aPtr;i!=0;--i,++aPtr){
                int ret=loopBody(i,aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
        int opApply(int delegate(ref T v) loopBody){
            for (T*aPtr=ptr;aPtr!=aEnd;++aPtr){
                int ret=loopBody(*aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
        int opApply(int delegate(size_t i,ref T v) loopBody){
            T*aPtr=ptr;
            for (i=aEnd-aPtr;i!=0;--i,++aPtr){
                int ret=loopBody(i,*aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
        int opApply(int delegate(T v) loopBody){
            for (T*aPtr=ptr;aPtr!=aEnd;++aPtr){
                int ret=loopBody(*aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
        int opApply(int delegate(size_t i,T v) loopBody){
            T*aPtr=ptr;
            for (i=aEnd-aPtr;i!=0;--i,++aPtr){
                int ret=loopBody(i,*aPtr0);
                if (ret) return ret;
            }
            return 0;
        }
    }
    /// return what is needed for a sequential foreach loop on the array
    BulkArray sLoop(){
        return this;
    }
    /// return what is needed for a parallel foreach loop on the array
    PLoop pLoop(size_t optimalBlockSize=defaultOptimalBlockSize){
        return PLoop(this);
    }
    /// implement an FIterator compliant interface on T*
    final class FIteratorP:FIteratorI!(T*){
        BulkArray it;
        bool parallel;
        size_t optimalChunkSize;
        this(BulkArray array){
            it=array;
            parallel=false;
            optimalChunkSize=defaultOptimalBlockSize;
        }
        T* next(){
            return it.next();
        }
        bool atEnd(){
            return it.atEnd();
        }
        int opApply(int delegate(T* v) loopBody){
            if (parallel){
                array.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                array.sLoop().opApply(loopBody);
            }
        }
        int opApply(int delegate(size_t i,T* v) loopBody){
            if (parallel){
                array.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                array.sLoop().opApply(loopBody);
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
    /// implement an FIterator compliant interface on T
    final class FIteratorV:FIteratorI!(T){
        Iterator it;
        bool parallel;
        size_t optimalChunkSize;
        this(BulkArray array,T* ptr=null, T*ptrEnd=null){
            it=Iterator(array,ptr,ptrEnd);
            parallel=false;
            optimalChunkSize=defaultOptimalBlockSize;
        }
        T next(){
            return *it.next();
        }
        bool atEnd(){
            return it.atEnd();
        }
        int opApply(int delegate(T v) loopBody){
            if (parallel){
                array.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                array.sLoop().opApply(loopBody);
            }
        }
        int opApply(int delegate(size_t i,T v) loopBody){
            if (parallel){
                array.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                array.sLoop().opApply(loopBody);
            }
        }
        FIteratorV parallelLoop(size_t myOptimalChunkSize){
            optimalChunkSize=myOptimalChunkSize;
            parallel=true;
            return this;
        }
        FIteratorV parallelLoop(){
            parallel=true;
            return this;
        }
    }
    /// returns an iterator
    BulkArray iterator(){
        return this;
    }
    /// return an FIteratorI
    FIteratorP fIterator(){
        return new FIteratorP(this);
    }
}

void baUnaryOpStr(char[] opStr,T)(BulkArray!(T) a){
    T * aEnd=a.ptr+a.length;
    for (aPtr0=a.ptr;aPtr0!=aEnd;++aPtr0){
        mixin(opStr);
    }
}

void baBinaryOpStr(char[] opStr,T,U)(BulkArray!(T) a,BulkArray!(U) b){
    assert(a.length==b.length,"binaryOpStr only on equally sized arrays");
    U * bPtr0=b.ptr;
    T aEnd=a.ptr+a.length;
    for (aPtr0=a.ptr;aPtr0!=aEnd;++aPtr0,++bPtr0){
        mixin(opStr);
    }
}

