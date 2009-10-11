/*******************************************************************************
    N dimensional dense rectangular arrays
    
    An attempt a creating a reasonably fast and easy to use multidimensional array
    
    - rank must be choosen at compiletime -> smart indexing possible
    - sizes can be choosen at runtime -> no compile time size
      (overhead should be acceptable for all but the smallest arrays)
    - a given array has fixed startIdx, and strides (in D 2.0 these should be invariant)
    - also the rest of the structure should be as "fixed" as possible.
    - at the moment only the underlying array is modified after creation when using
      subviews, but in the future also this might go away.
    - generic efficent looping templates are available.
    - store array not pointer (safer, but might be changed in the future)
    - structure not class (faster, but might be changed)
    Rationale:
    - indexing should be as fast as possible (if one uses multidimensional arrays
      probably indexing is going to be important to him) -> fixed rank, invariant strides
    - close to optimal (performacewise) looping should be easy to perform -> generic looping templates
    - A good compiler should be able to move most of indexing out of a loop -> invariant strides
    - avoid copying as much as possible (lots of operations guaranteed to return a view).
    
    all operation assume that there is *no* overlap between parst that are assigned and those
    that are read (for example assignement of an array to itself has an undefined behaviour)
    
    Possible changes: I might switch to a struct+class to keep a pointer to non gc memory
      (should be a little bit faster)
     
    History:
        Inspired by muarray by William V. Baxter (III) with hints of 
        numpy, and haskell GSL/Matrix Library, but evolved to something of quite different
        I used native strides as Robert Jacques suggested for strided arrays
    
    copyright:      Copyright (c) 2008. Fawzi Mohamed
    license:        Apache 2.0
    version:        Initial release: July 2008
    author:         Fawzi Mohamed
*******************************************************************************/
module blip.narray.BasicTypes;
import tango.core.Memory: GC;
import tango.core.Array: sort;
import tango.stdc.string: memset,memcpy,memcmp;
import blip.TemplateFu;
import tango.core.Traits;
import tango.io.stream.Format: FormatOutput;
import tango.math.Math: abs;
import blip.rtest.RTest;
import blip.BasicModels;
import blip.serialization.Serialization;
import blip.text.Stringify;
import tango.core.sync.Atomic;
//import tango.io.Stdout;

/// flags for fast checking of 
enum ArrayFlags {
    /// C-style contiguous which means that a linear scan of
    /// data with stride 1 is equivalent to scanning with a loop
    /// in which the last index is the fastest varying
    Contiguous   = 0x1,
    /// Fortran-style contiguous means that a lineat scan of
    /// data with stride 1 with a (transpose of Contiguous).
    Fortran      = 0x2,
    /// if the array is "compact" and data=startPtr[0..size]
    /// Contiguous|Fortran implies Compact1
    Compact1      = 0x8,
    /// if the array is "compact" and data.length==size
    /// Contiguous|Fortran|Compact1 implies Compact2
    Compact2      = 0x100,
    /// if the array is non small
    Small        = 0x10,
    /// if the array is large
    Large        = 0x20,
    /// if the array can be only read
    ReadOnly     = 0x40,
    /// if the array has size 0
    Zero         = 0x80,
    /// flags that the user can set (the other are automatically calculated)
    ExtFlags = ReadOnly,
    All = Contiguous | Fortran | Compact1 | Compact2 | Small | Large| ReadOnly| Zero, // useful ??
    None = 0
}

alias ptrdiff_t index_type; // switch back to int later?

/// describes a range
/// upper bound is not part of the range if positive
/// negative numbers are from the end, and (unlike the positive range)
/// the upper bound is inclusive (i.e. Range(-1,-1) is the last element,
/// but Range(0,0) contains no elements)
/// if the increment is 0, the range is unbounded (with increment 1)
struct Range{
    index_type from,to,inc;
    /// a range from 0 to to (not included)
    static Range opCall(index_type to){
        Range res;
        res.from=0;
        res.to=to;
        res.inc=1;
        return res;
    }
    /// a range from start to end
    static Range opCall(index_type start,index_type end){
        Range res;
        res.from=start;
        res.to=end;
        res.inc=1;
        return res;
    }
    /// a range from start to end with steps inc
    static Range opCall(index_type start,index_type end,index_type inc){
        Range res;
        res.from=start;
        res.to=end;
        res.inc=inc;
        return res;
    }
}

/// returns the reduction of the rank done by the arguments in the tuple
/// allow also static arrays?
template reductionFactor(){
    const int reductionFactor=0;
}
/// ditto
template reductionFactor(T,S...){
    static if (is(T==int) || is(T==long)||is(T==uint)||is(T==ulong))
        const int reductionFactor=1+reductionFactor!(S);
    else static if (is(T==Range))
        const int reductionFactor=reductionFactor!(S);
    else{
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactor, this will fail");
    }
}

/// threshold for manual allocation
const int manualAllocThreshold=200*1024;

/// guard object to deallocate large arrays that contain inner pointers
///
/// to use ref counting this has to be long lived memory (i.e. survive until 
/// all finalizers of the current sweep have been run), which is not yet implemented in tango
/// as some finalizer on half filled pages will be run later...
class Guard{
    void *dataPtr;
    size_t dataDim; // just informative, remove?
    size_t refCount; // used to guarantee collection when used with scope objects
    this(void[] data){
        this.dataPtr=cast(void*)data.ptr;
        this.dataDim=data.length;
    }
    this(size_t size,bool scanPtr=false){
        GC.BlkAttr attr;
        if (!scanPtr)
            attr=GC.BlkAttr.NO_SCAN;
        dataPtr=cast(void*)GC.malloc(size,attr);
        if(dataPtr is null && size!=0) throw new Exception("malloc failed");
        dataDim=size;
        refCount=1;
    }
    version(RefCount){
        // warning see note about ref counting
        void retain(){
            assert(refCount>0,"refCount was 0 in retain...");
            atomicAdd(refCount,cast(size_t)1);
        }
        void release(){
            assert(refCount>0,"refCount was 0 in release...");
            if (atomicAdd(refCount,-cast(size_t)1)==cast(size_t)1){
                free();
            }
        }
    }
    ~this(){
        free();
    }
    void free(){
        void *d=atomicSwap(dataPtr,null);
        if (d !is null) {
            GC.free(dataPtr);
        }
    }
}

/// the template class that represent a rank-dimensional dense rectangular array of type T
/// WARNING the fields of the array (bStrides,shape,nElArray,flags,mBase) should not be changed
/// they are public for performance reason (and to have static arrays)
template NArray(V=double,int rank=1){
static if (rank<1)
    alias V NArray;
else {
    final class NArray : CopiableObjectI, Serializable
    {
        // default optimal chunk size for parallel looping
        static index_type defaultOptimalChunkSize=200*1024/V.sizeof;
        /// pointer to the element 0,...0 (not necessarily the start of the slice)
        V* startPtrArray;
        /// strides multiplied by V.sizeof (can be negative)
        index_type[rank] bStrides;
        /// shape of the array (should never be changed)
        index_type[rank] shape;
        /// size of the array
        index_type nElArray;
        /// flags to quickly check properties of the array
        uint flags = Flags.None;
        /// owner of the data if it is manually managed
        Guard mBase = null;
        alias V dtype;
        alias ArrayFlags Flags;
        /// the underlying data slice
        V[] data() {
            if (nElArray==0) return null;
            index_type minExt=0,maxExt=0;
            for (int i=0;i<rank;++i){
                if (bStrides[i]>=0){
                    maxExt+=bStrides[i]*(shape[i]-1);
                } else {
                    minExt+=bStrides[i]*(shape[i]-1);
                }
            }
            return (cast(V*)(cast(size_t)startPtrArray+minExt))[0..((maxExt-minExt)/cast(index_type)V.sizeof+1)];
        }
        /// calulates the base flags (Contiguos,Fortran,Compact1,Compact2,Small,Large)
        static uint calcBaseFlags(index_type[rank] strides, index_type[rank] shape)
        out(flags){
            debug(TestNArray){
                index_type sz=cast(index_type)V.sizeof;
                for (int i=0;i<rank;++i){
                    sz*=shape[i];
                }
                if (flags&Flags.Contiguous){
                    assert(strides[rank-1]==cast(index_type)V.sizeof || sz==0 || shape[rank-1]==1);
                    assert(flags&Flags.Compact1);
                }
                if (flags&Flags.Fortran){
                    assert(strides[0]==cast(index_type)V.sizeof || sz==0 || shape[0]==1);
                    assert(flags&Flags.Compact1);
                }
                if (flags&(Flags.Compact1|Flags.Compact2)){
                    index_type minExt=0,maxExt=0;
                    index_type size=cast(index_type)V.sizeof;
                    for (int i=0;i<rank;++i){
                        if (strides[i]>=0){
                            maxExt+=strides[i]*(shape[i]-1);
                        } else {
                            minExt+=strides[i]*(shape[i]-1);
                        }
                        size*=shape[i];
                    }
                    if (flags&Flags.Compact1) {
                        assert(minExt==0);
                        assert(maxExt==size-cast(index_type)V.sizeof);
                        assert(flags&Flags.Compact2);
                    }
                    if (flags&Flags.Compact2){
                        assert(maxExt-minExt==size-cast(index_type)V.sizeof);
                    }
                }
            }
        }
        body{
            uint flags=Flags.None;
            // check contiguos & fortran
            bool contiguos,fortran;
            index_type bSize=-1;
            static if (rank == 1) {
                contiguos=fortran=(shape[0]==0 || shape[0] == 1 || cast(index_type)V.sizeof == strides[0]);
                bSize=shape[0]*cast(index_type)V.sizeof;
            } else {
                index_type sz=cast(index_type)V.sizeof;
                for (int i=0;i<rank;i++){
                    if (strides[i]!=sz && shape[i]!=1)
                        fortran=false;
                    sz*=shape[i];
                }
                bSize=sz;
                if (bSize==0){
                    contiguos=true;
                    fortran=true;
                } else {
                    contiguos=true;
                    sz=cast(index_type)V.sizeof;
                    for (int i=rank-1;i>=0;i--){
                        if (strides[i]!=sz && shape[i]!=1)
                            contiguos=false;
                        sz*=shape[i];
                    }
                }
            }
            if (contiguos)
                flags|=Flags.Contiguous|Flags.Compact1|Flags.Compact2;
            if (fortran)
                flags|=Flags.Fortran|Flags.Compact1|Flags.Compact2;
            else if (! contiguos) {
                // check compact
                index_type[rank] posStrides;
                index_type minExt=0,maxExt=0;
                for (int i=0;i<rank;++i){
                    if (strides[i]>=0){
                        maxExt+=strides[i]*(shape[i]-1);
                        posStrides[i]=strides[i];
                    } else {
                        minExt+=strides[i]*(shape[i]-1);
                        posStrides[i]=-strides[i];
                    }
                }
                int[rank] sortIdx;
                static if(rank==1){
                    bool compact=(posStrides[0]==1);
                } else {
                    static if(rank==2){
                        if (posStrides[0]<=posStrides[1]){
                            sortIdx[0]=1;
                            sortIdx[1]=0;
                        } else {
                            sortIdx[0]=1;
                            sortIdx[1]=0;
                        }
                    } else {
                        for (int i=0;i<rank;i++)
                            sortIdx[i]=i;
                        sortIdx.sort((int x,int y){return strides[x]<posStrides[y];});
                    }
                    index_type sz2=cast(index_type)V.sizeof;
                    bool compact=true;
                    for (int i=0;i<rank;i++){
                        if (posStrides[sortIdx[i]]!=sz2)
                            compact=false;
                        sz2*=shape[sortIdx[i]];
                    }
                }
                if (bSize==0)
                    compact=true;
                if (compact){
                    if (minExt==0)
                        flags|=Flags.Compact1|Flags.Compact2;
                    else
                        flags|=Flags.Compact2;
                }
            }
            if (bSize==0){
                flags|=Flags.Zero;
            }
            if (bSize< 4*rank*cast(index_type)V.sizeof && bSize<20*cast(index_type)V.sizeof) {
                flags|=Flags.Small;
            }
            if (bSize>30*cast(index_type)V.sizeof || bSize>100*cast(index_type)V.sizeof) {
                flags|=Flags.Large;
            }
            return flags;
        }
        
        /// constructor using an array storage, preferred over the pointer based,
        /// as it does some checks more, still it is quite lowlevel, you are
        /// supposed to create arrays with higher level functions (empty,zeros,ones,...)
        /// flags not in Flags.ExtFlags are ignored
        this(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            V[] data, uint flags, Guard mBase=null)
        in {
            index_type minIndex=startIdx,maxIndex=startIdx,size=1;
            for (int i=0;i<rank;i++){
                assert(shape[i]>=0,"shape has to be positive in NArray construction");
                size*=shape[i];
                if (strides[i]<0){
                    minIndex+=strides[i]*(shape[i]-1);
                } else {
                    maxIndex+=strides[i]*(shape[i]-1);
                }
            }
            assert(size==0|| data.ptr!is null,"null data allowed only for empty arrays"); // allow?
            if (size!=0 && data !is null){
                assert(minIndex>=0,"minimum real internal index negative in NArray construction");
                assert(maxIndex<data.length*cast(index_type)V.sizeof,"data array too small in NArray construction");
            }
        }
        body { this(strides,shape,data.ptr+startIdx,flags,mBase); }
        
        /// this is the designated constructor, it is quite lowlevel and you are
        /// supposed to create arrays with higher level functions (empty,zeros,ones,...)
        /// flags not in Flags.ExtFlags are ignored
        this(index_type[rank] strides, index_type[rank] shape, V* startPtr, uint flags, Guard mBase=null)
        in{
            index_type sz=1;
            for (int i=0;i<rank;++i){
                assert(strides[i]%cast(index_type)V.sizeof==0,"stride is not a multiple of element size"); // allow?
                sz*=shape[i];
            }
        }
        body {
            this.shape[] = shape;
            this.bStrides[] = strides;
            this.startPtrArray=startPtr;
            index_type sz=1;
            for(int i=0;i<rank;++i)
                sz*=shape[i];
            this.nElArray=sz;
            this.flags=calcBaseFlags(strides,shape)|(flags & Flags.ExtFlags);
            this.mBase=mBase;
            version(RefCount){
                if (mBase !is null) mBase.retain;
            }
        }
        
        ~this(){
            version(RefCount){
                if (mBase !is null) {
                    mBase.release;
                    mBase=null;
                }
            }
        }
        
        /// the preferred low level way to construct an object
        /// for high level see empty, zeros and ones for better ways)
        /// this should be used over the constructor because it would ease the transition to a struct
        /// should it be done
        static NArray opCall(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            V[] data, uint flags, Guard mBase=null){
            return new NArray(strides,shape,startIdx,data,flags,mBase);
        }

        /// another way to construct an object (also low level, see empty, zeros and ones for better ways)
        /// this should be used over the constructor because it would ease the transition to a struct
        /// should it be done
        static NArray opCall(index_type[rank] strides, index_type[rank] shape, 
            V*startPtr, uint flags, Guard mBase=null){
            return new NArray(strides,shape,startPtr,flags,mBase);
        }
                    
        /// returns an empty (uninitialized) array of the requested shape
        static NArray empty(index_type[rank] shape,bool fortran=false){
            index_type size=1;
            foreach (sz;shape)
                size*=sz;
            uint flags=ArrayFlags.None;
            V[] mData;
            Guard guard;
            if (size>manualAllocThreshold/cast(index_type)V.sizeof) {
                guard=new Guard(size*V.sizeof,(typeid(V).flags & 2)!=0);
                V* mData2=cast(V*)guard.dataPtr;
                mData=mData2[0..size];
            } else {
                mData=new V[size];
            }
            index_type[rank] strides;
            if (!fortran){
                index_type sz=cast(index_type)V.sizeof;
                foreach_reverse(i, d; shape) {
                    strides[i] = sz;
                    sz *= d;
                }
            } else {
                index_type sz=cast(index_type)V.sizeof;
                foreach(i, d; shape) {
                    strides[i] = sz;
                    sz *= d;
                }
            }
            auto res=NArray(strides,shape,cast(index_type)0,mData,flags,guard);
            version(RefCount) if (guard !is null) guard.release;
            return res;
        }
        /// returns an array initialized to 0 of the requested shape
        static NArray zeros(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            static if(isAtomicType!(V)){
                memset(res.startPtrArray,0,res.nElArray*cast(index_type)V.sizeof);
            } else {
                res.startPtrArray[0..res.nElArray]=cast(V)0;
            }
            return res;
        }
        /// returns an array initialized to 1 of the requested shape
        static NArray ones(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            res.startPtrArray[0..res.nElArray]=cast(V)1;
            return res;
        }
        
        /+ -------------- indexing, slicing subviews ------------- +/
        /// indexing
        /// if array has rank 3: array[1,4,3] -> scalar, array[2] -> 2D array,
        /// array[3,Range(6,7)] -> 2D array, ...
        /// if a sub array is returned (and not a scalar) then it is *always* a subview
        /// indexing never copies data
        NArray!(V,rank-reductionFactor!(S))opIndex(S...)(S idx_tup)
        in {
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if(rank==reductionFactor!(S)){
                foreach (i,v;idx_tup){
                    if (0>v || v>=shape[i]){
                        assert(false,"index "~ctfe_i2a(i)~" out of bounds");
                    }
                }
            } else {
                foreach(i,TT;S){
                    static if(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<shape[i],"index "~ctfe_i2a(i)~" out of bounds");
                    } else static if(is(TT==Range)){
                        {
                            index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                            if (from<0) from+=shape[i];
                            if (to<0) to+=shape[i]+1;
                            if (from<to && step>=0 || from>to && step<0){
                                assert(0<=from && from<shape[i],
                                    "invalid lower range for dimension "~ctfe_i2a(i));
                                if (step==0)
                                    to=shape[i];
                                else if (step>0)
                                    to=from+(to-from+step-1)/step;
                                else
                                    to=from-(to-from+step+1)/step;
                                assert(to>=0 && to<=shape[i],
                                    "invalid upper range for dimension "~ctfe_i2a(i));
                            }
                        }
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndex");
                }
            }
        }
        out(res){
            debug(TestNArray){
                static if (rank!=reductionFactor!(S)){
                    V[] oldData=data;
                    V[] newdata=res.data;
                    assert(oldData.ptr<=newdata.ptr && ((oldData.ptr+oldData.length)>=(newdata.ptr+newdata.length)),
                        "new data slice outside actual data slice");
                }
            }
        }
        body {
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                V *pos=startPtrArray;
                foreach(i,TT;S){
                    static assert(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    pos=cast(V*)(cast(size_t)pos+cast(index_type)idx_tup[i]*bStrides[i]);
                }
                return *pos;
            } else {
                const int rank2=rank-reductionFactor!(S);
                index_type[rank2] newstrides,newshape;
                index_type newStartIdx=cast(index_type)0;
                int idim=0;
                foreach(i,TT;S){
                    static if (is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        newStartIdx+=cast(index_type)idx_tup[i]*bStrides[i];
                    } else static if (is(TT==Range)){
                        {
                            index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                            if (from<0) from+=shape[i];
                            if (to<0) to+=shape[i]+1;
                            index_type n;
                            if (step>0) {
                                n=(to-from+step-1)/step;
                            } else if (step==0) {
                                n=shape[i]-from;
                                step=1;
                            } else{
                                n=(to-from+step+1)/step;
                            }
                            if (n>0) {
                                newshape[idim]=n;
                                newStartIdx+=from*bStrides[i];
                                newstrides[idim]=step*bStrides[i];
                            } else {
                                newshape[idim]=0; // set everything to 0?
                                newstrides[idim]=step*bStrides[i];
                            }
                            idim+=1;
                        }
                    } else static assert(0,"unexpected type in opIndex");
                }
                for (int i=rank2-idim;i>0;--i){
                    newstrides[rank2-i]=bStrides[rank-i];
                    newshape[rank2-i]=shape[rank-i];
                }
                V* newStartPtr=cast(V*)(cast(size_t)startPtrArray+newStartIdx);
                if (size==0) newStartPtr=null;
                NArray!(V,rank2) res=NArray!(V,rank2)(newstrides,newshape,newStartPtr,
                    newFlags,newBase);
                return res;
            }
        }
        
        /// index assignement
        /// if array has rank 3 array[1,2,3]=4.0, array[1]=2Darray, array[1,Range(3,7)]=2Darray
        NArray!(V,rank-reductionFactor!(S)) opIndexAssign(U,S...)(U val,
            S idx_tup)
        in{
            assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
            static assert(is(U==NArray!(V,rank-reductionFactor!(S)))||is(U==V),"invalid value type <"~U.stringof~"> in opIndexAssign ot type "~V.stringof);
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if (rank==reductionFactor!(S)){
                foreach(i,TT;S){
                    static if(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<shape[i],"index "~ctfe_i2a(i)~" out of bounds");                        
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndexAssign");
                } // else check done in opIndex...
            }
        }
        body{
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                V* pos=startPtrArray;
                foreach(i,TT;S){
                    static assert(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    pos=cast(V*)(cast(size_t)pos+cast(index_type)idx_tup[i]*bStrides[i]);
                }
                *pos=val;
            } else {
                auto subArr=opIndex(idx_tup);
                subArr[]=val;
            }
            return val;
        }
                
        /// static array indexing (separted from opIndex as potentially less efficient)
        NArray!(V,rank-cast(int)staticArraySize!(S))arrayIndex(S)(S index){
            static assert(is(S:int[])||is(S:long[])||is(S:uint[])||is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArrayType!(S),"arrayIndex needs *static* arrays as input");
            const char[] loopBody=("auto res=opIndex("~arrayToSeq("index",cast(int)staticArraySize!(S))~");");
            mixin(loopBody);
            return res;
        }

        /// static array indexAssign (separted from opIndexAssign as potentially less efficient)
        NArray!(V,rank-cast(int)staticArraySize!(S))arrayIndexAssign(S,U)(U val,S index){
            static assert(is(S:int[])||is(S:long[])||is(S:uint[])||is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArrayType!(S),"arrayIndex needs *static* arrays as input");
            mixin("NArray!(V,rank-cast(int)staticArraySize!(S)) res=opIndexAssign(val,"~arrayToSeq("index",staticArraySize!(S))~");");
            return res;
        }
        
        /// copies the array, undefined behaviour if there is overlap
        NArray opSliceAssign(S,int rank2)(NArray!(S,rank2) val)
        in { 
            static assert(rank2==rank,"assign operation should have same rank "~ctfe_i2a(rank)~"vs"~ctfe_i2a(rank2));
            assert(shape==val.shape,"assign arrays need to have the same shape");
            assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
        }
        body {
            static if (is(T==S)){
                if (flags & val.flags & (Flags.Fortran | Flags.Contiguous)){
                    memcpy(startPtrArray,val.startPtrArray,nElArray*cast(index_type)T.sizeof);
                }
            }
            binaryOpStr!("*aPtr0=cast("~V.stringof~")*bPtr0;",rank,V,S)(this,val);
            return this;
        }
        
        /// assign a scalar to the whole array with array[]=value;
        NArray opSliceAssign()(V val)
        in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
        body{
            mixin unaryOpStr!("*aPtr0=val;",rank,V);
            unaryOpStr(this);
            return this;
        }
                
        /++
        + this sub iterator trades a little speed for more safety when used step by step.
        + This is safe also to updates of the base array in the sense that each next/get
        + is done using the base array startPtrArray, not a local copy.
        + After an update in the base array a call to value is wrong, but next or get will set it correctly.
        + Dropping this (unlikely to be used) thing would speed up a little some things.
        +/
        static if (rank==1){
            struct SubView{
                NArray baseArray;
                index_type stride; // invariant
                index_type iPos, iDim, iIdx;
                static SubView opCall(NArray a, int axis=0)
                in { assert(axis==0); }
                body {
                    SubView res;
                    res.baseArray=a;
                    res.iPos=0;
                    res.stride=a.bStrides[axis];
                    res.iDim=a.shape[axis];
                    res.iIdx=0;
                    return res;
                }
                bool next(){
                    iPos++;
                    if (iPos<iDim){
                        iIdx+=stride;
                        return false;
                    } else {
                        iPos=iDim;
                        return false;
                    }
                }
                V value()
                in { assert(iPos<iDim); }
                body {
                    return *cast(V*)(cast(size_t)baseArray.startPtrArray+iIdx);
                }
                void value(V val)
                in { assert(iPos<iDim); }
                body {
                    *cast(V*)(cast(size_t)baseArray.startPtrArray+iIdx)=val;
                }
                V get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    iIdx+=(index-iIdx)*stride;
                    iPos=index;
                    return *cast(V*)(cast(size_t)baseArray.startPtrArray+iIdx);
                }
                int opApply( int delegate(ref V) loop_body ) {
                    if (iPos<iDim){
                        V* pos=cast(V*)(cast(size_t)baseArray.startPtrArray+iIdx);
                        for (index_type i=iPos;i!=iDim;++i){
                            if (auto r=loop_body(*pos)) return r;
                            pos=cast(V*)(cast(size_t)pos+stride);
                        }
                    }
                    return 0;
                }
                int opApply( int delegate(ref index_type,ref V) loop_body ) {
                    if (iPos<iDim){
                        V* pos=cast(V*)(cast(size_t)baseArray.startPtrArray+iIdx);
                        for (index_type i=iPos;i!=iDim;i++){
                            if (auto r=loop_body(i,*pos)) return r;
                            pos=cast(V*)(cast(size_t)pos+stride);
                        }
                    }
                    return 0;
                }
            }
        } else {
            struct SubView{
                NArray baseArray;
                NArray!(V,rank-1) view;
                index_type iPos, iDim, stride,idxAtt;
                static SubView opCall(NArray a, int axis=0)
                in { assert(0<=axis && axis<rank); }
                out(res){
                    debug(TestNArray){
                        V[] subData=res.view.data;
                        V[] aData=a.data;
                        assert(subData.ptr>=aData.ptr && (subData.ptr+subData.length)<=(aData.ptr+aData.length),
                            "subview out of range");
                    }
                }
                body {
                    index_type[rank-1] shape,strides;
                    int ii=0;
                    for(int i=0;i<rank;i++){
                        if (i!=axis){
                            shape[ii]=a.shape[i];
                            strides[ii]=a.bStrides[i];
                            ii++;
                        }
                    }
                    SubView res;
                    res.baseArray=a;
                    res.stride=a.bStrides[axis];
                    res.iPos=cast(index_type)0;
                    res.iDim=a.shape[axis];
                    res.idxAtt=cast(index_type)0;
                    res.view=NArray!(V,rank-1)(strides,shape,a.startPtrArray,
                        a.newFlags,a.newBase);
                    return res;
                }
                bool next()
                out(res){
                    debug(TestNArray){
                        V[] subData=view.data;
                        V[] aData=baseArray.data;
                        assert(subData.ptr>=aData.ptr && (subData.ptr+subData.length)<=(aData.ptr+aData.length),
                            "subview out of range");
                    }
                }
                body {
                    iPos++;
                    if (iPos<iDim){
                        idxAtt+=stride;
                        view.startPtrArray=cast(V*)(cast(size_t)baseArray.startPtrArray+idxAtt);
                        return true;
                    } else {
                        iPos=iDim;
                        return false;
                    }
                }
                NArray!(V,rank-1) value(){
                    return view;
                }
                void value(NArray!(V,rank-1) val){
                    view[]=val;
                }
                NArray!(V,rank-1) get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    idxAtt=index*stride;
                    iPos=index;
                    view.startPtrArray=cast(V*)(cast(size_t)baseArray.startPtrArray+idxAtt);
                    return view;
                }
                int opApply( int delegate(ref NArray!(V,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim;i++){
                        if (auto r=loop_body(view)) return r;
                        view.startPtrArray=cast(V*)(cast(size_t)view.startPtrArray+stride);
                    }
                    return 0;
                }
                int opApply( int delegate(ref index_type,ref NArray!(V,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim;i++){
                        if (auto r=loop_body(i,view)) return r;
                        view.startPtrArray=cast(V*)(cast(size_t)view.startPtrArray+stride);
                    }
                    return 0;
                }
                FormatOutput!(char)desc(FormatOutput!(char)s){
                    if (this is null){
                        return s("<SubView *null*>").newline;
                    }
                    s("<SubView!(")(V.stringof)(",")(rank)(")").newline;
                    s("baseArray:");
                    baseArray.desc(s)(",").newline;
                    view.desc(s("view:"))(",").newline;
                    s("idxAtt:")(idxAtt)(",").newline;
                    s("iPos:")(iPos)(", ")("iDim:")(iDim)(", ")("stride :")(stride).newline;
                    s(">").newline;
                    return s;
                }
            }
        }
                
        /++ Iterates over the values of the array according to the current strides. 
         +  Usage is:  for(; !iter.end; iter.next) { ... } or (better and faster)
         +  foreach(v;iter) foreach(i,v;iter)
         +/
        struct FlatIterator{
            V* p;
            NArray baseArray;
            index_type [rank] left;
            index_type [rank] adds;
            static FlatIterator opCall(NArray baseArray){
                FlatIterator res;
                res.baseArray=baseArray;
                for (int i=0;i<rank;++i)
                    res.left[rank-1-i]=baseArray.shape[i]-1;
                res.p=baseArray.startPtrArray;
                foreach (s; baseArray.shape) {
                    if (s==0) {
                        res.left[]=0;
                        res.p=null;
                    }
                }
                res.adds[0]=baseArray.bStrides[rank-1];
                index_type toRm=0;
                for(int i=1;i<rank;i++){
                   toRm+=baseArray.bStrides[rank-i]*(baseArray.shape[rank-i]-1);
                   res.adds[i]=baseArray.bStrides[rank-1-i]-toRm;
                }
                return res;
            }
            /// Advance to the next item.  Return false if there is no next item.
            bool next(){
                if (left[0]!=0){
                    left[0]-=1;
                    p=cast(V*)(cast(size_t)p+adds[0]);
                    return true;
                } else {
                    static if (rank==1){
                        p=null;
                        return false;
                    } else static if (rank==2){
                        if (left[1]!=0){
                            left[0]=baseArray.shape[rank-1]-1;
                            left[1]-=1;
                            p=cast(V*)(cast(size_t)p+adds[1]);
                            return true;
                        } else {
                            p=null;
                            return false;
                        }
                    } else {
                        if (!p) return false; // remove?
                        left[0]=baseArray.shape[rank-1]-1;
                        for (int i=1;i<rank;i++){
                            if (left[i]!=0){
                                left[i]-=1;
                                p=cast(V*)(cast(size_t)p+adds[i]);
                                return true;
                            } else{
                                left[i]=baseArray.shape[rank-1-i]-1;
                            }
                        }
                        p=null;
                        return false;
                    }
                }
            }
            /// Advance to the next item.  Return false if there is no next item.
            bool opAddAssign(int i) {
                assert(i==1, "+=1, or ++ are the only allowed increments");
                return next();
            }
            /// Assign a value to the element the iterator points at using 
            /// The syntax  iter[] = value.
            /// Equivalent to  *iter.ptr = value
            /// This is an error if the iter.end() is true.
            void opSliceAssign(V v) { *p = v; }
            /// Advance to the next item.  Return false if there is no next item.
            bool opPostInc() {  return next(); }
            /// Return true if at the end, false otherwise.
            bool end() { return p is null; }
            /// Return the value at the current location of the iterator
            V value() { return *p; }
            /// Sets the value at the current location of the iterator
            void value(V val) { *p=val; }
            /// Return a pointer to the value at the current location of the iterator
            V* ptr() { return p; }
            /// Return the array over which this iterator is iterating
            NArray array() { return baseArray; }

            int opApply( int delegate(ref V) loop_body ) 
            {
                if (p is null) return 0;
                if (left!=baseArray.shape){
                    for(;!end(); next()) {
                        int ret = loop_body(*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(*baseArrayPtr0);
                    if (ret) return ret;
                    `;
                    mixin(sLoopPtr(rank,["baseArray"],loopBody,"i"));
                }
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                if (p is null) return 0;
                if (left==baseArray.shape) {
                    for(index_type i=0; !end(); next(),i++) {
                        int ret = loop_body(i,*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(iPos,*baseArrayPtr0);
                    if (ret) return ret;
                    ++iPos;
                    `;
                    index_type iPos=0;
                    mixin(sLoopPtr(rank,["baseArray"],loopBody,"i"));
                }
                return 0;
            }
            FormatOutput!(char)desc(FormatOutput!(char)s){
                if (this is null){
                    return s("<FlatIterator *null*>").newline;
                }
                s("<FlatIterator rank:")(rank)(", p:")(p)(",").newline;
                s("left:")(left)(",").newline;
                s("adds:")(adds).newline;
                baseArray.desc(s("baseArray:"))(",").newline;
                s(">").newline;
                return s;
            }
        }
        
        struct SFlatLoop{
            NArray a;
            static SFlatLoop opCall(NArray a){
                SFlatLoop res;
                res.a=a;
                return res;
            }
            int opApply( int delegate(inout V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(*aPtr0);
                if (ret) return ret;
                `;
                mixin(sLoopPtr(rank,["a"],loopBody,"i"));
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(iPos,*aPtr0);
                if (ret) return ret;
                ++iPos;
                `;
                index_type iPos=0;
                mixin(sLoopPtr(rank,["a"],loopBody,"i"));
                return 0;
            }
            static if (rank>1){
                mixin(opApplyIdxAll(rank,"a",true));
            }
        }

        struct PFlatLoop{
            NArray a;
            index_type optimalChunkSize;
            static PFlatLoop opCall(NArray a,index_type optimalChunkSize=defaultOptimalChunkSize){
                PFlatLoop res;
                res.a=a;
                res.optimalChunkSize=optimalChunkSize;
                return res;
            }
            int opApply( int delegate(ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(*aPtr0);
                if (ret) return ret;
                `;
                index_type optimalChunkSize_i=optimalChunkSize;
                mixin(pLoopPtr(rank,["a"],loopBody,"i"));
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(iPos,*aPtr0);
                if (ret) return ret;
                ++iPos;
                `;
                index_type iPos=0;
                index_type optimalChunkSize_i=optimalChunkSize;
                mixin(pLoopPtr(rank,["a"],loopBody,"i"));
                return 0;
            }
            static if (rank>1){
                mixin(opApplyIdxAll(rank,"a",false));
            }
        }
        
        static if(rank==1){
            /// loops on the 0 axis
            int opApply( int delegate(ref V) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
            /// loops on the 0 axis
            int opApply( int delegate(ref index_type,ref V) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
        } else {
            /// loops on the 0 axis
            int opApply( int delegate(ref NArray!(V,rank-1)) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
            /// loops on the 0 axis
            int opApply( int delegate(ref index_type,ref NArray!(V,rank-1)) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
        }

        /// returns a subview along the given axis
        SubView subView(int axis=0){
            return SubView(this,axis);
        }

        /// returns a flat iterator
        FlatIterator flatIter(){
            return FlatIterator(this);
        }
        
        /// returns a proxy for sequential flat foreach
        SFlatLoop sFlat(){
            return SFlatLoop(this);
        }

        /// returns a proxy for parallel flat foreach
        PFlatLoop pFlat(){
            return PFlatLoop(this);
        }

        /// forward iterator compatible class on the adresses (FIteratorI!(V*))
        class FIterator:FIteratorI!(V*){
            FlatIterator it;
            bool parallel;
            index_type optimalChunkSize;
            this(NArray a){
                it=FlatIterator(a);
                parallel=false;
                optimalChunkSize=defaultOptimalChunkSize;
            }
            V *next(){
                it.next();
                return it.p;
            }
            bool atEnd() {
                return it.end();
            }
            int opApply(int delegate(ref V x) loop_body){
                NArray a=it.baseArray;
                const char[] loopBody=`
                int ret=loop_body(*aPtr0);
                if (ret) return ret;
                `;
                index_type iPos=0;
                index_type optimalChunkSize_i=optimalChunkSize;
                if (parallel){
                    mixin(pLoopPtr(rank,["a"],loopBody,"i"));
                } else {
                    mixin(sLoopPtr(rank,["a"],loopBody,"i"));
                }
                return 0;
            }
            int opApply(int delegate(size_t i,ref V x) loop_body){
                NArray a=it.baseArray;
                index_type optimalChunkSize_i=optimalChunkSize;
                size_t iPos=0;
                const char[] loopBody=`
                int ret=loop_body(iPos,*aPtr0);
                if (ret) return ret;
                ++iPos;
                `;
                if (parallel){
                    /// should use the pLoopIdx with one initial fixup
                    size_t ii=0;
                    mixin(sLoopPtr(rank,["a"],loopBody,"i"));
                } else {
                    size_t ii=0;
                    mixin(sLoopPtr(rank,["a"],loopBody,"i"));
                }
                return 0;
            }
            /// might make opApply parallel (if the work amount is larger than
            /// pThreshold. chunks are, if possible, optimalChunkSize)
            /// might modify the current iterator or return a new one
            FIterator parallelLoop(size_t myOptimalChunkSize){
                optimalChunkSize=cast(index_type)myOptimalChunkSize;
                parallel=true;
                return this;
            }
            /// might make opApply parallel.
            /// might modify the current iterator or return a new one
            FIterator parallelLoop(){
                parallel=true;
                return this;
            }
        }
        
        /// forward iterator on adresses compatible interface (FIteratorI!(V*))
        FIterator fiterator(){
            return new FIterator(this);
        }
        
        /+ --------------------------------------------------- +/
        
        /// Return a shallow copy of the array
        /// (but as normally one stores values this is often equivalent to a deep copy)
        /// fortran ordering in the copy can be requested.
        NArray dup(bool fortran)
        {
            NArray res=empty(this.shape,fortran);
            if ( flags & res.flags & (Flags.Fortran | Flags.Contiguous) ) 
            {
                memcpy(res.startPtrArray, startPtrArray, cast(index_type)V.sizeof * nElArray);
            }
            else
            {
                binaryOpStr!("*aPtr0=*bPtr0;",rank,V,V)(res,this);
            }
            return res;
        }
        /// ditto
        NArray dup() { return dup(false); }

        /// Return a deep copy of the array
        /// (but as normally one stores values this is often equivalent to dup)
        /// fortran ordering in the copy can be requested.
        NArray deepdup(bool fortran)
        {
            NArray res=empty(this.shape,fortran);
            static if (is(typeof(V.init.deepdup()))){
                binaryOpStr!("*aPtr0=(*bPtr0).deepdup();",rank,V,V)(res,this);
            } else static if (is(typeof(V.init.dup()))){
                binaryOpStr!("*aPtr0=(*bPtr0).dup();",rank,V,V)(res,this);
            } else{
                if ( flags & res.flags & (Flags.Fortran | Flags.Contiguous) ) 
                {
                    memcpy(res.startPtrArray, startPtrArray, cast(index_type)V.sizeof * nElArray);
                }
                else
                {
                    binaryOpStr!("*aPtr0=*bPtr0;",rank,V,V)(res,this);
                }
            }
            return res;
        }
        /// ditto
        NArray deepdup() { return deepdup(false); }
        
        /// Returns a copy of the given type (if the type is the same return itself)
        NArray!(S,rank)asType(S)(){
            static if(is(S==V)){
                return this;
            } else {
                auto res=NArray!(S,rank).empty(shape);
                binaryOpStr!("*aPtr0=cast("~S.stringof~")*bPtr0;",rank,S,V)(res,this);
                return res;
            }
        }
        

        /+ --------------------- math ops ------------------- +/

        // should the cast be removed from array opXxxAssign, and move out of the static if?
        
        static if (is(typeof(-V.init))) {
            /// Return a negated version of the array
            NArray opNeg() {
                NArray res=empty(shape);
                binaryOpStr!("*bPtr0=-(*aPtr0);",rank,V,V)(this,res);
                return res;
            }
        }

        static if (is(typeof(+V.init))) {
            /// Allowed as long as the underlying type has op pos
            /// But it always makes a full value copy regardless of whether the underlying unary+ 
            /// operator is a no-op.
            NArray opPos() {
                NArray res=empty(shape);
                binaryOpStr!("*bPtr0= +(*aPtr0);",rank,V,V)(this,res);
                return res;
            }
        }

        /// Add this array and another one and return a new array.
        NArray!(typeof(V.init+S.init),rank) opAdd(S,int rank2)(NArray!(S,rank2) o) { 
            static assert(rank2==rank,"opAdd only on equally shaped arrays");
            NArray!(typeof(V.init+S.init),rank) res=NArray!(typeof(V.init+S.init),rank).empty(shape);
            ternaryOpStr!("*cPtr0=(*aPtr0)+(*bPtr0);",rank,V,S,typeof(V.init+S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init+V.init))) {
            /// Add a scalar to this array and return a new array with the result.
            NArray!(typeof(V.init+V.init),rank) opAdd()(V o) { 
                NArray!(typeof(V.init+V.init),rank) res=NArray!(typeof(V.init+V.init),rank).empty(shape);
                mixin binaryOpStr!("*bPtr0 = (*aPtr0) * o;",rank,V,V);
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init+V.init)==V)) {
            /// Add another array onto this one in place.
            NArray opAddAssign(S,int rank2)(NArray!(S,rank2) o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                static assert(rank==rank2,"opAddAssign accepts only identically shaped arrays");
                binaryOpStr!("*aPtr0 += cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// Add a scalar to this array in place.
            NArray opAddAssign()(V o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0+=o;",rank,V);
                unaryOpStr(this);
                return this;
            }            
        }

        /// Subtract this array and another one and return a new array.
        NArray!(typeof(V.init-S.init),rank) opSub(S,int rank2)(NArray!(S,rank2) o) { 
            static assert(rank2==rank,"suptraction only on equally shaped arrays");
            NArray!(typeof(V.init-S.init),rank) res=NArray!(typeof(V.init-S.init),rank).empty(shape);
            ternaryOpStr!("*cPtr0=(*aPtr0)-(*bPtr0);",rank,V,S,typeof(V.init-S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init-V.init))) {
            /// Subtract a scalar from this array and return a new array with the result.
            NArray opSub()(V o) { 
                NArray res=empty(shape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)-o;",rank,V,V);
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init-V.init)==V)) {
            /// Subtract another array from this one in place.
            NArray opSubAssign(S,int rank2)(NArray!(S,rank2) o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                static assert(rank2==rank,"opSubAssign supports only arrays of the same shape");
                binaryOpStr!("*aPtr0 -= cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// Subtract a scalar from this array in place.
            NArray opSubAssign()(V o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0-=o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }

        /// Element-wise multiply this array and another one and return a new array.
        /// For matrix multiply, use the non-member dot(a,b) function.
        NArray!(typeof(V.init*S.init),rank) opMul(S,int rank2)(NArray!(S,rank2) o) { 
            static assert(rank2==rank);
            auto res=NArray!(typeof(V.init*S.init),rank).empty(shape);
            ternaryOpStr!("*cPtr0=(*aPtr0)*(*bPtr0);",rank,V,S,typeof(V.init*S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init*V.init))) {
            /// Multiplies this array by a scalar and returns a new array.
            NArray!(typeof(V.init*V.init),rank) opMul()(V o) { 
                NArray!(typeof(V.init*V.init),rank) res=NArray!(typeof(V.init*V.init),rank).empty(shape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)*o;",rank,V,typeof(V.init*V.init));
                binaryOpStr(this,res);
                return res;
            }
        }
        
        static if (is(typeof(V.init*V.init)==V)) {
            /// Element-wise multiply this array by another in place.
            /// For matrix multiply, use the non-member dot(a,b) function.
            NArray opMulAssign(S,int rank2)(NArray!(S,rank2) o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                static assert(rank2==rank,"opMulAssign supports only arrays of the same shape");
                binaryOpStr!("*aPtr0 *= cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// scales the current array.
            NArray opMulAssign()(V o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0 *= o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }

        /// Element-wise divide this array by another one and return a new array.
        /// To solve linear equations like A * x = b for x, use the nonmember linsolve
        /// function.
        NArray!(typeof(V.init/S.init),rank) opDiv(S,rank2)(NArray!(S,rank2) o) {
            static assert(rank2==rank,"opDiv on equally shaped array");
            NArray!(typeof(V.init/S.init),rank) res=NArray!(typeof(V.init/S.init),rank).empty(shape);
            ternaryOpStr!("*cPtr0=(*aPtr0)/(*bPtr0);",rank,V,S,typeof(V.init/S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init/V.init))) {
            /// divides this array by a scalar and returns a new array with the result.
            NArray!(typeof(V.init/V.init),rank) opDiv()(V o) { 
                NArray!(typeof(V.init/V.init),rank) res=NArray!(typeof(V.init/V.init),rank).empty(shape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)/o;",rank,V,typeof(V.init/V.init));
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init/V.init)==V)) {
            /// Element-wise divide this array by another in place.
            /// To solve linear equations like A * x = b for x, use the nonmember linsolve
            /// function.
            NArray opDivAssign(S,int rank2)(NArray!(S,rank2) o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                static assert(rank2==rank,"opDivAssign supports only arrays of the same shape");
                binaryOpStr!("*aPtr0 /= cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// divides in place this array by a scalar.
            NArray opDivAssign()(V o)
            in { assert(!(flags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0 /= o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }
        
        /+ --------------------------------------------------- +/
        
        /// Compare with another array for value equality
        bool opEquals(NArray o) { 
            if (shape!=o.shape) return false;
            if (flags & o.flags & Flags.Compact1){
                return !memcmp(startPtrArray,o.startPtrArray,nElArray*cast(index_type)V.sizeof);
            }
            mixin(sLoopPtr(rank,["","o"],"if (*Ptr0 != *oPtr0) return false;","i"));
            return true; 
        }

        /// Compare for ordering not allowed (do it lexicographically on rank, shape, and then 
        /// elements using the standard C ordering??)
        int opCmp(NArray o) { 
            assert(0, "Comparison of arrays not allowed");
        }

        char[] toString(){
            return getString(printData(new Stringify()));
        }
        
        FormatOutput!(char) printData(FormatOutput!(char)s,char[] formatEl="{,10}", index_type elPerLine=10,
            char[] indent=""){
            s("[");
            static if(rank==1) {
                index_type lastI=shape[0]-1;
                foreach(index_type i,V v;SubView(this)){
                    static if (isComplexType!(V)){
                        s.format(formatEl,v.re)("+1i*").format(formatEl,v.im);
                    } else {
                        s.format(formatEl,v);
                    }
                    if (i!=lastI){
                        s(",");
                        if (i%elPerLine==elPerLine-1){
                            s("\n")(indent)(" ");
                        }
                    }
                }
            } else {
                index_type lastI=shape[0]-1;
                foreach(i,v;this){
                    v.printData(s,formatEl,elPerLine,indent~" ");
                    if (i!=lastI){
                        s(",\n")(indent)(" ");
                    }
                }
            }
            s("]");
            return s;
        }
            
        /// description of the NArray wrapper, not of the contents, for debugging purposes...
        FormatOutput!(char) desc(FormatOutput!(char)s){
            if (this is null){
                return s("<NArray *null*>").newline;
            }
            s("<NArray @:")(&this)(",").newline;
            s("  bStrides:")(bStrides)(",").newline;
            s("  shape:")(shape)(",").newline;
            s("  flags:")(flags)("=None");
            if (flags&Flags.Contiguous) s("|Contiguos");
            if (flags&Flags.Fortran) s("|Fortran");
            if (flags&Flags.Compact1) s("|Compact1");
            if (flags&Flags.Compact2) s("|Compact2");
            if (flags&Flags.Small) s("|Small");
            if (flags&Flags.Large) s("|Large");
            if (flags&Flags.ReadOnly) s("|ReadOnly");
            s(",").newline;
            s("  data: <array<")(V.stringof)("> @:")(startPtrArray)(", #:")(nElArray)(",").newline;
            s("  base:")(mBase).newline;
            s(">");
            return s;
        }
        
        /// returns the base for an array that is a view of the current array
        Guard newBase(){
            return mBase;
        }
        
        /// returns the flags for an array derived from the current one
        uint newFlags(){
            return flags; // &Flags.ExtFlags ???
        }
        
        /// increments a static index array, return true if it did wrap
        bool incrementArrayIdx(index_type[rank] index){
            int i=rank-1;
            while (i>=0) {
                ++index[i];
                if (index[i]<shape[i]) break;
                index[i]=0;
                --i;
            }
            return i<0;
        }
        /// return the total number of elements in the array
        index_type size(){
            index_type res=1;
            for (int i=0;i<rank;++i){
                res*=shape[i];
            }
            return res;
        }
        /// return the transposed view of the array
        NArray T(){
            index_type[rank] newshape,newstrides;
            for (int i=0;i<rank;++i){
                newshape[i]=shape[rank-1-i];
            }
            for (int i=0;i<rank;++i){
                newstrides[i]=bStrides[rank-1-i];
            }
            return NArray(newstrides,newshape,startPtrArray,newFlags,newBase);
        }
        
        static if(isComplexType!(V)){
            /// conjugates the array in place
            /// WARNING modifies the array!!!
            NArray conj1(){
                unaryOpStr!("*aPtr0=cast(T)((*aPtr0).re-(*aPtr0).im*1i);",rank,V)(this);
                return this;
            }
            /// returns a conjugated copy of the array
            NArray conj(){
                NArray res=NArray.empty(shape);
                binaryOpStr!("*aPtr0=cast(T)((*bPtr0).re-(*bPtr0).im*1i);",rank,V,V)(res,this);
                return res;
            }
        } else static if (isImaginaryType!(V)){
            /// conjugates the array in place
            /// WARNING modifies the array!!!
            NArray conj1(){
                unaryOpStr!("*aPtr0=-(*aPtr0);",rank,V)(this);
                return this;
            }
            /// returns a conjugated copy of the array
            NArray conj(){
                NArray res=NArray.empty(shape);
                binaryOpStr!("*aPtr0=-(*bPtr0);",rank,V,V)(res,this);
                return res;
            }
        } else {
            NArray conj1() { return this; }
            NArray conj() { return this; }
        }
        /// returns a hermitian copy of the array
        NArray H(){
            return this.T().conj();
        }
        /// returns a hermitian view of this array
        /// WARNING modifies the array (it conjugates it)!!!
        NArray H1(){
            return this.conj1().T();
        }
        
        /// returns an array that loops over the elements in the best possible way
        NArray optAxisOrder()
        in {
            for (int i=0;i<rank;++i)
                assert(shape[i]>0,"zero sized arrays not accepted");
        }
        out(res){
            debug(TestNArray){
                V[]myData=data,resData=res.data;
                assert(myData.ptr==resData.ptr && myData.length==resData.length,"underlying slice changed");
            }
        }
        body {
            static if(rank==1){
                if (bStrides[0]>=0)
                    return this;
                return NArray([-bStrides[0]],shape,
                    cast(V*)(cast(size_t)startPtrArray+bStrides[0]*(shape[0]-1)),
                    newFlags,newBase);
            } else static if(rank==2){
                if (bStrides[0]>=bStrides[1] && bStrides[0]>=0){
                    return this;
                } else {
                    index_type[rank] newstrides;
                    index_type newStartIdx=0;
                    if (bStrides[0]>0){
                        newstrides[0]=bStrides[0];
                    } else {
                        newstrides[0]=-bStrides[0];
                        newStartIdx+=bStrides[0]*(shape[0]-1);
                    }
                    if (bStrides[1]>0){
                        newstrides[1]=bStrides[1];
                    } else {
                        newstrides[1]=-bStrides[1];
                        newStartIdx+=bStrides[1]*(shape[1]-1);
                    }
                    index_type[rank] newshape;
                    if(newstrides[0]>=newstrides[1]){
                        newshape[0]=shape[0];
                        newshape[1]=shape[1];
                    } else {
                        newshape[0]=shape[1];
                        newshape[1]=shape[0];
                        auto tmp=newstrides[0];
                        newstrides[0]=newstrides[1];
                        newstrides[1]=tmp;
                    }
                    return NArray(newstrides,newshape,
                        cast(V*)(cast(size_t)startPtrArray+newStartIdx),newFlags,newBase);
                }
            } else {
                int no_reorder=1;
                for (int i=1;i<rank;++i)
                    if(bStrides[i-1]<bStrides[i]) no_reorder=0;
                if (no_reorder && bStrides[rank-1]>=0) return this;
                index_type[rank] pstrides;
                index_type newStartIdx=0;
                for (int i=0;i<rank;++i){
                    if (bStrides[i]>0){
                        pstrides[i]=bStrides[i];
                    } else {
                        pstrides[i]=-bStrides[i];
                        newStartIdx+=bStrides[i]*(shape[i]-1);
                    }
                }
                int[rank] sortIdx;
                for (int i=0;i<rank;i++)
                    sortIdx[i]=i;
                sortIdx.sort((int x,int y){return pstrides[x]>pstrides[y];});
                index_type[rank] newshape,newstrides;
                for (int i=0;i<rank;i++)
                    newshape[i]=shape[sortIdx[i]];
                for (int i=0;i<rank;i++)
                    newstrides[i]=pstrides[sortIdx[i]];
                return NArray(newstrides,newshape,
                    cast(V*)(cast(size_t)startPtrArray+newStartIdx),newFlags,newBase);
            }
        }
        
        /// perform a generic axis transformation (inversion an then permutation)
        /// and returns the resulting view (check validity of permutation?)
        NArray axisTransform(int[rank]perm,int[rank] invert)
        in{
            int [rank] found=0;
            for (int i=0;i<rank;++i){
                found[perm[i]]=1;
            }
            for (int i=0;i<rank;++i){
                assert(found[i],"invalid permutation");
            }
        }
        out(res){
            debug(TestNArray){
                V[]myData=data,resData=res.data;
                assert(myData.ptr==resData.ptr && myData.length==resData.length,"underlying slice changed in axisTransform");
            }
        }
        body{
            int no_change=1;
            for (int i=0;i<rank;++i){
                no_change=invert[i]==0&&perm[i]==i&&no_change;
            }
            if (no_change)
                return this;
            index_type[rank] newshape, pstrides, newstrides;
            index_type newStartIdx=0;
            for (int i=0;i<rank;++i){
                if (!invert[i]){
                    pstrides[i]=-bStrides[i];
                } else {
                    pstrides[i]=-bStrides[i];
                    newStartIdx+=bStrides[i]*(shape[i]-1);
                }
            }
            for (int i=0;i<rank;++i){
                newstrides[i]=pstrides[perm[i]];
                newshape[i]=shape[perm[i]];
            }
            return NArray(newstrides,newshape,
                cast(V*)(cast(size_t)startPtrArray+newStartIdx),newFlags,newBase);
        }
        
        /// returns a random array
        static NArray randomGenerate(Rand r){
            const index_type maxSize=1_000_000;
            float mean=10.0f;
            index_type[rank] dims;
            index_type totSize;
            do {
                foreach (ref el;dims){
                    el=cast(index_type)r.gamma(mean);;
                }
                totSize=1;
                foreach (el;dims)
                    totSize*=el;
                mean*=(cast(float)maxSize)/(cast(float)totSize);
            } while (totSize>maxSize)
            NArray res=NArray.empty(dims);
            return randNArray(r,res);
        }
        // ---- Serialization ---
        /// meta information for serialization
        static ClassMetaInfo metaI;
        /// registers this type into the serialization facilities
        //static void registerSerialization(){
        static this(){
            synchronized{
                if (metaI is null){
                    metaI=ClassMetaInfo.createForType!(NArray)
                        ("NArray!("~V.stringof~","~ctfe_i2a(rank)~")",
                        function void *(ClassMetaInfo){
                            index_type[rank] strid=0;
                            index_type[rank] shap=0;
                            auto res=new NArray(strid,shap, cast(V*)null, ArrayFlags.Zero ,null);
                            return cast(void*)res;
                        });
                    metaI.addFieldOfType!(index_type[])("shape","shape of the array");
                    metaI.addFieldOfType!(V[])("data","flattened data");
                }
            }
        }
        /// serialization meta informations
        ClassMetaInfo getSerializationMetaInfo(){
            //if (metaI is null) NArray.registerSerialization();
            return metaI;
        }
        /// the actual serialization function;
        void serialize(Serializer s){
            index_type[] shp=shape;
            s.field(metaI[0],shp);
            s.customField(metaI[1],{
                auto ac=s.writeArrayStart(null,size());
                mixin(sLoopPtr(rank,[""],`s.writeArrayEl(ac,{ s.field(cast(FieldMetaInfo*)null, *Ptr0); } );`,"i"));
                s.writeArrayEnd(ac);
            });
        }
        /// unserialization function
        void unserialize(Unserializer s){
            index_type[] shp;
            s.field(metaI[0],shp);
            if (shp.length>0) {
                shape[]=shp;
                scope tmp=empty(shape,false);
                this.shape[] = tmp.shape;
                this.bStrides[] = tmp.bStrides;
                this.startPtrArray=tmp.startPtrArray;
                this.nElArray=tmp.nElArray;
                this.flags=tmp.flags;
                this.mBase=tmp.mBase;
                version(RefCount) if (this.mBase !is null) this.mBase.retain;
            }
            void getData()
            {
                if (flags == 0) {
                    s.serializationError("cannot read data before knowing shape",__FILE__,__LINE__);
                }
                auto ac=s.readArrayStart(null);
                mixin(sLoopPtr(rank,[""],`if (!s.readArrayEl(ac,{ s.field(cast(FieldMetaInfo*)null, *Ptr0); } )) s.serializationError("unexpected number of elements",__FILE__,`~ctfe_i2a(__LINE__)~`);`,"i"));
                V dummy;
                if (s.readArrayEl(ac,{ s.field(cast(FieldMetaInfo*)null, dummy); } ))
                    s.serializationError("unexpected extra elements",__FILE__,__LINE__);
            }
            s.customField(metaI[1],&getData);
        }
        /// pre serializer hook, useful to (for example) lock the structure and guarantee a consistent snapshot
        void preSerialize(Serializer s){ /+if (metaI is null) NArray.registerSerialization();+/ }
        /// post serializer hook, useful to (for example) unlock the structure
        /// guaranteed to be called if preSerialize ended sucessfully
        void postSerialize(Serializer s){ }
        /// pre unserializer hook, useful to (for example) lock or replace the object
        typeof(this) preUnserialize(Unserializer s){ return this; }
        /// post unserializer hook, useful to (for example) unlock the structure
        /// or replace to unserialized object (for things that must be unique)
        /// guaranteed to be called if preSerialize ended sucessfully
        typeof(this) postUnserialize(Unserializer s){
            return this;
        }
    } // end NArray class
}// end static if
}// end template NArray

/// returns a "null" or dummy array (useful as default parameter)
template nullNArray(T,int rank){
    static if (rank>0){
        const NArray!(T,rank) nullNArray=null;
    } else {
        const T nullNArray=T.init;
    }
}


/// returns if the argument is a null or dummy array (useful as default parameter)
/// cannot recognize rank 0 null arrays
bool isNullNArray(T,int rank, bool acceptZeroRank=false)(NArray!(T,rank)a){
    static if (rank>0){
        return a is null;
    } else {
        static if (acceptZeroRank) {
            return false;
        } else {
            static assert(false,"cannot recognize rank 0 null arrays");
        }
    }
}

/+ -------- looping/generic operations --------- +/

/// applies an operation on all elements of the array. The looping order is arbitrary
/// and might be concurrent
void unaryOp(alias op,int rank,T)(NArray!(T,rank) a,
        index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize){
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a"],"op(*aPtr0);\n","i"));
}
/// ditto
void unaryOpStr(char[] op,int rank,T)(NArray!(T,rank) a,
        index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize){
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a"],op,"i"));
}

/// applies an operation combining the corresponding elements of two arrays.
/// The looping order is arbitrary and might be concurrent.
void binaryOp(alias op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b,
    index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize)
in { assert(a.shape==b.shape,"incompatible shapes in binaryOp"); }
body {
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a","b"],"op(*aPtr0,*bPtr0);\n","i"));
}
/// ditto
void binaryOpStr(char[] op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b,
    index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize)
in { assert(a.shape==b.shape,"incompatible shapes in binaryOp"); }
body {
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a","b"],op,"i"));
}

/// applies an operation combining the corresponding elements of three arrays .
/// The looping order is arbitrary and might be concurrent.
void ternaryOp(alias op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c,
    index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize)
in { assert(a.shape==b.shape && a.shape==c.shape,"incompatible shapes in ternaryOp"); }
body {
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a","b","c"],
        "op(*aPtr0,*bPtr0,*cPtr0);\n","i"));
}
/// ditto
void ternaryOpStr(char[] op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c,
    index_type optimalChunkSize=NArray!(T,rank).defaultOptimalChunkSize)
in { assert(a.shape==b.shape && a.shape==c.shape,"incompatible shapes in ternaryOp"); }
body {
    index_type optimalChunkSize_i=optimalChunkSize;
    mixin(pLoopPtr(rank,["a","b","c"],op,"i"));
}

/+ -------------- looping mixin constructs ---------------- +/

/// if baseName is not empty adds a dot (somethime this.xxx does not work and xxx works)
char [] arrayNameDot(char[] baseName){
    if (baseName=="") {
        return "";
    } else {
        return baseName~".";
    }
}
/++
+ general sequential index based loop character mixin
+ guarantted to loop in order, and to make valid indexes available
+ (ivarStr~_XX_, X=dimension, starting with 0) 
+ pointers to the actual elements are also available (arrayName~"Ptr0")
+/
char [] sLoopGenIdx(int rank,char[][] arrayNames,char[] loop_body,char[]ivarStr,char[]indent="    ",
    char[][] idxPre=[], char[][] idxPost=[]){
    char[] res="".dup;
    char[] indentInc="    ";
    char[] indent2=indent~indentInc;

    foreach(i,arrayName;arrayNames){
        res~=indent~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-1)~"="
            ~arrayNameDot(arrayName)~"startPtrArray;\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent~"index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="
                ~arrayNameDot(arrayName)~"bStrides["~ctfe_i2a(idim)~"];\n";
        }
    }
    for (int idim=0;idim<rank;idim++){
        res~=indent~"index_type "~ivarStr~"Shape"~ctfe_i2a(idim)~"="
            ~arrayNameDot(arrayNames[0])~"shape["~ctfe_i2a(idim)~"];\n";
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        res~=indent~"for (index_type "~ivar~"=0;"
            ~ivar~"<"~ivarStr~"Shape"~ctfe_i2a(idim)~";++"~ivar~"){\n";
        if (idxPre.length>idim) res~=idxPre[idim];
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                res~=indent2~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
        indent=indent2;
        indent2=indent~indentInc;
    }
    res~=indent~loop_body~"\n";
    for (int idim=rank-1;idim>=0;idim--){
        indent2=indent[0..indent.length-indentInc.length];
        if (idxPost.length>idim) res~=idxPost[idim]; // move after increment??
        foreach(arrayName;arrayNames){
            res~=indent~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~" = "
                ~"cast("~arrayNameDot(arrayName)~"dtype*)(cast(size_t)"~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)
                ~"+"~arrayName~"Stride"~ctfe_i2a(idim)~");\n";
        }
        res~=indent2~"}\n";
        indent=indent2;
    }
    return res;
}

/++
+ general sequential pointer based mixin
+ partial pointers are defined, but indexes are not (counts backward)
+/
char [] sLoopGenPtr(int rank,char[][] arrayNames,
        char[] loop_body,char[]ivarStr,char[] indent="    "){
    char[] res="".dup;
    char[] indInc="    ";
    char[] indent2=indent~indInc;

    foreach(i,arrayName;arrayNames){
        res~=indent;
        res~=arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-1)~"="~arrayNameDot(arrayName)~"startPtrArray;\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent;
            res~="index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="~arrayNameDot(arrayName)~"bStrides["~ctfe_i2a(idim)~"];\n";
        }
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        res~=indent~"for (index_type "~ivar~"="~arrayNameDot(arrayNames[0])~"shape["~ctfe_i2a(idim)~"];"
            ~ivar~"!=0;--"~ivar~"){\n";
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                res~=indent2~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
        indent=indent2;
        indent2=indent~indInc;
    }
    res~=indent~loop_body~"\n";
    for (int idim=rank-1;idim>=0;idim--){
        indent2=indent[0..indent.length-indInc.length];
        foreach(arrayName;arrayNames){
            res~=indent~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~" = "
                ~"cast("~arrayNameDot(arrayName)~"dtype*)(cast(size_t)"~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)
                ~"+"~arrayName~"Stride"~ctfe_i2a(idim)~");\n";
        }
        res~=indent2~"}\n";
        indent=indent2;
    }
    return res;
}

/++
+ possibly parallel Index based loop that never compacts.
+ All indexes in each dimension (ivarStr~_X_ , X=dimension, starting with 0) are available
+ pointers to the actual elements are also available (arrayName~"Ptr0")
+ hooks for each loop level are available
+ array might be split in sub pieces, each with its loop, and looping might be in a
+ different order, but the indexes are the correct ones
+/
char [] pLoopIdx(int rank,char[][] arrayNames,
        char[] loopBody,char[]ivarStr,char[][] arrayNamesDot=[],int[] optAccess=[],char[] indent="    ",
        char[][] idxPre=[], char[][] idxPost=[]){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    char[] indent2=indent~"    ";
    char[] indent3=indent2~"    ";
    bool hasNamesDot=true;
    res~=indent~"size_t dummy"~ivarStr~"=optimalChunkSize_"~ivarStr~";\n";
    if (arrayNamesDot.length==0){
        hasNamesDot=false;
        arrayNamesDot=[];
        foreach(i,arrayName;arrayNames)
            arrayNamesDot~=[arrayNameDot(arrayName)];
    }
    assert(arrayNamesDot.length==arrayNames.length);
    // needs more finesse: flat itaration not correct and reordering has to recover correct indexes
/+    if(hasNamesDot)
        res~=indent~"commonFlags"~ivarStr~"=";
    else
        res~=indent~"uint commonFlags"~ivarStr~"=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n";
    res~=indent~"if ("~arrayNameDot(arrayNames[0])~"mData !is null &&\n";
    res~=indent~"    (commonFlags"~ivarStr~"&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~=indent~"    commonFlags"~ivarStr~"&(ArrayFlags.Small | ArrayFlags.Compact)==ArrayFlags.Compact\n";
    res~=indent2;
    for (int i=1;i<arrayNames.length;i++)
        res~="&& "~arrayNameDot(arrayNames[0])~"bStrides=="~arrayNameDot(arrayNames[i])~"bStrides ";
    res~=")){\n";
    res~=indent2~"index_type "~ivarStr~"_0;\n";
    res~=indent2~"index_type "~ivarStr~"Length="~arrayNameDot(arrayNames[0])~"mData.length;\n";
    foreach(i,arrayName;arrayNames){
        res~=indent2~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="
            ~arrayNameDot(arrayName)~"mData.ptr;\n";
        res~=indent2~"alias "~ivarStr~"_0 "~arrayName~"Idx0;\n";
    }
    res~=indent2~"for ("~ivarStr~"_0=0;"~ivarStr~"_0!="~ivarStr~"Length;++"~ivarStr~"_0){\n";
    res~=indent3~loopBody~"\n";
    res~=indent2~"}\n";
    res~=indent~"}";
    if(!hasNamesDot && arrayNames.length==1){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"typeof("~arrayNames[0]~") "~arrayNames[0]~"_opt_="
            ~arrayNamesDot[0]~"optAxisOrder;\n";
        char[][] newNamesDot=[arrayNames[0]~"_opt_."];
        res~=pLoopIdx(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    } else if ((!hasNamesDot) && arrayNames.length>1 && optAccess.length>0){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"int[rank] perm,invert;\n";
        res~=indent2~"findOptAxisTransform(perm,invert,[";
        foreach(i,iArr;optAccess){
            assert(iArr>=0&&iArr<arrayNames.length,"out of bound optAccess");
            res~=arrayNames[iArr];
            if (i!=optAccess.length-1)
                res~=",";
        }
        res~="]);\n";
        foreach(i,arrayName;arrayNames){
            res~=indent2~"typeof("~arrayName~") "~arrayName~"_opt_="
                ~arrayNamesDot[i]~"axisTransform(perm,invert);\n";
        }
        char[][] newNamesDot=[];
        foreach(arrayName;arrayNames){
            newNamesDot~=[arrayName~"_opt_."];
        }
        res~=pLoopIdx(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    }
    res~=" else {\n";+/
    res~=sLoopGenIdx(rank,arrayNames,loopBody,ivarStr,indent2,idxPre,idxPost);
//    res~=indent~"}";
    return res;
}
/++
+ (possibly) parallel pointer based loop character mixin
+ might do a compact loop, only the final pointers are valid
+/
char [] pLoopPtr(int rank,char[][] arrayNames,
        char[] loopBody,char[]ivarStr,char[][] arrayNamesDot=[],int[] optAccess=[],char[] indent="    "){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    char[] indent2=indent~"    ";
    char[] indent3=indent2~"    ";
    bool hasNamesDot=true;
    if (arrayNamesDot.length==0){
        hasNamesDot=false;
        arrayNamesDot=[];
        foreach(i,arrayName;arrayNames)
            arrayNamesDot~=[arrayNameDot(arrayName)];
    }
    assert(arrayNamesDot.length==arrayNames.length);
    if(hasNamesDot){
        res~=indent~"commonFlags"~ivarStr~"=";
    } else{
        res~=indent~"size_t dummy"~ivarStr~"=optimalChunkSize_"~ivarStr~";\n";
        res~=indent~"uint commonFlags"~ivarStr~"=";
    }
    foreach (i,arrayNameD;arrayNamesDot){
        res~=arrayNameD~"flags";
        if (i!=arrayNamesDot.length-1) res~=" & ";
    }
    res~=";\n";
    res~=indent~"if (commonFlags"~ivarStr~"&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~=indent2~"commonFlags"~ivarStr~"&(ArrayFlags.Small | ArrayFlags.Compact1)==ArrayFlags.Compact1\n";
    res~=indent2;
    for (int i=1;i<arrayNamesDot.length;i++){
        res~="&& is("~arrayNamesDot[0]~"dtype=="~arrayNamesDot[i]~"dtype) ";
        res~="&& "~arrayNamesDot[0]~"bStrides=="~arrayNamesDot[i]~"bStrides ";
    }
    res~="){\n";
    foreach(i,arrayName;arrayNames)
        res~=indent2~arrayNamesDot[i]~"dtype * "~arrayName~"Ptr0="
            ~arrayNamesDot[i]~"startPtrArray;\n";
    res~=indent2~"for (index_type "~ivarStr~"_0="~arrayNamesDot[0]~"nElArray;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~=indent3~loopBody~"\n";
    foreach(i,arrayName;arrayNames)
        res~=indent3~"++"~arrayName~"Ptr0;\n";
    res~=indent2~"}\n";
    res~=indent~"}";
    if(!hasNamesDot && arrayNames.length==1){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"typeof("~arrayNames[0]~") "~arrayNames[0]~"_opt_="
            ~arrayNamesDot[0]~"optAxisOrder;\n";
        char[][] newNamesDot=[arrayNames[0]~"_opt_."];
        res~=pLoopPtr(rank,arrayNames,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    } else if ((!hasNamesDot) && arrayNames.length>1 && optAccess.length>0){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"int[rank] perm,invert;\n";
        res~=indent2~"findOptAxisTransform(perm,invert,[";
        foreach(i,iArr;optAccess){
            assert(iArr>=0&&iArr<arrayNames.length,"out of bound optAccess");
            res~=arrayNames[iArr];
            if (i!=optAccess.length-1)
                res~=",";
        }
        res~="]);\n";
        foreach(i,arrayName;arrayNames){
            res~=indent2~"typeof("~arrayName~") "~arrayName~"_opt_="
                ~arrayNamesDot[i]~"axisTransform(perm,invert);\n";
        }
        char[][] newNamesDot=[];
        foreach(arrayName;arrayNames){
            newNamesDot~=[arrayName~"_opt_."];
        }
        res~=pLoopPtr(rank,arrayNames,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    }
    res~=" else {\n";
    res~=sLoopGenPtr(rank,arrayNames,loopBody,ivarStr,indent2);
    res~=indent~"}\n";
    return res;
}

/++
+ sequential (inner fastest) loop character mixin
+/
char [] sLoopPtr(int rank,char[][] arrayNames, char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags"~ivarStr~"=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags"~ivarStr~"&ArrayFlags.Contiguous){\n";
    foreach (i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr0="~arrayNameDot(arrayName)~"startPtrArray;\n";
    }
    res~="        for (index_type "~ivarStr~"_0="~arrayNameDot(arrayNames[0])~"nElArray;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~="            "~loopBody~"\n";
    foreach(i,arrayName;arrayNames)
        res~="            ++"~arrayName~"Ptr0;\n";
    res~="        }\n";
    res~="    } else {\n";
    res~=sLoopGenPtr(rank,arrayNames,loopBody,ivarStr);
    res~="    }\n";
    return res;
}

/// array to Sequence (for arrayIndex,arrayIndexAssign)
char[] arrayToSeq(char[] arrayName,int dim){
    char[] res="".dup;
    for (int i=0;i<dim;++i){
        res~=arrayName~"["~ctfe_i2a(i)~"]";
        if (i!=dim-1)
            res~=", ";
    }
    return res;
}

char[] opApplyIdxAll(int rank,char[] arrayName,bool sequential){
    char[] res="".dup;
    char[] indent="    ";
    res~="int opApply(int delegate(";
    for (int i=0;i<rank;++i){
        res~="ref index_type, ";
    }
    res~="ref V) loop_body) {\n";
    char[] loopBody="".dup;
    loopBody~=indent~"int ret=loop_body(";
    for (int i=0;i<rank;++i){
        loopBody~="i_"~ctfe_i2a(i)~"_, ";
    }
    loopBody~="*aPtr0);\n";
    loopBody~=indent~"if (ret) return ret;\n";
    if (sequential) {
        res~=sLoopGenIdx(rank,["a"],loopBody,"i");
    } else {
        res~=indent~"index_type optimalChunkSize_i=optimalChunkSize;\n";
        res~=pLoopIdx(rank,["a"],loopBody,"i");
    }
    res~="    return 0;";
    res~="}\n";
    return res;
}

/// finds the optimal axis transform for the given arrays
/// make it a variadic template?
void findOptAxisTransform(int rank,T,uint nArr)(out int[rank]perm,out int[rank]invert,
    NArray!(T,rank)[nArr] arrays)
in {
    assert(!(arrays[0].flags&ArrayFlags.Zero),"zero arrays not supported"); // accept them??
    for (int iArr=1;i<nArr;++i){
        assert(arrays[0].shape==arrays[i].shape,"all arrays need to have the same shape");
    }
}
body {
    invert[]=0;
    index_type[nArr][rank] pstrides;
    index_type[nArr] newStartIdx;
    for (int iArr=0;iArr<nArr;++iArr){
        auto nArr=arrays[iArr];
        newStartIdx[iArr]=0;
        for (int i=0;i<rank;++i){
            auto s=nArr.bStrides[i];
            if (s>0){
                pstrides[i][iArr]=s;
                invert-=1;
            } else if (s!=0){
                pstrides[i][iArr]=-s;
                newStartIdx[iArr]+=s*(nArr.shape[i]-1);
                invert+=1;
            } else {
                pstrides[i][iArr]=s;
            }
        }
    }
    for (int i=0;i<rank;++i)
        invert[i]=invert[i]>0;
    for (int i=0;i<rank;++i)
        perm[i]=[i];
    const int maxR=(rank>3)?rank-4:0;
    // use also the shape as criteria?
    for (int i=rank-1;i>=0;--i){
        for (int j=i-1;j>=0;--j){
            int shouldSwap=0;
            for (int iArr=0;iArr<nArr;++iArr){
                if (pstrides[perm[i]][iArr]<pstrides[perm[j]][iArr]){
                    shouldSwap-=1;
                }else if (pstrides[perm[i]][iArr]>pstrides[perm[j]][iArr]){
                    shouldSwap+=1;
                }
            }
            if (shouldSwap>0){
                auto tmp=perm[i];
                perm[i]=perm[j];
                perm[j]=tmp;
            }
        }
    }
}
/+ ------------------------------------------------- +/
/// rank of NArray for the given shape (for empty,zeros,ones)
/// more flexible than member function, accepts int/long, int/long static array
template rkOfShape(T){
    static if(isStaticArrayType!(T)){
        static assert(is(BaseTypeOfArrays!(T)==int)||is(BaseTypeOfArrays!(T)==uint)||
            is(BaseTypeOfArrays!(T)==long)||is(BaseTypeOfArrays!(T)==ulong),
            "only integer types supported as shape dimensions");
        const int rkOfShape = cast(int)staticArraySize!(T);
    } else {
        static assert(is(T==int)||is(T==uint)||is(T==long)||is(T==ulong),
            "only integer types (and static arrays of them) supported as dimensions");
        const int rkOfShape = 1;
    }
}

// array randomization (here because due to bug 2246 in the 
// compiler the specialization of randomGenerate does not work,
// and it uses the RandGen interface)

/// randomizes the content of the array
NArray!(T,rank) randomizeNArray(RandG,T,int rank)(RandG r,NArray!(T,rank)a){
    if (a.flags | ArrayFlags.Compact2){
        T[] d=a.data;
        r.randomize(d);
    } else {
        mixin unaryOpStr!("r.randomize(*aPtr0);",rank,T);
        unaryOpStr(a);
    }
    return a;
}
/// returns a random array of the given size with the given distribution
/// this seems to triggers bugs in DMD
template randomNArray(T){
    NArray!(T,rkOfShape!(S))randomNArray(RandG,S)(RandG r,S dim){
        static if (! isStaticArrayType!(S)){
            index_type[1] mdim;
            mdim[0]=cast(index_type)dim;
        } else static if (is(ElementTypeOfArray!(S)==index_type)){
            alias dim mdim;
        } else {
            index_type[rkOfShape!(S)] mdim;
            foreach (i,ref el;mdim)
                el=dim[i];
        }
        NArray!(T,rkOfShape!(S)) res=NArray!(T,rkOfShape!(S)).empty!(T)(mdim);
        return randomizeNArray(r,res);
    }
}
/// returns the array a after having randomized its contens with normal (signed values)
/// or exp (unsigned values) distribued numbers.
NArray!(T,rank) randNArray(T,int rank)(Rand r, NArray!(T,rank) a){
    static if (is(T==float)|| is(T==double)||is(T==real)){
        auto source=r.normalD(cast(T)3.0);
    }else static if (is(T==ubyte)||is(T==uint)||is(T==ulong)) {
        auto source=r.expD(10.0);
    } else {
        auto source=r.normalD(30.0);
    }
    return randomizeNArray(source,a);
}

/// returns a new array with the same content as a, but with a random layout
/// (row ordering, loop order, strides,...)
NArray!(T,rank) randLayout(T,int rank)(Rand r, NArray!(T,rank)a){
    if (a.size==0) return a;
    int[rank] permutation,rest;
    foreach (i,ref el;rest)
        el=i;
    foreach (i,ref el;permutation){
        int pRest=r.uniformR(rank-i);
        permutation[i]=rest[pRest];
        rest[pRest]=rest[rank-i-1];
    }
    index_type[rank] gaps;
    index_type[] g=gaps[];
    r.normalD(1.0).randomize(g);
    foreach(ref el;gaps){
        if (el==0 || el>5 || el<-5) el=1;
    }
    index_type newStartIdx=0;
    index_type[rank] newStrides;
    index_type sz=cast(index_type)T.sizeof;
    foreach(perm;permutation){
        newStrides[perm]=sz*gaps[perm];
        sz*=a.shape[perm]*abs(gaps[perm]);
        if (gaps[perm]<0) {
            newStartIdx+=-(a.shape[perm]-1)*newStrides[perm];
        }
    }
    auto base=NArray!(T,1).empty([sz/cast(index_type)T.sizeof]);
    auto res=NArray!(T,rank)(newStrides,a.shape,cast(T*)
        (cast(size_t)base.startPtrArray+newStartIdx),a.newFlags&~ArrayFlags.ReadOnly,base.newBase);
    debug(TestNArray){
        if (sz>0){
            T[] resData=res.data;
            assert(base.startPtrArray<=resData.ptr && base.startPtrArray+base.nElArray>=resData.ptr+resData.length,
                "error randLayout slice outside expected region ");
        }
    }
    res[]=a;
    if (a.flags&ArrayFlags.ReadOnly){
        res=NArray!(T,rank)(newStrides,cast(index_type[rank])a.shape,cast(T*)
            (cast(size_t)base.startPtrArray+newStartIdx),
            (a.newFlags&~ArrayFlags.ReadOnly)|ArrayFlags.ReadOnly,base.newBase);
    }
    return res;
}
/+ ------------------------------------------------- +/
NArray!(double,1) dummy;