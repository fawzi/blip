/// efficiently grow an array/chunk of memory
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
module blip.util.Grow;
const PAGESIZE=512;
private const smallSizes=[4,8,16,32,48,64,96,128,192,256,384,512,768,1024];

/**
* returns the amount to allocate to keep some extra space
* for large allocations the extra allocated space decreases, but is still enough
* so that the number of reallocations when linearly growing stays logaritmic
* for small sizes might not be a multiple of elSize
* Params:
* newlength = the number of elements to allocate
* elSize = size of one element
*/
size_t growSize(size_t newlength,size_t elSize=1){
    size_t newcap = newlength*elSize;
    if (newcap<PAGESIZE){
        for(int i=0;i<smallSizes.length;++i){
            if (smallSizes[i]>newcap){
                return smallSizes[i];
            }
        }
    }
    size_t newext = 0;
    const size_t b=0; // flatness factor, how fast the extra space decreases with array size
    const size_t a=100; // allocate at most a% of the requested size as extra space (rounding will change this)
    const size_t minBits=1; // minimum bit size


    static size_t log2plusB(size_t c)
    {
        // could use the bsr bit op
        size_t i=b+1;
        while(c >>= 1){
            ++i;
        }
        return i;
    }
    ulong mult = 100 + a*(minBits+b) / log2plusB(newlength);

    newext = elSize*cast(size_t)(((newcap * mult)+99) / 100);
    newcap = newext > newcap ? newext : newcap; // just to handle overflows
    return newcap;
}
/// return at least newlength, growns so as to waste the least space possible, but still
/// do at most O(log(N)) reallocs even when growing linearly up to N
size_t growLength(size_t newlength,size_t elSize=1){
    return growSize(newlength,elSize)/elSize;
}

/**
* returns the amount to allocate to keep some extra space
* for large allocations the extra allocated space decreases, but is still enough
* so that the number of reallocations when linearly growing stays logaritmic
* for small length it might not be a perfect multiple of elSize
* Params:
* newlength = the number of elements to allocate
* elSize = size of one element
* a = maximum extra space in percent (the allocated space gets rounded up, so might be larger)
* b = flatness factor, how fast the extra space decreases with array size (the larger the more constant)
* minBits = minimum number of bits of newlength
*/
size_t growSize(size_t newlength, size_t elSize,size_t a, size_t b=0,size_t minBits=1){
    size_t newcap = newlength*elSize;
    if (newcap<PAGESIZE){
        for(int i=0;i<smallSizes.length;++i){
            if (smallSizes[i]>newcap){
                return smallSizes[i];
            }
        }
    }
    size_t newext = 0;
    static size_t log2(size_t c)
    {
        // could use the bsr bit op
        size_t i=1;
        while(c >>= 1){
            ++i;
        }
        return i;
    }
    ulong mult = 100 + a*(minBits+b) / (log2(newlength)+b);

    newext = elSize*cast(size_t)(((newcap * mult)+99) / 100);
    newcap = newext > newcap ? newext : newcap; // just to handle overflows
    return newcap;
}

/// return at least newlength, growns so as to waste the least space possible, but still
/// do at most O(log(N)) reallocs even when growing linearly up to N
size_t growLength(size_t newlength, size_t elSize,size_t a, size_t b=0,size_t minBits=1){
    return growSize(newlength,elSize,a,b,minBits)/elSize;
}

