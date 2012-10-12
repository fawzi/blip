/// Basic Operations on NArrays.
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
module blip.narray.NArrayBasicOps;
import blip.narray.NArrayType;
import blip.util.TemplateFu;
import blip.core.Traits;
import blip.math.Math: round,sqrt,min,ceil;
import blip.math.IEEE: feqrel;
//import tango.core.Memory:GC;
import cstdlib = blip.stdc.stdlib : free, malloc;
import blip.Comp;

template isNArray(T){
    static if (is(typeof(T.dim)) && is(T.dtype)) // is(T:NArray!(T.dtype,T.dim)) sometime fails with dmd 2.060
        enum isNArray=true;
    else
        enum isNArray=false;
}

/+ ---------------- structural ops -------------------- +/

/// returns a view of the current data with the axes reordered
T reorderAxis(T,int r2)(T a,int[r2] perm) if (isNArray!(T))
in {
    static assert(T.dim==r2,"array rank and permutation must have the same size");
    foreach (i,iAxis;perm) {
        assert(0<=i && i<T.dim);
        foreach(iAxis2;perm[0..i])
            assert(iAxis2!=iAxis);
    }
}
body {
    index_type[T.dim] newshape,newstrides;
    for (int i=0;i<T.dim;++i){
        newshape[i]=a.shape[perm[i]];
    }
    for (int i=0;i<t.dim;++i){
        newstrides[i]=a.bStrides[perm[i]];
    }
    return T(newstrides,newshape,a.startPtrArray,a.newFlags,a.newBase);
}

/// transposed view
T transpose(T)(T a) if (isNArray!(T)) {
    return a.T;
}

/// returns an array that loops from the end toward the beginning of this array
/// (returns a view, no data is copied)
T reverse(T)(T a) if (isNArray!(T))
out(res){
    debug(TestNArray){
        T.dtype[] resData=res.data,aData=a.data;
        assert(resData.ptr==aData.ptr && resData.length==aData.length,"reversed dataSlice changed");
    }
}
body {
    index_type[T.dim] newstrides;
    index_type newStartIdx=0;
    for (int i=0;i<T.dim;++i){
        newStartIdx+=(a.shape[i]-1)*a.bStrides[i];
        newstrides[i]=-a.bStrides[i];
    }
    return T(newstrides,a.shape,cast(T.dtype*)(cast(size_t)a.startPtrArray+newStartIdx),
        a.newFlags,a.newBase);
}

/// adds an axis to the current array and repeats the current data along it
/// does not copy and returns a readonly (overlapping) version if amount>1.
/// Use dup to have a writable fully replicated version
/// note: putting this in the class forces the instantiation of NArray!(T,rank+1)
///       which then forces the instantiation of N+2 which...
NArray!(T.dtype,T.dim+1) repeat(T)(T a,index_type amount, int axis=0) if (isNArray!(T))
in {
    assert(0<=amount,"amount should be positive");
    assert(-T.dim-1<=axis && axis<T.dim+1,"axis out of bounds in repeat");
}
out(res){
    debug(TestNArray){
        T.dtype[] resData=res.data,aData=a.data;
        assert(resData.ptr==aData.ptr && resData.length==aData.length,"repeat changed dataSlice");
    }
}
body {
    alias T.dim rank;
    if (axis<0) axis+=rank+1;
    index_type[rank+1] newshape,newstrides;
    int i=0,ii=0;
    for (;;){
        if (ii==axis) {
            newshape[ii]=amount;
            if (amount==1)
                newstrides[ii]=a.nElArray*cast(index_type)T.dtype.sizeof; // leave it compact if possible
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
    return NArray!(T.dtype,rank+1)(newstrides,newshape,a.startPtrArray,
        newflags,a.newBase);
}

/// changes the dimensions and rank of the array.
/// no elements can be thrown away (sizes must match).
/// if the present array is not 1D or contiguous this operation returns a copy.
/// fortran returns fortran ordering wrt. to flat iterator (i.e. to C-style looping)
/// thus fortran=true with a fortran matrix a returns a fortran ordered transpose of it.
NArray!(TT.dtype,newRank) reshapeR(int newRank,TT)(TT a,index_type[newRank] newShape,bool fortran=false)
    if (isNArray!(TT))
{
    alias TT.dtype T;
    alias TT.dim rank;
    static if (newRank==rank) {
        if (newShape == a.shape) return a;
    }
    index_type newsize = 1;
    index_type aSize = a.nElArray;
    int autosize = -1;
    index_type[newRank] newstrides;
    foreach(i,val; newShape) {
        if (val<0) {
            assert(autosize==-1,"Only one shape dimension can be automatic");
            autosize = cast(int)i;
        } else {
            newsize *= cast(index_type)val;
        }
    }
    if (autosize!=-1) {
        newShape[autosize] = aSize/newsize;
        newsize *= newShape[autosize];
    }
    assert(newsize==aSize,"reshape cannot change the size of the array");
    
    index_type sz=cast(index_type)T.sizeof;
    static if (rank==1){
        sz=a.bStrides[0];
    }
    if (fortran){
        foreach(i, d; newShape) {
            newstrides[i] = sz;
            sz *= d;
        }
    } else {
        foreach_reverse(i, d; newShape) {
            newstrides[i] = sz;
            sz *= d;
        }
    }
    static if (rank==1) {
        return NArray!(T,newRank)(newstrides,newShape,a.startPtrArray,a.newFlags,a.newBase);
    } else {
        if (a.flags&ArrayFlags.Contiguous) {
            return NArray!(T,newRank)(newstrides,newShape,a.startPtrArray,a.newFlags,a.newBase);
        } else {
            // copy data to contiguous mem first.
            scope NArray!(T,rank) cpy = a.dup();
            T* newData=cpy.startPtrArray;
            uint newF=cpy.flags;
            auto res=NArray!(T,newRank)(newstrides,newShape,newData,newF,cpy.mBase);
            return res;
        }
    }
}
/// ditto
NArray!(TT.dtype,rkOfArgs!(S)) reshape(TT,S...)(TT a,S args)
    if (isNArray!(TT))
{
    alias rkOfArgs!(S) newRank;
    index_type[newRank] newShape;
    int irank=0;
    bool fortran=false;
    foreach(i,T;S){
        static if (is(T==ArrayFlags)){
            switch(args[i]){
            case ArrayFlags.Fortran:
                fortran=true;
                break;
            case ArrayFlags.Contiguous:
                fortran=false;
                break;
            default:
                assert(0,"unexpected ArrayFlags value, only Contiguos and Fortran accepted, not "~ctfe_i2s(args[i]));
            }
        } else {
            newShape[irank++]=cast(index_type)args[i];
        }
    }
    assert(irank==newRank);
    return reshapeR!(newRank)(a,newShape,fortran);
}

/// returns a flattened view of the array, copies if the array is not Contiguos
NArray!(T.dtype,1) ravel(T)(T a) if (isNArray!(T)) {
    return reshape(a,-1);
}

/// diagonal view
NArray!(T.dtype,1)diag(T)(T a) if (isNArray!(T))
in {
    static assert(T.dim>1,"rank must be at least 2");
    for (int i=0;i<T.dim;++i) assert(a.shape[0]==a.shape[i],"a must be square");
}
body {
    index_type inc=0;
    for (int i=0;i<T.dim;++i) inc+=a.bStrides[i];
    index_type[1] newstrides=inc, newshape=a.shape[0];
    return NArray!(T.dtype,1)(newstrides,newshape,a.startPtrArray,a.newFlags,a.newBase);
}
/+ --------- array creation ---------- +/

/// function to create free standing empty,zeros,ones
string freeFunMixin(string opName){
    return `
    template `~opName~`(V){
        template `~opName~`(S...){
            NArray!(V,rkOfArgs!(S)) `~opName~`(S args){
                alias rkOfArgs!(S) rank;
                index_type[rank] shape;
                int irank=0;
                bool fortran=false;
                foreach(i,T;S){
                    static if (is(T==ArrayFlags)){
                        switch(args[i]){
                        case ArrayFlags.Fortran:
                            fortran=true;
                            break;
                        case ArrayFlags.Contiguous:
                            fortran=false;
                            break;
                        default:
                            assert(0,"unexpected ArrayFlags value, only Contiguos and Fortran accepted, not "~ctfe_i2s(cast(int)args[i]));
                        }
                    } else {
                        shape[irank++]=cast(index_type)args[i];
                    }
                }
                assert(irank==rank);
                return NArray!(V,rank).`~opName~`(shape,fortran);
            }
        }
    }
    `;
}

/// returns an uninitialized NArray of type V and the requested shape
/// it is useful to alias empty!(double) emptyD; and then emptyD(10,3) creates a 10,3 NArray
mixin(freeFunMixin("empty"));
/// returns an NArray of 0 of type V and the requested shape
/// it is useful to alias zeros!(double) zerosD; and then zerosD(10,3) creates a 10,3 NArray
mixin(freeFunMixin("zeros"));
/// returns an NArray of 1 of type V and the requested shape
/// it is useful to alias zeros!(double) zerosD; and then zerosD(10,3) creates a 10,3 NArray
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
    istring loopBody=`
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
NArray!(BaseTypeOfArrays!(T),cast(int)rankOfArray!(T))a2NAC(T)(T arr,bool fortran=false){
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
            enum int rank=rankOfArray!(T);
            index_type[rank] shape;
            calcShapeArray!(T,rankOfArray!(T))(arr,shape);
            auto res=NArray!(V,cast(int)rankOfArray!(T)).empty(shape,fortran);
            istring loop_body="*resPtr0=cast(V)"~arrayInLoop("arr",rank,"i")~";";
            index_type optimalChunkSize_i=NArray!(V,cast(int)rankOfArray!(T)).defaultOptimalChunkSize;
            mixin(pLoopIdx(rank,["res"],loop_body,"i"));
            return res;
        }
    }
}
/// acquires an array using it as NArray, without copying.
/// reshape can be used to perform an immediate reshaping of the array (one -1 can be used for 
/// an implicitly calculated size)
/// if shouldFree=true it frees the array when destroyed (using stdc free)
/// fortran if it should be in fortran order (in fortran order the inner shapes are 1 by default, 
/// otherwise the outer ones)
NArray!(T,dim)a2NA(T,int dim=1,U=int)(T[] arr,bool shouldFree=false,bool fortran=false,U[] reshape=null){
    static assert(dim>0,"conversion for arrays of rank at least 1");
    uint flags=ArrayFlags.None;
    Guard guard;
    if (shouldFree) guard=new Guard(arr);
    auto totLen=arr.length;
    index_type[dim] strides,shape;
    if (reshape.length>0){
        size_t restDim=totLen;
        int posImplicit=-1;
        for(int idim=0;idim<dim;++idim){
            if(reshape[idim]<0){
                if (posImplicit!=-1){
                    throw new Exception("You can have only one implicit (<0) dimension in reshape",
                        __FILE__,__LINE__);
                }
                posImplicit=idim;
            } else {
                shape[idim]=reshape[idim];
                if (reshape[idim]!=0){
                    restDim/=reshape[idim];
                }
            }
        }
        if (posImplicit!=-1){
            shape[posImplicit]=cast(index_type)restDim;
        }
        restDim=1;
        for(int idim=0;idim<dim;++idim){
            restDim *= shape[idim];
        }
        if (restDim!=totLen){
            throw new Exception("incompatible dimensions in reshape",
                __FILE__,__LINE__);
        }
    } else {
        shape[]=1;
        if (!fortran){
            shape[$-1]=cast(index_type)totLen;
        } else {
            shape[0]=cast(index_type)totLen;
        }
    }
    if (!fortran){
        index_type stride=cast(index_type)T.sizeof;
        for(int idim=0;idim<dim;++idim){
            strides[idim]=stride;
            stride *= shape[idim];
        }
    } else {
        index_type stride=cast(index_type)T.sizeof;
        int idim=dim;
        while (idim!=0){
            strides[--idim]=stride;
            stride *= shape[idim];
        }
    }
    auto res=NArray!(T,dim)(strides,shape,0,arr,flags,guard);
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
string arrayInLoop(string arrName,int rank,string ivarStr){
    string res="";
    res~=arrName;
    for (int i=0;i<rank;++i)
        res~="["~ivarStr~"_"~ctfe_i2s(i)~"_]";
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
S reduceAllGen(alias foldOp,alias mergeOp, alias dupInitial,T,S=T.dtype)(T a,S x0) if (isNArray!(T))
{
    S x=dupInitial(x0);
    mixin(sLoopPtr(T.dim,["a"],"foldOp(x,*(aPtr0));\n","i"));
    mergeOp(x,x0);  /+ just to test it +/
    return x;
}

/// collects data on the whole array using the given folding operation
/// if not given mergeOp is built from foldOp 
S reduceAll(T,S=T.dtype,U=S delegate(S,T.dtype),V=S delegate(S,S))(scope U foldOp,T a,S x0,scope V mergeOp=null)
    if (isNArray!(T))
{
    if (mergeOp is null){
        mergeOp=(S x,S y){ x=foldOp(x,cast(T.dtype)y); };
    }
    return reduceAllGen!((ref S x,T y){ x=foldOp(x,y); },(ref S x,S y){ x=mergeOp(x,y); },(S x){ return x; },T,S)(a,x0);
}

/// applies an operation that "collects" data on an axis of the array
/// this is basically a possibly parallel fold on the array along that axis
/// foldOp(x,t) is the operations that accumulates on x the element t
/// of the array, mergeOp(x,y) merges in x the two partial results x and y
/// dupInitial(S x) is an operation that makes a copy of x at the beginning of the
/// folding (receiving the value in res), and can be used to set x0.
/// the folding starts with the corresponding element in the result array.
/// If S==T normally mergeOp==foldOp
SS reduceAxisGen(alias foldOp, alias mergeOp,alias dupInitial, T, SS=NArray!(T.dtype,T.dim-1))
    (T a, int axis=-1, SS res=SS.init)
    if (isNArray!(T))
in {
    assert(-T.dim<=axis && axis<T.dim,"axis out of bounds");
    int ii=0;
    static if (T.dim>1){
        if (! isNullNArray(res)){
            for(int i=0;i<T.dim;i++){
                if(i!=axis && i!=T.dim+axis){
                    assert(res.shape[ii]==a.shape[i],"invalid res shape");
                    ii++;
                }
            }
        }
    }
}
body  {
    static if (T.dim==1){
        SS x=dupInitial(res);
        mixin(sLoopPtr(T.dim,["a"],"foldOp(x,*(aPtr0));\n","i"));
        return x;
    } else {
        alias SS.dtype S;
        alias T.dim rank;
        alias T.dtype TT;
        void myFold(ref S x0,TT* startP, index_type my_stride, index_type my_dim){
            S x=dupInitial(x0);
            TT* ii=startP;
            for (index_type i=my_dim;i!=0;--i){
                foldOp(x,*ii);
                ii=cast(TT*)(cast(size_t)ii+my_stride);
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
            scope NArray!(TT,rank-1) tmp=NArray!(TT,rank-1)(newstrides,res.shape,a.startPtrArray,
                a.newFlags,a.newBase);
            index_type axisStride=a.bStrides[axis];
            index_type axisDim=a.shape[axis];
            index_type optimalChunkSize_i=(T.defaultOptimalChunkSize+axisDim-1)/axisDim;
            mixin(pLoopPtr(rank-1,["res","tmp"],
                "myFold(*resPtr0,tmpPtr0,axisStride,axisDim);\n","i"));
        }
    }
    return res;
}

/// applies a reduction operation along the given axis
U reduceAxis(T, S=T.dtype,V=S delegate(S,T),U=NArray!(S,T.dim-1),W=S delegate(S,S))
    (scope V foldOp,T a, S x0, int axis=-1, U res=U.init,scope W mergeOp=null)
        if (isNArray!(T))
{
    static if (T.dim>1)
        static assert(U.dim+1==T.dim,"dimension mismatch with "~T.stringof~" and "~U.stringof);
    if (mergeOp is null){
        mergeOp=(S x,S y){ x=foldOp(x,cast(T)y); };
    }
    return reduceAxisGen!((ref S x,T.dtype y){ x=foldOp(x,y); },(ref S x,S y){ x=mergeOp(x,y); },(S x){ return x0; })(a,axis,res);
}

/// sums along the given axis
S sumAxis(T,S=NArray!(T.dtype,T.dim-1)) (T a,int axis=-1, S res=S.init)
    if (isNArray!(T))
{
    static if (is(S.dtype)){
        alias S.dtype SS;
        static assert(S.dim+1==T.dim,"rank mismatch for result "~S.stringof~" when summing on an axis of "~T.stringof);
    } else {
        alias S SS;
        static assert(1==T.dim,"rank mismatch for result "~S.stringof~" when summing on an axis of "~T.stringof);
    }
    return reduceAxisGen!((ref SS x,T.dtype y){ x+=cast(SS)y; },(ref SS x,SS y){ x+=y; },(SS x){ return cast(SS)0; })
        (a,axis,res);
}

/// sum of the whole array
S sumAll(T,S=T.dtype)(T a) if (isNArray!(T)) {
    return reduceAllGen!((ref S x,T.dtype y){x+=cast(S)y;},(ref S x,S y){x+=y;}, (S x){ return x;},T,S)(a,cast(S)0);
}

/// multiplies of the whole array
S multiplyAll(T,S=T.dtype)(T a)
    if (isNArray!(T))
{
    return reduceAllGen!((ref S x,T.dtype y){x*=cast(S)y;},(ref S x,S y){x*=y;}, (S x){ return x; })(a,cast(S)1);
}
/// multiplies along an axis of the array
S multiplyAxis(T,S=NArray!(T.dtype,T.dim-1))(T a,int axis=-1,S res=S.init)
    if (isNArray!(T))
{
    static if (T.dim>1){
        alias S.dtype SS;
        static assert(S.dim+1==T.dim,"rank mismatch for result "~S.stringof~" when multiplying on an axis of "~T.stringof);
    } else {
        alias S SS;
    }
    return reduceAxisGen!(delegate void(ref SS x,T.dtype y){x=cast(SS)(x*y);},delegate void(ref SS x,SS y){x*=y;},delegate SS(SS x){ return cast(SS)1; })(a,axis,res);
}

/// fuses two arrays combining two axis of the same length with the given fuse op
/// basically this is a generalized dot product of tensors
/// implements a simple streaming algorithm (some blocking in the x direction would 
/// be a natural extension)
/// should look into something like "A Cache Oblivious Algorithm for Matrix 
/// Multiplication Based on Peano’s Space Filling Curve" by Michael Bader and Christoph Zenger
/// or other kinds of recursive refinements
void fuse1(alias fuseOp,alias inOp, alias outOp, TT,SS,UU)(TT a,
    SS b, ref UU c, int axis1=-1, int axis2=0,
    index_type optimalChunkSize=TT.defaultOptimalChunkSize)
in {
    alias TT.dim rank1;
    alias SS.dim rank2;
    static assert(rank1>0,"rank1 should be at least 1");
    static assert(rank2>0,"rank2 should be at least 1");
    assert(-rank1<=axis1 && axis1<rank1,"invalid axis1 in fuse1");
    assert(-rank2<=axis2 && axis2<rank2,"invalid axis2 in fuse1");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
    static if(rank1+rank2>2){
        alias UU.dim rank3;
        static assert(rank3==rank1+rank2-2,"rank3 has incorrect size");
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
    alias TT.dim rank1;
    alias SS.dim rank2;
    alias TT.dtype T;
    alias SS.dtype S;
    static if (is(UU.dtype))
        alias UU.dtype U;
    else
        alias UU U;
    void myFuse(U* x0,T* start1Ptr, index_type my_stride1, 
        S* start2Ptr, index_type my_stride2, index_type my_dim){
        T*yPtr=start1Ptr;
        S*zPtr=start2Ptr;
        U xVal;
        inOp(x0,xVal);
        for (index_type i=my_dim;i!=0;--i){
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
            istring innerLoop=`myFuse(c1Ptr0,tmp1Ptr0,a.bStrides[axis1],b.startPtrArray,
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
        istring innerLoop=pLoopPtr(rank2-1,["tmp2","c2"],
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
NArray!(TT.dtype,1) filterMask(TT,U)(TT a,U mask, index_type allocSize=0)
    if (isNArray!(TT) && isNArray!(U) && TT.dim==U.dim)
in { assert(mask.shape==a.shape); }
body {
    static assert(is(U.dtype:bool)||is(U.dtype:int),"mask should be castable to bool");
    alias TT.dtype T;
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
        //res=cast(T*)GC.malloc(resSize*T.sizeof,GC.BlkAttr.NO_SCAN);
        res=cast(T*)cstdlib.malloc(resSize*T.sizeof);
    } else {
        resA=new T[resSize];
        res=resA.ptr;
    }
    T* resP=res, resEnd=res+resSize;
    
    index_type ii=0;
    
    istring loopInstr=`
    if (*maskPtr0){
        if (resP==resEnd)
        {
            size_t newSize=min(resSize+a.nElArray/10,a.nElArray);
            if(manualAlloc){
                //res=cast(T*)GC.realloc(res,newSize*T.sizeof,GC.BlkAttr.NO_SCAN);
                res=cast(T*)cstdlib.realloc(res,newSize*T.sizeof);
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
    mixin(sLoopPtr(TT.dim,["a","mask"],loopInstr,"i"));
    resSize=resP-res;
    if(manualAlloc){
        //res=cast(T*)GC.realloc(res,resSize*T.sizeof,GC.BlkAttr.NO_SCAN);
        cstdlib.realloc(res,resSize*T.sizeof);
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
U unfilterMask(T,S,U=NArray!(T.dtype,S.dim))(T a,S mask, U res=U.init)
    if (isNArray!(T)&&isNArray!(S)&&isNArray!(U))
in{
    static assert(T.dim==1,"a needs to have rank 1");
    static assert(S.dim==U.dim,"mask and result need to have the same shape");
    static assert(is(S.dtype:bool)||is(S.dtype:int),"mask should be castable to bool");
    if (! isNullNArray(res)){
        assert(res.shape==mask.shape);
    }
    index_type nEl=sumAll!(typeof(mask),index_type)(mask);
    assert(nEl<=a.shape[0],"mask has more true elements than size of filtered array");
}
body {
    if (isNullNArray(res)){
        res=U.zeros(mask.shape);
    }
    T.dtype* elAtt=a.startPtrArray;
    index_type myStride=a.bStrides[0];
    istring loopInstr=`
    if (*maskPtr0){
        *resPtr0=*elAtt;
        elAtt=cast(T.dtype*)(cast(size_t)elAtt+myStride);
    }`;
    mixin(sLoopPtr(S.dim,["res","mask"],loopInstr,"i"));
    return res;
}

/// returns the reduction of the rank done by the arguments in the tuple
/// allow also static arrays?
template reductionFactorFilt(){
    enum int reductionFactorFilt=0;
}
/// ditto
template reductionFactorFilt(T,S...){
    static if (is(T==int) || is(T==long)||is(T==uint)||is(T==ulong)){
        enum int reductionFactorFilt=1+reductionFactorFilt!(S);
    } else static if (is(T==Range)){
        enum int reductionFactorFilt=reductionFactorFilt!(S);
    } else static if (is(T:int[])||is(T:long[])||is(T:uint[])||is(T:ulong[])){
        enum int reductionFactorFilt=reductionFactorFilt!(S);
    } else static if (is(T:NArray!(long,1))||is(T:NArray!(int,1))||is(T:NArray!(uint,1))||is(T:NArray!(ulong,1))){
        enum int reductionFactorFilt=reductionFactorFilt!(S);
    } else {
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactorFilt, this will fail");
    }
}

// creates an empty array of the requested shape for axis filtering (support function)
NArray!(T,rank-reductionFactorFilt!(S)) arrayAxisFilter(T,int rank,S...)(NArray!(T,rank) a,S idx_tup)
{
    enum int rank2=rank-reductionFactorFilt!(S);
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
                    "invalid lower range for dimension "~ctfe_i2s(i));
                if (step==0)
                    to=a.shape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.shape[i],
                    "invalid upper range for dimension "~ctfe_i2s(i));
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
string axisFilterLoop(T,int rank,V,S...)(string loopBody)
{
    string res;
    string indent;
    indent~="    ";
    enum int rank2=rank-reductionFactorFilt!(S);
    res~=indent~"enum int rank2=rank-reductionFactorFilt!(S);";
    res~=indent~"index_type from,to,step;\n";
    res~=indent~"T* aPtr"~ctfe_i2s(rank)~"=a.startPtrArray;\n";
    res~=indent~"T* bPtr"~ctfe_i2s(rank2)~"=b.startPtrArray;\n";
    for (int i=0;i<rank;++i){
        res~=indent~"index_type aStride"~ctfe_i2s(i)~"=a.bStrides["~ctfe_i2s(i)~"];\n";
        res~=indent~"index_type aShape"~ctfe_i2s(i)~"=a.shape["~ctfe_i2s(i)~"];\n";
    }
    for (int i=0;i<rank2;++i){
        res~=indent~"index_type bStride"~ctfe_i2s(i)~"=b.bStrides["~ctfe_i2s(i)~"];\n";
    }
    foreach(i,U;S){
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"aPtr"~ctfe_i2s(rank)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(rank)
                ~"+idx_tup["~ctfe_i2s(i)~"]*a.bStrides["~ctfe_i2s(i)~"]);\n";
        } else static if (is(U==Range)){
            res~=`
            from=idx_tup[i].from;
            to=idx_tup[i].to;
            step=idx_tup[i].inc;
            if (from<0) from+=a.shape[i];
            if (to<0) to+=a.shape[i]+1;
            if (from<to && step>=0 || from>to && step<0){
                assert(0<=from && from<a.shape[i],
                    "invalid lower range for dimension "~ctfe_i2s(i));
                if (step==0)
                    to=a.shape[i]-1;
                else
                    to=to-(to-from)%step;
                assert(to>=0 && to<=a.shape[i],
                    "invalid upper range for dimension "~ctfe_i2s(i));
            }
            `;
            res~=indent~"aPtr"~ctfe_i2s(rank)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(rank)
                ~"+from*a.bStrides["~ctfe_i2s(i)~"]);\n";
            res~=indent~"index_type j"~ctfe_i2s(i)~"_1=(to-from)/inc;\n";
            res~=indent~"aStride"~ctfe_i2s(i)~"*=inc;\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~"index_type j"~ctfe_i2s(i)~"_1=idx_tup["~ctfe_i2s(i)~"].length;\n";
        } else static if (is(U:NArray!(long,1))||is(U:NArray!(int,1))||is(U:NArray!(uint,1))||is(U:NArray!(ulong,1))){
            res~=indent~"index_type j"~ctfe_i2s(i)~"_1=idx_tup["~ctfe_i2s(i)~"].shape[0];\n";
            res~=indent~"index_type j"~ctfe_i2s(i)~"_2=idx_tup["~ctfe_i2s(i)~"].bStrides[0];\n";
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in reductionFactorFilt, this will fail");
        }
    }
    int ii=0;
    foreach(i,U;S){
        string indent2=indent~"    ";
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent~"{\n";
            res~=indent2~"T* aPtr"~ctfe_i2s(rank-i-1)~"=aPtr"~ctfe_i2s(rank-i)~";\n";
        } else static if (is(U==Range)){
            res~=indent~"T* aPtr"~ctfe_i2s(rank-i-1)~"=aPtr"~ctfe_i2s(rank-i)~";\n";
            res~=indent~"T* bPtr"~ctfe_i2s(rank2-ii-1)~"=bPtr"~ctfe_i2s(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2s(i)~"=j"~ctfe_i2s(i)~"_1;i"~ctfe_i2s(i)~"!=0;--i"~ctfe_i2s(i)~"){\n";
            ++ii;
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            res~=indent~BaseTypeOfArrays!(U).stringof~"* idx"~ctfe_i2s(i)~"=idx_tup["~ctfe_i2s(i)~"].ptr;\n";
            res~=indent~"T* bPtr"~ctfe_i2s(rank2-ii-1)~"=bPtr"~ctfe_i2s(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2s(i)~"=0;i"~ctfe_i2s(i)~"!=j"~ctfe_i2s(i)~"_1;++i"~ctfe_i2s(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2s(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(rank-i)~
                "+cast(index_type)(*idx"~ctfe_i2s(i)~")*aStride"~ctfe_i2s(i)~");\n";
            ++ii;
        } else static if (is(U:NArray!(long,1))||is(U:NArray!(int,1))||is(U:NArray!(uint,1))||is(U:NArray!(ulong,1))){
            res~=indent;
            static if (is(U:NArray!( long,1))) res~="long";
            static if (is(U:NArray!(  int,1))) res~="int";
            static if (is(U:NArray!(ulong,1))) res~="ulong";
            static if (is(U:NArray!( uint,1))) res~="uint";
            res~="* idx"~ctfe_i2s(i)~
                "=idx_tup["~ctfe_i2s(i)~"].startPtrArray;\n";
            res~=indent~"T* bPtr"~ctfe_i2s(rank2-ii-1)~"=bPtr"~ctfe_i2s(rank2-ii)~";\n";
            res~=indent~"for(index_type i"~ctfe_i2s(i)~"=0;i"~ctfe_i2s(i)~"!=j"~ctfe_i2s(i)~"_1;++i"~ctfe_i2s(i)~"){\n";
            res~=indent2~"T* aPtr"~ctfe_i2s(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(rank-i)~
                "+cast(index_type)(*idx"~ctfe_i2s(i)~")*aStride"~ctfe_i2s(i)~");\n";
            ++ii;
        } else {
            static assert(0,"ERROR: unexpected type <"~U.stringof~"> in axisFilterLoop, this will fail");
        }
        indent=indent2;
    }
    for (int i=rank2-ii;i>0;--i){
        string indent2=indent~"    ";
        res~=indent~"T* aPtr"~ctfe_i2s(i-1)~"=aPtr"~ctfe_i2s(i)~";\n";
        res~=indent~"T* bPtr"~ctfe_i2s(i-1)~"=bPtr"~ctfe_i2s(i)~";\n";
        res~=indent~"for (index_type iIn"~ctfe_i2s(i-1)~"=aShape"~ctfe_i2s(rank-i)~";iIn"~ctfe_i2s(i-1)~"!=0;--iIn"~ctfe_i2s(i-1)~"){\n";
        indent=indent2;
    }
    res~=indent~loopBody~"\n";
    for (int i=0;i<rank2-ii;++i){
        assert(indent.length>=4);
        string indent2=indent[0..(indent.length-4)];
        res~=indent~"aPtr"~ctfe_i2s(i)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(i)
            ~"+aStride"~ctfe_i2s(rank-1-i)~");\n";
        res~=indent~"bPtr"~ctfe_i2s(i)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2s(i)
            ~"+bStride"~ctfe_i2s(rank-1-i)~");\n";
        res~=indent2~"}\n";
        indent=indent2;
    }
    foreach_reverse(i,U;S){
        assert(indent.length>=4);
        string indent2=indent[0..(indent.length-4)];
        static if (is(U==int) || is(U==long)||is(U==uint)||is(U==ulong)){
            res~=indent2~"}\n";
        } else static if (is(U==Range)){
            --ii;
            res~=indent~"aPtr"~ctfe_i2s(rank-i-1)~"=cast(T*)(cast(size_t)aPtr"~ctfe_i2s(rank-i-1)
                ~"+aStride"~ctfe_i2s(i)~");\n";
            res~=indent~"bPtr"~ctfe_i2s(rank2-ii-1)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2s(rank2-ii-1)
                ~"+bStride"~ctfe_i2s(ii)~");\n";
            res~=indent2~"}\n";
        } else static if (is(U:int[])||is(U:long[])||is(U:uint[])||is(U:ulong[])){
            --ii;
            res~=indent~"++idx"~ctfe_i2s(i)~";\n";
            res~=indent~"bPtr"~ctfe_i2s(rank2-ii-1)~"=cast(T*)(cast(size_t)bPtr"~ctfe_i2s(rank2-ii-1)
                ~"+bStride"~ctfe_i2s(ii)~");\n";
            res~=indent2~"}\n";
        } else static if (is(U:NArray!(long,1))||is(U:NArray!(int,1))||is(U:NArray!(uint,1))||is(U:NArray!(ulong,1))){
            --ii;
            res~=indent~"idx"~ctfe_i2s(i)~"=cast(typeof(idx"~ctfe_i2s(i)~"))"
                ~"(cast(size_t)idx"~ctfe_i2s(i)~"+j"~ctfe_i2s(i)~"_2);\n";
            res~=indent~"bPtr"~ctfe_i2s(rank2-ii-1)~"=cast(T*)"
                ~"(cast(size_t)bPtr"~ctfe_i2s(rank2-ii-1)~"+bStride"~ctfe_i2s(ii)~");\n";
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
B axisFilter1(TT,B,S...)(TT a,B b,S idx_tup)
        if (isNArray!(TT))
{
    alias TT.dim rank;
    alias TT.dtype T;
    static if (TT.dim>reductionFactorFilt!(S))
        static assert(isNArray!(B)&&B.dim==TT.dim-reductionFactorFilt!(S),"invalid result type "~B.stringof~" for axis filter "~S.stringof~" on "~TT.stringof);
    else
        static assert(TT.dim==reductionFactorFilt!(S),"invalid result type "~B.stringof~" for axis filter "~S.stringof~" on "~T.stringof);
    static assert(nArgs!(S)<=TT.dim,"too many indexing arguments");
    mixin(axisFilterLoop!(TT.dtype,TT.dim,B.dtype,S)("*bPtr0 = *aPtr0;"));
    return b;
}

/// Filters the array a using indexes, ranges and index arrays and returns the result
NArray!(T.dtype,T.dim-reductionFactorFilt!(S))axisFilter(T,S...)(T a,S index)
    if (isNArray!(T))
{
    static assert(nArgs!(S)<=T.dim,"too many indexing arguments");
    NArray!(T.dtype,T.dim-reductionFactorFilt!(S)) res=arrayAxisFilter!(T.dtype,T.dim,S)(a,index);
    return axisFilter1!(T,typeof(res),S)(a,res,index);
}

/// unfilters an array
TT axisUnfilter1(TT,V,S...)
    (TT a,V b,S idx_tup) if (isNArray!(TT))
{
    static if (TT.dim>reductionFactorFilt!(S))
        static assert(V.dim==TT.dim-reductionFactorFilt!(S),"b has incorrect rank, expected "~
                      ctfe_i2s(TT.dim-reductionFactorFilt!(S))~" got "~ctfe_i2s(V.dim));
    else
        static assert(TT.dim==reductionFactorFilt!(S),"invalid result type "~B.stringof~" for axis filter "~S.stringof~" on "~TT.stringof);
    static assert(nArgs!(S)<=TT.dim,"too many indexing arguments");
    alias TT.dim rank;
    alias TT.dtype T;
    mixin(axisFilterLoop!(TT.dtype,TT.dim,V.dtype,S)("*aPtr0=*bPtr0;"));
    return a;
}

// -------------- norm/compare -------------
/// feqrel version more forgiving close to 0
/// if you sum values you cannot expect better than magnitude*T.epsilon absolute error.
/// feqrel compares relative error, and close to 0 (where the density of floats is high)
/// it is much more stringent.
/// To guarantee T.epsilon absolute error one should use magnitude=1.0.
/// by default we are more stingent and we use T.mant_dig/4 digits more when close to 0.
int feqrel2(T,U=RealTypeOf!(T))(T x,T y,U magnitude_=ctfe_powI(0.5,T.mant_dig/4)){
    RealTypeOf!(T) magnitude=cast(RealTypeOf!(T))magnitude_;
    assert(magnitude>=0,"magnitude should be non negative");
    static if(isComplexType!(T)){
        return min(feqrel2(x.re,y.re),feqrel2(x.im,y.im));
    } else {
        if (x<0){
            return feqrel(x-magnitude,y-magnitude);
        } else {
            return feqrel(x+magnitude,y+magnitude);
        }
    }
}

/// returns the minimum number of significand bits in common between array a and b
/// using feqrel2
int minFeqrel2(T,V,U=RealTypeOf!(T.dtype))(T a,V b,U magnitude=ctfe_powI(0.5,T.dtype.mant_dig/4))
    if (isNArray!(T) && isNArray!(V) && T.dim==V.dim)
in { assert(b.shape==a.shape,"array need to have the same size in minFeqrel"); }
body {
    int minEq=T.dtype.mant_dig;
    mixin(sLoopPtr(T.dim,["a","b"],
        "int diffAtt=feqrel2!(T.dtype)(*aPtr0,*bPtr0,magnitude); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

/// returns the minimum number of significand bits in common between this array and b
int minFeqrel(T,U=T.dtype)(T a,U b=cast(U)0){
    int minEq=feqrel(T.dtype.init,T.dtype.init);
    mixin(sLoopPtr(T.dim,["a"],
        "int diffAtt=feqrel(*aPtr0,b); if (diffAtt<minEq) minEq=diffAtt;","i"));
    return minEq;
}

template TypeOfNorm22NARes(T){
    static if(is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        alias RealTypeOf!(T) TypeOfNorm22NARes;
    } else {
        alias T TypeOfNorm22NARes;
    }
}

/// return the square of the 2 norm of the array
S norm22NA(T,S=TypeOfNorm22NARes!(T.dtype))(T a)
    if (isNArray!(T))
{
    static if(is(T.dtype==cfloat)||is(T.dtype==cdouble)||is(T.dtype==creal)){
        S res=reduceAllGen!((ref S x,T.dtype y){ x+=cast(S)y.re * cast(S)y.re + cast(S)y.im * cast(S)y.im; },
            (ref S x,S y){ x+=y; }, (S x){return x;})(a,cast(S)0);
    } else {
        S res=reduceAllGen!((ref S x,T.dtype y){ x+=cast(S)y*cast(S)y; },(ref S x,S y){ x+=y; }, (S x){return x;})
            (a,cast(S)0);
    }
    return res;
}

S norm2NA(T, S=TypeOfNorm22NARes!(T.dtype))(T a)
    if (isNArray!(T))
{
    return cast(S)sqrt(norm22NA!(T,S)(a));
}

/// generic norm22 return type
template TypeOfNorm22(T){
    static if (is(typeof(T.norm22(T.init)))){
        alias typeof(T.norm22(T.init)) ResType;
    } else static if (is(typeof(T.init.norm22()))){
        alias typeof(T.init.norm22()) ResType;
    } else static if (is(typeof(norm22NA(T.init)))){
        alias typeof(norm22NA(T.init)) ResType;
    } else {
        alias void ResType;
    }
}
/// generic squared norm2
TypeOfNorm22!(T).ResType norm22(T)(T t){
    static if (is(typeof(T.norm22(t)))){
        return T.norm22(t);
    } else static if (is(typeof(t.norm22()))){
        return t.norm22();
    } else static if (is(typeof(norm22NA(t)))){
        return norm22NA(t);
    } else {
        static assert(0,"could not find an implementation of norm22 for type "~T.stringof);
    }
}

/// generic norm22 return type
template TypeOfNorm2(T){
    static if (is(typeof(T.norm2(T.init)))){
        alias typeof(T.norm2(T.init)) ResType;
    } else static if (is(typeof(T.init.norm22()))){
        alias typeof(T.init.norm2()) ResType;
    } else static if (is(typeof(sqrt(norm22(T.init))))){
        alias typeof(sqrt(norm22(T.init))) ResType;
    } else {
        alias void ResType;
    }
}
/// generic squared norm2
TypeOfNorm2!(T).ResType norm2(T)(T t){
    static if (is(typeof(T.norm2(t)))){
        return T.norm2(t);
    } else static if (is(typeof(t.norm2()))){
        return t.norm2();
    } else static if (is(typeof(sqrt(norm22(t))))){
        return sqrt(norm22(t));
    } else {
        static assert(0,"could not find an implementation of norm2 for type "~T.stringof);
    }
}

/// makes the array hermitish (a==a.H) should use a recursive algorithm
T hermitize(T)(T a){
    static if (isComplexType!(T.dtype)){
        auto b=a.T;
        index_type optimalChunkSize_i=T.defaultOptimalChunkSize;
        mixin(pLoopPtr(T.dim,["a","b"],
        "if (aPtr0<=bPtr0) {T.dtype val=((*aPtr0).re+(*bPtr0).re+cast(T.dtype)1i*((*aPtr0).im-(*bPtr0).im))/cast(T.dtype)2; *aPtr0=val; *bPtr0=val.re-cast(T.dtype)1i*val.im;}","i"));
        return a;
    } else static if (isImaginaryType!(T.dtype)){
        return antiSymmetrize(a);
    } else {
        return symmetrize(a);
    }
}

/// symmetrizes the array
T symmetrize(T)(T a){
    auto b=a.T;
    index_type optimalChunkSize_i=T.defaultOptimalChunkSize;
    mixin(pLoopPtr(T.dim,["a","b"],
    "if (aPtr0<bPtr0) {T.dtype val=(*aPtr0+*bPtr0)/cast(T.dtype)2; *aPtr0=val; *bPtr0=val;}","i"));
    return a;
}

/// anti symmetrizes the array
T antiSymmetrize(T)(T a){
    auto b=a.T;
    index_type optimalChunkSize_i=T.defaultOptimalChunkSize;
    mixin(pLoopPtr(T.dim,["a","b"],
    "if (aPtr0<bPtr0) {T.dtype val=(*aPtr0-*bPtr0)/cast(T.dtype)2; *aPtr0=val; *bPtr0=-val;}","i"));
    return a;
}
