/*******************************************************************************
    Basic Operations on NArrays.
    
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        Apache 2.0
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.narray.BasicOps;
import blip.narray.BasicTypes;
import blip.TemplateFu;
import tango.core.Traits;
import tango.math.Math: round,sqrt,min,ceil;
import tango.math.IEEE: feqrel;
import tango.core.Memory:GC;

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
        newshape[i]=a.shape[perm[i]];
    }
    for (int i=0;i<rank;++i){
        newstrides[i]=a.bStrides[perm[i]];
    }
    return NArray!(T,rank)(newstrides,newshape,a.startPtrArray,a.newFlags,a.newBase);
}

/// transposed view
NArray!(T,rank) transpose(T,int rank)(NArray!(T,rank) a){
    return a.T;
}

/// returns an array that loops from the end toward the beginning of this array
/// (returns a view, no data is copied)
NArray!(T,rank) reverse(T,int rank)(NArray!(T,rank) a)
out(res){
    debug(TestNArray){
        T[] resData=res.data,aData=a.data;
        assert(resData.ptr==aData.ptr && resData.length==aData.length,"reversed dataSlice changed");
    }
}
body {
    index_type[rank] newstrides;
    index_type newStartIdx=0;
    for (int i=0;i<rank;++i){
        newStartIdx+=(a.shape[i]-1)*a.bStrides[i];
        newstrides[i]=-a.bStrides[i];
    }
    return NArray!(T,rank)(newstrides,a.shape,cast(T*)(cast(size_t)a.startPtrArray+newStartIdx),
        a.newFlags,a.newBase);
}

/// adds an axis to the current array and repeats the current data along it
/// does not copy and returns a readonly (overlapping) version if amount>1.
/// Use dup to have a writable fully replicated version
/// note: putting this in the class forces the instantiation of NArray!(T,rank+1)
///       which then forces the instantiation of N+2 which...
NArray!(T,rank+1) repeat(T,int rank)(NArray!(T,rank) a,index_type amount, int axis=0)
in {
    assert(0<=amount,"amount should be positive");
    assert(-rank-1<=axis && axis<rank+1,"axis out of bounds in repeat");
}
out(res){
    debug(TestNArray){
        T[] resData=res.data,aData=a.data;
        assert(resData.ptr==aData.ptr && resData.length==aData.length,"repeat changed dataSlice");
    }
}
body {
    if (axis<0) axis+=rank+1;
    index_type[rank+1] newshape,newstrides;
    int i=0,ii=0;
    for (;;){
        if (ii==axis) {
            newshape[ii]=amount;
            if (amount==1)
                newstrides[ii]=a.nElArray*cast(index_type)T.sizeof; // leave it compact if possible
            else
                newstrides[ii]=0;
            ++ii;
        }
        if (i>=rank) break;
        newshape[ii]=a.shape[i];
        newstrides[ii]=a.bStrides[i];
        ++ii;
        ++i;
    }
    uint newflags=a.newFlags;
    if (amount>1) newflags|=ArrayFlags.ReadOnly;
    return NArray!(T,rank+1)(newstrides,newshape,a.startPtrArray,
        newflags,a.newBase);
}

/// changes the dimensions and rank of the array.
/// no elements can be thrown away (sizes must match).
/// if the present array is not 1D or contiguous this operation returns a copy.
/// fortran returns fortran ordering wrt. to flat iterator (i.e. to C-style looping)
/// thus fortran=true with a fortran matrix a returns a fortran ordered transpose of it.
NArray!(T,newRank) reshape(T,int rank,S,int newRank)(NArray!(T,rank) a,S[newRank] newshape,bool fortran=false) {
    static assert(is(S==int)|| is(S==long)|| is(S==uint) || is(S==ulong),"newshape must be a static array of integer types");
    static if (newRank==rank) {
        if (newshape == a.shape) return a;
    }
    index_type newsize = 1;
    index_type aSize = a.nElArray;
    int autosize = -1;
    index_type[newRank] newstrides;
    index_type[newRank] ns;
    foreach(i,val; newshape) {
        if (val<0) {
            assert(autosize==-1,"Only one shape dimension can be automatic");
            autosize = i;
        } else {
            newsize *= cast(index_type)val;
        }
        ns[i]=cast(index_type)val;
    }
    if (autosize!=-1) {
        ns[autosize] = aSize/newsize;
        newsize *= ns[autosize];
    }
    assert(newsize==aSize,"reshape cannot change the size of the array");
    
    index_type sz=cast(index_type)T.sizeof;
    static if (rank==1){
        sz=a.bStrides[0];
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
        return NArray!(T,newRank)(newstrides,ns,a.startPtrArray,a.newFlags,a.newBase);
    } else {
        if (a.flags&ArrayFlags.Contiguous) {
            return NArray!(T,newRank)(newstrides,ns,a.startPtrArray,a.newFlags,a.newBase);
        } else {
            // copy data to contiguous mem first.
            scope NArray!(T,rank) cpy = a.dup();
            T* newData=cpy.startPtrArray;
            uint newF=cpy.flags;
            auto res=NArray!(T,newRank)(newstrides,ns,newData,newF,cpy.mBase);
            return res;
        }
    }
}

/// returns a flattened view of the array, copies if the array is not Contiguos
NArray!(T,1) ravel(T,int rank)(NArray!(T,rank)a){
    return reshape(a,[-1]);
}

/// diagonal view
NArray!(T,1)diag(T,int rank)(NArray!(T,rank)a)
in {
    static assert(rank>1,"rank must be at least 2");
    for (int i=0;i<rank;++i) assert(a.shape[0]==a.shape[i],"a must be square");
}
body {
    index_type inc=0;
    for (int i=0;i<rank;++i) inc+=a.bStrides[i];
    index_type[1] newstrides=inc, newshape=a.shape[0];
    return NArray!(T,1)(newstrides,newshape,a.startPtrArray,a.newFlags,a.newBase);
}
/+ --------- array creation ---------- +/

/// function to create free standing empty,zeros,ones
char[] freeFunMixin(char[] opName){
    char[] res="".dup;
    res~="template "~opName~"(V){\n";
    res~="    template "~opName~"(T){\n";
    res~="        NArray!(V,rkOfShape!(T))"~opName~"(T shape, bool fortran=false){\n";
    res~="            static if (isStaticArrayType!(T)){\n";
    res~="                static if(is(BaseTypeOfArrays!(T)==index_type)) {\n";
    res~="                    return NArray!(V,rkOfShape!(T))."~opName~"(shape,fortran);\n";
    res~="                } else {\n";
    res~="                    index_type[rkOfShape!(T)] s;\n";
    res~="                    for (int i=0;i<rkOfShape!(T);++i)\n";
    res~="                        s[i]=cast(index_type)shape[i];\n";
    res~="                    return NArray!(V,rkOfShape!(T))."~opName~"(s,fortran);\n";
    res~="                }\n";
    res~="            } else {\n";
    res~="                index_type[1] s;\n";
    res~="                s[0]=cast(index_type) shape;\n";
    res~="                return NArray!(V,rkOfShape!(T))."~opName~"(s,fortran);\n";
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
    mixin(sLoopPtr(1,["res"],loopBody,"i"));
    return res;
}

/// unity matrix of dimension dim x dim
NArray!(T,2)eye(T)(index_type dim){
    NArray!(T,2) res=NArray!(T,2).zeros([dim,dim]);
    scope d=diag(res);
    d[]=cast(T)1;
    return res;
}

/++
+ converts the given array to an copying the data to an NArray.
+ The array has to be rectangular.
+ note: this put all the indexes of the array arr in the inner loop, not so efficient with many dimensions
+/
NArray!(BaseTypeOfArrays!(T),cast(int)rankOfArray!(T))a2NA(T)(T arr,bool fortran=false){
    return a2NAof!(BaseTypeOfArrays!(T))(arr,fortran);
}
/// converts the given array to an NArray of the given type copying
template a2NAof(V){
    template a2NAof(T){
        NArray!(V,cast(int)rankOfArray!(T))a2NAof(T arr,bool fortran=false)
        in {
            index_type[rankOfArray!(T)] shape;
            calcShapeArray!(T,rankOfArray!(T))(arr,shape);
            checkShape!(T,rankOfArray!(T))(arr,shape);
        }
        body{
            const int rank=rankOfArray!(T);
            index_type[rank] shape;
            calcShapeArray!(T,rankOfArray!(T))(arr,shape);
            auto res=NArray!(V,cast(int)rankOfArray!(T)).empty(shape,fortran);
            const char[] loop_body="*resPtr0=cast(V)"~arrayInLoop("arr",rank,"i")~";";
            index_type optimalChunkSize_i=NArray!(V,cast(int)rankOfArray!(T)).defaultOptimalChunkSize;
            mixin(pLoopIdx(rank,["res"],loop_body,"i"));
            return res;
        }
    }
}
/// acquires an array using it as NArray, without copying.
/// if shouldFree=true it frees the array when destroyed
NArray!(T,1)a2NA2(T)(T[] arr,bool shouldFree=false){
    uint flags=ArrayFlags.None;
    Guard guard;
    if (shouldFree) guard=new Guard(arr);
    auto res=NArray!(T,1)([cast(index_type)T.sizeof],[cast(index_type)arr.length],0,arr,flags,guard);
    version(RefCount) if (shouldFree) guard.release;
    return res;
}

/// returns a into shape the shape of the nested D array T (for a2NA)
void calcShapeArray(T,uint rank)(T arr,index_type[] shape){
    static assert(rank==rankOfArray!(T),"inconsistent rank/shape");
    assert(shape.length==rank,"shape array has wrong size");
    static if (rankOfArray!(T)>0) {
        shape[0]=arr.length;
        static if (rankOfArray!(T)>1){
            calcShapeArray!(typeof(arr[0]),rank-1)(arr[0],shape[1..$]);
        }
    }
}

/// checks that the D array arr is rectangular and has the shape in shape (for a2NA)
private void checkShape(T,uint rank)(T arr,index_type[] shape){
    static assert(rank==rankOfArray!(T),"inconsistent rank/shape");
    assert(shape.length==rank,"shape array has wrong size");
    static if (rankOfArray!(T)>0) {
        assert(shape[0]==arr.length,"array does not match shape (non rectangular?)");
        static if (rankOfArray!(T)>1){
            foreach(subArr;arr)
                calcShapeArray!(typeof(arr[0]),rank-1)(subArr,shape[1..$]);
        }
    }
}

/// returns a D array indexed with the variables of a pLoopIdx or sLoopGenIdx (for a2NA)
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
/// dupInitial(x) is an operation that makes a copy of x (for simple types normally returns x)
/// and is used to split the loop in different subloops starting with dupInitial(x0)
/// the folding starts with the element x0, if S==T normally mergeOp==foldOp
S reduceAllGen(alias foldOp,alias mergeOp, alias dupInitial,T,int rank,S=T)(NArray!(T,rank)a,S x0){
    S x=dupInitial(x0);
    mixin(sLoopPtr(rank,["a"],"foldOp(x,*(aPtr0));\n","i"));
    mergeOp(x,x0);  /+ just to test it +/
    return x;
}

/// collects data on the whole array using the given folding operation
/// if not given mergeOp is built from foldOp 
S reduceAll(T,int rank,S=T)(S delegate(S,T)foldOp,NArray!(T,rank)a,S x0,S delegate(S,S)mergeOp=null){
    if (mergeOp is null){
        mergeOp=(S x,S y){ x=foldOp(x,cast(T)y); };
    }
    return reduceAllGen!((ref S x,T y){ x=foldOp(x,y); },(ref S x,S y){ x=mergeOp(x,y); },(S x){ return x; }, T,rank,S)(a,x0);
}

/// applies an operation that "collects" data on an axis of the array
/// this is basically a possibly parallel fold on the array along that axis
/// foldOp(x,t) is the operations that accumulates on x the element t
/// of the array, mergeOp(x,y) merges in x the two partial results x and y
/// dupInitial(S x) is an operation that makes a copy of x at the beginning of the
/// folding (receiving the value in res), and can be used to set x0.
/// the folding starts with the corresponding element in the result array.
/// If S==T normally mergeOp==foldOp
NArray!(S,rank-1) reduceAxisGen(alias foldOp, alias mergeOp,alias dupInitial, T, int rank, S=T)
    (NArray!(T,rank)a, int axis=-1, NArray!(S,rank-1) res=nullNArray!(S,rank-1))
in {
    assert(-rank<=axis && axis<rank,"axis out of bounds");
    int ii=0;
    static if (rank>1){
        if (! isNullNArray(res)){
            for(int i=0;i<rank;i++){
                if(i!=axis && i!=rank+axis){
                    assert(res.shape[ii]==a.shape[i],"invalid res shape");
                    ii++;
                }
            }
        }
    }
}
body  {
    static if (rank==1){
        S x=dupInitial(res);
        mixin(sLoopPtr(rank,["a"],"foldOp(x,*(aPtr0));\n","i"));
        return x;
    } else {
        void myFold(ref S x0,T* startP, int my_stride, int my_dim){
            S x=dupInitial(x0);
            T* ii=startP;
            for (int i=my_dim;i!=0;--i){
                foldOp(x,*ii);
                ii=cast(T*)(cast(size_t)ii+my_stride);
            }
            x0=x;
        }
        if (axis<0) axis+=rank;
        if (isNullNArray(res)){
            index_type[rank-1] newshape;
            int ii=0;
            for(int i=0;i<rank;i++){
                if(i!=axis && i!=rank+axis){
                    newshape[ii]=a.shape[i];
                    ii++;
                }
            }
            res=NArray!(S,rank-1).empty(newshape);
        }
        static if (rank==1){
            myFold(res,a.startPtrArray,a.bStrides[0],a.shape[0]);
        } else {
            index_type [rank-1] newstrides;
            {
                int ii=0;
                for(int i=0;i<rank;i++){
                    if(i!=axis){
                        newstrides[ii]=a.bStrides[i];
                        ii++;
                    }
                }
            }
            scope NArray!(T,rank-1) tmp=NArray!(T,rank-1)(newstrides,res.shape,a.startPtrArray,
                a.newFlags,a.newBase);
            index_type axisStride=a.bStrides[axis];
            index_type axisDim=a.shape[axis];
            index_type optimalChunkSize_i=(NArray!(T,rank).defaultOptimalChunkSize+axisDim-1)/axisDim;
            mixin(pLoopPtr(rank-1,["res","tmp"],
                "myFold(*resPtr0,tmpPtr0,axisStride,axisDim);\n","i"));
        }
    }
    return res;
}

/// applies a reduction operation along the given axis
NArray!(S,rank-1) reduceAxis(int rank, T, S=T)
    (S delegate(S,T) foldOp,NArray!(T,rank)a, S x0, int axis=-1, NArray!(S,rank-1) res=nullNArray!(S,rank-1),S delegate(S,S)mergeOp=null)
{
    if (mergeOp is null){
        mergeOp=(S x,S y){ x=foldOp(x,cast(T)y); };
    }
    return reduceAxisGen!((ref S x,T y){ x=foldOp(x,y); },(ref S x,S y){ x=mergeOp(x,y); },(S x){ return x0; }, T,rank,S)(a,axis,res);
}

/// sum of the whole array
S sumAll(T,int rank,S=T)(NArray!(T,rank)a){
    return reduceAllGen!((ref S x,T y){x+=cast(S)y;},(ref S x,S y){x+=y;}, (S x){ return x;},
        T, rank,S)(a,cast(S)0);
}
/// sum along an axis of the array
NArray!(S,rank-1) sumAxis(T,int rank,S=T)(NArray!(T,rank)a,int axis=-1,NArray!(S,rank-1) res=nullNArray!(S,rank-1))
{
    return reduceAxisGen!((ref S x,T y){x+=cast(S)y;},(ref S x,S y){x+=y;}, (S x){ return cast(S)0;},
        T, rank,S)(a,axis,res);
}

/// multiplies of the whole array
S multiplyAll(T,int rank,S=T)(NArray!(T,rank)a){
    return reduceAllGen!((ref S x,T y){x*=cast(S)y;},(ref S x,S y){x*=y;}, (S x){ return x; },
        T, rank,S)(a,cast(S)1);
}
/// sum along an axis of the array
NArray!(S,rank-1) multiplyAxis(T,int rank,S=T)(NArray!(T,rank)a,int axis=-1,NArray!(S,rank-1) res=nullNArray!(S,rank-1))
{
    return reduceAxisGen!((ref S x,T y){x*=y;},(ref S x,S y){x*=y;}, (S x){ return cast(S)1; },
        T, rank,S)(a,axis,res);
}

/// fuses two arrays combining two axis of the same length with the given fuse op
/// basically this is a generalized dot product of tensors
/// implements a simple streaming algorithm (some blocking in the x direction would 
/// be a natural extension)
/// should look into something like "A Cache Oblivious Algorithm for Matrix 
/// Multiplication Based on Peano’s Space Filling Curve" by Michael Bader and Christoph Zenger
/// or other kinds of recursive refinements
void fuse1(alias fuseOp,alias inOp, alias outOp, T,int rank1,S,int rank2,U)(NArray!(T,rank1) a,
    NArray!(S,rank2) b, ref NArray!(U,rank1+rank2-2) c, int axis1=-1, int axis2=0,
    index_type optimalChunkSize=NArray!(U,rank1+rank2-1).defaultOptimalChunkSize)
in {
    static assert(rank1>0,"rank1 should be at least 1");
    static assert(rank2>0,"rank2 should be at least 1");
    assert(-rank1<=axis1 && axis1<rank1,"invalid axis1 in fuse1");
    assert(-rank2<=axis2 && axis2<rank2,"invalid axis2 in fuse1");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
    static if(rank1+rank2>2){
        int ii=0;
        for(int i=0;i<rank1;i++){
            if(i!=axis1 && i!=axis1+rank1){
                assert(c.shape[ii]==a.shape[i],"invalid c shape");
                ii++;
            }
        }
        for(int i=0;i<rank2;i++){
            if(i!=axis2 && i!=rank2+axis2){
                assert(c.shape[ii]==b.shape[i],"invalid c shape");
                ii++;
            }
        }
    }
} body {
    void myFuse(U* x0,T* start1Ptr, int my_stride1, 
        S* start2Ptr, int my_stride2, int my_dim){
        T*yPtr=start1Ptr;
        S*zPtr=start2Ptr;
        U xVal;
        inOp(x0,xVal);
        for (int i=my_dim;i!=0;--i){
            fuseOp(xVal,*yPtr,*zPtr);
            yPtr=cast(T*)(cast(size_t)yPtr+my_stride1);
            zPtr=cast(S*)(cast(size_t)zPtr+my_stride2);
        }
        outOp(x0,xVal);
    }
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    static if (rank2==1){
        static if (rank1==1){
            myFuse(&c,a.startPtrArray,a.bStrides[0],b.startPtrArray,
                b.bStrides[0],a.shape[0]);
        } else {
            const char [] innerLoop=`myFuse(c1Ptr0,tmp1Ptr0,a.bStrides[axis1],b.startPtrArray,
                b.bStrides[0],b.shape[0]);`;
        }
    } else {
        index_type [rank2-1] newshape2,newstrides2,newstrides2c;
        {
            int ii=0;
            for(int i=0;i<rank2;i++){
                if(i!=axis2){
                    newstrides2[ii]=b.bStrides[i];
                    newshape2[ii]=b.shape[i];
                    ii++;
                }
            }
            newstrides2c[]=c.bStrides[(rank1-1)..(rank1+rank2-2)];
        }
        scope NArray!(S,rank2-1) tmp2=NArray!(S,rank2-1)(newstrides2,newshape2,b.startPtrArray,
            b.newFlags,b.newBase);
        scope NArray!(U,rank2-1) c2=NArray!(U,rank2-1)(newstrides2c,newshape2,null,c.newFlags);
        const char [] innerLoop=pLoopPtr(rank2-1,["tmp2","c2"],
                "myFuse(cast(U*)(cast(size_t)c2Ptr0+cast(size_t)c1Ptr0),tmp1Ptr0,a.bStrides[axis1],tmp2Ptr0,\n"~
                "            b.bStrides[axis2],a.shape[axis1]);\n","j");
    }
    
    static if (!(rank1==1 && rank2==1)){
        index_type oChunk=(optimalChunkSize+a.shape[axis1]-1)/a.shape[axis1];
        index_type oChunk2=cast(index_type)(ceil(sqrt(cast(real)oChunk)));
        index_type optimalChunkSize_i=oChunk2;
        index_type optimalChunkSize_j=oChunk2;
        if (a.size()/a.shape[axis1]<oChunk2){
            optimalChunkSize_j=cast(index_type)(oChunk2*(cast(real)oChunk2/cast(real)(a.size()/a.shape[axis1])));
        } else if (b.size()/a.shape[axis1]<oChunk2){
            optimalChunkSize_i=cast(index_type)(oChunk2*(cast(real)oChunk2/cast(real)(b.size()/a.shape[axis1])));
        }
    }
    
    static if (rank1==1) {
        static if (rank2>1){
            U* c1Ptr0=c.startPtrArray;
            T* tmp1Ptr0=a.startPtrArray;
            mixin(innerLoop);
        }
    } else {
        index_type [rank1-1] newshape1,newstrides1,newstrides1c;
        {
            int ii=0;
            for(int i=0;i<rank1;i++){
                if(i!=axis1){
                    newstrides1[ii]=a.bStrides[i];
                    newshape1[ii]=a.shape[i];
                    ii++;
                }
            }
            newstrides1c[]=c.bStrides[0..rank1-1];
        }
        scope NArray!(T,rank1-1) tmp1=NArray!(T,rank1-1)(newstrides1,newshape1,a.startPtrArray,
            a.newFlags,a.newBase);
        scope NArray!(U,rank1-1) c1=NArray!(U,rank1-1)(newstrides1c,newshape1,c.startPtrArray,a.newFlags);
        // to use a parallel loop here one should not modify c2
        mixin(pLoopPtr(rank1-1,["tmp1","c1"],"mixin(innerLoop);\n","i"));
    }
}

// ------------------ filter ops ------------------

/// filters the array with a mask array. If allocSize>0 it is used for the initial allocation
/// of the filtred array
NArray!(T,1) filterMask(T,int rank)(NArray!(T,rank) a,NArray!(bool,rank) mask, index_type allocSize=0)
in { assert(mask.shape==a.shape); }
body {
    index_type sz=1;
    foreach (d;a.shape)
        sz*=d;
    int manualAlloc=sz*cast(index_type)T.sizeof>manualAllocThreshold || allocSize*cast(index_type)T.sizeof>manualAllocThreshold;
    T* res;
    T[] resA;
    size_t resSize=1;
    if (allocSize>0){
        resSize=allocSize;
    } else {
        if (a.nElArray<10) {
            resSize=a.nElArray;
        } else {
            index_type nTest=(10<a.nElArray)?10:a.nElArray;
            bool[] maskData=mask.data; // this is not always correct, but it used just to have a quick guess
            for (index_type i=0;i<nTest;++i)
                if(maskData[i]) ++resSize;
            resSize=cast(size_t)(sqrt(cast(real)resSize/cast(real)(1+nTest))*a.nElArray);
        }
    }
    if (manualAlloc){
        res=cast(T*)GC.malloc(resSize*T.sizeof,GC.BlkAttr.NO_SCAN);
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
            size_t newSize=min(resSize+a.nElArray/10,a.nElArray);
            if(manualAlloc){
                res=cast(T*)GC.realloc(res,newSize*T.sizeof,GC.BlkAttr.NO_SCAN);
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
    mixin(sLoopPtr(rank,["a","mask"],loopInstr,"i"));
    resSize=resP-res;
    if(manualAlloc){
        res=cast(T*)GC.realloc(res,resSize*T.sizeof,GC.BlkAttr.NO_SCAN);
        resA=res[0..resSize];
    } else {
        resA.length=resSize;
    }
    index_type[1] newshape,newstrides;
    newshape[0]=resSize;
    newstrides[0]=cast(index_type)T.sizeof;
    uint newflags=ArrayFlags.None;
    Guard guard;
    if (manualAlloc) guard=new Guard(resA);
    return NArray!(T,1)(newstrides,newshape,0,resA,newflags,guard);
    version(RefCount) if (manualAlloc) guard.release;
}

/// writes back the data to an array in the places where mask is true.
/// if res is given it writes into res
NArray!(T,rank2) unfilterMask(T,int rank1,S,int rank2,U=T,int rank3=rank2)(NArray!(T,rank1) a,NArray!(S,rank2) mask, NArray!(T,rank3)res=nullNArray!(T,rank3))
in{
    static assert(rank2==rank3,"mask and result need to have the same shape");
    if (! isNullNArray(res)){
        assert(res.shape==mask.shape);
    }
    index_type nEl=sumAll!(bool,rank2,index_type)(mask);
    assert(nEl<=a.shape[0],"mask has more true elements than size of filtered array");
}
body {
    static assert(rank1==1,"a needs to have rank 1");
    static assert(rank2==rank3,"mask and result need to have the same shape");
    static assert(is(S:bool)||is(S:int),"maks should be castable to bool");
    if (isNullNArray(res)){
        res=NArray!(T,rank2).zeros(mask.shape);
    }
    T* elAtt=a.startPtrArray;
    index_type myStride=a.bStrides[0];
    const char[] loopInstr=`
    if (*maskPtr0){
        *resPtr0=*elAtt;
        elAtt=cast(T*)(cast(size_t)elAtt+myStride);
    }`;
    mixin(sLoopPtr(rank2,["res","mask"],loopInstr,"i"));
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
    } else static if (is(T:NArray!(long,1))||is(T:NArray!(int,1))||is(T:NArray!(uint,1))||is(T:NArray!(ulong,1))){
        const int reductionFactorFilt=reductionFactorFilt!(S);
    } else {
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactorFilt, this will fail");
    }
}

// creates an empty array of the requested shape for axis filtering (support function)
NArray!(T,rank-reductionFactorFilt!(S)) arrayAxisFilter(T,int rank,S...)(NArray!(T,rank) a,S idx_tup)
{
    const int rank2=rank-reductionFactorFilt!(S);
    index_type from,to,step;
    index_type[rank2] newshape;
    int ii=0;
    foreach(i,U;S){
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
        } else static if (is(U==Range)){
            from=idx_tup[i].from;
            to=idx_tup[i].to;
            step=idx_tup[i].inc;
            if (from<0) from+=a.shape[i];
            if (to<0) to+=a.shape[i]+1;
            if (from<to && step>=0 || from>to && step<0){
                assert(0<=from && from<a.shape[i],
                    "invalid lower range for dimension "~ctfe_i2a(i));
                if (step==0)
                    to=a.shape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.shape[i],
                    "invalid upper range for dimension "~ctfe_i2a(i));
            }
            newshape[ii]=(to-from)/inc;
            ++ii;
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            newshape[ii]=idx_tup[i].length;
            ++ii;
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(int,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            newshape[ii]=idx_tup[i].shape[0];
            ++ii;
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in reductionFactorFilt, this will fail");
        }
    }
    for (int i=rank2-ii;i>0;--i){
        newshape[rank2-i]=a.shape[rank-i];
    }
    return NArray!(T,rank2).empty(newshape);
}

// loops on filtered and non filtered array in parallel (support function)
char[] axisFilterLoop(T,int rank,V,S...)(char[] loopBody)
{
    char[] res="".dup;
    char[] indent="    ".dup;
    static const int rank2=rank-reductionFactorFilt!(S);
    res~=indent~"const int rank2=rank-reductionFactorFilt!(S);";
    res~=indent~"index_type from,to,step;\n";
    res~=indent~"T* aPtr"~ctfe_i2a(rank)~"=a.startPtrArray;\n";
    res~=indent~"T* bPtr"~ctfe_i2a(rank2)~"=b.startPtrArray;\n";
    for (int i=0;i<rank;++i){
        res~=indent~"index_type aStride"~ctfe_i2a(i)~"=a.bStrides["~ctfe_i2a(i)~"];\n";
        res~=indent~"index_type aShape"~ctfe_i2a(i)~"=a.shape["~ctfe_i2a(i)~"];\n";
    }
    for (int i=0;i<rank2;++i){
        res~=indent~"index_type bStride"~ctfe_i2a(i)~"=b.bStrides["~ctfe_i2a(i)~"];\n";
    }
    foreach(i,U;S){
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"aPtr"~ctfe_i2a(rank)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(rank)
                ~"+idx_tup["~ctfe_i2a(i)~"]*a.bStrides["~ctfe_i2a(i)~"]);\n";
        } else static if (is(U==Range)){
            res~=`
            from=idx_tup[i].from;
            to=idx_tup[i].to;
            step=idx_tup[i].inc;
            if (from<0) from+=a.shape[i];
            if (to<0) to+=a.shape[i]+1;
            if (from<to && step>=0 || from>to && step<0){
                assert(0<=from && from<a.shape[i],
                    "invalid lower range for dimension "~ctfe_i2a(i));
                if (step==0)
                    to=a.shape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.shape[i],
                    "invalid upper range for dimension "~ctfe_i2a(i));
            }
            `;
            res~=indent~"aPtr"~ctfe_i2a(rank)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(rank)
                ~"+from*a.bStrides["~ctfe_i2a(i)~"]);\n";
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=(to-from)/inc;\n";
            res~=indent~"aStride"~ctfe_i2a(i)~"*=inc;\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=idx_tup["~ctfe_i2a(i)~"].length;\n";
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(int,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            res~=indent~"index_type j"~ctfe_i2a(i)~"_1=idx_tup["~ctfe_i2a(i)~"].shape[0];\n";
            res~=indent~"index_type j"~ctfe_i2a(i)~"_2=idx_tup["~ctfe_i2a(i)~"].bStrides[0];\n";
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in reductionFactorFilt, this will fail");
        }
    }
    int ii=0;
    foreach(i,U;S){
        char[] indent2=indent~"    ";
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"{\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~";\n";
        } else static if (is(U==Range)){
            res~=indent~"T* aPtr"~ctfe_i2a(rank-i-1)~"=aPtr"~ctfe_i2a(rank-i)~";\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=j"~ctfe_i2a(i)~"_1;i"~ctfe_i2a(i)~"!=0;--i"~ctfe_i2a(i)~"){\n";
            ++ii;
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~BaseTypeOfArrays!(U).stringof~"* idx"~ctfe_i2a(i)~"=idx_tup["~ctfe_i2a(i)~"].ptr;\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=0;i"~ctfe_i2a(i)~"!=j"~ctfe_i2a(i)~"_1;++i"~ctfe_i2a(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(rank-i)~
                "+cast(index_type)(*idx"~ctfe_i2a(i)~")*aStride"~ctfe_i2a(i)~");\n";
            ++ii;
        } else static if (is(U==NArray!(long,1))||is(U:NArray!(int,1))||is(U:NArray!(uint,1))||is(U:NArray!(ulong,1))){
            res~=indent;
            static if (is(U:NArray!( long,1))) res~="long";
            static if (is(U:NArray!(  int,1))) res~="int";
            static if (is(U:NArray!(ulong,1))) res~="ulong";
            static if (is(U:NArray!( uint,1))) res~="uint";
            res~="* idx"~ctfe_i2a(i)~
                "=idx_tup["~ctfe_i2a(i)~"].startPtrArray;\n";
            res~=indent~"T* bPtr"~ctfe_i2a(rank2-ii-1)~"=bPtr"~ctfe_i2a(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2a(i)~"=0;i"~ctfe_i2a(i)~"!=j"~ctfe_i2a(i)~"_1;++i"~ctfe_i2a(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2a(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(rank-i)~
                "+cast(index_type)(*idx"~ctfe_i2a(i)~")*aStride"~ctfe_i2a(i)~");\n";
            ++ii;
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in axisFilterLoop, this will fail");
        }
        indent=indent2;
    }
    for (int i=rank2-ii;i>0;--i){
        char[] indent2=indent~"    ";
        res~=indent~"T* aPtr"~ctfe_i2a(i-1)~"=aPtr"~ctfe_i2a(i)~";\n";
        res~=indent~"T* bPtr"~ctfe_i2a(i-1)~"=bPtr"~ctfe_i2a(i)~";\n";
        res~=indent~"for (index_type iIn"~ctfe_i2a(i-1)~"=aShape"~ctfe_i2a(rank-i)~";iIn"~ctfe_i2a(i-1)~"!=0;--iIn"~ctfe_i2a(i-1)~"){\n";
        indent=indent2;
    }
    res~=indent~loopBody~"\n";
    for (int i=0;i<rank2-ii;++i){
        assert(indent.length>=4);
        char[] indent2=indent[0..(indent.length-4)];
        res~=indent~"aPtr"~ctfe_i2a(i)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(i)
            ~"+aStride"~ctfe_i2a(rank-1-i)~");\n";
        res~=indent~"bPtr"~ctfe_i2a(i)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2a(i)
            ~"+bStride"~ctfe_i2a(rank-1-i)~");\n";
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
            res~=indent~"aPtr"~ctfe_i2a(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2a(rank-i-1)
                ~"+aStride"~ctfe_i2a(i)~");\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2a(rank2-ii-1)
                ~"+bStride"~ctfe_i2a(ii)~");\n";
            res~=indent2~"}\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            --ii;
            res~=indent~"++idx"~ctfe_i2a(i)~";\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2a(rank2-ii-1)
                ~"+bStride"~ctfe_i2a(ii)~");\n";
            res~=indent2~"}\n";
        } else static if (is(U==NArray!(long,1))||is(U==NArray!(int,1))||is(U==NArray!(uint,1))||is(U==NArray!(ulong,1))){
            --ii;
            res~=indent~"idx"~ctfe_i2a(i)~"=cast(typeof(idx"~ctfe_i2a(i)~"))"
                ~"(cast(size_t)idx"~ctfe_i2a(i)~"+j"~ctfe_i2a(i)~"_2);\n";
            res~=indent~"bPtr"~ctfe_i2a(rank2-ii-1)~"=cast(T*)"
                ~"(cast(size_t)bPtr"~ctfe_i2a(rank2-ii-1)~"+bStride"~ctfe_i2a(ii)~");\n";
            res~=indent2~"}\n";
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in axisFilterLoop, this will fail");
        }
        indent=indent2;
    }
    return res;
}

/// Filters the array a into the array b using indexes, ranges and index arrays
/// and returns the array b
NArray!(T,rank-reductionFactorFilt!(S)) axisFilter1(T,int rank,S...)
    (NArray!(T,rank) a,NArray!(T,rank-reductionFactorFilt!(S)) b,S idx_tup)
{
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    mixin(axisFilterLoop!(T,rank,T,S)("*bPtr0 = *aPtr0;"));
    return b;
}

/// Filters the array a using indexes, ranges and index arrays and returns the result
NArray!(T,rank-reductionFactorFilt!(S))axisFilter(T,int rank,S...)(NArray!(T,rank) a,S index){
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    return axisFilter1!(T,rank,S)(a,arrayAxisFilter!(T,rank,S)(a,index),index);
}

/// unfilters an array
NArray!(T,rank) axisUnfilter1(T,int rank,V,int rank2,S...)
    (NArray!(T,rank) a,NArray!(V,rank2) b,S idx_tup)
{
    static assert(rank2==rank-reductionFactorFilt!(S),"b has incorrect rank, expected "~
        ctfe_i2a(rank-reductionFactorFilt!(S))~" got "~ctfe_i2a(rank2));
    static assert(nArgs!(S)<=rank,"too many indexing arguments");
    mixin(axisFilterLoop!(T,rank,V,S)("*aPtr0=*bPtr0;"));
    return a;
}

// -------------- norm/compare -------------
/// feqrel version more forgiving close to 0
/// if you sum values you cannot expect better than T.epsilon absolute error.
/// feqrel compares relative error, and close to 0 (where the density of floats is high) it is
/// much more stringent.
/// To guarantee T.epsilon absolute error one should use shift=1.0, here we are more stingent
/// and we use T.mant_dig/4 digits more when close to 0.
int feqrel2(T)(T x,T y){
    static if(isComplexType!(T)){
        return min(feqrel2(x.re,y.re),feqrel2(x.im,y.im));
    } else {
        const T shift=ctfe_powI(0.5,T.mant_dig/4);
        if (x<0){
            return feqrel(x-shift,y-shift);
        } else {
            return feqrel(x+shift,y+shift);
        }
    }
}

/// returns the minimum number of significand bits in common between array a and b
/// using feqrel2
int minFeqrel2(T,int rank)(NArray!(T,rank) a,NArray!(T,rank) b)
in { assert(b.shape==a.shape,"array need to have the same size in minFeqrel"); }
body {
    int minEq=T.mant_dig;
    mixin(sLoopPtr(rank,["a","b"],
        "int diffAtt=feqrel2(*aPtr0,*bPtr0); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/// returns the minimum number of significand bits in common between this array and b
int minFeqrel(T,int rank)(NArray!(T,rank) a,T b=cast(T)0){
    int minEq=feqrel(T.init,T.init);
    mixin(sLoopPtr(rank,["a"],
        "int diffAtt=feqrel(*aPtr0,b); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/// return the square of the 2 norm of the array
S norm2(T,int rank, S=T)(NArray!(T,rank)a){
    static if(is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        S res=reduceAllGen!((ref S x,T y){ x+=cast(S)y.re * cast(S)y.re + cast(S)y.im * cast(S)y.im; },
            (ref S x,S y){ x+=y; }, (S x){return x;},T,rank,S)(a,cast(S)0);
    } else {
        S res=reduceAllGen!((ref S x,T y){ x+=cast(S)y*cast(S)y; },(ref S x,S y){ x+=y; }, (S x){return x;},
            T,rank,S)(a,cast(S)0);
    }
    return cast(S)sqrt(res);
}

/// makes the array hermitish (a==a.H) should use a recursive algorithm
NArray!(T,rank)hermitize(T,int rank)(NArray!(T,rank)a){
    static if (isComplexType!(T)){
        auto b=a.T;
        index_type optimalChunkSize_i=NArray!(T,rank).defaultOptimalChunkSize;
        mixin(pLoopPtr(rank,["a","b"],
        "if (aPtr0<=bPtr0) {T val=((*aPtr0).re+(*bPtr0).re+cast(T)1i*((*aPtr0).im-(*bPtr0).im))/cast(T)2; *aPtr0=val; *bPtr0=val.re-cast(T)1i*val.im;}","i"));
        return a;
    } else static if (isImaginaryType!(T)){
        return antiSymmetrize(a);
    } else {
        return symmetrize(a);
    }
}

/// symmetrizes the array
NArray!(T,rank)symmetrize(T,int rank)(NArray!(T,rank)a){
    auto b=a.T;
    index_type optimalChunkSize_i=NArray!(T,rank).defaultOptimalChunkSize;
    mixin(pLoopPtr(rank,["a","b"],
    "if (aPtr0<bPtr0) {T val=(*aPtr0+*bPtr0)/cast(T)2; *aPtr0=val; *bPtr0=val;}","i"));
    return a;
}

/// anti symmetrizes the array
NArray!(T,rank)antiSymmetrize(T,int rank)(NArray!(T,rank)a){
    auto b=a.T;
    index_type optimalChunkSize_i=NArray!(T,rank).defaultOptimalChunkSize;
    mixin(pLoopPtr(rank,["a","b"],
    "if (aPtr0<bPtr0) {T val=(*aPtr0-*bPtr0)/cast(T)2; *aPtr0=val; *bPtr0=-val;}","i"));
    return a;
}
