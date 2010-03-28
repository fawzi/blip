/// a double ended queue
module blip.container.Deque;
import blip.t.stdc.string:memmove;
import blip.BasicModels:CopiableObjectI;
import blip.t.math.Math;
import blip.io.BasicIO;
import blip.util.Grow:growLength;

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
        baseArr.length=growLength(nEl,T.sizeof,60);
        size_t to1=min(start,baseArr.length-nEl);
        baseArr[nEl..nEl+to1]=baseArr[0..to1];
        if (to1<start){
            memmove(baseArr.ptr,baseArr.ptr+to1,(start-to1)*T.sizeof);
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
    /// returns the element at the beginning of the array into el and drops it
    /// if the array is empty returns false
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
    /// returns the first element that matches the given filter
    bool popFront(ref T el,bool delegate(T) filter){
        debug(SafeDeque){
            synchronized(this){
                size_t i=0;
                bool res=false;
                while (i<length){
                    if (filter(opIndex(i))){
                        el=opIndex(i);
                        res=true;
                        break;
                    }
                    ++i;
                }
                ++i;
                while (i<length){
                    opIndexAssign(opIndex(i-1),i);
                    ++i;
                }
                if (res) popBack();
                return res;
            }
        } else {
            bool retRes(){
                baseArr[start]=T.init;
                start=(start+1)%baseArr.length;
                --nEl;
                return true;
            }
            synchronized(this){
                if (nEl==0) return false;
                T res=baseArr[start];
                auto pAtt=start;
                if(filter(baseArr[pAtt])){
                    el=baseArr[start];
                    return retRes();
                } else {
                    size_t to1=start+nEl;
                    if (to1>baseArr.length){
                        auto to2=baseArr.length-start;
                        for (size_t i=1;i<to2;++i){
                            if (filter(baseArr[start+i])){
                                el=baseArr[start+i];
                                memmove(baseArr.ptr+start+1,baseArr.ptr+start,i*T.sizeof);
                                return retRes();
                            }
                        }
                        for (size_t i=0;i<nEl-to2;++i){
                            if (filter(baseArr[i])){
                                el=baseArr[i];
                                memmove(baseArr.ptr+i,baseArr.ptr+i+1,(nEl-to2-i-1)*T.sizeof);
                                baseArr[nEl-to2-1]=T.init;
                                --nEl;
                                return true;
                            }
                        }
                    } else {
                        for (size_t i=1;i<nEl;++i){
                            if (filter(baseArr[start+i])){
                                el=baseArr[start+i];
                                memmove(baseArr.ptr+start+1,baseArr.ptr+start,i*T.sizeof);
                                return retRes();
                            }
                        }
                    }
                }
            }
        }
        return false;
    }
    /// returns the element at the beginning of the array and drops it
    T popFront(){
        T res;
        if (popFront(res)) return res;
        assert(0,"popFront on empty Deque");
    }
    /// appends an element at the end of the array and returns the new length
    size_t appendL(T val){
        synchronized(this){
            if (nEl==baseArr.length){
                growLen();
            }
            baseArr[(start+nEl)%baseArr.length]=val;
            ++nEl;
            return nEl-1;
        }
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
            el=baseArr[(start+nEl-1)%baseArr.length];
            baseArr[(start+nEl-1)%baseArr.length]=T.init;
            --nEl;
        }
        return true;
    }
    /// returns the last element that matches the given filter
    bool popBack(ref T el,bool delegate(T) filter){
        version(SafeDeque){
            synchronized(this){
                bool res;
                size_t pos=nEl;
                while (pos!=0){
                    --pos;
                    if (filter(opIndex(pos))){
                        el=opIndex(pos);
                        res=true;
                        break;
                    }
                }
                while (pos!=0){
                    --pos;
                    opIndexAssign(opIndex(pos+1),pos);
                }
                return res;
            }
        } else {
            synchronized(this){
                if (nEl==0) return false;
                if (filter(baseArr[(start+nEl-1)%baseArr.length])){
                    el=baseArr[(start+nEl-1)%baseArr.length];
                    baseArr[(start+nEl-1)%baseArr.length]=T.init;
                    --nEl;
                    return true;
                }
                size_t i=start+nEl;
                if (i>=baseArr.length){
                    size_t ii=i-baseArr.length+1;
                    while(ii!=0){
                        --ii;
                        if (filter(baseArr[ii])){
                            el=baseArr[ii];
                            memmove(baseArr.ptr+ii,baseArr.ptr+ii+1,(i-baseArr.length-ii)*T.sizeof);
                            baseArr[(start+nEl-1)-baseArr.length]=T.init;
                            --nEl;
                            return true;
                        }
                    }
                    i=baseArr.length;
                }
                while(i!=start){
                    --i;
                    if (filter(baseArr[i])){
                        el=baseArr[i];
                        memmove(baseArr.ptr+start+1,baseArr.ptr+start,(i-start)*T.sizeof);
                        baseArr[start]=T.init;
                        --nEl;
                        ++start;
                        return true;
                    }
                }
            }
            return false;
        }
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
                auto to2=baseArr.length;
                for (size_t i=start;i<to2;++i){
                    if (auto res=loopBody(baseArr[i])) return res;
                }
                to1-=baseArr.length;
                for (size_t i=0;i<to1;++i){
                    if (auto res=loopBody(baseArr[i])) return res;
                }
            } else {
                for (size_t i=start;i<to1;++i){
                    if (auto res=loopBody(baseArr[i])) return res;
                }
            }
        }
        return 0;
    }
    /// foreach looping
    int opApply(int delegate(ref size_t i,ref T) loopBody){
        synchronized(this){
            size_t to1=start+nEl;
            size_t ii=0;
            if (to1>baseArr.length){
                auto to2=baseArr.length;
                for (size_t i=start;i<to2;++i){
                    if (auto res=loopBody(ii,baseArr[i])) return res;
                    ++ii;
                }
                to1-=baseArr.length;
                for (size_t i=0;i<to1;++i){
                    if (auto res=loopBody(ii,baseArr[i])) return res;
                    ++ii;
                }
            } else {
                for (size_t i=start;i<to1;++i){
                    if (auto res=loopBody(ii,baseArr[i])) return res;
                    ++ii;
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

