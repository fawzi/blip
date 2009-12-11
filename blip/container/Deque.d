/// a double ended queue
module blip.container.Deque;
import tango.stdc.string:memmove;
import blip.BasicModels:CopiableObjectI;
import tango.core.Memory;
import tango.math.Math;
import blip.io.BasicIO;

class Deque(T):CopiableObjectI{
    T[] baseArr;
    size_t start,nEl;
    
    this(size_t capacity=10){
        baseArr.length=capacity;
        start=0;
        nEl=0;
    }
    size_t length(){
        return nEl;
    }
    private void growLen(){
        assert(nEl==baseArr.length,"growLen should be called only when the array is full");
        baseArr.length=GC.growLength(nEl,T.sizeof,60)/T.sizeof;
        size_t to1=min(start,baseArr.length-nEl);
        baseArr[nEl..$]=baseArr[0..to1];
        if (to1<start){
            memmove(baseArr.ptr,baseArr.ptr+to1,start-to1);
        }
        baseArr[start-to1..start]=T.init;
    }
    
    /// pushes (inserts) an element at the beginning of the array
    void push(T t){
        synchronized(this){
            if (nEl==baseArr.length){
                growLen();
            }
            ++nEl;
            if (start==0)
                start=baseArr.length-1;
            else
                --start;
        }
    }
    /// returns the element at the beginning of the array and drops it
    bool popFront(ref T el){
        synchronized(this){
            if (nEl==0) return false;
            T res=baseArr[start];
            baseArr[start]=T.init;
            start=(start+1)%baseArr.length;
            --nEl;
            el=res;
        }
        return true;
    }
    /// returns the element at the beginning of the array and drops it
    T popFront(){
        T res;
        if (popFront(res)) return res;
        assert(0,"popFront on empty Deque");
    }
    /// appends an element at the end of the array
    void append(T val){
        synchronized(this){
            if (nEl==baseArr.length){
                growLen();
            }
            baseArr[(start+nEl)%baseArr.length]=val;
            ++nEl;
        }
    }
    /// returns the last element of the array and drops it
    bool popBack(ref T el){
        synchronized(this){
            if (nEl==0) return false;
            T res=baseArr[(start+nEl-1)%baseArr.length];
            baseArr[(start+nEl-1)%baseArr.length]=T.init;
            --nEl;
            el=res;
        }
        return true;
    }
    /// returns the last element of the array and drops it
    T popBack(){
        T res;
        if (popBack(res)) return res;
        assert(0,"popBack on empty Deque");
    }
    /// index
    T opIndex(size_t i){
        synchronized(this){
            assert(i<nEl,"index out of bounds");
            return baseArr[(start+i)%baseArr.length];
        }
    }
    /// assigns
    void opIndexAssign(T val,size_t i){
        synchronized(this){
            assert(i<nEl,"index out of bounds");
            baseArr[(start+i)%baseArr.length]=val;
        }
    }
    /// foreach looping
    int opApply(int delegate(ref T) loopBody){
        synchronized(this){
            size_t to1=start+nEl;
            if (to1>baseArr.length){
                auto to2=baseArr.length-start;
                for (size_t i=0;i<to2;++i){
                    if (auto res=loopBody(baseArr[start+i])) return res;
                }
                for (size_t i=to2;i<nEl;++i){
                    if (auto res=loopBody(baseArr[i-to1])) return res;
                }
            } else {
                for (size_t i=0;i<nEl;++i){
                    if (auto res=loopBody(baseArr[start+i])) return res;
                }
            }
        }
        return 0;
    }
    /// foreach looping
    int opApply(int delegate(ref size_t i,ref T) loopBody){
        synchronized(this){
            size_t to1=start+nEl;
            if (to1>baseArr.length){
                auto to2=baseArr.length-start;
                for (size_t i=0;i<to2;++i){
                    if (auto res=loopBody(i,baseArr[start+i])) return res;
                }
                for (size_t i=to2;i<nEl;++i){
                    if (auto res=loopBody(i,baseArr[i-to1])) return res;
                }
            } else {
                for (size_t i=0;i<nEl;++i){
                    if (auto res=loopBody(i,baseArr[start+i])) return res;
                }
            }
        }
        return 0;
    }
    
    static if (is(typeof(T.serialize(Serializer.init)))){
        static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(this))("blip.container.Deque");
            metaI.addFieldOfType!(T[])("array","the items in the deque");
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        void preSerialize(Serializer s){ }
        void postSerialize(Serializer s){ }
        void serialize(Serializer s){
            auto la=LazyArray!(T)(cast(int delegate(ref T))&this.opApply,nEl);
            s.field(metaI[0],la);
        }

        void unserialize(Unserializer s){
            T[] arr;
            s.field(metaI[0],arr);
            start=0;
            nEl=arr.length;
            baseArr=arr;
        }
    
        mixin printOut!();
    } else {
        void desc(void delegate(char[]) s){
            s("{<Deque!(");
            s(T.stringof);
            s(") nEl=");
            writeOut(s,nEl);
            s("}");
        }
    }
    
    Deque dup(){
        auto newD=new Deque(nEl);
        auto to1=min(baseArr.length-start,nEl);
        newD.baseArr[0..to1]=baseArr[start..start+to1];
        if (to1<nEl){
            newD.baseArr[to1..nEl]=baseArr[0..nEl-to1];
        }
        newD.nEl=nEl;
        return newD;
    }
    
    Deque deepdup(){
        auto newD=dup();
        static if (is(typeof(T.init.deepdup))){
            foreach(ref el; newD){
                el=el.deepdup;
            }
        } else static if (is(typeof(T.init.dup))){
            foreach(ref el; newD){
                el=el.dup;
            }
        }
        return newD;
    }
    
}

