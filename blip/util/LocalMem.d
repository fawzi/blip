/// modules that tries to use a local buffer to allocate stuff.
/// very basic.
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
module blip.util.LocalMem;

/// structure that tries to use a block of local memory to allocate stuff
struct LocalMem{
    ubyte* localBufStart;
    ubyte* localBufEnd;
    ubyte* localBufPos;
    
    static LocalMem opCall(T)(T[] buf){
        localBufStart=cast(ubyte*)buf.ptr;
        localBufEnd=cast(ubyte*)(buf.ptr+buf.length);
        localBufPos=localBufStart;
    }
    
    /// allocates an array of type T and dimension dim
    T[] allocArr(T)(size_t dim){
        enum { alignment=T.alignof }
        static assert(alignment!=0);
        static if((alignment&(alignment-1))==0){
            auto rest=localBufPos &(alignment-1);
        } else {
            auto rest=localBufPos%alignment;
        }
        if (rest!=0) rest=alignment-rest;
        if (localBufEnd-localBufPos>=dim*T.sizeof+rest){
            localBufPos+=rest;
            T* res=cast(T*)localBufPos;
            localBufPos+=dim*T.sizeof;
            return res[0..dim];
        }
        return new T[](dim);
    }
    /// grows an array to at least minDim and at most maxDim
    T[] growArr(T)(T[] arr,size_t minDim,size_t maxDim=size_t.max){
        if(arr.length>=minDim) return arr;
        size_t idealSize=growLength(minDim,T.sizeof);
        if (idealSize>maxDim) idealSize=maxDim;
        // check if it is the last array in local mem
        if ((cast(ubyte*)(arr.ptr+arr.length))is localBufPos){
            if (localBufEnd-cast(ubyte*)arr.ptr>=minDim*T.sizeof){
                auto bEnd=(cast(ubyte*)arr.ptr)+idealSize*T.sizeof;
                if (bEnd>localBufEnd) idealSize=(localBufEnd-cast(ubyte*)arr.ptr)/T.sizeof;
                localBufPos+=(idealSize-arr.length)*T.sizeof;
                auto res=arr.ptr[0..idealSize];
                // res[arr.length..$]=T.init; // add init?
                return res;
            }
        }
        // should I try to use local mem? will fragment things...
        auto res=new T[](idealSize);
        res[0..arr.length]=arr;
        deallocArr(arr);
    }
    /// deallocates an array that was allocated with this
    void deallocArr(T)(ref T[] arr){
        if (cast(ubyte*)arr.ptr>=localBufEnd || cast(ubyte*)arr.ptr<localBufStart){
            delete arr.ptr;
        }
        arr=null;
    }
}
