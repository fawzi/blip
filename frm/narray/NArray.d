/+
+ N dimensional dense rectangular arrays
+
+ Inspired by muarray by William V. Baxter (III) with hints of 
+ numpy, and haskell GSL/Matrix Library, but evolved to something of quite different
+
+ - rank must be choosen at compiletime -> smart indexing possible
+ - sizes can be choosen at runtime -> no compile time size
+   (overhead should be acceptable for all but the smallest arrays)
+ - a given array has fixed startIdx, and strides (in D 2.0 these should be invariant)
+ - also the rest of the structure should be as "fixed" as possible.
+ - at the moment only the underlying array is modified after creation when using
+   subviews, but in the future also this might go away.
+ - generic efficent looping templates are available.
+ - store array not pointer (safer, but might be changed in the future)
+ - structure not class (faster, but might be changed)
+ Rationale:
+ - indexing should be as fast as possible (if one uses multidimensional arrays
+   probably indexing is going to be important to him) -> fixed rank, invariant strides
+ - close to optimal (performacewise) looping should be easy to perform -> generic looping templates
+ - A good compiler should be able to move most of indexing out of a loop -> invariant strides
+/

module frm.narray.NArray;
import tango.stdc.stdlib: calloc,free,realloc;
import tango.core.Array;
import tango.stdc.string: memset,memcpy,memcmp;
import frm.TemplateFu;
import tango.io.Stdout;
import tango.io.Print;
import tango.math.Math;
import tango.math.IEEE;

enum ArrayFlags {
    /// Contiguous really means C-style contiguious.  The
    /// contiguous part means that there are no 'skipped
    /// elements'.  That is, that a flat_iter over the array will
    /// touch every location in memory from the location of the
    /// first element to that of the last element.  The C-style
    /// part means that the data is laid out such that the last index 
    /// is the fastest varying as one scans though the array's
    /// memory.
    Contiguous   = 0x1,
    /// Fortran really means Fortran-style contiguous.  The
    /// contiguous part means that there are no 'skipped
    /// elements'.  That is, that a flat_iter over the array will
    /// touch every location in memory from the location of the
    /// first element to that of the last element.  The Fortran-style
    /// part means that the data is laid out such that the first index 
    /// is the fastest varying as one scans though the array's
    /// memory.
    Fortran      = 0x2,
    /// If this flag is set this array frees its data in the destructor.
    ShouldFreeData      = 0x4,
    /// if the array is "compact" and mData scans the whole array
    /// only once (and mData can be directly used to loop on all elements)
    /// Contiguous|Fortran impies Compact
    Compact      = 0x8,
    /// if the array is non small
    Small        = 0x10,
    /// if the array is large
    Large        = 0x20,
    /// if the array can be only read
    ReadOnly     = 0x40,
    /// flags that the user can set (the other are automatically calculated)
    ExtFlags = ShouldFreeData | ReadOnly,
    All = Contiguous | Fortran | ShouldFreeData | Compact | Small | Large| ReadOnly, // useful ??
    None = 0
}

alias int index_type; // switch back to int later

index_type[] stridesVal(index_type[] shape, bool fortran, index_type[] strides=null){
    index_type[] res;
    if (strides is null || strides.length!=shape.length){
        res=new index_type[shape.length];
    } else {
        res=strides;
    }
    if (!fortran){
        index_type sz=1;
        foreach_reverse(i, d; shape) {
            res[i] = sz;
            sz *= d;
        }
    } else {
        index_type sz=1;
        foreach(i, d; shape) {
            res[i] = sz;
            sz *= d;
        }
    }
    return res;
}

/// describes a range
/// upper bound is not part of the range if positive
/// negative numbers are from the end, and (unlike the positive range)
/// the upper bound is inclusive (i.e. Range(-1,-1) is the last element,
/// but Range(0,0) contains no elements)
/// if the increment is 0, the range is unbounded (with increment 1)
struct Range{
    index_type from,to,inc;
    /// a range from start to infinity
    static Range opCall(index_type start){
        Range res;
        res.from=start;
        res.to=start+1;
        res.inc=0;
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
template reductionFactor(){
    const int reductionFactor=0;
}
/// returns the reduction of the rank done by the arguments in the tuple
/// allow also static arrays?
template reductionFactor(T,S...){
    static if (is(T==int) || is(T==long)|is(TT==uint)|is(TT==ulong))
        const int reductionFactor=1+reductionFactor!(S);
    else static if (is(T==Range))
        const int reductionFactor=reductionFactor!(S);
    else{
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactor, this will fail");
    }
}

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
+/
char [] s_loop_genIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr){
    char[] res="".dup;
    char[] indent="                  ";

    foreach(i,arrayName;arrayNames){
        res~=indent[0..2];
        res~=arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="~arrayNameDot(arrayName)~"mData.ptr;\n";
        
        res~=indent[0..2];
        res~="index_type "~arrayName~"Idx"~ctfe_i2a(rank-1)~"=";
        if (startIdxs.length<=i || startIdxs[i]=="")
            res~=arrayNameDot(arrayName)~"mStartIdx;\n";
        else
            res~=startIdxs[i]~";\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent[0..2];
            res~="index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="~arrayNameDot(arrayName)~"mStrides["~ctfe_i2a(idim)~"];";
        }
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        if (rank<8) res~=indent[0..(2+idim*2)];
        res~="for (index_type "~ivar~"=0;"~ivar~"<"~arrayNameDot(arrayNames[0])~"mShape["~ctfe_i2a(idim)~"];++"~ivar~"){\n";
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                if (rank<8) res~=indent[0..(4+idim*2)];
                res~="index_type "~arrayName~"Idx"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Idx"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
    }
    if (rank<8) res~=indent[0..(2+rank*2)];
    res~=loop_body~"\n";
    for (int idim=rank-1;idim>=0;idim--){
        foreach(arrayName;arrayNames){
            if (rank<8) res~=indent[0..(4+idim*2)];
            res~=arrayName~"Idx"~ctfe_i2a(rank-1-idim)~" += "~arrayName~"Stride"~ctfe_i2a(idim)~";\n";
        }
        if (rank<8) res~=indent[0..(idim+1)*2];
        res~="}\n";
    }
    return res;
}

/+
+ general sequential pointer based mixin
+ partial pointers are defined, but indexes are not (counts backward)
+/
char [] s_loop_genPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr){
    char[] res="".dup;
    char[] indent="                  ";

    foreach(i,arrayName;arrayNames){
        res~=indent[0..2];
        res~=arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-1)~"="~arrayNameDot(arrayName)~"mData.ptr+";
        if (startIdxs.length<=i || startIdxs[i]=="")
            res~=arrayNameDot(arrayName)~"mStartIdx;\n";
        else
            res~=startIdxs[i]~";\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent[0..2];
            res~="index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="~arrayNameDot(arrayName)~"mStrides["~ctfe_i2a(idim)~"];\n";
        }
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        if (rank<8) res~=indent[0..(2+idim*2)];
        res~="for (index_type "~ivar~"="~arrayNameDot(arrayNames[0])~"mShape["~ctfe_i2a(idim)~"];"~ivar~"!=0;--"~ivar~"){\n";
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                if (rank<8) res~=indent[0..(4+idim*2)];
                res~=arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
    }
    if (rank<8) res~=indent[0..(2+rank*2)];
    res~=loop_body;
    for (int idim=rank-1;idim>=0;idim--){
        foreach(arrayName;arrayNames){
            if (rank<8) res~=indent[0..(4+idim*2)];
            res~=arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~" += "~arrayName~"Stride"~ctfe_i2a(idim)~";\n";
        }
        if (rank<8) res~=indent[0..(idim+1)*2];
        res~="}\n";
    }
    return res;
}

/++
+ possibly parallel Index based loop that never compacts.
+ All indexes (flat and in each dimension) are defined.
+/
char [] p_loop_genIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr){
    return s_loop_genIdx(rank,arrayNames,startIdxs,loop_body,ivarStr);
}

/++
+ (possibly) parallel index based loop character mixin.
+ Only the flat indexes are valid if it can do a compact loop.
+ startIdxs is ignored if it can do a compact loop.
+/
char [] p_loopIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~="        commonFlags&(ArrayFlags.Small | ArrayFlags.Compact)==ArrayFlags.Compact\n        ";
    for (int i=1;i<arrayNames.length;i++)
        res~="&& "~arrayNameDot(arrayNames[0])~"mStrides=="~arrayNameDot(arrayNames[i])~"mStrides ";
    res~="){\n";
    res~="        index_type "~ivarStr~"_0;\n";
    res~="        index_type "~ivarStr~"Length="~arrayNameDot(arrayNames[0])~"mData.length;\n";
    foreach(i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="
            ~arrayNameDot(arrayName)~"mData.ptr;\n";
        res~="        alias "~ivarStr~"_0 "~arrayName~"Idx0;\n";
    }
    res~="        for ("~ivarStr~"_0=0;"~ivarStr~"_0!="~ivarStr~"Length;++"~ivarStr~"_0){\n";
    res~="            "~loopBody~"\n";
    res~="        }";
    res~="    } else {\n";
    res~=s_loop_genIdx(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }";
    return res;
}

/++
+ (possibly) parallel pointer based loop character mixin
+ startIdxs is ignored if it can do a compact loop, only the final pointers are valid
+/
char [] p_loopPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~="        commonFlags&(ArrayFlags.Small | ArrayFlags.Compact)==ArrayFlags.Compact\n        ";
    for (int i=1;i<arrayNames.length;i++)
        res~="&& "~arrayNameDot(arrayNames[0])~"mStrides=="~arrayNameDot(arrayNames[i])~"mStrides ";
    res~="){\n";
    foreach(i,arrayName;arrayNames)
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr0="
            ~arrayNameDot(arrayName)~"mData.ptr;";
    res~="        for (index_type "~ivarStr~"_0="~arrayNameDot(arrayNames[0])~"mData.length;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~="            "~loopBody~"\n";
    foreach(i,arrayName;arrayNames)
        res~="            ++"~arrayName~"Ptr0;";
    res~="        }";
    res~="    } else {\n";
    res~=s_loop_genPtr(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }";
    return res;
}

/++
+ sequential (inner fastest) index based loop character mixin
+ only the 
+/
char [] s_loopIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags&ArrayFlags.Contiguous){\n";
    foreach (i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="~arrayNameDot(arrayName)~"mData.ptr;\n";
    }
    res~="        index_type "~arrayNames[0]~"_length="~arrayNameDot(arrayNames[0])~"mData.length;\n";
    res~="        for (index_type "~ivarStr~"_=0;"~ivarStr~"_!="~arrayNames[0]~"_length;++"~ivarStr~"_){\n";
    foreach(i,arrayName;arrayNames)
        res~="        index_type "~arrayName~"Idx0="~ivarStr~"_;";
    res~="            "~loopBody~"\n";
    res~="        }";
    res~="    } else {";
    res~=s_loop_genIdx(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }";
    return res;
}

/++
+ sequential (inner fastest) loop character mixin
+/
char [] s_loopPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"flags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags&ArrayFlags.Contiguous){\n";
    foreach (i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr0="~arrayNameDot(arrayName)~"mData.ptr;\n";
    }
    res~="        for (index_type "~ivarStr~"_0="~arrayNameDot(arrayNames[0])~"mData.length;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~="            "~loopBody~"\n";
    foreach(i,arrayName;arrayNames)
        res~="            ++"~arrayName~"Ptr0;\n";
    res~="        }\n";
    res~="    } else {\n";
    res~=s_loop_genPtr(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }\n";
    return res;
}

/// array to Sequence
char[] arrayToSeq(char[] arrayName,int dim){
    char[] res="".dup;
    for (int i=0;i<dim;++i){
        res~=arrayName~"["~ctfe_i2a(i)~"]";
        if (i!=dim-1)
            res~=", ";
    }
    return res;
}

/// threshold for manual allocation
const int manualAllocThreshold=200*1024;

template NArray(T=double,int rank=1){
static if (rank<1)
    alias T NArray;
else {
    final class NArray
    {
        alias T dtype;
        alias ArrayFlags Flags;

        /// initial index (useful when looping backward)
        const index_type mStartIdx;
        /// strides (can be negative)
        index_type[rank] mStrides;
        /// shape of the array
        index_type[rank] mShape;
        /// the raw data of the array
        T[] mData;
        /// flags to quickly check properties of the array
        uint mFlags = Flags.None;
        /// owner of the data if it is manually managed
        void *mBase = null;

        uint flags() { return mFlags; }
        T[] data() { return mData; }
        index_type[] strides() { return mStrides; }
        index_type[] shape() { return mShape; }
        index_type startIdx() { return mStartIdx; }
        
        /// calulates the base flags (Contiguos,Fortran,Compact,Small,Large)
        static uint calcBaseFlags(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            T[] data){
            uint flags=Flags.None;
            // check contiguos & fortran
            bool contiguos,fortran;
            index_type size=-1;
            contiguos=fortran=(startIdx==0);
            if (contiguos){
                static if (rank == 1) {
                    contiguos=fortran=(shape[0]==0 || shape[0] == 1 || 1 == strides[0]);
                    size=shape[0];
                } else {
                    index_type sz=1;
                    for (int i=0;i<rank;i++){
                        if (strides[i]!=sz && shape[i]!=1)
                            fortran=false;
                        sz*=shape[i];
                    }
                    size=sz;
                    sz=1;
                    if (sz==0){
                        contiguos=true;
                        fortran=true;
                    } else {
                        for (int i=rank-1;i>=0;i--){
                            if (strides[i]!=sz && shape[i]!=1)
                                contiguos=false;
                            sz*=shape[i];
                        }
                    }
                }
            }
            if (contiguos)
                flags|=Flags.Contiguous|Flags.Compact;
            if (fortran)
                flags|=Flags.Fortran|Flags.Compact;
            else if (! contiguos) {
                // check compact
                index_type[rank] posStrides=strides;
                index_type posStart=startIdx;
                for (int i=0;i<rank;i++){
                    if (posStrides[i]<0){
                        posStart+=posStrides[i]*(shape[i]-1);
                        posStrides[i]=-posStrides[i];
                    }
                }
                int[rank] sortIdx;
                for (int i=0;i<rank;i++)
                    sortIdx[i]=i;
                sortIdx.sort((int x,int y){return strides[x]<strides[y];});
                index_type sz=1;
                bool compact=true;
                for (int i=0;i<rank;i++){
                    if (posStrides[sortIdx[i]]!=sz)
                        compact=false;
                    sz*=shape[sortIdx[i]];
                }
                size=sz;
                if (sz==0)
                    compact=true;
                if (posStart!=0)
                    compact=false;
                if (compact)
                    flags|=Flags.Compact;
            }
            if (flags & Flags.Compact){
                if (data !is null && data.length!=size){
                    // should this be an error, or should it be accepted ???
                    flags &= ~(Flags.Contiguous|Flags.Fortran|Flags.Compact);
                }
            }
            if (size< 4*rank && size<20) {
                flags|=Flags.Small;
            }
            if (size>30*rank || size>100) {
                flags|=Flags.Large;
            }
            return flags;
        }
        
        /// this is the default constructor, it is quite lowlevel and you are
        /// supposed to create arrays with higher level functions (empty,zeros,ones,...)
        /// the data will be freed if flags & Flags.ShouldFreeData, the other flags are ignored
        this(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            T[] data, uint flags, void *mBase=null)
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
            if (size!=0 && data !is null){
                assert(minIndex>=0,"minimum real internal index negative in NArray construction");
                assert(maxIndex<data.length,"data array too small in NArray construction");
            }
        }
        body {
            this.mShape[] = shape;
            this.mStrides[] = strides;
            this.mStartIdx = startIdx;
            this.mData=data;
            this.mFlags=calcBaseFlags(strides,shape,startIdx,data)|(flags & Flags.ExtFlags);
            this.mBase=mBase;
        }
        
        ~this(){
            if (flags&Flags.ShouldFreeData){
                free(mData.ptr);
            }
        }
        
        /// another way to construct an object (also low level, see empty, zeros and ones for better ways)
        static NArray opCall(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            T[] data, uint flags, void* mBase=null){
            return new NArray(strides,shape,startIdx,data,flags,mBase);
        }
                
        /// returns an empty (uninitialized) array of the requested shape
        static NArray empty(index_type[rank] shape,bool fortran=false){
            index_type size=1;
            foreach (sz;shape)
                size*=sz;
            uint flags=ArrayFlags.None;
            T[] mData;
            if (size*T.sizeof>manualAllocThreshold) {
                T* mData2=cast(T*)calloc(size,T.sizeof);
                if(mData2 is null) throw new Exception("calloc failed");
                mData=mData2[0..size];
                flags=ArrayFlags.ShouldFreeData;
            } else {
                mData=new T[size];
            }
            index_type[rank] strides;
            stridesVal(shape,fortran,strides);
            return NArray(strides,shape,cast(index_type)0,mData,flags);
        }
        static NArray empty(index_type[] shape,bool fortran=false){
            assert(shape.length==rank,"invalid shape length");
            index_type[rank] dims=shape;
            return empty(dims,fortran); // cast(index_type[rank]) does not work
        }
        /// returns an array initialized to 0 of the requested shape
        static NArray zeros(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            static if(isAtomicType!(T)){
                memset(res.mData.ptr,0,res.mData.length*T.sizeof);
            } else {
                res.mData[]=cast(T)0;
            }
            return res;
        }
        /// returns an array initialized to 1 of the requested shape
        static NArray ones(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            res.mData[]=cast(T)1;
            return res;
        }
        
        /// applies an operation that "collects" data on the whole array
        /// this is basically a possibly parallel fold on the flattened array
        /// foldOp(x,t) is the operations that accumulates on x the element t
        /// of the array, mergeOp(x,y) merges in x the two partial results x and y
        /// dupOp(x) is an operation that makes a copy of x (for simple types normally a nop)
        /// the folding starts with the element x0, if S==T normally mergeOp==foldOp
        S reduceAll(alias foldOp,alias mergeOp, alias dupOp,S)(S x0){
            S x=dupOp(x0);
            mixin(s_loopIdx(rank,["this"],"foldOp(x,*(thisBasePtr+thisIdx0));\n"));
            mergeOp(x,x0);  /+ just to test it +/
            return x;
        }
        
        /// indexing
        /// if array has rank 3: array[1,4,3] -> scalar, array[2] -> 2D array,
        /// array[3,Range(6,7)] -> 2D array, ...
        /// if a sub array is returned (and not a scalar) then it is *always* a subview
        /// indexing never copies data
        NArray!(T,rank-reductionFactor!(S))opIndex(S...)(S idx_tup)
        in {
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if(rank==reductionFactor!(S)){
                foreach (i,v;idx_tup){
                    assert(0<=v && v<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");
                }
            } else {
                foreach(i,TT;S){
                    static if(is(TT==int)|is(TT==long)|is(TT==uint)|is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");                        
                    } else static if(is(TT==Range)){
                        index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                        if (from<0) from+=mShape[i];
                        if (to<0) to+=mShape[i]+1;
                        if (from<to && step>=0 || from>to && step<0){
                            assert(0<=from && from<mShape[i],
                                "invalid lower range for dimension "~ctfe_i2a(i));
                            if (step==0)
                                to=mShape[i]-1;
                            else
                                to=to-(to-from)%step;
                            assert(to>=0 && to<=mShape[i],
                                "invalid upper range for dimension "~ctfe_i2a(i));
                        }
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndex");
                }
            }
        }
        body {
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                index_type idx=mStartIdx;
                foreach(i,TT;S){
                    static assert(is(TT==int)|is(TT==long)|is(TT==uint)|is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    idx+=idx_tup[i]*mStrides[i];
                }
                return mData[idx];
            } else {
                const int rank2=rank-reductionFactor!(S);
                index_type[rank2] newstrides,newshape;
                index_type newStartIdx;
                int idim=0;
                foreach(i,TT;S){
                    static if (is(TT==int)|is(TT==long)|is(TT==uint)|is(TT==ulong)){
                        newStartIdx+=idx_tup[i]*mStrides[i];
                    } else static if (is(TT==Range)){
                        index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                        if (from<0) from+=mShape[i];
                        if (to<0) to+=mShape[i]+1;
                        if (from<to && step>=0 || from>to && step<0){
                            if (step==0)
                                to=mShape[i]-1;
                            else
                                to=to-(to-from)%step;
                            newshape[idim]=1+(to-from)/step;
                            newStartIdx+=from*mStrides[i];
                            if (step==0)
                                newstrides[idim]=mStrides[i];
                            else
                                newstrides[idim]=step*mStrides[i];
                        } else {
                            newshape[idim]=0; // set everything to 0?
                            if (step==0)
                            newstrides[idim]=mStrides[i];
                            else
                                newstrides[idim]=step*mStrides[i];
                        }
                        idim+=1;
                    } else static assert(0,"unexpected type in opIndex");
                }
                for (int i=rank2-idim;i>0;--i){
                    newstrides[rank2-i]=mStrides[rank-i];
                    newshape[rank2-i]=mShape[rank-i];
                }
                // calc min index & max index (optimal subslice)
                index_type minIndex=newStartIdx,maxIndex=newStartIdx,size=1;
                for (int i=0;i<rank2;i++){
                    size*=newshape[i];
                    if (newstrides[i]<0){
                        minIndex+=newstrides[i]*(newshape[i]-1);
                    } else {
                        maxIndex+=newstrides[i]*(newshape[i]-1);                            
                    }
                }
                T[] newdata;
                if (size>0) {
                    newdata=mData[minIndex..maxIndex+1];
                } else {
                    newdata=null;
                }
                NArray!(T,rank2) res=NArray!(T,rank2)(newstrides,newshape,newStartIdx-minIndex,newdata,
                    flags & ~Flags.ShouldFreeData,newBase);
                return res;
            }
        }
        
        /// index assignement
        /// if array has rank 3 array[1,2,3]=4.0, array[1]=2Darray, array[1,Range(3,7)]=2Darray
        NArray!(T,rank-reductionFactor!(S)) opIndexAssign(U,S)(U val,
            S idx_tup)
        in{
            assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
            static assert(is(U==NArray!(T,rank-reductionFactor!(S)))||is(U==T),"invalid value type <"~U.stringof~"> in opIndexAssign");
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if (rank==reductionFactor!(S)){
                foreach(i,TT;S){
                    static if(is(TT==int)|is(TT==long)|is(TT==uint)|is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");                        
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndexAssign");
                } // else check done in opIndex...
            }
        }
        body{
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                index_type idx=mStartIdx;
                foreach(i,TT;S){
                    static assert(is(TT==int)|is(TT==long)|is(TT==uint)|is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    idx+=idx_tup[i]*mStrides[i];
                }
                data[idx]=val;
                return val;
            } else {
                auto subArr=opIndex(idx_tup);
                subArr[]=val;
            }
        }
                
        /// static array indexing (separted from opIndex as potentially less efficient)
        NArray!(T,rank-cast(int)staticArraySize!(S))arrayIndex(S)(S index){
            static assert(is(S:int[])|is(S:long[])|is(S:uint[])|is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArray!(S),"arrayIndex needs *static* arrays as input");
            const char[] loopBody=("auto res=opIndex("~arrayToSeq("index",cast(int)staticArraySize!(S))~");");
            mixin(loopBody);
            return res;
        }

        /// static array indexAssign (separted from opIndexAssign as potentially less efficient)
        NArray!(T,rank-cast(int)staticArraySize!(S))arrayIndexAssign(S,U)(U val,S index){
            static assert(is(S:int[])|is(S:long[])|is(S:uint[])|is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArray!(S),"arrayIndex needs *static* arrays as input");
            mixin("NArray!(T,rank-cast(int)staticArraySize!(S)) res=opIndexAssign(val,"~arrayToSeq("index",staticArraySize!(S))~");");
            return res;
        }
        
        /// copies the array;
        NArray opSliceAssign(S,int rank2)(NArray!(S,rank2) val)
        in { 
            static assert(rank2==rank,"assign operation should have same rank "~ctfe_i2a(rank)~"vs"~ctfe_i2a(rank2));
            assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
        }
        body {
            binary_op_str!("*aPtr0=cast(T)*bPtr0;",rank,T,S)(this,val);
            return this;
        }
        
        /// assign a scalar to the whole array with array[]=value;
        NArray opSliceAssign()(T val)
        in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
        body{
            mixin unary_op_str!("*aPtr0=val",rank,T);
            unary_op_str(this);
            return this;
        }
        
        /++
        + this sub iterator trades a little speed for more safety when used step by step.
        + For example instead of updating only the pointer or the starting point it updates the slice.
        + This is safe also to updates of the base array mData in the sense that each next/get
        + is done using the base array mData, not a local copy.
        + After an update in the base array a call to value is wrong, but next or get will set it correctly.
        + Dropping this (unlikely to be used) thing would speed up a little some things.
        +/
        static if (rank==1){
            struct SubView{
                NArray * baseArray;
                index_type stride; // invariant
                index_type iPos, iDim, iIdx;
                static SubView opCall(NArray *a, int axis=0)
                in { assert(axis==0); }
                body {
                    SubView res;
                    res.baseArray=a;
                    res.iPos=0;
                    res.stride=a.strides[axis];
                    res.iDim=a.shape[axis];
                    res.iIdx=a.startIdx;
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
                T value()
                in { assert(iPos<iDim); }
                body {
                    return baseArray.mData[iIdx];
                }
                void value(T val)
                in { assert(iPos<iDim); }
                body {
                    baseArray.mData[iIdx]=val;
                }
                T get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    iIdx+=(index-iIdx)*stride;
                    iPos=index;
                    return baseArray.mData[iIdx];
                }
                int opApply( int delegate(ref T) loop_body ) {
                    if (iPos<iDim){
                        T* pos= &(baseArray.mData[iIdx]);
                        for (index_type i=iPos;i!=iDim;++i){
                            if (auto r=loop_body(*pos)) return r;
                            pos+=stride;
                        }
                    }
                    return 0;
                }
                int opApply( int delegate(index_type,ref T) loop_body ) {
                    if (iPos<iDim){
                        T*pos= &(baseArray.mData[iIdx]);
                        for (index_type i=iPos;i!=iDim;i++){
                            if (auto r=loop_body(i,*pos)) return r;
                            pos+=stride;
                        }
                    }
                    return 0;
                }
            }
        } else {
            struct SubView{
                NArray * baseArray;
                NArray!(T,rank-1) view;
                index_type[2] subSlice;
                index_type iPos, iDim, stride;
                static SubView opCall(NArray *a, int axis)
                in { assert(0<=axis && axis<rank); }
                body {
                    index_type[rank-1] shape,strides;
                    int ii=0;
                    for(int i=0;i<rank;i++){
                        if (i!=axis){
                            shape[ii]=a.shape[i];
                            strides[ii]=a.strides[i];
                            ii++;
                        }
                    }
                    index_type startIdx;
                    if (a.strides[axis]>=0)
                        startIdx=a.startIdx;
                    else
                        startIdx=a.startIdx-(a.shape[axis]-1)*a.strides[axis];
                    index_type [2]subSlice=a.startIdx;
                    for (int i=0;i<rank-1;i++) {
                        if (shape[i]<1){
                            subSlice[1]=subSlice[0];
                            break;
                        }
                        if (strides[i]>=0)
                            subSlice[1]+=(shape[i]-1)*strides[i];
                        else
                            subSlice[0]+=(shape[i]-1)*strides[i];
                    }
                    SubView res;
                    res.baseArray=a;
                    res.subSlice[]=subSlice;
                    res.stride=a.strides[axis];
                    res.iPos=0;
                    res.iDim=a.shape[axis];
                    res.view=NArray!(T,rank-1)(strides,shape,startIdx-subSlice[0],
                        a.mData[subSlice[0]..subSlice[1]],
                        a.flags&~Flags.ShouldFreeData,a.newBase);
                    return res;
                }
                bool next(){
                    iPos++;
                    if (iPos<iDim){
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                        return true;
                    } else {
                        iPos=iDim;
                        return false;
                    }
                }
                NArray!(T,rank-1) value(){
                    return view;
                }
                void value(NArray!(T,rank-1) val){

                }
                NArray!(T,rank-1) get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    subSlice[0]+=(index-iPos)*stride;
                    subSlice[1]+=(index-iPos)*stride;
                    iPos=index;
                    view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                    return view;
                }
                int opApply( int delegate(NArray!(T,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim;i++){
                        if (auto r=loop_body(view)) return r;
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                    }
                    return 0;
                }
                int opApply( int delegate(int,NArray!(T,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim;i++){
                        if (auto r=loop_body(i,view)) return r;
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                    }
                    return 0;
                }
            }
        }
        
        /++ Iterates over the values of the array according to the current strides. 
         +  Usage is:  for(; !iter.end; iter.next) { ... } or (better and faster)
         +  foreach(v;iter) foreach(i,v;iter)
         +/
        struct flat_iterator{
            T* p;
            NArray baseArray;
            index_type [rank] left;
            index_type [rank] dims;
            index_type [rank] adds;
            static flat_iterator forward_iterate(ref NArray baseArray){
                flat_iterator res;
                res.baseArray=baseArray;
                res.left[]=baseArray.shape;
                res.p=baseArray.mData.ptr+baseArray.mStartIdx;
                foreach (s; baseArray.shape) {
                    if (s==0) {
                        res.left[]=0;
                        res.p=null;
                    }
                }
                res.adds[0]=baseArray.mStrides[0];
                for(int i=1;i<rank;i++){
                    res.adds[i]=baseArray.mStrides[i]-baseArray.mStrides[i-1]*(baseArray.shape[i-1]-1);
                }
                return res;
            }
            /// Advance to the next item.  Return false if there is no next item.
            bool next(){
                if (left[0]!=0){
                    left[0]-=1;
                    p+=adds[0];
                    return true;
                } else {
                    static if (rank==1){
                        p=null;
                        return false;
                    } else static if (rank==2){
                        if (left[1]!=0){
                            left[0]=baseArray.mShape[0];
                            left[1]-=1;
                            p+=adds[1];
                            return true;
                        } else {
                            p=null;
                            return false;
                        }
                    } else {
                        if (!p) return false; // remove?
                        left[0]=baseArray.mShape[0];
                        for (int i=1;i<rank;i++){
                            if (left[i]!=0){
                                left[i]-=1;
                                p+=adds[i];
                                return true;
                            } else{
                                left[i]=baseArray.mShape[i];
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
            void opSliceAssign(T v) { *p = v; }
            /// Advance to the next item.  Return false if there is no next item.
            bool opPostInc() {  return next(); }
            /// Return true if at the end, false otherwise.
            bool end() { return p is null; }
            /// Return the value at the current location of the iterator
            T value() { return *p; }
            /// Sets the value at the current location of the iterator
            void value(T val) { *p=val; }
            /// Return a pointer to the value at the current location of the iterator
            T* ptr() { return p; }
            /// Return the array over which this iterator is iterating
            NArray array() { return baseArray; }

            int opApply( int delegate(ref T) loop_body ) 
            {
                if (p is null) return 0;
                if (left!=baseArray.mShape){
                    for(;!end(); next()) {
                        int ret = loop_body(*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(*p);
                    if (ret) return ret;
                    `;
                    mixin(s_loopPtr(rank,["baseArray"],[],loopBody,"i"));
                }
                return 0;
            }
            int opApply( int delegate(index_type,ref T) loop_body ) 
            {
                if (p is null) return 0;
                if (left==baseArray.mShape) {
                    for(index_type i=0; !end(); next(),i++) {
                        int ret = loop_body(i,*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(iPos,*p);
                    if (ret) return ret;
                    ++iPos;
                    `;
                    index_type iPos=0;
                    mixin(s_loopPtr(rank,["baseArray"],[],loopBody,"i"));
                }
                return 0;
            }
        }
        
        /// returns an array that loops from the end toward the beginning of this array
        /// (returns a view, no data is copied)
        NArray reverse(){
            index_type[rank] newstrides;
            index_type newStartIdx=startIdx;
            for (int i=0;i<rank;++i){
                newStartIdx+=(mShape[i]-1)*mStrides[i];
                newstrides[i]=-mStrides[i];
            }
            return NArray(newstrides,mShape,newStartIdx,mData,
                flags&~Flags.ShouldFreeData,newBase);
        }
        
        /// applies an operation that "collects" data on an axis of the array
        /// this is basically a possibly parallel fold on the array along that axis
        /// foldOp(x,t) is the operations that accumulates on x the element t
        /// of the array, mergeOp(x,y) merges in x the two partial results x and y
        /// dupOp(x) is an operation that makes a copy of x (for simple types normally a nop)
        /// the folding starts with the corresponding element in the result array.
        /// If S==T normally mergeOp==foldOp
        void reduceAxis(alias foldOp, alias mergeOp,alias dupOp, S)(
            inout NArray!(S,rank-1) res, int axis=0)
        in {
            assert(0<=axis && axis<rank);
            int ii=0;
            for(int i=0;i<rank;i++){
                if(i!=axis){
                    assert(res.mShape[ii]==mShape[i],"invalid res shape");
                    ii++;
                }
            }
        } body {
            void myFold(ref S x0,T[] my_data, int my_stride, int my_dim, int my_start){
                S x=x0;
                index_type ii=my_start;
                for (int i=0;i<my_dim;i++){
                    foldOp(x,my_data[ii]);
                    ii+=my_stride;
                }
                x0=x;
            }
            static if (rank==1){
                myFold(res,mData,mStrides[0],mShape[0],mStartIdx);
            } else {
                int [rank-1] newstrides;
                {
                    int ii=0;
                    for(int i=0;i<rank;i++){
                        if(i!=axis){
                            newstrides[ii]=mStrides[i];
                            ii++;
                        }
                    }
                }
                NArray!(T,rank-1) tmp=NArray!(T,rank-1)(newstrides,res.mShape,mStartIdx,mData,
                    flags & ~Flags.ShouldFreeData);
                mixin(p_loopIdx(maxRank,["res","tmp"],[],
                    "myFold(res.mData[resIdx0],mData,tmpIdx0,mStrides[axis],mShape[axis]);\n","i"));
            }
        }
        
        /// fuses two arrays combining two axis of the same length with the given fuse op
        /// basically this is a generalized dot product of tensors
        void fuse1(alias fuseOp,S,int rank2,U)(
            NArray!(S,rank2) b, inout NArray!(U,rank+rank2-2) c, int axis1=-1, int axis2=0)
        in {
            assert(0<=axis1 && axis1<rank,"invalid axis1 in fuse1");
            assert(0<=axis2 && axis1<rank2,"invalid axis2 in fuse1");
            int ii=0;
            for(int i=0;i<rank;i++){
                if(i!=axis1){
                    assert(c.mShape[ii]==mShape[i],"invalid res shape");
                    ii++;
                }
            }
            for(int i=0;i<rank2;i++){
                if(i!=axis2){
                    assert(res.mShape[ii]==b.mShape[i],"invalid res shape");
                    ii++;
                }
            }
        } body {
            void myFuse(inout U x0,T[] my_data1, int my_stride1, int my_start1, 
                S[] my_data2, int my_stride2, int my_start2, int my_dim, int my_start){
                ii=my_start1;
                ij=my_start2;
                for (int i=0;i<my_dim;i++){
                    fuseOp(x0,my_data1[ii],my_data2[ij]);
                    ii+=my_stride1;
                    ij+=my_stride2;
                }
            }
            static if (rank2==1){
                static if (rank==1){
                    const char [] innerLoop=`myFuse(c,mData,mStrides[0],mStartIdx,b.mData[0],
                        b.mStrides[0],b.mStartIdx[0],mShape[0]);`;
                } else {
                    const char [] innerLoop=`myFuse(c[c1Idx],mData,mStrides[axis1],tmp1Idx,b.mData[0],
                        b.mStrides[0],b.mStartIdx[0],b.mShape[0]);`;
                }
            } else {
                int [rank2-1] newshape2,newstrides2,newstrides2c;
                {
                    int ii=0;
                    for(int i=0;i<rank2;i++){
                        if(i!=axis2){
                            newstrides2[ii]=b.mStrides[i];
                            newshape2[ii]=b.mShape[i];
                            ii++;
                        }
                    }
                    newstrides2c[]=c.mStrides[(rank-1)..(rank+rank2-2)];
                }
                NArray!(T,rank2-1) tmp2=NArray!(T,rank2-1)(newstrides2,newshape2,b.mStartIdx,null,b.flags & ~Flags.ShouldFreeData),
                    c2=NArray!(T,rank2-1)(newstrides2c,newshape2,0,null,c.flags & ~Flags.ShouldFreeData);
                const char [] innerLoop=p_loopIdx(maxRank,["tmp2","c2"],["","c1Idx0"],
                        "myFuse(c[c2Idx0],mData,mStrides[axis1],tmp1Idx0,b.mData[0],\n"~
                        "            b.mStrides[axis2],tmp2Idx0,mShape[axis1]);\n","j");
            }
            
            static if (rank==1) {
                int c1Idx=c.mStartIdx,t1Idx=mStartIdx;
                mixin(innerLoop);
            } else {
                int [rank-1] newshape1,newstrides1,newstrides1c;
                {
                    int ii=0;
                    for(int i=0;i<rank;i++){
                        if(i!=axis){
                            newstrides1[ii]=mStrides[i];
                            newshape1[ii]=mShape[i];
                            ii++;
                        }
                    }
                    newstrides1c[]=c.mStrides[0..rank-1];
                }
                NArray!(T,rank-1) tmp1=NArray!(T,rank-1)(newstrides1,newshape1,mStartIdx,null,flags & ~Flags.ShouldFreeData),
                    c1=NArray!(T,rank-1)(newstrides1c,newshape1,c.mStartIdx,null,flags& ~Flags.ShouldFreeData);
                mixin(p_loopIdx(maxRank,["tmp1","c1"],[],"mixin(innerLoop);\n","i"));
            }
        }
        
        /// Return a deep copy of the array, using the fastest possible method.
        /// A flag can be specified to force a particular memory ordering in the copy.
        /// Possible values are Flags.Fortran or Flags.Contiguous (C-style contiguous);
        NArray dup(bool fortran=false)
        {
            void cpVal(T a,out T b){
                b=a;
            }
            NArray res=empty(this.mShape,fortran);
            if ( flags & res.flags & (Flags.Fortran | Flags.Contiguous) ) 
            {
                // use memcpy, the easy & fast way
                memcpy(res.mData.ptr, mData.ptr, T.sizeof * mData.length);
            }
            else
            {
                binary_op_str!("*aPtr0=*bPtr0;",rank,T,T)(res,this);
            }
            return res;
        }
        

        // math ops
        // should the cast be removed from array opXxxAssign, and move out of the static if?
        
        static if (is(typeof(-T.init))) {
            /// Return a negated version of the array
            NArray opNeg() {
                NArray res=empty(mShape);
                binary_op_str!("*bPtr0=-(*aPtr0);",rank,T,T)(this,res);
                return res;
            }
        }

        static if (is(typeof(+T.init))) {
            /// Allowed as long as the underlying type has op pos
            /// But it always makes a full value copy regardless of whether the underlying unary+ 
            /// operator is a no-op.
            NArray opPos() {
                NArray res=empty(mShape);
                binary_op_str!("*bPtr0= +(*aPtr0);",rank,T,T)(this,res);
                return res;
            }
        }

        /// Add this array and another one and return a new array.
        NArray!(typeof(T.init+S.init),rank) opAdd(S)(NArray!(S,rank) o) { 
            NArray!(typeof(T.init+S.init),rank) res=NArray!(typeof(T.init+S.init),rank).empty(mShape);
            ternary_op_str!("*cPtr0=(*aPtr0)+(*bPtr0);",rank,T,S,typeof(T.init+S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(T.init+T.init))) {
            /// Add a scalar to this array and return a new array with the result.
            NArray!(typeof(T.init+T.init),rank) opAdd()(T o) { 
                NArray!(typeof(T.init+T.init),rank) res=NArray!(typeof(T.init+T.init),rank).empty(mShape);
                mixin binary_op_str!("*bPtr0 = (*aPtr0) * o;",rank,T,T);
                binary_op_str(this,res);
                return res;
            }
        }
        static if (is(typeof(T.init+T.init)==T)) {
            /// Add another array onto this one in place.
            NArray opAddAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binary_op_str!("*aPtr0 += cast(T)*bPtr0;",rank,T,S)(this,o);
                return this;
            }
            /// Add a scalar to this array in place.
            NArray opAddAssign()(T o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unary_op_str!("*aPtr0+=o;",rank,T);
                unary_op_str(this);
                return this;
            }            
        }

        /// Subtract this array and another one and return a new array.
        NArray!(typeof(T.init-S.init),rank) opSub(S)(NArray!(S,rank) o) { 
            NArray!(typeof(T.init-S.init),rank) res=NArray!(typeof(T.init-S.init),rank).empty(mShape);
            ternary_op_str!("*cPtr0=(*aPtr0)-(*bPtr0);",rank,T,S,typeof(T.init-S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(T.init-T.init))) {
            /// Subtract a scalar from this array and return a new array with the result.
            final NArray opSub()(T o) { 
                NArray res=empty(mShape);
                mixin binary_op_str!("*bPtr0=(*aPtr0)-o;",rank,T,T);
                binary_op_str(this,res);
                return res;
            }
        }
        static if (is(typeof(T.init-T.init)==T)) {
            /// Subtract another array from this one in place.
            NArray opSubAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binary_op_str!("*aPtr0 -= cast(T)*bPtr0;",rank,T,T)(this,o);
                return this;
            }
            /// Subtract a scalar from this array in place.
            NArray opSubAssign()(T o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unary_op_str!("*aPtr0-=o;",rank,T);
                unary_op_str(this);
                return this;
            }
        }

        /// Element-wise multiply this array and another one and return a new array.
        /// For matrix multiply, use the non-member dot(a,b) function.
        NArray!(typeof(T.init*S.init),rank) opMul(S)(NArray!(S,rank) o) { 
            NArray res=NArray!(typeof(T.init*S.init),rank).empty(mShape);
            ternary_op_str!("*cPtr0=(*aPtr0)*(*bPtr0);",rank,T,S,typeof(T.init*S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(T.init*T.init))) {
            /// Multiplies this array by a scalar and returns a new array.
            final NArray!(typeof(T.init*T.init),rank) opMul()(T o) { 
                NArray!(typeof(T.init*T.init),rank) res=NArray!(typeof(T.init*T.init),rank).empty(mShape);
                mixin binary_op_str!("*bPtr0=(*aPtr0)*o;",rank,T,typeof(T.init*T.init));
                binary_op_str(this,res);
                return res;
            }
        }
        
        static if (is(typeof(T.init*T.init)==T)) {
            /// Element-wise multiply this array by another in place.
            /// For matrix multiply, use the non-member dot(a,b) function.
            NArray opMulAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binary_op_str!("*aPtr0 *= cast(T)*bPtr0;",rank,T,typeof(T.init*T.init))(this,o);
                return this;
            }
            /// scales the current array.
            NArray opMulAssign()(T o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unary_op_str!("*aPtr0 *= o;",rank,T);
                unary_op_str(this);
                return this;
            }
        }

        /// Element-wise divide this array by another one and return a new array.
        /// To solve linear equations like A * x = b for x, use the nonmember linsolve
        /// function.
        NArray!(typeof(T.init/S.init),rank) opDiv(S)(NArray!(S,rank) o) { 
            NArray!(typeof(T.init/S.init),rank) res=NArray!(typeof(T.init/S.init),rank).empty(mShape);
            ternary_op_str!("*cPtr0=(*aPtr0)/(*bPtr0);",rank,T,S,typeof(T.init/S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(T.init/T.init))) {
            /// divides this array by a scalar and returns a new array with the result.
            NArray!(typeof(T.init/T.init),rank) opDiv()(T o) { 
                NArray!(typeof(T.init/T.init),rank) res=NArray!(typeof(T.init/T.init),rank).empty(mShape);
                mixin binary_op_str!("*bPtr0=(*aPtr0)/o;",rank,T,typeof(T.init/T.init));
                binary_op_str(this,res);
                return res;
            }
        }
        static if (is(typeof(T.init/T.init)==T)) {
            /// Element-wise divide this array by another in place.
            /// To solve linear equations like A * x = b for x, use the nonmember linsolve
            /// function.
            NArray opDivAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binary_op_str!("*aPtr0 /= cast(T)*bPtr0;",rank,T,S)(this,o);
                return this;
            }
            /// divides in place this array by a scalar.
            NArray opDivAssign()(T o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unary_op_str!("*aPtr0 /= o;",rank,T);
                unary_op_str(this);
                return this;
            }
        }
        
        /// Compare with another array for value equality
        bool opEquals(NArray o) { 
            if (mShape!=o.mShape) return false;
            if (flags & o.flags & Flags.Compact){
                return !memcmp(mData.ptr,o.mData.ptr,mData.length*T.sizeof);
            }
            mixin(s_loopPtr(rank,["","o"],[],"if (*Ptr0 != *oPtr0) return false;","i"));
            return true; 
        }

        /// Compare for ordering not allowed (do it lexicographically on rank, shape, and then 
        /// elements using the standard C ordering??)
        int opCmp(NArray o) { 
            assert(0, "Comparison of arrays not allowed");
            return 0; 
        }
        
        /// description of the NArray wrapper, not of the contents, for debugging purposes...
        Print!(char) desc(Print!(char)s){
            s("<NArray @:")(&this)(",").newline;
            s("  startIdx:")(mStartIdx)(",").newline;
            s("  strides:")(mStrides)(",").newline;
            s("  shape:")(mShape)(",").newline;
            s("  flags:")(flags)("=None");
            if (flags&Flags.Contiguous) s("|Contiguos");
            if (flags&Flags.Fortran) s("|Fortran");
            if (flags&Flags.Compact) s("|Compact");
            if (flags&Flags.Small) s("|Small");
            if (flags&Flags.Large) s("|Large");
            if (flags&Flags.ShouldFreeData) s("|ShouldFreeData");
            if (flags&Flags.ReadOnly) s("|ReadOnly");
            s(",").newline;
            s("  data: <array<")(T.stringof)("> @:")(mData.ptr)(", #:")(mData.length)(",").newline;
            s("  base:")(mBase).newline;
            s(">");
            return s;
        }
        
        /// returns the base for an array that is a view of the current array
        void *newBase(){
            void *res=mBase;
            if (flags&Flags.ShouldFreeData){
                assert(mBase is null,"if this array is the owner of the data it should not have base arrays");
                res=cast(void *)&this;
            }
            return res;
        }
        
        /// returns a view of the current data with the axes reordered
        NArray reorderAxis(int[rank] perm)
        in {
            foreach (i,iAxis;perm) {
                assert(0<=i && i<rank);
                foreach(iAxis2;perm[0..i])
                    assert(iAxis2!=iAxis);
            }
        }
        body {
            index_type[rank] newshape,newstrides;
            for (int i=0;i<rank;++i){
                newshape[i]=mShape[perm[i]];
            }
            for (int i=0;i<rank;++i){
                newstrides[i]=mStrides[perm[i]];
            }
            return NArray(newstrides,newshape,mStartIdx,mData,flags & ~Flags.ShouldFreeData,newBase);
        }

        static if (rank==2){
            /// transposed matrix
            NArray transpose(){
                return reorderAxis([1,0]);
            }
        }
        
        /// filters the array with a mask array. If allocSize>0 it is used for the initial allocation
        /// of the filtred array
        NArray!(T,1) filterMask(NArray!(bool,rank) mask, index_type allocSize=0)
        in { assert(mask.mShape==mShape); }
        body {
            index_type sz=1;
            foreach (d;mShape)
                sz*=d;
            int manualAlloc=sz*T.sizeof>manualAllocThreshold;
            T* res;
            T[] resA;
            size_t resSize=1;
            if (allocSize>0){
                resSize=allocSize;
            } else {
                if (mData.length<10) {
                    resSize=mData.length;
                } else {
                    index_type nTest=(10<mData.length)?10:mData.length;
                    for (index_type i=0;i<nTest;++i)
                        if(mask.mData[i]) ++resSize;
                    resSize=cast(size_t)(sqrt(cast(real)resSize/cast(real)(1+nTest))*mData.length);
                }
            }
            if (manualAlloc){
                res=cast(T*)calloc(resSize,T.sizeof);
            } else {
                resA=new T[resSize];
                res=resA.ptr;
            }
            T* resP=res, resEnd=res+resSize;
            
            index_type ii=0;
            
            const char[] loopInstr=`
            if (*maskPtr0){
                if (resP==resEnd)
                {
                    size_t newSize=min(resSize+mData.length/10,mData.length);
                    if(manualAlloc){
                        res=cast(T*)realloc(res,newSize);
                    } else {
                        resA.length=newSize;
                        res=resA.ptr;
                    }
                    resP=res+resSize;
                    resEnd=res+newSize;
                    resSize=newSize;
                }
                *resP=*Ptr0;
                ++resP;
            }`;
            mixin(s_loopPtr(rank,["","mask"],[],loopInstr,"i"));
            resSize=resP-res;
            if(manualAlloc){
                res=cast(T*)realloc(res,resSize);
                resA=res[0..resSize];
            } else {
                resA.length=resSize;
            }
            index_type[1] newshape,newstrides;
            newshape[0]=resSize;
            newstrides[0]=1;
            uint newflags=Flags.None;
            if (manualAlloc) newflags=Flags.ShouldFreeData;
            return NArray!(T,1)(newstrides,newshape,0,resA,newflags);
        }
        
        static if (rank==1){
            /// writes back the data to an array in the places where mask is true.
            /// if res is given it writes into res
            NArray!(T,rank2) unfilterMask(int rank2)(NArray!(bool,rank2) mask, NArray!(T,rank2)res=null)
            in{
                if (res !is null){
                    assert(res.mShape==mask.mShape);
                }
                index_type nEl=mask.reduceAll!((inout index_type x,bool r){ if (r) ++x; },
                    (inout index_type x,index_type y){ x+=y; },(index_type x){ return x; },
                    index_type)(0);
                assert(nEl<=mShape[0],"mask has more true elements than size of filtered array");
            }
            body {
                if (res is null){
                    res=NArray!(T,rank2).zeros(mask.shape);
                }
                T* elAtt=mData.ptr+mStartIdx;
                const char[] loopInstr=`
                if (*maskPtr0){
                    *resPtr0=*elAtt;
                    elAtt+=mStrides[0];
                }`;
                mixin(s_loopPtr!(rank2,["res","mask"],[],loopInstr,"i"));
                return res;
            }
        }
        
        /// increments a static index array, return true if it did wrap
        bool incrementArrayIdx(index_type[rank] index){
            int i=rank-1;
            while (i>=0) {
                ++index[i];
                if (index[i]<mShape[i]) break;
                index[i]=0;
                --i;
            }
            return i<0;
        }
        
    }
}// end static if
}// end template NArray

// convolution base in 2d
char[] convolveBase(char[] indent,bool istream_m=true, bool istream_z=true, bool istream_p=true,
        int jshift=0, int jmin=0, int jmax=3, int imin=0,int imax=3){
    char [] res="".dup;
    if (istream_m){
        res~=indent;
        res~="res[i-1,j]+=";
        bool shouldAdd=false;
        for (int i=2;i<imax;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c2"~ctfe_i2a(j)~"*a1"~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    if (istream_z){
        res~=indent;
        res~="res[i,j]+=";
        bool shouldAdd=false;
        for (int i=imin;i<imax;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c"~ctfe_i2a(i)~ctfe_i2a(j)~"*a"~ctfe_i2a(i)~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    if (istream_p){
        res~=indent;
        res~="res[i+1,j]+=";
        bool shouldAdd=false;
        for (int i=imin;i<2;++i){
            for (int j=jmin;j<jmax;++j){
                if (shouldAdd) res~="+";
                res~="c"~ctfe_i2a(i)~ctfe_i2a(j)~"*a"~ctfe_i2a(i+1)~ctfe_i2a((j+jshift)%3);
                shouldAdd=true;
            }
        }
        res~=";\n";
    }
    return res;
}

// inner convolution loop (for 2d convolve)
char[] convolveJLoop(char[] indent,int jrest=0,bool istream_m=true, bool istream_z=true, bool istream_p=true,int imin=0,int imax=3){
    char [] res="".dup;
    if (jrest<0){
        // no loop (few elements)
        for (int i=imin;i<imax;++i){
            for (int j=0;j<-jrest;++j){
                res~=indent;
                res~="res[i+("~ctfe_i2a(i)~"),jmin+("~ctfe_i2a(j)~")]+=";
                bool shouldAdd=false;
                for (int diff=-1;diff<2;++diff){
                    if (0<=j+diff && j+diff<-jrest){
                        if (shouldAdd) res~="+";
                        res~="c"~ctfe_i2a(i)~ctfe_i2a(1+diff)~
                            "*a[i+("~ctfe_i2a(i-1)~"),jmin+("~ctfe_i2a(j+diff)~")]";
                        shouldAdd=true;
                    }
                }
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j)~"=a[i+("~ctfe_i2a(i-1)~"),j+("~ctfe_i2a(j)~")];\n";
            } 
        }
    } else {
        // loop (>3 elements)
        res~=indent;
        res~="index_type j=jmin;\n";
        for (int i=imin;i<imax;++i){
            for (int j=0;j<2;++j){
                res~=indent;
                res~="a"~ctfe_i2a(i)~ctfe_i2a(j)~"=a[i+("~ctfe_i2a(i-1)~"),j+("~ctfe_i2a(j)~")];\n";
            } 
        }
        // set partial border
        res~=convolveBase(indent,istream_m,istream_z,istream_p,2,1,3,imin,imax);
        res~=indent;
        res~="while(j<jmax){\n";
        char[] indent2=indent~"    ";
        for (int jshift=0;jshift<3;++jshift){
            res~=indent2~"++j;\n";
            for (int i=imin;i<imax;++i){
                res~=indent2~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"=a[i+("~ctfe_i2a(i-1)~"),j+1];\n";
            }
            res~=convolveBase(indent2,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        res~=indent~"}\n";
        // jrest=(maxj-1)%3
        for (int jshift=0;jshift<jrest;++jshift){
            res~=indent~"++j;\n";
            for (int i=imin;i<imax;++i){
                res~=indent~"a"~ctfe_i2a(i)~ctfe_i2a(jshift)~"=a[i+("~ctfe_i2a(i-1)~"),j+1];\n";
            }
            res~=convolveBase(indent,istream_m,istream_z,istream_p,jshift,0,3,imin,imax);
        }
        // set partial border
        res~=indent~"++j;\n";
        res~=convolveBase(indent,istream_m,istream_z,istream_p,jrest,0,2,imin,imax);
        res~=indent~"assert(j==maxj);\n";
    }
    return res;
}

// outer loop for 2d convolve
char[] convolveILoop(char[]indent,int jrest,int irest){
    char [] res="".dup;
    if (irest<0){
        if (irest==-1) {
            res~=indent~"index_type i=imin;\n";
            res~=convolveJLoop(indent,jrest,false,true,false,1,2);
        } else if (irest==-2) {
            res~=indent~"index_type i=imin;\n";
            res~=convolveJLoop(indent,jrest,false,true,true,1,3);
        } else {
            assert(0,"explicit i loops with more than two streams not implemented");
        }
    } else {
        //first load
        res~=indent~"index_type i=imin;\n";
        res~=convolveJLoop(indent,jrest,false,false,true,1,3);
        // bulk calc
        res~=indent~"while (i<imax){\n";
        char[] indent2=indent~"    ";
        res~=indent2~"++i;\n";
        res~=convolveJLoop(indent2,jrest,true,true,true,0,3);
        res~=indent2~"++i;\n";
        res~=indent~"}\n";
        // final set
        res~=indent~"if (maxi>i){\n";
        res~=indent2~"++i;\n";
        res~=convolveJLoop(indent2,jrest,true,true,false,0,2);
        res~=indent~"}\n";
        res~=indent~"assert(maxi==i);\n";
    }
    return res;
}

/// operations to do before convolveIJ
const char[] preConvolveIJSetup=`
    index_type jmax=maxj-4;
    int jrest=(maxj-1-minj)%3;
    index_type imax=maxi-2;
    int ires=0;
    if(jmax<=jmin)
        jrest=-jrest;
    if (imax<=imin)
        ires=mini-maxi;
    int switchTag=10*ires+jrest;
    if (maxi<=mini || maxj<=minj){
        switchTag=-1000;
    }
    `;

/// 2d convolution with nearest neighbors
char[] convolveIJ(char[] indent){
    char[] res="".dup;
    res~=indent~"switch (switchTag)\n";
    char[] indent2=indent~"    ";
    foreach (ires;[-2,-1,0]){
        foreach (jres;[-4,-3,-2,-1,0,1,2]){
            res~=indent~"case "~ctfe_i2a(10*ires+jres)~":\n";
            res~=indent~"{\n";
            res~=convolveILoop(indent2,jres,ires);
            res~=indent~"}\n";
            res~=indent~"break;\n";
        }
    }
    res~=indent~"case(-1000) break;\n";
    res~=indent2~"default: assert(0);\n";
    res~=indent~"}\n";
    return res;
}
//pragma(msg,"----------");
//pragma(msg,convolveIJ("  "));
//pragma(msg,"==========");

/// adds an axis to the current array and repeats the current data along it
/// does not copy and returns a readonly (overlapping) version.
/// Use dup to have a vritable fully replicated version
/// note: putting this in the class forces the instantiation of NArray!(T,rank+1)
///       which then forces the instantiation of N+2 which...
NArray!(T,rank+1) repeat(T,rank)(NArray!(T,rank) a,index_type amount, int axis=0)
in {
    assert(0<=amount);
    assert(0<=axis && axis<rank+1,"axis out of bounds in repeat"); }
body {
    index_type[rank+1] newshape,newstrides;
    int ii=0;
    for (int i=0;i<rank;++i){
        if (i==axis) {
            newshape[ii]=amount;
            newstrides[ii]=0;
            ++ii;
        }
        newshape[ii]=a.mShape[i];
        newstrides[ii]=a.mStrides[i];
        ++ii;
    }
    return NArray!(T,rank+1)(newstrides,newshape,a.mStartIdx,a.mData,
        (a.flags & ~Flags.ShouldFreeData)|Flags.ReadOnly,a.newBase);
}

// looping/generic operations

/// applies an operation on all elements of the array. The looping order is arbitrary
/// and might be concurrent
void unary_op(alias op,int rank,T)(NArray!(T,rank) a){
    mixin(p_loopPtr(rank,["a"],[],"op(*aPtr0);\n","i"));
}
void unary_op_str(char[] op,int rank,T)(NArray!(T,rank) a){
    mixin(p_loopPtr(rank,["a"],[],op,"i"));
}

/// applies an operation combining the corresponding elements of two arrays.
/// The looping order is arbitrary and might be concurrent.
void binary_op(alias op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b)
in { assert(a.mShape==b.mShape,"incompatible shapes in binary_op"); }
body {
    mixin(p_loopPtr(rank,["a","b"],[],"op(*aPtr0,*bPtr0);\n","i"));
}

void binary_op_str(char[] op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b)
in { assert(a.mShape==b.mShape,"incompatible shapes in binary_op"); }
body {
    mixin(p_loopPtr(rank,["a","b"],[],op,"i"));
}

/// applies an operation combining the corresponding elements of three arrays .
/// The looping order is arbitrary and might be concurrent.
void ternary_op(alias op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c)
in { assert(a.mShape==b.mShape && a.mShape==c.mShape,"incompatible shapes in ternary_op"); }
body {
    mixin(p_loopPtr(rank,["a","b","c"],[],
        "op(*aPtr0,*bPtr0,*cPtr0);\n","i"));
}
void ternary_op_str(char[] op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c)
in { assert(a.mShape==b.mShape && a.mShape==c.mShape,"incompatible shapes in ternary_op"); }
body {
    mixin(p_loopPtr(rank,["a","b","c"],[],op,"i"));
}

/// returns a into shape the shape of the nested D array T
void calcShapeArray(T,uint rank)(T arr,index_type[rank] shape){
    static assert(rank==arrayRank!(T),"inconsistent rank/shape");
    static if (arrayRank!(T)>0) {
        shape[0]=arr.length;
        static if (arrayRank!(T)>1){
            calcShapeArray(arr[0],shape[1..$]);
        }
    }
}

/// checks that the D array arr is rectangular and has the shape in shape
private void checkShape(T,uint rank)(T arr,index_type[rank] shape){
    static assert(rank==arrayRank!(T),"inconsistent rank/shape");
    static if (arrayRank!(T)>0) {
        assert(shape[0]==arr.length,"array does not match shape (non rectangular?)");
        static if (arrayRank!(T)>1){
            foreach(subArr;arr)
                calcShapeArray(subArr,shape[1..$]);
        }
    }
}

/// returns a D array indexed with the variables of a p_loop_genIdx or s_loop_genIdx
char[] arrayInLoop(char[] arrName,int rank,char[] ivarStr){
    char[] res="".dup;
    res~=arrName;
    for (int i=0;i<rank;++i)
        res~="["~ivarStr~"_"~ctfe_i2a(i)~"_]";
    return res;
}

/++
+ converts the given array to an NArray.
+ The array has to be rectangular.
+ note: this put all the indexes of the array arr in the inner loop, not so efficient with many dimensions
+/
NArray!(arrayBaseT!(T),cast(int)arrayRank!(T)) a2NA(T)(T arr)
in {
    index_type[arrayRank!(T)] shape;
    calcShapeArray(arr,shape);
    checkShape(arr,shape);
}
body{
    const int rank=arrayRank!(T);
    index_type[rank] shape;
    calcShapeArray(arr,shape);
    auto res=NArray!(arrayBaseT!(T),cast(int)arrayRank!(T)).empty(shape);
    const char[] loop_body="*(resBasePtr+resIdx0)="~arrayInLoop("arr",rank,"i")~";";
    mixin(p_loop_genIdx(rank,["res"],[],loop_body,"i"));
    return res;
}

/// returns the minimum number of significand bits in common between this array and b
int minFeqrel(T,int rank)(NArray!(T,rank) a,NArray!(T,rank) b)
in { assert(b.mShape==mShape,"array need to have the same size in minFeqrel"); }
body {
    int minEq=feqrel(T.init,T.init);
    mixin(s_loopPtr(rank,["a","b"],[],
        "int diffAtt=feqrel(*aPtr0,*bPtr0); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}
/// returns the minimum number of significand bits in common between this array and b
int minFeqrel(T,int rank)(NArray!(T,rank) a,T b=cast(T)0){
    int minEq=feqrel(T.init,T.init);
    mixin(s_loopPtr(rank,["a"],[],
        "int diffAtt=feqrel(*aPtr0,b); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/+ -------- TESTS ------- +/
/// returns a NArray indexed with the variables of a p_loop_genIdx or s_loop_genIdx
char[] NArrayInLoop(char[] arrName,int rank,char[] ivarStr){
    char[] res="".dup;
    res~=arrName~"[";
    for (int i=0;i<rank;++i) {
        res~=ivarStr~"_"~ctfe_i2a(i)~"_";
        if (i!=rank-1)
            res~=", ";
    }
    res~="]";
    return res;
}

void checkLoop1(T,int rank)(NArray!(T,rank) a){
    {
        mixin(p_loop_genIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"p_loop_genIdx looping1 failed\");","i"));
    }
    {
        mixin(s_loop_genIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"s_loop_genIdx looping1 failed\");","i"));
    }
    {
        mixin(s_loop_genIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"s_loop_genPtr looping1 failed\");","i"));
    }
    index_type[rank] iPos;
    const char[] loopBody1=`
    assert(!did_wrap,"counter wrapped");
    assert(a.arrayIndex(iPos)==*aPtr0,"s_loopPtr failed");
    did_wrap=a.incrementArrayIdx(iPos);
    `;
    {
        bool did_wrap=false;
        iPos[]=cast(index_type)0;
        mixin(s_loopPtr(rank,["a"],[],loopBody1,"i"));
        assert(did_wrap,"incomplete loop");
    }
    const char[] loopBody2=`
    assert(!did_wrap,"counter wrapped");
    assert(a.arrayIndex(iPos)==*(aBasePtr+aIdx0),"s_loopIdx looping failed");
    did_wrap=a.incrementArrayIdx(iPos);
    `;
    {
        bool did_wrap=false;
        iPos[]=cast(index_type)0;
        pragma(msg,s_loopIdx(rank,["a"],[],loopBody2,"i"));
        mixin(s_loopIdx(rank,["a"],[],loopBody2,"i"));
        assert(did_wrap,"incomplete loop");
    }
}

unittest{
    NArray!(int,1) a1=a2NA([1,2,3,4,5,6]);
    NArray!(int,1) a2=NArray!(int,1).zeros([6]);
    auto a3=NArray!(int,2).zeros([5,6]);
    auto a4=NArray!(int,3).zeros([2,3,4]);
    assert(a1!=a2,"should be different");
    a2[]=a1;
    assert(a1==a2,"should be equal");
    checkLoop1(a1);
    checkLoop1(a2);
    checkLoop1(a3);
    checkLoop1(a4);
    auto a5=a3[1,Range(0,6,2)];
    a5[]=a1[Range(0,3)];
    Stdout("a5:")(a5).newline;
}