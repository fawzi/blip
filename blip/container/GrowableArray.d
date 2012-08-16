/// Objects to collect several pieces into a single array.
/// To create a local object that can grow look at the function lGrowableArray.
/// If the object has to be passed around use growableArray.
/// collectAppender and sinkTogether are useful functions that use lGrowableArray
/// internally
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
module blip.container.GrowableArray;
import blip.util.Grow;
import blip.io.BasicIO: dumper; // needed just for the desc method
import blip.Comp;

enum GASharing{
    Local, /// local, don't free
    GlobalNoFree, /// global, don't free, don't grow
    Global, /// global, free
}

/// a growable(on one end) data storage
/// appending can cause reallocation and deletion of older data storage
/// i.e. one cannot assume that adresses to data element remain valid after one append
///
/// Data can have varius sharing values:
///  * Local: a local buffer on the stack,
///  * GlobalNoFree: either a global buffer, or (more likely) a local buffer that will 
///    remain valid long enough, so that for this array it can be considered global
///  * Global: a buffer on the heap, it can be reallocated an will remain valid.
///
/// When you take the data contained in the array with takeData you can make sure that
/// the data returned is Global, so that a dup is done if it uses a local buffer, and
/// *only* in that case.
///
/// local (stack) storage, do not pass this around (use GrowableArray for that)
///
/// should overload math ops if T supports them?
struct LocalGrowableArray(T){
    T*dataPtr;
    size_t dataLen;
    size_t capacity;
    GASharing sharing;
    /// new appender using a (sharing) buffer buf, that contains len valid data
    /// (buf,0,GASharing.Local) to initialize if with a local buffer, (arr) to initialize it with
    /// a (non local) array of valid data
    void init(T[]buf=null,size_t len=size_t.max,GASharing sharing=GASharing.GlobalNoFree){
        capacity=buf.length;
        dataPtr=buf.ptr;
        if (len>buf.length){
            dataLen=buf.length;
        } else {
            dataLen=len;
        }
        this.sharing=sharing;
    }
    /// guarantees the given capacity
    void guaranteeCapacity(size_t c){
        if (capacity<c){
            if(sharing==GASharing.Global){ // try to grow in place, destroy old data when reallocated
                auto newData=dataPtr[0..capacity];
                newData.length=growLength(c,T.sizeof);
                if (newData.ptr!is dataPtr){
                    // actively destroy old data, it is an error to use it
                    delete (dataPtr);
                }
                dataPtr=newData.ptr;
                capacity=newData.length;
            } else { /// reallocate from scratch
                auto newData=new T[](growLength(c,T.sizeof));
                newData[0..dataLen]=dataPtr[0..dataLen];
                dataPtr=newData.ptr;
                capacity=newData.length;
                sharing=GASharing.Global;
            }
        }
        assert(capacity>=c);
    }
    /// grows the array to the requested size.
    /// if c is less than the current length the array is trimmed.
    void growTo(size_t c){
        guaranteeCapacity(c);
        dataLen=c;
    }
    void desc(void delegate(cstring)sink){
        // this is the only dependency on BasicIO...
        auto s=dumper(sink);
        s("<GrowableArray@")(cast(void*)this.dataPtr)(" len:")(this.dataLen);
        s(" capacity:")(capacity)(" sharing:")(cast(int)sharing)(">")("\n");
    }
    /// appends to the array
    void opCall(V)(V v){
        opCatAssign(v);
    }
    static if(is(T==ubyte)||is(T==byte)){
        void appendVoid(const(void)[]t){
            if (t.length!=0){
                growTo(data.length+t.length);
                dataPtr[(dataLen-t.length)..dataLen]=cast(T[])t;
            }
        }
        //alias appendVoid opCatAssign;
        void opCatAssign(const(void)[]t){ appendVoid(t); }
    }
    void appendEl(const T t){
        guaranteeCapacity(dataLen+1);
        dataPtr[dataLen]=t;
        // with a write barrier here one can guarantee that the data seen is always initialized...
        // whereas the method used in appendVoid allows appends with smaller locking to reserve the space
        // one could acheive both storing two lengths (reservedLen,initializedLen), but the update of
        // initializedLen might get messy
        ++dataLen;
    }
    void appendArr(const(T)[] t){
        if (t.length!=0){
            assert(dataLen<=dataLen+t.length,"wrapping, garbled memory?");
            guaranteeCapacity(dataLen+t.length);
            dataPtr[dataLen..(dataLen+t.length)]=t;
            dataLen+=t.length;
        }
    }
    /// sets the internal buffer (valid only if no data is stored in the array, 
    /// use takeData, clearData, or deallocData to empty it)
    /// similar to the constructor
    void assign(T[] buf=null,size_t len=size_t.max,GASharing sharing=GASharing.GlobalNoFree){
        dataPtr=buf.ptr;
        if (len>buf.length) len=buf.length;
        dataLen=len;
        this.sharing=sharing;
    }
    /// appends an element
    //alias appendEl opCatAssign;
    void opCatAssign(const T t){ appendEl(t); }
    /// appends a slice
    //alias appendArr opCatAssign;
    void opCatAssign(const(T)[] t){ appendArr(t); }
    /// appends what the appender delegate sends
    void opCatAssign(void delegate(void delegate(const T)) appender){
        appender(&this.appendEl);
    }
    /// appends what the appender delegate sends
    void opCatAssign(void delegate(void delegate(const(T)[])) appender){
        appender(&this.appendArr);
    }
    /// slice of the data contained in this object, will be invalided at the next append,...
    T[] data(){
        return dataPtr[0..dataLen];
    }
    /// returns of the data contained in this object, and clears the content of this object.
    /// data is guaranteed to be global if guaranteeGlobal is true (default)
    T[] takeData(bool guaranteeGlobal=true){
        auto res=dataPtr[0..dataLen];
        if(sharing==GASharing.Local && guaranteeGlobal){
            res=res.dup;
        } else {
            dataPtr=null;
            capacity=0;
            sharing=GASharing.Global;
        }
        dataLen=0;
        return res;
    }
    /// returns of the data contained in this object as immutable data, and clears the content of this object.
    /// data is guaranteed to be global if guaranteeGlobal is true (default)
    immutable(T)[] takeIData(bool guaranteeGlobal=true){
	return cast(immutable(T)[])takeData(guaranteeGlobal);
    }
    /// deallocates data
    void deallocData(){
        if (sharing==GASharing.Global){
            delete (dataPtr);
        }
        dataPtr=null;
        capacity=0;
        dataLen=0;
        sharing=GASharing.Global;
    }
    /// clears the stored data, but keeps the underlying storage
    void clearData(){
        capacity=0;
        dataLen=0;
    }
    size_t length(){
        return dataLen;
    }
    /// returns element at index i
    T opIndex(size_t i){
        assert(i<dataLen,"index out of bounds");
        return dataPtr[i];
    }
    /// pointer to element at index i
    T *ptrI(size_t i){
        assert(i<dataLen,"index out of bounds");
        return dataPtr+i;
    }
    /// sets element at index i
    void opIndexAssign(T val,size_t i){
        assert(i<dataLen,"index out of bounds");
        dataPtr[i]=val;
    }
    /// pointer to the beginning of the array
    T* ptr(){
        return dataPtr;
    }
    /// loops on the array
    int opApply(int delegate(ref T)loopBody){
        T* pos=dataPtr;
        T* end=dataPtr+dataLen;
        while(pos!=end){
            if (auto res=loopBody(*pos)){
                return res;
            }
            ++pos;
        }
        return 0;
    }
    /// ditto
    int opApply(int delegate(ref size_t,ref T)loopBody){
        T* pos=dataPtr;
        for (size_t i=0;i<dataLen;++i){
            auto res=loopBody(i,*pos);
            if (res!=0) return res;
            ++pos;
        }
        return 0;
    }
}
/// utility alias, use GrowableArray if you want to pass around GrowableArrays
template GrowableArray(T){
    alias LocalGrowableArray!(T)* GrowableArray;
}
/// utility method to create a new GrowableArray that can be passed around
GrowableArray!(T) growableArray(T)(T[]buf=null,size_t len=size_t.max,GASharing sharing=GASharing.Local){
    auto res=new LocalGrowableArray!(T);
    res.init(buf,len,sharing);
    return res;
}
/// utility method to initialize a LocalGrowableArray
LocalGrowableArray!(T) lGrowableArray(T)(T[]buf=null,size_t len=size_t.max,GASharing sharing=GASharing.Local){
    LocalGrowableArray!(T) res;
    res.init(buf,len,sharing);
    return res;
}

template MutableEl(T){
    static if(is(T U:U[])){
        alias Unqual!(U) MutableEl;
    } else {
        static assert(false,T.stringof~" is not an array");
    }
}
/// collects what is appended by the appender in a single array and returns it
/// it buf is provided the appender tries to use it (but allocates if extra space is needed)
MutableEl!(T)[] collectAppender(T,U=MutableEl!(T))(void delegate(void delegate(T)) appender,U[] buf=null){
    static assert(is(U==MutableEl!(T)));
    MutableEl!(T)[512/T.sizeof] buf2;
    if (buf.length==0) buf=buf2;
    auto arr=lGrowableArray(buf,0,((buf.ptr is buf2.ptr)?GASharing.Local:GASharing.GlobalNoFree));
    arr(appender);
    return arr.takeData();
}

/// collects what is appended by the appender in a single array and returns it
/// it buf is provided the appender tries to use it (but allocates if extra space is needed)
immutable(MutableEl!(T))[] collectIAppender(T,U=MutableEl!(T))(void delegate(void delegate(T)) appender,U[] buf=null){
    static assert(is(U==MutableEl!(T)));
    MutableEl!(T)[512/T.sizeof] buf2;
    if (buf.length==0) buf=buf2;
    auto arr=lGrowableArray(buf,0,((buf.ptr is buf2.ptr)?GASharing.Local:GASharing.GlobalNoFree));
    arr(appender);
    return arr.takeIData();
}

/// collects what is appended by the appender and adds it at once to the given sink
void sinkTogether(U,T,V=MutableEl!(T))(U sink,void delegate(void delegate(T)) appender,V[] buf=null){
    static assert(is(V==MutableEl!(T)));
    MutableEl!(T)[512/T.sizeof] buf2;
    if (buf.length==0) buf=buf2;
    auto arr=lGrowableArray(buf,0,((buf.ptr is buf2.ptr)?GASharing.Local:GASharing.GlobalNoFree));
    arr(appender);
    sink(arr.data());
    arr.deallocData();
}

