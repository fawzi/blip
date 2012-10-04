/// a double ended queue
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
module blip.container.Deque;
import blip.stdc.string:memmove,memcpy;
import blip.BasicModels:CopiableObjectI;
import blip.math.Math;
import blip.io.BasicIO;
import blip.util.Grow:growLength;
import blip.serialization.Serialization;
import blip.Comp;

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
    private void growLen(size_t newSize){
        if (newSize>baseArr.length){
            synchronized(this){
                if (newSize>baseArr.length){
                    auto newArr=new T[](growLength(newSize,T.sizeof,60));
                    auto to1=start+nEl;
                    if (to1>baseArr.length){
                        auto nel1=baseArr.length-start;
                        assert(nel1<=newArr.length && start+nel1<=baseArr.length);
                        memcpy(newArr.ptr,baseArr.ptr+start,nel1*T.sizeof);
                        assert(nel1+(to1-baseArr.length)<=newArr.length && to1-baseArr.length<=baseArr.length);
                        memcpy(newArr.ptr+nel1,baseArr.ptr,(to1-baseArr.length)*T.sizeof);
                    } else {
                        assert(nEl<=newArr.length && start+nEl<=baseArr.length);
                        memcpy(newArr.ptr,baseArr.ptr+start,nEl*T.sizeof);
                    }
                    auto oldArr=baseArr;
                    baseArr=newArr;
                    delete(oldArr); // be less aggressive with memory reclaim?
                    start=0;
                }
            }
        }
    }
    
    /// pushes (inserts) an element at the beginning of the array
    void push(T t){
        synchronized(this){
            if (nEl==baseArr.length){
                growLen(nEl+1);
            }
            ++nEl;
            if (start==0)
                start=baseArr.length-1;
            else
                --start;
            baseArr[start]=t;
        }
    }
    alias push pushFront;
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
    bool popFront(ref T el,scope bool delegate(T) filter){
        debug(SafeDeque){
            synchronized(this){
                size_t i=0;
                bool res=false;
                while (i<nEl){
                    if (filter(opIndex(i))){
                        el=opIndex(i);
                        res=true;
                        break;
                    }
                    ++i;
                }
                ++i;
                while (i<nEl){
                    opIndexAssign(opIndex(i-1),i);
                    ++i;
                }
                if (res) {
                    opIndexAssign(T.init,length);
                    --nEl;
                }
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
                                assert(start+1<=baseArr.length && start+1+i<=baseArr.length);
                                memmove(baseArr.ptr+start+1,baseArr.ptr+start,i*T.sizeof);
                                return retRes();
                            }
                        }
                        for (size_t i=0;i<nEl-to2;++i){
                            if (filter(baseArr[i])){
                                el=baseArr[i];
                                assert(i<=baseArr.length && (i+nEl-to2-i-1)<=baseArr.length && nEl-to2-i-1>=0);
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
                                assert(start+1+i<=baseArr.length);
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
                growLen(nEl+1);
            }
            baseArr[(start+nEl)%baseArr.length]=val;
            ++nEl;
            return nEl-1;
        }
    }
    /// appends an element at the end of the array
    void appendEl(T val){
        synchronized(this){
            if (nEl==baseArr.length){
                growLen(nEl+1);
            }
            baseArr[(start+nEl)%baseArr.length]=val;
            ++nEl;
        }
    }
    /// appends vals at the end of the array
    /// could be improved (realloc just once if needed)
    void appendArr(T[] vals){
        synchronized(this){
            growLen(nEl+vals.length);
            foreach(val;vals){
                baseArr[(start+nEl)%baseArr.length]=val;
                ++nEl;
            }
        }
    }
    alias appendArr append;
    alias appendEl append;
    alias appendEl pushBack;
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
    bool popBack(ref T el,scope bool delegate(T) filter){
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
                if (res){
                    --nEl;
                }
                return res;
            }
        } else {
            synchronized(this){
                if (nEl==0) return false;
                auto lastIdx=(start+nEl-1)%baseArr.length;
                if (filter(baseArr[lastIdx])){
                    el=baseArr[lastIdx];
                    baseArr[lastIdx]=T.init;
                    --nEl;
                    return true;
                }
                size_t i=start+nEl;
                if (i>baseArr.length){
                    size_t ii=i-baseArr.length;
                    while(ii!=0){
                        --ii;
                        if (filter(baseArr[ii])){
                            el=baseArr[ii];
                            assert(ii+1<=baseArr.length && i-baseArr.length<=baseArr.length);
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
                        assert(start+1<=baseArr.length && i+1<=baseArr.length);
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
    int opApplyNoIdx(scope int delegate(ref T) loopBody){
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
    alias opApplyNoIdx opApply;
    /// foreach looping
    int opApplyIdx(scope int delegate(ref size_t i,ref T) loopBody){
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
    alias opApplyIdx opApply;
    
    /// removes all elements that do not match the given predicate
    void filterInPlace(U)(U filter){
        synchronized(this){
            size_t to1=start+nEl;
            size_t writePos=start;
            if (to1>baseArr.length){
                auto to2=baseArr.length;
                for (size_t i=start;i<to2;++i){
                    if (filter(baseArr[i])){
                        baseArr[writePos]=baseArr[i];
                        ++writePos;
                    } else {
                        --nEl;
                    }
                }
                if (writePos==baseArr.length) writePos=0;
                to1-=baseArr.length;
                for (size_t i=0;i<to1;++i){
                    if (filter(baseArr[i])){
                        baseArr[writePos]=baseArr[i];
                        ++writePos;
                        if (writePos==baseArr.length) writePos=0;
                    } else {
                        --nEl;
                    }
                }
                if (writePos>to1){
                    for(size_t i=writePos;i<baseArr.length;++i){
                        baseArr[i]=T.init;
                    }
                    writePos=0;
                }
                for (size_t i=writePos;i<to1;++i){
                    baseArr[i]=T.init;
                }
            } else {
                for (size_t i=start;i<to1;++i){
                    if (filter(baseArr[i])){
                        baseArr[writePos]=baseArr[i];
                        ++writePos;
                    } else {
                        --nEl;
                    }
                }
                for (size_t i=writePos;i<to1;++i){
                    baseArr[i]=T.init;
                }
            }
        }
    }
    
    void clear(){
        synchronized(this){
            baseArr[]=T.init;
            start=0;
            nEl=0;
        }
    }
    
    static if (isCoreType!(T) ||is(typeof(T.init.serialize(Serializer.init)))) {
        static __gshared ClassMetaInfo metaI;
        shared static this(){
            if (metaI is null){
                metaI=ClassMetaInfo.createForType!(typeof(this))("blip.container.Deque("~T.mangleof~")","a threadsafe double ended queue");
                metaI.addFieldOfType!(T[])("array","the items in the deque");
            }
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        void preSerialize(Serializer s){ }
        void postSerialize(Serializer s){ }
        void serialize(Serializer s){
            LazyArray!(T) la=LazyArray!(T)(&this.opApplyNoIdx,cast(ulong)nEl);
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
        void desc(scope void delegate(in cstring) s){
            s("{<Deque!(");
            s(T.stringof);
            s(") nEl=");
            writeOut(s,nEl);
            static if (is(typeof(writeOut(s,baseArr)))){
                s(", baseArr=");
                writeOut(s,baseArr);
            }
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

