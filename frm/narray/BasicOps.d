/*******************************************************************************
    Basic Operations on NArrays.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.narray.BasicOps;
import frm.narray.BasicTypes;
import frm.TemplateFu;
import tango.math.Math: round;
import frm.rtest.RTest;
import tango.math.IEEE: feqrel;

template nullNArray(T,int rank){
    static if (rank>0){
        const NArray!(T,rank) nullNArray=null;
    } else {
        const T nullNArray=T.init;
    }
}
/+ ---------------- structural ops -------------------- +/

/// returns a view of the current data with the axes reordered
NArray!(T,rank) reorderAxis(T,int rank,int r2)(NArray!(T,rank) a,int[r2] perm)
in {
    static assert(rank==r2,"array rank and permutation must have the same size");
    foreach (i,iAxis;perm) {
        assert(0<=i && i<rank);
        foreach(iAxis2;perm[0..i])
            assert(iAxis2!=iAxis);
    }
}
body {
    index_type[rank] newshape,newstrides;
    for (int i=0;i<rank;++i){
        newshape[i]=a.mShape[perm[i]];
    }
    for (int i=0;i<rank;++i){
        newstrides[i]=a.mStrides[perm[i]];
    }
    return NArray!(T,rank)(newstrides,newshape,a.mStartIdx,a.mData,a.newFlags,a.newBase);
}

/// transposed view
NArray!(T,rank) transpose(T,int rank)(NArray!(T,rank) a){
    return a.T;
}

/// returns an array that loops from the end toward the beginning of this array
/// (returns a view, no data is copied)
NArray!(T,rank) reverse(T,int rank)(NArray!(T,rank) a){
    index_type[rank] newstrides;
    index_type newStartIdx=a.startIdx;
    for (int i=0;i<rank;++i){
        newStartIdx+=(a.mShape[i]-1)*a.mStrides[i];
        newstrides[i]=-a.mStrides[i];
    }
    return NArray(newstrides,a.mShape,newStartIdx,a.mData,a.newFlags,a.newBase);
}

/// adds an axis to the current array and repeats the current data along it
/// does not copy and returns a readonly (overlapping) version if amount>1.
/// Use dup to have a vritable fully replicated version
/// note: putting this in the class forces the instantiation of NArray!(T,rank+1)
///       which then forces the instantiation of N+2 which...
NArray!(T,rank+1) repeat(T,rank)(NArray!(T,rank) a,index_type amount, int axis=0)
in {
    assert(0<=amount);
    assert(-rank-1<=axis && axis<rank+1,"axis out of bounds in repeat"); }
body {
    if (axis<0) axis+=rank+1;
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
    uint newflags=a.newFlags;
    if (amount>1) newflags|=Flags.ReadOnly;
    return NArray!(T,rank+1)(newstrides,newshape,a.mStartIdx,a.mData,
        newflags,a.newBase);
}

/// changes the dimensions and rank of the array.
/// no elements can be thrown away (sizes must match).
/// if the present array is not 1D or contiguous this operation returns a copy.
/// fortran returns fortran ordering wrt. to flat iterator (i.e. to C-style looping)
/// thus fortran=true with a fortran matrix a returns a fortran ordered transpose of it.
NArray!(T,newRank) reshape(T,int rank,int newRank)(NArray!(T,rank) a,int[newRank] newshape,bool fortran=false) {
    static if (newRank==rank) {
        if (newshape == m_shape) return this;
    }
    index_type newsize = 1;
    index_type aSize = a.size();
    int autosize = -1;
    index_type[newRank] newstrides;
    foreach(i,val; newshape) {
        if (val<0) {
            assert(autosize==-1,"Only one shape dimension can be automatic");
            autosize = i;
        } else {
            newsize *= val;
        }
    }
    index_type[newRank] ns=newshape;
    if (autosize!=-1) {
        ns[autosize] = aSize/newsize;
        newsize *= ns[autosize];
    }
    assert(newsize==aSize,"reshape cannot change the size of the array");
    
    index_type sz=1;
    static if (rank==1){
        sz=a.mStrides[0];
    }
    if (fortran){
        foreach(i, d; ns) {
            newstrides[i] = sz;
            sz *= d;
        }
    } else {
        foreach_reverse(i, d; ns) {
            newstrides[i] = sz;
            sz *= d;
        }
    }
    static if (rank==1) {
        return NArray!(T,newRank)(newstrides,ns,a.startIdx,a.mData,a.newFlags,a.newBase);
    } else {
        if (m.mFlags&Flags.Contiguous) {
            return NArray!(T,newRank)(newstrides,ns,0,a.mData,a.newFlags,a.newBase);
        } else {
            // copy data to contiguous mem first.
            NArray cpy = this.dup;
            T[] newData=cpy.mData;
            uint newF=cpy.flags;
            // Steal new array's data (do as with slices without really stealing the data?)
            cpy.mData = null;
            return NArray!(T,newRank)(newstrides,ns,0,newData,null,newF);
        }
    }
}

/// diagonal view
NArray!(T,1)diag(T,int rank)(NArray!(T,rank)a)
in {
    static assert(rank>1,"rank must be at least 2");
    for (int i=0;i<rank;++i) assert(a.mShape[0]==a.mShape[i],"a must be square");
}
body {
    index_type inc=0;
    for (int i=0;i<rank;++i) inc+=a.shape[i];
    index_type[1] newstrides=inc,newshape=a.mShape[0];
    return NArray!(T,1)(newstrides,newshape,a.mStartIdx,a.mData,a.newFlags,a.newBase);
}
/+ --------- array creation ---------- +/
/// rank of NArray for the given shape (for empty,zeros,ones)
/// more flexible than member function, accepts int/long, int/long static array
template rkOfShape(T){
    static if(isStaticArray!(T)){
        static assert(is(arrayBaseT!(T)==int)||is(arrayBaseT!(T)==uint)||
            is(arrayBaseT!(T)==long)||is(arrayBaseT!(T)==ulong),
            "only integer types supported as shape dimensions");
        const int rkOfShape = cast(int)staticArraySize!(T);
    } else {
        static assert(is(T==int)||is(T==uint)||is(T==long)||is(T==ulong),
            "only integer types supported as dimensions");
        const int rkOfShape = 1;
    }
}

/// function to create free standing empty,zeros,ones
char[] freeFunMixin(char[] opName){
    char[] res="".dup;
    res~="template "~opName~"(V){\n";
    res~="    template "~opName~"(T){\n";
    res~="        NArray!(V,rkOfShape!(T))"~opName~"(T shape, bool fortran=false){\n";
    res~="            static if (isStaticArray!(T)){\n";
    res~="                static if(is(arrayBaseT!(T)==index_type)) {\n";
    res~="                    return NArray!(V,rkOfShape!(T))."~opName~"(shape);\n";
    res~="                } else {\n";
    res~="                    index_type[arrayRank!(T)] s;\n";
    res~="                    for (int i=0;i<shape;++i)\n";
    res~="                        s[i]=cast(index_type)shape[i];\n";
    res~="                    return NArray!(V,rkOfShape!(T))."~opName~"(s);\n";
    res~="                }\n";
    res~="            } else {\n";
    res~="                index_type[1] s;\n";
    res~="                s[0]=cast(index_type) shape;\n";
    res~="                return NArray!(V,rkOfShape!(T))."~opName~"(s);\n";
    res~="            }\n";
    res~="        }\n";
    res~="    }\n";
    res~="}\n";
    return res;
}

/// returns an uninitialized NArray of type V and the requested shape
/// it is useful to alias empty!(double) emptyD; and then emptyD([10,3]) creates a 10,3 NArray
mixin(freeFunMixin("empty"));
/// returns an NArray of 0 of type V and the requested shape
/// it is useful to alias zeros!(double) zerosD; and then zerosD([10,3]) creates a 10,3 NArray
mixin(freeFunMixin("zeros"));
/// returns an NArray of 1 of type V and the requested shape
/// it is useful to alias zeros!(double) zerosD; and then zerosD([10,3]) creates a 10,3 NArray
mixin(freeFunMixin("ones"));
/// returns a 1d array with numbers from to up to to (not included)
NArray!(T,1) arange(T)(T to){
    return arange(cast(T)0,to);
}
/// returns an array with numbers from from to to (not included) with steps step
/// for floating point numbers returns round((to-from+(step/2))/step) numbers
/// for integers returns (to-from+step-sign(step))/step numbers, numerical roundig aside the
/// behavious should be the same.
NArray!(T,1) arange(T)(T from, T to, T step=cast(T)1){
    assert(step!=0,"step cannot be 0");
    index_type n;
    static if ((cast(T)1)/(cast(T)2)==cast(T)0) { // integer type
        if (step>0)
            n=(to-from+step-1)/step;
        else
            n=(to-from+step+1)/step;
    } else {
        n=cast(index_type)round((to-from+(step/2))/step);
    }
    NArray!(T,1) res=NArray!(T,1).empty([n]);
    T x=from;
    const char[] loopBody=`
    *resPtr0=x;
    x+=step;`;
    mixin(sLoopPtr(1,["res"],[],loopBody,"i"));
    return res;
}

/// unity matrix of dimension dim x dim
NArray!(T,2)eye(T)(index_type dim){
    NArray!(T,2) res=NArray!(T,2).zeros([dim,dim]);
    scope d=diag(res);
    d=cast(T)1;
    return res;
}

/++
+ converts the given array to an NArray.
+ The array has to be rectangular.
+ note: this put all the indexes of the array arr in the inner loop, not so efficient with many dimensions
+/
NArray!(arrayBaseT!(T),cast(int)arrayRank!(T))a2NA(T)(T arr,bool fortran=false){
    return a2NAof!(arrayBaseT!(T))(arr,fortran);
}

template a2NAof(V){
    template a2NAof(T){
        NArray!(V,cast(int)arrayRank!(T))a2NAof(T arr,bool fortran=false)
        in {
            index_type[arrayRank!(T)] shape;
            calcShapeArray!(T,arrayRank!(T))(arr,shape);
            checkShape!(T,arrayRank!(T))(arr,shape);
        }
        body{
            const int rank=arrayRank!(T);
            index_type[rank] shape;
            calcShapeArray!(T,arrayRank!(T))(arr,shape);
            auto res=NArray!(V,cast(int)arrayRank!(T)).empty(shape,fortran);
            const char[] loop_body="*(resBasePtr+resIdx0)=cast(V)"~arrayInLoop("arr",rank,"i")~";";
            mixin(pLoopGenIdx(rank,["res"],[],loop_body,"i"));
            return res;
        }
    }
}

/// returns a into shape the shape of the nested D array T (for a2NA)
void calcShapeArray(T,uint rank)(T arr,index_type[] shape){
    static assert(rank==arrayRank!(T),"inconsistent rank/shape");
    assert(shape.length==rank,"shape array has wrong size");
    static if (arrayRank!(T)>0) {
        shape[0]=arr.length;
        static if (arrayRank!(T)>1){
            calcShapeArray!(typeof(arr[0]),rank-1)(arr[0],shape[1..$]);
        }
    }
}

/// checks that the D array arr is rectangular and has the shape in shape (for a2NA)
private void checkShape(T,uint rank)(T arr,index_type[] shape){
    static assert(rank==arrayRank!(T),"inconsistent rank/shape");
    assert(shape.length==rank,"shape array has wrong size");
    static if (arrayRank!(T)>0) {
        assert(shape[0]==arr.length,"array does not match shape (non rectangular?)");
        static if (arrayRank!(T)>1){
            foreach(subArr;arr)
                calcShapeArray!(typeof(arr[0]),rank-1)(subArr,shape[1..$]);
        }
    }
}

/// returns a D array indexed with the variables of a pLoopGenIdx or sLoopGenIdx (for a2NA)
char[] arrayInLoop(char[] arrName,int rank,char[] ivarStr){
    char[] res="".dup;
    res~=arrName;
    for (int i=0;i<rank;++i)
        res~="["~ivarStr~"_"~ctfe_i2a(i)~"_]";
    return res;
}

/+ ------------------------------ +/

/+ ------------------- folding (reduction) ops -------------------- +/

/// applies an operation that "collects" data on the whole array
/// this is basically a possibly parallel fold on the flattened array
/// foldOp(x,t) is the operations that accumulates on x the element t
/// of the array, mergeOp(x,y) merges in x the two partial results x and y
/// dupOp(x) is an operation that makes a copy of x (for simple types normally a nop)
/// the folding starts with the element x0, if S==T normally mergeOp==foldOp
S reduceAll(alias foldOp,alias mergeOp, alias dupOp,T,int rank,S)(NArray!(T,rank)a,S x0){
    S x=dupOp(x0);
    mixin(sLoopPtr(rank,["a"],"foldOp(x,*(aPtr0));\n"));
    mergeOp(x,x0);  /+ just to test it +/
    return x;
}

/// applies an operation that "collects" data on an axis of the array
/// this is basically a possibly parallel fold on the array along that axis
/// foldOp(x,t) is the operations that accumulates on x the element t
/// of the array, mergeOp(x,y) merges in x the two partial results x and y
/// dupOp(x) is an operation that makes a copy of x (for simple types normally a nop)
/// the folding starts with the corresponding element in the result array.
/// If S==T normally mergeOp==foldOp
NArray!(S,rank-1) reduceAxis(alias foldOp, alias mergeOp,alias dupOp, int rank, T, S=T)
    (NArray!(T,rank)a, int axis=-1, NArray!(S,rank-1) res=nullNArray!(S,rank-1))
in {
    assert(-rank<=axis && axis<rank,"axis out of bounds");
    int ii=0;
    if (res !is null){
        for(int i=0;i<rank;i++){
            if(i!=axis && i!=rank+axis){
                assert(res.mShape[ii]==a.mShape[i],"invalid res shape");
                ii++;
            }
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
    if (axis<0) axis+=rank;
    if (res is null){
        index_type[rank-1] newshape;
        int ii=0;
        for(int i=0;i<rank;i++){
            if(i!=axis && i!=rank+axis){
                newshape[ii]=a.mShape[i];
                ii++;
            }
        }
        res=NArray!(S,rank-1).empty(newshape);
    }
    static if (rank==1){
        myFold(res,a.mData,a.mStrides[0],a.mShape[0],a.mStartIdx);
    } else {
        int [rank-1] newstrides;
        {
            int ii=0;
            for(int i=0;i<rank;i++){
                if(i!=axis){
                    newstrides[ii]=a.mStrides[i];
                    ii++;
                }
            }
        }
        scope NArray!(T,rank-1) tmp=NArray!(T,rank-1)(newstrides,res.mShape,a.mStartIdx,a.mData,
            newFlags);
        mixin(pLoopIdx(rank-1,["res","tmp"],[],
            "myFold(res.mData[resIdx0],mData,tmpIdx0,mStrides[axis],mShape[axis]);\n","i"));
    }
    return res;
}

/// sum of the whole array
T sumAll(T,int rank)(NArray!(T,rank)a){
    return reduceAll((ref T x,T y){x+=y;},(ref T x,T y){x+=y;}, (ref T x,T y){x=cast(T)0;},
        T, rank,T)(a,cast(T)0);
}
/// sum along an axis of the array
NArray!(T,rank-1) sumAxis(T,int rank,S=T)(NArray!(T,rank)a,int axis=-1,NArray!(S,rank-1) res=null)
{
    reduceAxis((ref T x,T y){x+=y;},(ref T x,T y){x+=y;}, (ref T x,T y){x=cast(T)0;},
        T, rank,S)(a,axis,res);
}

/// multiplies of the whole array
T multiplyAll(T,int rank)(NArray!(T,rank)a){
    return reduceAll((ref T x,T y){x*=y;},(ref T x,T y){x*=y;}, (ref T x,T y){x=cast(T)1;},
        T, rank,T)(a,cast(T)1);
}
/// sum along an axis of the array
NArray!(T,rank-1) multiplyAxis(T,int rank,S=T)(NArray!(T,rank)a,int axis=-1,NArray!(S,rank-1) res=null)
{
    reduceAxis((ref T x,T y){x*=y;},(ref T x,T y){x*=y;}, (ref T x,T y){x=cast(T)1;},
        T, rank,S)(a,axis,res);
}

/// fuses two arrays combining two axis of the same length with the given fuse op
/// basically this is a generalized dot product of tensors
/// implements a simple streaming algorithm (some blocking in the x direction would 
/// be a natural extension)
void fuse1(alias fuseOp,alias inOp, alias outOp, T,int rank1,S,int rank2,U)(NArray!(S,rank1) a,
    NArray!(S,rank2) b, inout NArray!(U,rank1+rank2-2) c, int axis1=-1, int axis2=0)
in {
    static assert(rank1>0,"rank1 should be at least 1");
    static assert(rank2>0,"rank2 should be at least 1");
    assert(-rank1<=axis1 && axis1<rank1,"invalid axis1 in fuse1");
    assert(-rank2<=axis2 && axis2<rank2,"invalid axis2 in fuse1");
    assert(a.mShape[((axis1<0)?(rank1+axis1):axis1)]==b.mShape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
    static if(rank1+rank2>2){
        int ii=0;
        for(int i=0;i<rank1;i++){
            if(i!=axis1 && i!=axis1+rank1){
                assert(c.mShape[ii]==a.mShape[i],"invalid c shape");
                ii++;
            }
        }
        for(int i=0;i<rank2;i++){
            if(i!=axis2 && i!=rank2+axis2){
                assert(c.mShape[ii]==b.mShape[i],"invalid c shape");
                ii++;
            }
        }
    }
} body {
    void myFuse(U* x0,T[] my_data1, int my_stride1, int my_start1, 
        S[] my_data2, int my_stride2, int my_start2, int my_dim){
        T*yPtr=my_data1.ptr+my_start1;
        S*zPtr=my_data2.ptr+my_start2;
        U xVal;
        inOp(x0,xVal);
        for (int i=0;i<my_dim;i++){
            fuseOp(xVal,*yPtr,*zPtr);
            yPtr+=my_stride1;
            zPtr+=my_stride2;
        }
        outOp(x0,xVal);
    }
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    static if (rank2==1){
        static if (rank1==1){
            myFuse(&c,a.mData,a.mStrides[0],a.mStartIdx,b.mData,
                b.mStrides[0],b.mStartIdx,a.mShape[0]);
        } else {
            const char [] innerLoop=`myFuse(cBasePtr+c1Idx0,a.mData,a.mStrides[axis1],tmp1Idx0,b.mData,
                b.mStrides[0],b.mStartIdx,b.mShape[0]);`;
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
            newstrides2c[]=c.mStrides[(rank1-1)..(rank1+rank2-2)];
        }
        scope NArray!(T,rank2-1) tmp2=NArray!(T,rank2-1)(newstrides2,newshape2,b.mStartIdx,null,b.newFlags),
            c2=NArray!(T,rank2-1)(newstrides2c,newshape2,0,null,c.newFlags);
        const char [] innerLoop=pLoopIdx(rank2-1,["tmp2","c2"],["","c1Idx0"],
                "myFuse(cBasePtr+c2Idx0,a.mData,a.mStrides[axis1],tmp1Idx0,b.mData,\n"~
                "            b.mStrides[axis2],tmp2Idx0,a.mShape[axis1]);\n","j");
    }
    
    static if (rank1==1) {
        static if (rank2>1){
            S *cBasePtr=c.mData.ptr;
            int c1Idx0=c.mStartIdx,tmp1Idx0=a.mStartIdx;
            mixin(innerLoop);
        }
    } else {
        int [rank1-1] newshape1,newstrides1,newstrides1c;
        {
            int ii=0;
            for(int i=0;i<rank1;i++){
                if(i!=axis1){
                    newstrides1[ii]=a.mStrides[i];
                    newshape1[ii]=a.mShape[i];
                    ii++;
                }
            }
            newstrides1c[]=c.mStrides[0..rank1-1];
        }
        scope NArray!(T,rank1-1) tmp1=NArray!(T,rank1-1)(newstrides1,newshape1,a.mStartIdx,null,a.newFlags),
            c1=NArray!(T,rank1-1)(newstrides1c,newshape1,c.mStartIdx,null,a.newFlags);
        S *cBasePtr=c.mData.ptr;
        mixin(pLoopIdx(rank1-1,["tmp1","c1"],[],"mixin(innerLoop);\n","i"));
    }
}

// ------------------ filter ops ------------------

/// filters the array with a mask array. If allocSize>0 it is used for the initial allocation
/// of the filtred array
NArray!(T,1) filterMask(T,int rank)(NArray!(T,rank) a,NArray!(bool,rank) mask, index_type allocSize=0)
in { assert(mask.mShape==a.mShape); }
body {
    index_type sz=1;
    foreach (d;a.mShape)
        sz*=d;
    int manualAlloc=sz*T.sizeof>manualAllocThreshold || allocSize*T.sizeof>manualAllocThreshold;
    T* res;
    T[] resA;
    size_t resSize=1;
    if (allocSize>0){
        resSize=allocSize;
    } else {
        if (a.mData.length<10) {
            resSize=a.mData.length;
        } else {
            index_type nTest=(10<a.mData.length)?10:a.mData.length;
            for (index_type i=0;i<nTest;++i)
                if(mask.mData[i]) ++resSize;
            resSize=cast(size_t)(sqrt(cast(real)resSize/cast(real)(1+nTest))*a.mData.length);
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
            size_t newSize=min(resSize+a.mData.length/10,a.mData.length);
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
        *resP=*aPtr0;
        ++resP;
    }`;
    mixin(sLoopPtr(rank,["a","mask"],[],loopInstr,"i"));
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

/// writes back the data to an array in the places where mask is true.
/// if res is given it writes into res
NArray!(T,rank2) unfilterMask(T,int rank2)(NArray!(T,1) a,NArray!(bool,rank2) mask, NArray!(T,rank2)res=null)
in{
    if (res !is null){
        assert(res.mShape==mask.mShape);
    }
    index_type nEl=reduceAll!((inout index_type x,bool r){ if (r) ++x; },
        (inout index_type x,index_type y){ x+=y; },(index_type x){ return x; },
        T,rank2,index_type)(mask,0);
    assert(nEl<=a.mShape[0],"mask has more true elements than size of filtered array");
}
body {
    if (res is null){
        res=NArray!(T,rank2).zeros(mask.shape);
    }
    T* elAtt=a.mData.ptr+a.mStartIdx;
    const char[] loopInstr=`
    if (*maskPtr0){
        *resPtr0=*elAtt;
        elAtt+=mStrides[0];
    }`;
    mixin(sLoopPtr!(rank2,["res","mask"],[],loopInstr,"i"));
    return res;
}

/// returns the reduction of the rank done by the arguments in the tuple
/// allow also static arrays?
template reductionFactorFilt(){
    const int reductionFactorFilt=0;
}
/// ditto
template reductionFactorFilt(T,S...){
    static if (is(T==int) || is(T==long)||is(T==uint)||is(T==ulong)){
        const int reductionFactorFilt=1+reductionFactorFilt!(S);
    } else static if (is(T==Range)){
        const int reductionFactorFilt=reductionFactorFilt!(S);
    } else static if (is(T:int[])||is(T:long[])||is(T:uint[])||is(T:ulong[])){
        const int reductionFactorFilt=reductionFactorFilt!(S);
    } else static if (is(T==NArray!(long,1))||is(T==NArray!(uint,1))||is(T==NArray!(ulong,1))){
        const int reductionFactorFilt=reductionFactorFilt!(S);
    } else {
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactorFilt, this will fail");
    }
}

NArray!(T,rank-reductionFactorFilt!(S)) arrayAxisFilter(T,int rank,S...)(NArray!(T,rank) a,S idx_tup)
{
    const int rank2=rank-reductionFactorFilt!(S);
    index_type from,to,step;
    index_type[rank2] newshape;
    int ii=0;
    foreach(i,U;S){
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            mixin("index_type j"~ctfe_i2a(i)~"=idx_tup["~ctfe_i2a(i)~"]*a.strides["~ctfe_i2a(i)~"];");
        } else static if (is(U==Range)){
            from=idx_tup[i].from;
            to=idx_tup[i].to;
            step=idx_tup[i].inc;
            if (from<0) from+=a.mShape[i];
            if (to<0) to+=a.mShape[i]+1;
            if (from<to && step>=0 || from>to && step<0){
                assert(0<=from && from<a.mShape[i],
                    "invalid lower range for dimension "~ctfe_i2a(i));
                if (step==0)
                    to=a.mShape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.mShape[i],
                    "invalid upper range for dimension "~ctfe_i2a(i));
            }
            newshape[ii]=(to-from)/inc;
            ++ii;
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            newshape[ii]=idx_tup[i].length;
            ++ii;
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            newshape[ii]=idx_tup[i].mShape[0];
            ++ii;
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in reductionFactorFilt, this will fail");
        }
    }
    for (int i=rank2-ii;i>0;--i){
        newshape[rank2-i]=a.mShape[rank-i];
    }
    return NArray!(T,rank2).empty(newshape);
}

char[] axisFilterLoop(T,int rank,S...)(char[] loopBody)
{
    char[] res="".dup;
    char[] indent="    ".dup;
    const int rank2=rank-reductionFactorFilt!(S);
    res~=indent~"const int rank2=rank-reductionFactorFilt!(S);";
    res~=indent~"index_type from,to,step;\n";
    foreach(i,U;S){
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"index_type j"~ctfe_i2a(i)~"=idx_tup["~ctfe_i2a(i)~"]*a.strides["~ctfe_i2a(i)~"];\n";
        } else static if (is(U==Range)){
            res~=`
            from=idx_tup[i].from;
            to=idx_tup[i].to;
            step=idx_tup[i].inc;
            if (from<0) from+=a.mShape[i];
            if (to<0) to+=a.mShape[i]+1;
            if (from<to && step>=0 || from>to && step<0){
                assert(0<=from && from<a.mShape[i],
                    "invalid lower range for dimension "~ctfe_i2a(i));
                if (step==0)
                    to=a.mShape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.mShape[i],
                    "invalid upper range for dimension "~ctfe_i2a(i));
            }
            `;
            res~=indent~"index_type j"~ctfe_i2a(i)~"_0=from*a.strides["~ctfe_i2a(i)~"];\n";
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=(to-from)/inc;\n";
            res~=indent~"index_type j"~ctfe_i2a(i)~"_2=inc*a.strides["~ctfe_i2a(i)~"];\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=idx_tup["~ctfe_i2a(i)~"].length;\n";
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=idx_tup["~ctfe_i2a(i)~"].mShape[0];\n";
            res~=indent~"index_type j"~ctfe_i2a(i)~"_2=idx_tup["~ctfe_i2a(i)~"].strides[0];\n";
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in reductionFactorFilt, this will fail");
        }
    }
    for (int i=0;i<rank;++i){
        res~=indent~"index_type aStride"~ctfe_i2a(i)~"=a.mStrides["~ctfe_i2a(i)~"];\n";
    }
    for (int i=0;i<rank2;++i){
        res~=indent~"index_type bStride"~ctfe_i2a(i)~"=b.mStrides["~ctfe_i2a(i)~"];\n";
    }
    int ii=0;
    res~=indent~"T* aPtr"~ctfe_i2a(rank)~"=a.mData.ptr+a.mStartIdx;\n";
    res~=indent~"T* bPtr"~ctfe_i2a(rank2)~"=b.mData.ptr+b.mStartIdx;\n";
    foreach(i,U;S){
        char[] indent2=indent~"    ";
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"{\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~"+j"~ctfe_i2a(i)~";\n";
        } else static if (is(U==Range)){
            res~=indent~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~"+j"~ctfe_i2a(i)~"_0;\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=0;i"~ctfe_i2a(i)~"!=j"~ctfe_i2a(i)~"_1;++i"~ctfe_i2a(i)~"){\n";
            ++ii;
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~arrayBaseT!(U).stringof~"* idx"~ctfe_i2a(i)~"=idx_tup["~ctfe_i2a(i)~"].ptr;\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=0;i"~ctfe_i2a(i)~"!=j"~ctfe_i2a(i)~"_1;++i"~ctfe_i2a(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~
                "+(*idx"~ctfe_i2a(i)~")*aStride"~ctfe_i2a(i)~";\n";
            ++ii;
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            res~=indent~arrayBaseT!(U).stringof~"* idx"~ctfe_i2a(i)~
                "=idx_tup["~ctfe_i2a(i)~"].mData.ptr+idx_tup["~ctfe_i2a(i)~"].mStartIdx;\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=0;i"~ctfe_i2a(i)~"!=j"~ctfe_i2a(i)~"_1;++i"~ctfe_i2a(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~
                "+(*idx"~ctfe_i2a(i)~")*aStride"~ctfe_i2a(i)~";\n";
            ++ii;
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in axisFilterLoop, this will fail");
        }
        indent=indent2;
    }
    for (int i=rank2-ii;i>0;--i){
        char[] indent2=indent~"    ";
        res~=indent~"T* aPtr"~ctfe_i2a(i-1)~"=aPtr"~ctfe_i2a(i)~";\n";
        res~=indent~"T* bPtr"~ctfe_i2a(i-1)~"=aPtr"~ctfe_i2a(i)~";\n";
        res~=indent~"for (index_type i"~ctfe_i2a(i-1)~"=0;i"~ctfe_i2a(i-1)~"!=aShape"~ctfe_i2a(i-1)~
            ";++i"~ctfe_i2a(i-1)~"){\n";
        indent=indent2;
    }
    res~=indent~loopBody~"\n";
    for (int i=0;i<rank2-ii;++i){
        assert(indent.length>=4);
        char[] indent2=indent[0..(indent.length-4)];
        res~=indent~"aPtr"~ctfe_i2a(i-1)~"+=aStride"~ctfe_i2a(i)~";\n";
        res~=indent~"bPtr"~ctfe_i2a(i-1)~"+=aStride"~ctfe_i2a(i)~";\n";
        res~=indent2~"}\n";
        indent=indent2;
    }
    foreach_reverse(i,U;S){
        assert(indent.length>=4);
        char[] indent2=indent[0..(indent.length-4)];
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent2~"}\n";
        } else static if (is(U==Range)){
            --ii;
            res~=indent~"aPtr"~ctfe_i2a(rank-i-1)~"+=j"~ctfe_i2a(i)~"_2;\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"+=bStride"~ctfe_i2a(ii)~";\n";
            res~=indent2~"}\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            --ii;
            res~=indent~"++idx"~ctfe_i2a(i)~";\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"+=bStride"~ctfe_i2a(ii)~";\n";
            res~=indent2~"}\n";
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            --ii;
            res~=indent~"idx"~ctfe_i2a(i)~"+=j"~ctfe_i2a(i)~"_2;\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"+=bStride"~ctfe_i2a(ii)~";\n";
            res~=indent2~"}\n";
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in axisFilterLoop, this will fail");
        }
        indent=indent2;
    }
    return res;
}

NArray!(T,rank-reductionFactorFilt!(S)) axisFilter1(T,int rank,S...)
    (NArray!(T,rank) a,NArray!(T,rank-reductionFactorFilt!(S)) b,S idx_tup)
{
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    mixin(axisFilterLoop!(T,rank,S)("*bPtr0=*aPtr0;"));
    return b;
}

NArray!(T,rank-reductionFactorFilt!(S))axisFilter(T,int rank,S...)(NArray!(T,rank) a,S index){
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    return axisFilter1!(T,rank,S)(a,arrayAxisFilter!(T,rank,S)(a,index),index);
}

NArray!(T,rank-reductionFactorFilt!(S)) axisUnfilter1(T,int rank,S...)
    (NArray!(T,rank) a,NArray!(T,rank-reductionFactorFilt!(S)) b,S idx_tup)
{
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    mixin(axisFilterLoop!(T,rank,S)("*aPtr0=*bPtr0;"));
    return b;
}

// -------------- norm/compare -------------
/// feqrel version more forgiving close to 0
int feqrel2(T)(T x,T y){
    const T shift=T.epsilon*ctfe_powI(2,2*T.mant_dig/3);
    if (x<0){
        return feqrel(x-shift,y-shift);
    } else {
        return feqrel(x+shift,y+shift);
    }
}

/// returns the minimum number of significand bits in common between array a and b
/// using feqrel2
int minFeqrel2(T,int rank)(NArray!(T,rank) a,NArray!(T,rank) b)
in { assert(b.mShape==a.mShape,"array need to have the same size in minFeqrel"); }
body {
    int minEq=T.mant_dig;
    mixin(sLoopPtr(rank,["a","b"],[],
        "int diffAtt=feqrel2(*aPtr0,*bPtr0); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/// returns the minimum number of significand bits in common between this array and b
int minFeqrel(T,int rank)(NArray!(T,rank) a,T b=cast(T)0){
    int minEq=feqrel(T.init,T.init);
    mixin(sLoopPtr(rank,["a"],[],
        "int diffAtt=feqrel(*aPtr0,b); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/// return the square of the 2 norm of the array
S norm2(T,int rank, S=T)(NArray!(T,rank)a){
    S res=reduceAll!((ref S x,T y){ x+=cast(S)y*cast(S)y; },(ref S x,S y){ x+=y; }, (S x){return x;},
        T,rank,S)(a,cast(S)0);
    return cast(S)sqrt(res);
}

