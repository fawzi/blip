/// array of bits that behave like D slices + some autmatic allocation
/// this is a full rewrite and has different semantics than tango/phobos BitArray.
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
module blip.container.BitArray;
private import blip.core.BitManip;

/// mixin that loops on a bit array.
/// - opMask: operation on the bits selected by "mask" of ptr[iBlock]. valAtt contains the
///   (not necessarily filtered) elements of the right hand side. ibit0 is the index of the first selected bit
/// - opEl: operation on the element ptr[iBlock], valAtt contains the elements of the right side.
///   ibit0 is the index of the first element of the element
/// - opBit: operation on a single bit (as bool value), ibit is the the index to do the operation on
char[] loopOpMixin(char[]opMask,char[] opEl, char[] opBit){
    char[] res=`
    {
        if (len<bitsPerEl){
            if (start==rhs.start){
                if (len+start>bitsPerEl){
                    {
                        auto ibit0=0;
                        auto iBlock=0;
                        auto mask=all1>>start;
                        auto valAtt=rhs.ptr[0];
                        `~opMask~`
                    }
                    {
                        auto ibit0=bitsPerEl-start;
                        auto iBlock=1;
                        auto mask=(all1<<cast(int)(2*bitsPerEl-(len+start)));
                        auto valAtt=rhs.ptr[1];
                        `~opMask~`
                    }
                } else {
                    auto ibit0=0;
                    auto mask1=all1>>start;
                    auto maskRest=(all1<<cast(int)(bitsPerEl-(len+start)));
                    auto mask=(mask1&maskRest);
                    auto iBlock=0;
                    auto valAtt=rhs.ptr[0];
                    `~opMask~`
                }
            } else {
                for(size_t ibit=0;ibit<len;++ibit){
                    `~opBit~`
                }
            }
       } else {
            if (start==rhs.start){
                auto ibit0=0;
                {
                    auto iBlock=0;
                    auto mask=all1>>start;
                    auto valAtt=rhs.ptr[0];
                    `~opMask~`
                    ibit0+=bitsPerEl-start;
                }
                auto rBlock=1+(len-cast(ptrdiff_t)start)/bitsPerEl;
                for (size_t iBlock=1;iBlock!=rBlock;++iBlock){
                    auto valAtt=rhs.ptr[iBlock];
                    `~opEl~`
                    ibit0+=bitsPerEl;
                }
                {
                    auto rest=cast(int)((start+len)%bitsPerEl);
                    auto mask=(all1<<(bitsPerEl-rest));
                    auto iBlock=rBlock;
                    auto valAtt=rhs.ptr[rBlock];
                    `~opMask~`
                }
            } else {
                size_t bitCp=0;
                size_t iBlockStart=0;
                size_t ibit0=0;
                if (start!=0){
                    bitCp=bitsPerEl-start;
                    for (size_t ibit=0;ibit!=bitCp;++ibit){
                        `~opBit~`
                    }
                    iBlockStart=1;
                    ibit0+=bitCp;
                }
                auto rBlock=(len-bitCp)/bitsPerEl+iBlockStart;
                size_t iRhs=0;
                int posRhs=rhs.start+bitCp;
                if (posRhs>bitsPerEl){
                    iRhs=1;
                    posRhs-=bitsPerEl;
                }
                auto posRest=bitsPerEl-posRhs;
                auto valAtt=(ptr[iRhs]<<posRhs);
                for (size_t iBlock=iBlockStart;iBlock!=rBlock;++iBlock){
                    auto vNew=ptr[++iRhs];
                    valAtt|=(vNew>>posRest);
                    `~opEl~`
                    valAtt=(vNew<<posRhs);
                    ibit0+=bitsPerEl;
                }
                auto cpAll=bitCp+(rBlock-iBlockStart)*bitsPerEl;
                for (size_t ibit=cpAll;ibit<len;++ibit){ // could be optimized...
                    `~opBit~`
                }
            }
        }
    }`;
    return res;
}

/// An array or slice of boolean values, each of which occupy one bit of memory for storage.
/// BitArray is a reference type in the sense that it refers to memory containing the bits
/// but does not "own" it. BitVector in the other hand stores it in place and owns it (and has compile 
/// time size).
/// BitArray occupies 128 bits (on 64-bit computers), so it makes sense for larger bit sequences
/// or if you want to reference arbitrary bit slices within an array.
struct BitArray
{
    alias size_t el_t;
    enum { bitsPerEl=size_t.sizeof*8 }
    static if(el_t.sizeof==4){
        enum {bitsShift=5}
    } else static if (el_t.sizeof==8){
        enum {bitsShift=6}
    } else {
        static assert(0,"not implemented el_t sizeof");
    }
    enum :size_t {bitsShiftMask=((cast(size_t)1)<<bitsShift+1)-1}
    enum :el_t { all0=0, all1=(~all0) }
    // if uint is too small as length one could use an ulong, and store start in some bits of it
    int  start; // should be in 0..bitsPerEl
    uint  len;
    el_t* ptr;

    /// initializes a new array with the given bits
    static BitArray opCall( bool[] bits ){
        BitArray res;
        auto storage=new el_t[]((bits.length+bitsPerEl-1)/bitsPerEl);
        res.ptr=storage.ptr;
        res.len=cast(uint)bits.length;
        foreach( pos, val; bits )
            res[pos] = val;
        return res;
    }
    /// reinterprets the memory given as BitArray, this access bits a little before/after storage
    /// as it works with el_t units
    static BitArray opCall( void[] storage ){
        BitArray res;
        size_t p=cast(size_t)storage.ptr;
        auto rest=p%el_t.alignof;
        if (rest!=0){
            res.start=(el_t.sizeof-rest)*8;
            res.ptr=cast(el_t*)(p+el_t.sizeof-rest);
        } else {
            res.ptr=cast(el_t*)p;
        }
        res.len=cast(uint)storage.length*8;
        return res;
    }
    /// an array of zeros of the given length
    static BitArray zeros(size_t l){
        BitArray res;
        auto storage=new el_t[]((l+bitsPerEl-1)/bitsPerEl);
        // storage[]=all0; // should not be needed
        res.ptr=storage.ptr;
        return res;
    }
    /// an array of ones of the given length
    static BitArray ones(size_t l){
        BitArray res;
        auto storage=new el_t[]((l+bitsPerEl-1)/bitsPerEl);
        storage[]=all1;
        res.ptr=storage.ptr;
        return res;
    }
    /// number of bits
    size_t length(){
        return len;
    }
    /// number of el_t used
    size_t dim(){
        return (start+len + bitsPerEl-1) / bitsPerEl;
    }
    /// copy
    BitArray dup(){
        BitArray res;
        el_t[] buf = ptr[0 .. dim].dup;
        res.len=len;
        res.ptr=buf.ptr;
        res.start=start;
        return res;
    }
    /// sets the bits of this slice
    void opSliceAssign( bool[] bits ){
        assert(length == bits.length);
        foreach( i, b; bits )
        {
            (*this)[i] = b;
        }
    }
    /// sets the bits of this slice
    BitArray opSliceAssign(BitArray rhs){
        assert(rhs.len == len);
        mixin(loopOpMixin(`ptr[iBlock]=(ptr[iBlock]&(~mask))|(valAtt&mask);`,
            `ptr[iBlock]=valAtt;`,`(*this)[ibit]=rhs[ibit];`));
        return *this;
    }
    /// loops on the slice
    int opApply( int delegate(inout bool) dg ){
        // to do: optimize with loopOpMixin
        int result;

        for( size_t i = 0; i < len; ++i )
        {
            bool b = opIndex( i );
            result = dg( b );
            opIndexAssign( b, i );
            if( result )
                break;
        }
        return result;
    }
    /// ditto
    int opApply( int delegate(inout size_t, inout bool) dg ){
        int result;

        for( size_t i = 0; i < len; ++i )
        {
            bool b = opIndex( i );
            result = dg( i, b );
            opIndexAssign( b, i );
            if( result )
                break;
        }
        return result;
    }
    /// compares the contents of two slices
    int opEquals( BitArray rhs ){
        if( this.length != rhs.length )
            return 0; // not equal
        mixin(loopOpMixin(`if ((ptr[iBlock]&mask)!=(valAtt&mask)) return 0;`,
            `if (ptr[iBlock]!=valAtt) return 0;`,`if ((*this)[ibit]!=rhs[ibit]) return 0;`));
        return 1;
    }

    /// Performs a lexicographical comparison of this array to the supplied
    /// array.
    int opCmp( BitArray rhs ){
        mixin(loopOpMixin(`if ((ptr[iBlock]&mask)!=(valAtt&mask)) return (((ptr[iBlock]&mask)<(valAtt&mask))?-1:1);`,
            `if (ptr[iBlock]!=valAtt) return ((ptr[iBlock]<valAtt)?-1:1);`,`if ((*this)[ibit]!=rhs[ibit]) return (((*this)[ibit])?1:-1);`));
        return 0;
    }
    /// bit at index i
    bool opIndex( size_t pos ){
        assert( pos < len );
        auto p=(start+pos);
        auto bIdx=(p>>bitsShift);
        auto r=cast(int)(p&bitsShiftMask);
        return cast(bool)(ptr[bIdx]&((cast(el_t)1)<<r));
    }
    /// sets bit at index i
    void opIndexAssign( bool b, size_t pos ){
        assert( pos < len );
        auto p=(start+pos);
        auto bIdx=(p>>bitsShift);
        auto r=cast(int)(p&bitsShiftMask);
        el_t bitVal=((cast(el_t)1)<<r);
        if (b){
            ptr[bIdx]=(ptr[bIdx]|bitVal);
        } else {
            ptr[bIdx]=(ptr[bIdx]&(~bitVal));
        }
    }
    /// finds the index of the first occurence of 0 in both this and rhs
    /// if no occurence is found length is returned
    size_t findBoth0(BitArray rhs){
        mixin(loopOpMixin(`
            auto val=(ptr[iBlock]|(~mask)|valAtt);
            if (val!=all1) {
                int maskLow=0,maskUp=bitsPerEl;
                while (maskLow<=maskUp){
                    auto m=(maskUp+maskLow)/2;
                    auto bVal=((cast(el_t)1)<<m);
                    if ((mask & (bVal-1))==0){ // m<=lowestBit(mask)
                        maskLow=m+1;
                    } else{
                        maskUp=m-1;
                    }
                }
                // maskUp=lowestBit(mask)
                auto v=~val;
                int bitPosLow=maskUp,bitPosUp=bitsPerEl;
                while (bitPosLow<=bitPosUp){
                    auto m=(bitPosUp+bitPosLow)/2;
                    auto bVal=((cast(el_t)1)<<m);
                    if (((bVal-1)&v)==0){
                        bitPosLow=m+1;
                    } else{
                        bitPosUp=m-1;
                    }
                }
                return bitPosUp-maskUp+ibit0;
            }`,
            `if ((ptr[iBlock]|valAtt)!=all1) {
                auto v= ~(ptr[iBlock]|valAtt);
                int bitPosLow=0,bitPosUp=bitsPerEl;
                while (bitPosLow<=bitPosUp){
                    auto m=(bitPosUp+bitPosLow)/2;
                    auto bVal=((cast(el_t)1)<<m);
                    if (((bVal-1)&v)==0){
                        bitPosLow=m+1;
                    } else{
                        bitPosUp=m-1;
                    }
                }
                return bitPosUp+ibit0;
            }`,`if (!((*this)[ibit]||rhs[ibit])) return ibit;`));
        return len;
    }
}
