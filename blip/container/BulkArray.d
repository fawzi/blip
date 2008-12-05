module blip.container.BulkArray;

enum BulkArrayFlags{
    ShouldFreeData
}

/// 1D array mallocated if large, with parallel looping
class BulkArray(T){
    static size_t defaultOptimalBlockSize=100*1024/T.sizeof;
    const BulkArrayCallocSize=100*1024;
    BulkArray owner;
    T[] data;
    uint flags;
    this(size_t size){
        if (size*T.sizeof>BulkArrayCallocSize){
            aut p=calloc(size,T.sizeof);
            this((cast(T*)p)[0..size],BulkArrayFlags.ShouldFreeData,null);
        } else {
            this(new T[size],0,null);
        }
    }
    this(T[] data,uint flags,BulkArray owner){
        this.data=data;
        this.flags=flags;
        this.owner=owner;
    }
    ~this(){
        if (flags & BulkArrayFlags.ShouldFreeData){
            free(data.ptr);
        }
    }
    /// returns the adress of element i
    T* opIndex(size_t i){
        return &data[i];
    }
    /// returns a slice of the array
    T* opIndex(size_t i,size_t j){
        return new BulkArray(data[i..j],0,baseOwner());
    }
    /// returns the owner of the data
    BulkArray baseOwner(){
        if (flags & BulkArrayFlags.ShouldFreeData){
            assert(owner is null, "should free data and not owner");
            return this;
        } else {
            return owner;
        }
    }
    /// length of the array
    size_t length(){
        return data.length;
    }
    /// shallow copy of the array
    BulkArray dup(){
        BulkArray n=new BulkArray(length);
        memcopy(n.data.ptr,data.ptr,length*T.sizeof);
    }
    /// deep copy of the array
    BulkArray deepdup(){
        BulkArray n=new BulkArray(length);
        static if (T.deepdup){
            baBinaryOpStr("*bPtr0=aPtr0.deepdup",T,T)(this,n);
        } else static if (is(typeof(T.init.dup()))) {
            baBinaryOpStr("bPtr0=aPtr0.dup",T,T)(this,n);
        } else {
            memcopy(n.data.ptr,data.ptr,length*T.sizeof);
        }
    }
    /// implements an iterator
    struct Iterator{
        T *ptr,ptrEnd;
        BulkArray array;
        static Iterator opCall(BulkArray array,T* ptr=null, T*ptrEnd=null){
            Iterator it;
            it.ptr=ptr;
            it.ptrEnd=ptrEnd;
            it.array=array;
            assert(array !is null,"null array in iterator");
            if (ptr is null){
                it.ptr=array.data.ptr;
            }
            if (ptrEnd is null){
                it.ptrEnd=array.data.ptr+array.data.length;
            }
        }
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
    }
    /// sequential foreach loop structure
    struct SLoop{
        BulkArray array;
        static SLoop opCall(BulkArray array){
            SLoop it;
            assert(array!is null, "array cannot be null");
            it.array=array;
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
    SLoop sLoop(){
        return SLoop(this);
    }
    /// return what is needed for a parallel foreach loop on the array
    PLoop pLoop(size_t optimalBlockSize=defaultOptimalBlockSize){
        return PLoop(this);
    }
    /// implement an FIterator compliant interface on T*
    final class FIterator:FIteratorI!(T*){
        Iterator it;
        bool parallel;
        size_t optimalChunkSize;
        this(BulkArray array,T* ptr=null, T*ptrEnd=null){
            it=Iterator(array,ptr,ptrEnd);
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
        FIterator parallelLoop(size_t myOptimalChunkSize){
            optimalChunkSize=myOptimalChunkSize;
            parallel=true;
            return this;
        }
        FIterator parallelLoop(){
            parallel=true;
            return this;
        }
    }
    /// implement an FIterator compliant interface on T
    final class FIterator:FIteratorI!(T){
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
        FIterator parallelLoop(size_t myOptimalChunkSize){
            optimalChunkSize=myOptimalChunkSize;
            parallel=true;
            return this;
        }
        FIterator parallelLoop(){
            parallel=true;
            return this;
        }
    }
    /// returns an iterator
    Iterator iterator(){
        return Iterator(this);
    }
    /// return an FIteratorI
    FIteratorI fIterator(){
        return new FIteratorI(this);
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

