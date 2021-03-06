/// Basic linear algebra on NArrays
/// at the moment only dot is available without blas/lapack
///  inv        --- Inverse of a square matrix
///  solve      --- Solve a linear system of equations
///  det        --- Determinant of a square matrix
///  eig        --- Eigenvalues and vectors of a square matrix
///  eigh       --- Eigenvalues and eigenvectors of a Hermitian matrix
///  svd        --- Singular value decomposition of a matrix
///  
///  nice to add:
///  dgesvx/zgesvx (advanced linear solvers)
///  cholesky   --- Cholesky decomposition of a matrix
///  optimize lapack based calls for contiguous inputs
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
module blip.narray.NArrayLinAlg;
import blip.narray.NArrayType;
import blip.narray.NArrayBasicOps;
import blip.math.Math:min,max,round,sqrt,ceil,abs;
import blip.stdc.string:memcpy;
import blip.util.TemplateFu: nArgs;
import blip.core.Traits:isComplexType,isImaginaryType,ComplexTypeOf,RealTypeOf,isAtomicType;
import blip.Comp;
//import tango.util.log.Trace; //pippo

/// return type of the generic dot operation
template TypeOfDot(T,U,S...){
    struct dummy{ T t; U u; S args; } // .init sometime fails (for tuples of complex types for example), thus going this way
    static if (is(typeof(T.dotOp(dummy.init.t,dummy.init.u,dummy.init.args)))){ // static T.dotOp
        alias typeof(T.dotOp(dummy.init.t,dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(U.dotOp(dummy.init.t,dummy.init.u,dummy.init.args)))){ // static U.dotOp
        alias typeof(U.dotOp(dummy.init.t,dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.t.opDot(dummy.init.u,dummy.init.args)))){ // t.opDot
        alias typeof(dummy.init.t.opDot(dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.u.opDot_r(dummy.init.t,dummy.init.args)))){ // u.opDot_r
        alias typeof(dummy.init.u.opDot_r(dummy.init.t,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.t.opVecMul(dummy.init.u,dummy.init.args)))){ // t.opVecMul
        alias typeof(dummy.init.t.opVecMul(dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.u.opVecMul_r(dummy.init.t,dummy.init.args)))){ // u.opVecMul_r
        alias typeof(dummy.init.u.opVecMul_r(dummy.init.t,dummy.init.args)) ResType;
    } else static if (is(typeof(dotNA(dummy.init.t,dummy.init.u,dummy.init.args)))){ // NArray dot
        alias typeof(dotNA(dummy.init.t,dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.t.opMul(dummy.init.u,dummy.init.args)))){ // t.opMul
        alias typeof(dummy.init.t.opMul(dummy.init.u,dummy.init.args)) ResType;
    } else static if (is(typeof(dummy.init.u.opMul_r(dummy.init.t,dummy.init.args)))){ // u.opMul_r
        alias typeof(dummy.init.u.opMul_r(dummy.init.t,dummy.init.args)) ResType;
    } else static if(nArgs!(S)==0 && is(typeof(dummy.init.t*dummy.init.u))){ // multiplication (for scalars)
        alias typeof(dummy.init.t*dummy.init.u) ResType;
    } else {
        alias void ResType;
    }
}

/// generic op dot
TypeOfDot!(T,U,S).ResType dot(T,U,S...)(T t,U u,S args){
    static if (is(typeof(T.dotOp(t,u,args)))){ // static T.dotOp
        static if(is(typeof(T.dotOp(t,u,args))==void)){
            T.dotOp(t,u,args);
        } else {
            return T.dotOp(t,u,args);
        }
    } else static if (is(typeof(U.dotOp(t,u,args)))){ // static U.dotOp
        static if(is(typeof(U.dotOp(t,u,args))==void)){
            U.dotOp(t,u,args);
        } else {
            return U.dotOp(t,u,args);
        }
    } else static if (is(typeof(t.opDot(u,args)))){ // t.opDot
        static if(is(typeof(t.opDot(u,args))==void)){
            t.opDot(u,args);
        } else {
            return t.opDot(u,args);
        }
    } else static if (is(typeof(u.opDot_r(t,args)))){ // u.opDot_r
        static if(is(typeof(u.opDot_r(t,args))==void)){
            u.opDot_r(t,args);
        } else {
            return u.opDot_r(t,args);
        }
    } else static if (is(typeof(t.opVecMul(u,args)))){ // t.opVecMul
        static if(is(typeof(t.opVecMul(u,args))==void)){
            t.opVecMul(u,args);
        } else {
            return t.opVecMul(u,args);
        }
    } else static if (is(typeof(u.opVecMul_r(t,args)))){ // u.opVecMul_r
        static if(is(typeof(u.opVecMul_r(t,args))==void)){
            u.opVecMul_r(t,args);
        } else {
            return u.opVecMul_r(t,args);
        }
    } else static if (is(typeof(dotNA(t,u,args)))){ // NArray dot
        /// it is defined here because NArray dot is speacial, being so large it was split in several
        /// modules and putting it in NArray would create circular refs (or a huge module)
        /// unfortunaley (by design?) the only "free" templates that are picked up are those that are
        /// locally visible where the template is defined. To have other ones a mixin is needed...
        return dotNA(t,u,args);
    } else static if (is(typeof(t.opMul(u,args)))){ // t.opMul
        static if(is(typeof(t.opMul(u,args))==void)){
            t.opMul(u,args);
        } else {
            return t.opMul(u,args);
        }
    } else static if (is(typeof(u.opMul_r(t,args)))){ // u.opMul_r
        static if(is(typeof(u.opMul_r(t,args))==void)){
            u.opMul_r(t,args);
        } else {
            return u.opMul_r(t,args);
        }
    } else static if(nArgs!(S)==0 && is(typeof(t*u))){ // multiplication (for scalars)
        static if(is(typeof(t*u)==void)){
            t*u;
        } else {
            return t*u;
        }
    } else {
        static assert(0,"could not find a valid definition of dot with the following arguments:"~
            T.stringof~","~U.stringof~","~S.stringof);
    }
}

/// return type of the generic outer multiplication operation
template TypeOfOuter(T,U,S...){
    struct dummyS{ T t; U u; S args; } // .init sometime fails (for tuples of complex types for example), thus going this way
    static if (is(typeof(T.outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)))){ // static T.outerOp
        alias typeof(T.outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)) ResType;
    } else static if (is(typeof(U.outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)))){ // static U.outerOp
        alias typeof(U.outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)) ResType;
    } else static if (nArgs!(S)>0 && is(typeof(S[0].outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)))){ // static S[0].outerOp
        alias typeof(S[0].outerOp(dummyS.init.t,dummyS.init.u,dummyS.init.args)) ResType;
    } else static if (is(typeof(dummyS.init.t.opOuter(dummyS.init.u,dummyS.init.args)))){ // t.opOuter
        alias typeof(dummyS.init.t.opOuter(dummyS.init.u,dummyS.init.args)) ResType;
    } else static if (is(typeof(dummyS.init.u.opOuter_r(dummyS.init.t,dummyS.init.args)))){ // u.opOuter_r
        alias typeof(dummyS.init.u.opOuter_r(dummyS.init.t,dummyS.init.args)) ResType;
    } else static if (is(typeof(outerNA(dummyS.init.t,dummyS.init.u,dummyS.init.args)))){ // NArray outer
        alias typeof(outerNA(dummyS.init.t,dummyS.init.u,dummyS.init.args)) ResType;
    } else static if(nArgs!(S)==0 && (isAtomicType!(T) || isAtomicType!(U)) && is(typeof(dummyS.init.t*dummyS.init.u))){
        alias typeof(dummyS.init.t*dummyS.init.u) ResType;
    } else static if ((nArgs!(S)==1 || nArgs!(S)==2 || nArgs!(S)==3) && isAtomicType!(U) && is(typeof(bypax(dummyS.init.args[0],dummyS.init.t,dummyS.init.args[1..$])))){
        alias S[0] ResType;
    } else static if ((nArgs!(S)==1 || nArgs!(S)==2 || nArgs!(S)==3) && isAtomicType!(T) && is(typeof(bypax(dummyS.init.args[0],dummyS.init.u,dummyS.init.args[1..$])))){
        alias S[0] ResType;
    } else {
        alias void ResType;
    }
}

/// generic op outer
/// normally it should be like (tensorA,tensorB[[,targetTensor],scaleAB=1,scaleTarget=1])
/// and will return the result
TypeOfOuter!(T,U,S).ResType outer(T,U,S...)(T t,U u,S args){
    static if (is(typeof(T.outerOp(t,u,args)))){ // static T.outerOp
        static if(is(typeof(T.outerOp(t,u,args))==void)){
            T.outerOp(t,u,args);
        } else {
            return T.outerOp(t,u,args);
        }
    } else static if (is(typeof(U.outerOp(t,u,args)))){ // static U.outerOp
        static if(is(typeof(U.outerOp(t,u,args))==void)){
            U.outerOp(t,u,args);
        } else {
            return U.outerOp(t,u,args);
        }
    } else static if (nArgs!(S)>0 && is(typeof(S[0].outerOp(t,u,args)))){ // static U.outerOp
        static if(is(typeof(S[0].outerOp(t,u,args))==void)){
            S[0].outerOp(t,u,args);
        } else {
            return S[0].outerOp(t,u,args);
        }
    } else static if (is(typeof(t.opOuter(u,args)))){ // t.opOuter
        static if(is(typeof(t.opOuter(u,args))==void)){
            t.opOuter(u,args);
        } else {
            return t.opOuter(u,args);
        }
    } else static if (is(typeof(u.opOuter_r(t,args)))){ // u.opOuter_r
        static if(is(typeof(u.opOuter_r(t,args))==void)){
            u.opOuter_r(t,args);
        } else {
            return u.opOuter_r(t,args);
        }
    } else static if (is(typeof(outerNA(t,u,args)))){ // NArray outer
        /// it is defined here because NArray outer is special, being so large it was split in several
        /// modules and putting it in NArray would create circular refs (or a huge module)
        /// unfortunaley (by design?) the only "free" templates that are picked up are those that are
        /// locally visible where the template is defined. To have other ones a mixin is needed...
        return outerNA(t,u,args);
    } else static if(nArgs!(S)==0 && (isAtomicType!(T) || isAtomicType!(U)) && is(typeof(t*u))){ // multiplication (for scalars), enlarge support to all opMul? dot and outer are the same *only* for scalars... not (for example) for matrix multiplication
        return t*u;
    } else static if (nArgs!(S)==1 && isAtomicType!(U) && is(typeof(bypax(args[0],t,u)))){
        bypax(args[0],t,u);
        return args[0];
    } else static if (nArgs!(S)==2 && isAtomicType!(U) && is(typeof(bypax(args[0],t,u*args[1])))){
        bypax(args[0],t,u*args[1]);
        return args[0];
    } else static if (nArgs!(S)==3 && isAtomicType!(U) && is(typeof(bypax(args[0],t,u*args[1],args[2])))){
        bypax(args[0],t,u*args[1],args[2]);
        return args[0];
    } else static if (nArgs!(S)==1 && isAtomicType!(T) && is(typeof(bypax(args[0],u,t)))){
        bypax(args[0],u,t);
        return args[0];
    } else static if (nArgs!(S)==2 && isAtomicType!(T) && is(typeof(bypax(args[0],u,t*args[1])))){
        bypax(args[0],u,t*args[1]);
        return args[0];
    } else static if (nArgs!(S)==3 && isAtomicType!(T) && is(typeof(bypax(args[0],u,t*args[1],args[2])))){
        bypax(args[0],u,t*args[1],args[2]);
        return args[0];
    } else {
        static assert(0,"could not find a valid definition of outer with the following arguments:"~
            T.stringof~","~U.stringof~","~S.stringof);
    }
}


/// generic bypax, this is like blas axpy: but the modified argument is the the first one, y
/// so that bypax(y,x) is equivalent to y.opBypax(x)
void bypax(T,U,S...)(ref T t,U u,S args){
    static if (is(typeof(T.bypaxOp(t,u,args)))){ // static T.outerOp
        T.bypaxOp(t,u,args);
    } else static if (is(typeof(U.bypaxOp(t,u,args)))){
        U.bypaxOp(t,u,args);
    } else static if (is(typeof(t.opBypax(u,args)))){
        t.opBypax(u,args);
    } else static if (is(typeof(u.opBypax_r(t,args)))){
        u.opBypax_r(t,args);
    } else static if (nArgs!(S)==0 && is(typeof(t+=u))){
        t+=u;
    } else static if (nArgs!(S)==0 && is(typeof(t=u+t))){
        t=u+t;
    } else static if (nArgs!(S)==1 && is(typeof(t+=u*args[0]))){
        t+=u*args[0];
    } else static if (nArgs!(S)==1 && is(typeof(t=t+u*args[0]))){
        t=t+u*args[0];
    } else static if (nArgs!(S)==2 && is(typeof(t=args[1]*t+args[0]*u))){
        t=args[1]*t+args[0]*u;
    } else {
        static assert(0,"could not find a valid definition of bypax with the following arguments:"~
            T.stringof~","~U.stringof~","~S.stringof);
    }
}

version(no_blas){ 
    version(no_lapack){ }
    else {
        static assert(false,"lapack needs blas");
    }
} else {
    import DBlas=blip.bindings.blas.DBlas;
    public import blip.bindings.blas.Types;
}
version(no_lapack){ }
else {
    import DLapack=blip.bindings.lapack.DLapack;
}

class LinAlgException:Exception{
    this(string err){
        super(err);
    }
}

/// dot product between tensors (reduces a single axis) with scaling and
/// already present storage target
NArray!(S,rank3)dotNA(T,int rank1,U,int rank2,S,int rank3)
    (NArray!(T,rank1)a, NArray!(U,rank2)b, ref NArray!(S,rank3) c,
        S scaleRes=cast(S)1, S scaleC=cast(S)0, int axis1=-1, int axis2=0)
in {
    static assert(rank3==rank1+rank2-2,"rank3 has to be rank1+rank2-2");
    assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
    assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
    int ii=0;
    static if(rank3!=0){
        for (int i=0;i<rank1;++i){
            if (i!=axis1 && i!=rank1+axis1){
                assert(c.shape[ii]==a.shape[i],"invalid shape for c");
                ++ii;
            }
        }
        for (int i=0;i<rank2;++i){
            if (i!=axis2 && i!=rank2+axis2){
                assert(c.shape[ii]==b.shape[i],"invalid shape for c");
                ++ii;
            }
        }
    }
}
body {
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    if ((a.flags|b.flags)&ArrayFlags.Zero){
        if (scaleC==0){
            static if(rank3>0){
                c[]=cast(S)0;
            } else {
                c=cast(S)0;
            }
        } else {
            c *= scaleC;
        }
        return c;
    }
    version(no_blas){ }
    else {
        static if ((is(T==U) && isBlasType!(T)) && (rank1==1 || rank1==2)&&(rank2==1 || rank2==2)){
            // call blas
            // negative incremented vector in blas loops backwards on a[0..n], not on a[-n+1..1]
            static if(rank1==1 && rank2==1){
                version(CBlasDot){
                    T* aStartPtr=a.startPtrArray,bStartPtr=b.startPtrArray;
                    if (a.bStrides[0]<0) aStartPtr=cast(T*)(cast(size_t)aStartPtr+(a.shape[0]-1)*a.bStrides[0]);
                    if (b.bStrides[0]<0) bStartPtr=cast(T*)(cast(size_t)bStartPtr+(b.shape[0]-1)*b.bStrides[0]);
                    static if (is(T==f_float) && is(S==f_double)){
                        c=cast(S)DBlas.ddot(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                            bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                    } else static if (is(T==cfloat)|| is(T==cdouble)){
                        c=cast(S)DBlas.dotu(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                            bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                    } else {
                        c=cast(S)DBlas.dot(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                            bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                    }
                    return c;
                }
            } else static if (rank1==1 && rank2==2) {
                T* aStartPtr=a.startPtrArray;
                if (a.bStrides[0]<0) aStartPtr=cast(T*)(cast(size_t)aStartPtr+(a.shape[0]-1)*a.bStrides[0]);
                if (b.bStrides[0]==cast(index_type)T.sizeof && b.bStrides[1]>0 ||
                    b.bStrides[1]==cast(index_type)T.sizeof && b.bStrides[0]>0){
                    int transpose=1;
                    if (axis2==1) transpose=0;
                    if (b.bStrides[0]!=cast(index_type)T.sizeof) transpose=!transpose;
                    f_int ldb=cast(f_int)((b.bStrides[0]==cast(index_type)T.sizeof)?b.bStrides[1]:b.bStrides[0]);
                    f_int m=(transpose?a.shape[0]:c.shape[0]);
                    // this check is needed to give a valid ldb to blas (that checks it)
                    // even if ldb is never needed (only one column)
                    if (ldb!=cast(f_int)T.sizeof){
                        ldb/=cast(index_type)T.sizeof;
                    } else {
                        ldb=m;
                    }
                    DBlas.gemv((transpose?'T':'N'), m,
                        (transpose?c.shape[0]:a.shape[0]),scaleRes,
                        b.startPtrArray, ldb,
                        aStartPtr,a.bStrides[0]/cast(index_type)T.sizeof,
                        scaleC, c.startPtrArray, c.bStrides[0]/cast(index_type)T.sizeof);
                    return c;
                }
            } else static if (rank1==2 && rank2==1) {
                T* bStartPtr=b.startPtrArray;
                if (b.bStrides[0]<0) bStartPtr=cast(T*)(cast(size_t)bStartPtr+(b.shape[0]-1)*b.bStrides[0]);
                if (a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>0 ||
                    a.bStrides[1]==cast(index_type)T.sizeof && a.bStrides[0]>0){
                    int transpose=1;
                    if (axis1==1) transpose=0;
                    if (a.bStrides[0]!=cast(index_type)T.sizeof) transpose=!transpose;
                    f_int lda=cast(f_int)((a.bStrides[0]==cast(index_type)T.sizeof)?a.bStrides[1]:a.bStrides[0]);
                    f_int m=(transpose?b.shape[0]:c.shape[0]);
                    // this check is needed to give a valid lda to blas (that checks it)
                    // even if lda is never needed (only one column)
                    if (lda!=cast(f_int)T.sizeof){
                        lda/=cast(index_type)T.sizeof;
                    } else {
                        lda=m;
                    }
                    DBlas.gemv((transpose?'T':'N'), m,
                        (transpose?c.shape[0]:b.shape[0]), scaleRes,
                        a.startPtrArray, lda,
                        bStartPtr,b.bStrides[0]/cast(index_type)T.sizeof,
                        scaleC, c.startPtrArray, c.bStrides[0]/cast(index_type)T.sizeof);
                    return c;
                }
            } else static if(is(S==T)){
                static assert(rank1==2 && rank2==2);
                if ((a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>0 || a.bStrides[1]==cast(index_type)T.sizeof && a.bStrides[0]>0)&&
                    (b.bStrides[0]==cast(index_type)T.sizeof && b.bStrides[1]>0 || b.bStrides[1]==cast(index_type)T.sizeof && b.bStrides[0]>0)&&
                    (c.bStrides[0]==cast(index_type)T.sizeof && c.bStrides[1]>0 || c.bStrides[1]==cast(index_type)T.sizeof && c.bStrides[0]>0)){
                    int transposeA=0;
                    if (axis1==0) transposeA=1;
                    if (a.bStrides[0]!=cast(index_type)T.sizeof) transposeA=!transposeA;
                    int transposeB=0;
                    if (axis2==1) transposeB=1;
                    if (b.bStrides[0]!=cast(index_type)T.sizeof) transposeB=!transposeB;
                    int swapAB=c.bStrides[0]!=cast(index_type)T.sizeof;
                    f_int ldb=cast(f_int)((b.bStrides[0]==cast(index_type)T.sizeof)?b.bStrides[1]:b.bStrides[0]);
                    f_int lda=cast(f_int)((a.bStrides[0]==cast(index_type)T.sizeof)?a.bStrides[1]:a.bStrides[0]);
                    f_int ldc=cast(f_int)((c.bStrides[0]==cast(index_type)T.sizeof)?c.bStrides[1]:c.bStrides[0]);
                    // these checks are needed to give a valid ldX to blas (that checks it)
                    // even if ldX is never needed (only one column)
                    if (ldb!=cast(f_int)T.sizeof)
                        ldb/=cast(index_type)T.sizeof;
                    else
                        ldb=(transposeB?b.shape[1-axis2]:b.shape[axis2]);
                    if (lda!=cast(f_int)T.sizeof)
                        lda/=cast(index_type)T.sizeof;
                    else
                        lda=(transposeA?a.shape[axis1]:a.shape[1-axis1]);
                    if (ldc!=cast(f_int)T.sizeof)
                        ldc/=cast(index_type)T.sizeof;
                    else
                        ldc=c.shape[0];
                    if (swapAB){
                        DBlas.gemm((transposeB?'N':'T'), (transposeA?'N':'T'),
                        b.shape[1-axis2], a.shape[1-axis1], a.shape[axis1], scaleRes,
                        b.startPtrArray,ldb,
                        a.startPtrArray,lda,
                        scaleC,
                        c.startPtrArray,ldc);
                    } else {
                        DBlas.gemm((transposeA?'T':'N'), (transposeB?'T':'N'),
                        a.shape[1-axis1], b.shape[1-axis2], a.shape[axis1], scaleRes,
                        a.startPtrArray,lda,
                        b.startPtrArray,ldb,
                        scaleC,
                        c.startPtrArray,ldc);
                    }
                    return c;
                }
            }
        }
    }
    if (scaleC==0){
        if (scaleRes==1){
            mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S *x0,ref S x){x=cast(S)0;},
                (S* x0,S xV){*x0=xV;},T,rank1,U,rank2,S);
            fuse1(a,b,c,axis1,axis2);
        } else {
            mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S* x0,ref S x){x=cast(S)0;},
                (S* x0,S xV){*x0=scaleRes*xV;},T,rank1,U,rank2,S);
            fuse1(a,b,c,axis1,axis2);
        }
    } else {
        mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S* x0,ref S x){x=cast(S)0;},
            (S* x0,S xV){*x0=scaleC*(*x0)+scaleRes*xV;},T,rank1,U,rank2,S);
        fuse1(a,b,c,axis1,axis2);
    }
    return c;
}

/// dot product between tensors (reduces a single axis)
NArray!(typeof(T.init*U.init),rank1+rank2-2)dotNA(T,int rank1,U,int rank2)
    (NArray!(T,rank1)a,NArray!(U,rank2)b,int axis1=-1, int axis2=0)
in {
    assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
    assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
}
body {
    alias typeof(T.init*U.init) S;
    const int rank3=rank1+rank2-2;
    index_type[rank3] newshape;
    int ii=0;
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    for (int i=0;i<rank1;++i){
        if (i!=axis1){
            newshape[ii]=a.shape[i];
            ++ii;
        }
    }
    for (int i=0;i<rank2;++i){
        if (i!=axis2){
            newshape[ii]=b.shape[i];
            ++ii;
        }
    }
    static if(rank3==0){
        S res;
    } else {
        auto res=NArray!(S,rank3).empty(newshape);
    }
    return dotNA!(T,rank1,U,rank2,S,rank3)(a,b,res,cast(S)1,cast(S)0,axis1,axis2);
}

/// outer product between tensors with scaling and
/// already present storage target
NArray!(S,rank3)outerNA(T,int rank1,U,int rank2,S,int rank3)
    (NArray!(T,rank1)a, NArray!(U,rank2)b, ref NArray!(S,rank3) c,
        S scaleRes=cast(S)1, S scaleC=cast(S)0)
in {
    static assert(rank3==rank1+rank2,"rank3 has to be rank1+rank2");
    assert(a.shape==c.shape[0..rank1],"invalid shape for c");
    assert(b.shape==c.shape[rank1..rank1+rank2],"invalid shape for c");
}
body {
    if ((a.flags|b.flags)&ArrayFlags.Zero){
        if (scaleC==0){
            c[]=cast(S)0;
        } else {
            c *= scaleC;
        }
        return c;
    }
    version(no_blas){ }
    else {
/+ to do call gemm, can be used also for higher dims if everything is Contigous of Fortran
        static if ((is(T==U) && isBlasType!(T)) && (rank1==1)&&(rank2==1)){
            // call blas
            // negative incremented vector in blas loops backwards on a[0..n], not on a[-n+1..1]
            static if(rank1==1 && rank2==1){
                if ((a.bStrides[0]>0 && b.bStrides[0]>0)||(a.bStrides[0]<0 && b.bStrides[0]<0)){
                    T* aStartPtr=a.startPtrArray,bStartPtr=b.startPtrArray;
                    if (a.bStrides[0]<0 && b.bStrides[0]<0){
                        aStartPtr=cast(T*)(cast(size_t)aStartPtr+(a.shape[0]-1)*a.bStrides[0]);
                        bStartPtr=cast(T*)(cast(size_t)bStartPtr+(b.shape[0]-1)*b.bStrides[0]);
                    }
                    void gemm('N', 'N', a.shape[0], b.shape[0], 1, scaleRes, aStartPtr, a.shape[0], bStartPtr, b.shape[0], scaleC, c.startPtrArray, c.bStrides[0]/cast(index_type)T.sizeof);
                    return c;
                }
            }
        }+/
    }
    
    index_type[rank1] t1Strides=c.bStrides[0..rank1];
    auto t1=NArray!(S,rank1)(t1Strides,a.shape,c.startPtrArray,c.newFlags, c.mBase);
    index_type[rank2] t2Strides=c.bStrides[rank1..rank1+rank2];
    auto t2=NArray!(S,rank2)(t2Strides, b.shape,c.startPtrArray,c.newFlags, c.mBase);
    index_type optimalChunkSize_i=NArray!(S,rank1).defaultOptimalChunkSize;
    index_type optimalChunkSize_j=NArray!(S,rank2).defaultOptimalChunkSize;
    if (scaleC==0){
        if (scaleRes==1){
            const istring innerLoop=pLoopPtr(rank2,["b","t2"],
                    "*t2Ptr0 = (*aPtr0)*(*bPtr0);","j");
            mixin(pLoopPtr(rank1,["a","t1"],
                    "t2.startPtrArray=t1Ptr0;\n"~innerLoop,"i"));
        } else {
            const istring innerLoop=pLoopPtr(rank2,["b","t2"],
                    "*t2Ptr0 = scaleRes*(*aPtr0)*(*bPtr0);","j");
            mixin(pLoopPtr(rank1,["a","t1"],
                    "t2.startPtrArray=t1Ptr0;\n"~innerLoop,"i"));
        }
    } else {
        const istring innerLoop=pLoopPtr(rank2,["b","t2"],
                "*t2Ptr0 = scaleC*(*t2Ptr0)+scaleRes*(*aPtr0)*(*bPtr0);","j");
        mixin(pLoopPtr(rank1,["a","t1"],
                "t2.startPtrArray=t1Ptr0;\n"~innerLoop,"i"));
    }
    return c;
}

/// dot of the flattened version of two arrays (works for any equally shaped arrays)
S dotAll(T,int rank1,U,int rank2,S=typeof(T.init*U.init))(NArray!(T,rank1)a, NArray!(U,rank2)b){
    static assert(rank1==rank2,"dotAll needs the array to have the same shape");
    assert(a.shape==b.shape,"dotAll needs the array to have the same shape");
    static if (rank1==0){
        return a*b;
    } else static if (rank1==1){
        return dotNA(a,b);
    } else {
        S res=0; // could be smater about the sequence of dimensions...
        foreach(i,v;a){
            scope v2=b[i];
            res+=dotAll(v,v2);
        }
        return res;
    }
}

/// outer product between tensors (extends them)
NArray!(typeof(T.init*U.init),rank1+rank2)outerNA(T,int rank1,U,int rank2)
    (NArray!(T,rank1)a,NArray!(U,rank2)b)
body {
    alias typeof(T.init*U.init) S;
    const int rank3=rank1+rank2;
    index_type[rank3] newshape;
    newshape[0..rank1]=a.shape;
    newshape[rank1..rank1+rank2]=b.shape;
    static if(rank3==0){
        S res;
    } else {
        auto res=NArray!(S,rank3).empty(newshape);
    }
    return outerNA!(T,rank1,U,rank2,S,rank3)(a,b,res,cast(S)1,cast(S)0);
}

/// degenerate case v s
NArray!(T,rank1)outerNA(T,int rank1)(NArray!(T,rank1) a,T b){
  return a*b;
}
/// degenerate case s v
NArray!(T,rank1)outerNA(int rank1,T)(T b,NArray!(T,rank1) a){
  return a*b;
}
// scalar scalar case cannot be cleanly supported with D1 as far as can I see 
// (and also the previous cases are limited)

/// structure to request a subrange of eigenvalues
struct EigRange{
    char kind;
    index_type fromI, toI;
    real fromV,toV;
    static EigRange opCall(){
        EigRange res;
        res.kind='A';
        return res;
    }
    static EigRange opCall(long from, long to){
        EigRange res;
        res.kind='I';
        res.fromI=cast(index_type)from;
        res.toI=cast(index_type)to;
        return res;
    }
    static EigRange opCall(real from, real to){
        EigRange res;
        res.kind='V';
        res.fromV=from;
        res.toV=to;
        return res;
    }
}

/// storage of the matrix (upper or lower triangular)
enum MStorage{
    up=1,
    lo=2
}

version(no_lapack){ }
else {
    /// finds x for which dot(a,x)==b for a square matrix a
    /// not so efficient (copies a)
    NArray!(T,2) solve(T)(NArray!(T,2)a,NArray!(T,2)b,NArray!(T,2)x=nullNArray!(T,2))
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        if (!isNullNArray(x)){
            assert(a.shape[1]==x.shape[0],"incompatible shapes a-x");
            assert(x.shape[1]==b.shape[1],"incompatible shapes b-x");
        }
    }
    body {
        a=a.dup(true);
        scope ipiv=NArray!(f_int,1).empty([a.shape[0]]);
        f_int info;
        if (isNullNArray(x)) x=empty!(T)(b.shape,true);
        if (!(x.bStrides[0]==cast(index_type)T.sizeof && x.bStrides[1]>0)){
            scope NArray!(T,2) xx=b.dup(true);
            DLapack.gesv(a.shape[0], b.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof, ipiv.startPtrArray,
                xx.startPtrArray, xx.shape[0], info);
            x[]=xx; // avoid and return xx?
        } else {
            x[]=b;
            DLapack.gesv(a.shape[0], b.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof, ipiv.startPtrArray,
                x.startPtrArray, x.bStrides[1]/cast(index_type)T.sizeof, info);
        }
        if (info > 0)
            throw new LinAlgException("Singular matrix");
        if (info < 0)
            throw new LinAlgException("Illegal input to Fortran routine gesv");
        return x;
    }
    /// ditto
    NArray!(T,1) solve(T)(NArray!(T,2)a,NArray!(T,1)b,NArray!(T,1)x=nullNArray!(T,1))
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        assert(isNullNArray(x) || x.shape[0]==b.shape[0],"incompatible shapes b-x");
    }
    body {
        scope NArray!(T,2) b1=repeat(b,1,-1);
        if (isNullNArray(x)) x=zeros!(T)(b.shape,true);
        scope NArray!(T,2) x1=repeat(x,1,-1);
        auto res=solve(a,b1,x1);
        if (res.startPtrArray!=x.startPtrArray) {
            x[]=reshape(res,[-1]); // avoid and return res??
        }
        return x;
    }
    
    /// returns the inverse matrix
    NArray!(T,2) inv(T)(NArray!(T,2)a)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a has to be square");
    }
    body {
        scope un=eye!(T)(a.shape[0]);
        return solve(a,un);
    }
    
    /// determinant of the matrix a
    T det(T)(NArray!(T,2)a)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a has to be square");
    }
    body {
        scope NArray!(f_int,1) pivots = NArray!(f_int,1).zeros([a.shape[0]]);
        f_int info;
        auto a2=a.dup(true);
        auto results = getrf(a2, pivots, info);
        if (info > 0)
            return cast(T)0;
        int sign=0;
        for (index_type i=0;i<a.shape[0];++i)
            sign += (pivots[i] != i+1);
        sign=sign % 2;
        return (1.-2.*sign)*multiplyAll(diag(a2));
    }
    
    /// wrapper for the lapack Xgetrf routine
    /// computes an LU factorization of a general M-by-N matrix A in place
    /// using partial pivoting with row interchanges.
    /// T has to be a blas type, the matrix a has to ba acceptable to lapack (a.dup(true) if it is not)
    /// and ipiv has to be continuos
    /// if INFO = i>0, U(i-1,i-1) is exactly zero. The factorization
    /// has been completed, but the factor U is exactly
    /// singular, and division by zero will occur if it is used
    /// to solve a system of equations.
    NArray!(T,2) getrf(T)(NArray!(T,2) a,NArray!(f_int,1) ipiv,f_int info)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>=a.shape[0],"a has to be a blas matrix");
        assert(ipiv.bStrides[0]==cast(index_type)T.sizeof,"ipiv has to have stride 1");
        assert(ipiv.shape[0]>=a.shape[0]||ipiv.shape[0]>=a.shape[1],"ipiv should be at least min(a.shape)");
    }
    body {
        DLapack.getrf(a.shape[0], a.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof,
            ipiv.startPtrArray, info);
        if (info < 0)
            throw new LinAlgException("Illegal input to Fortran routine");
        return a;
    }
    
    /// calculates eigenvalues and (if not null) the  right (and left) eigenvectors
    /// of the given matrix
    /// dot(a,rightEVect)==repeat(ev,n,0)*rightEVect
    /// dot(leftEVect.H,a)==leftEVect.H*repeat(ev,n,-1)
    /// note: it could be relaxed and accept all matrixes with .bStrides[0]=T.sizeof
    /// without copying
    NArray!(ComplexTypeOf!(T),1) eig(T)(NArray!(T,2)a,
        NArray!(ComplexTypeOf!(T),1) ev=nullNArray!(ComplexTypeOf!(T),1),
        NArray!(ComplexTypeOf!(T),2)leftEVect=nullNArray!(ComplexTypeOf!(T),2),
        NArray!(ComplexTypeOf!(T),2)rightEVect=nullNArray!(ComplexTypeOf!(T),2))
    in {
        static assert(isBlasType!(T),"only blas types accepted, not "~T.stringof);
        assert(a.shape[0]==a.shape[1],"matrix a has to be square");
        if (!isNullNArray(ev)) {
            assert(a.shape[0]==ev.shape[0],"ev has an incorrect size");
        }
        if (!isNullNArray(rightEVect)) {
            assert(a.shape[0]==rightEVect.shape[0],"invalid size for rightEVect");
            assert(a.shape[0]==rightEVect.shape[1],"invalid size for rightEVect");
        }
        if (!isNullNArray(leftEVect)) {
            assert(a.shape[0]==leftEVect.shape[0],"invalid size for leftEVect");
            assert(a.shape[0]==leftEVect.shape[1],"invalid size for leftEVect");
        }
    }
    body {
        scope NArray!(T,2) a1=a.dup(true);
        NArray!(T,2) lE,rE;
        T* lEPtr=null,rEPtr=null;
        f_int lELd=1,rELd=1;
        if (!isNullNArray(leftEVect)){
            if (leftEVect.flags & ArrayFlags.Fortran) {
                lE=NArray!(T,2)([T.sizeof,T.sizeof*a.shape[0]],leftEVect.shape,
                    cast(T*)(leftEVect.startPtrArray+leftEVect.size)-leftEVect.size,
                    leftEVect.newFlags,leftEVect.newBase);
            } else {
                lE=NArray!(T,2).empty(leftEVect.shape,true);
            }
            lEPtr=lE.startPtrArray;
            lELd=lE.bStrides[1]/cast(index_type)T.sizeof;
        }
        if (!isNullNArray(rightEVect)){
            if (rightEVect.flags & ArrayFlags.Fortran) {
                rE=NArray!(T,2)([T.sizeof,T.sizeof*a.shape[0]],rightEVect.shape,
                    cast(T*)(rightEVect.startPtrArray+rightEVect.size)-rightEVect.size,
                    rightEVect.newFlags,rightEVect.newBase);
            } else {
                rE=empty!(T)(rightEVect.shape,true);
            }
            rEPtr=rE.startPtrArray;
            rELd=rE.bStrides[1]/cast(index_type)T.sizeof;
        }
        NArray!(ComplexTypeOf!(T),1) eigenval=ev;
        if (isNullNArray(eigenval) || is(T==ComplexTypeOf!(T)) && (!(eigenval.flags&ArrayFlags.Fortran))) {
            eigenval = zeros!(ComplexTypeOf!(T))(a.shape[0]);
        }
        f_int n=a.shape[0],info;
        f_int lwork = -1;
        T workTmp;
        static if(is(ComplexTypeOf!(T)==T)){
            scope NArray!(RealTypeOf!(T),1) rwork = empty!(RealTypeOf!(T))(2*n);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, eigenval.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                &workTmp, lwork, rwork.startPtrArray, info);
            lwork = cast(int)abs(workTmp)+1;
            scope NArray!(T,1) work = empty!(T)(lwork);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, eigenval.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                work.startPtrArray, lwork, rwork.startPtrArray, info);
            
            if (!isNullNArray(leftEVect) && leftEVect.startPtrArray != lE.startPtrArray) leftEVect[]=lE;
            if (!isNullNArray(rightEVect) && rightEVect.startPtrArray != rE.startPtrArray) rightEVect[]=rE;
            if (!isNullNArray(ev) && ev.startPtrArray != eigenval.startPtrArray) ev[]=eigenval;
        } else {
            scope NArray!(RealTypeOf!(T),1) wr = empty!(RealTypeOf!(T))(n);
            scope NArray!(RealTypeOf!(T),1) wi = empty!(RealTypeOf!(T))(n);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, wr.startPtrArray, wi.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                &workTmp, lwork, info);
            lwork = cast(int)abs(workTmp)+1;
            if (lwork<2*n && (lEPtr!is null|| rEPtr!is null)){
                lwork=2*n;
            }
            scope NArray!(T,1) work = empty!(T)(lwork);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, wr.startPtrArray, wi.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                work.startPtrArray, lwork, info);
            for (int i=0;i<n;++i)
                eigenval[i]=cast(ComplexTypeOf!(T))(wr[i]+wi[i]*1i);
            if (rEPtr !is null){
                index_type i=0;
                while(i<n) {
                    if (wi[i]==0){
                        for (index_type j=0;j<n;++j){
                            rightEVect[j,i]=cast(ComplexTypeOf!(T))rE[j,i];
                        }
                    } else {
                        if(i==n) throw new Exception("unexpected eigenvalues sequence",__FILE__,__LINE__);
                        if (rE.ptrI(0,i) is (cast(T*)(rightEVect.ptrI(0,i+1))))
                        {
                            memcpy(work.startPtrArray,rE.ptrI(0,i),2*n*T.sizeof);
                            for (index_type j=0;j<n;++j){
                                rightEVect[j,i]  =cast(ComplexTypeOf!(T))(work[j]+1i*work[j+n]);
                                rightEVect[j,i+1]=cast(ComplexTypeOf!(T))(work[j]-1i*work[j+n]);
                            }
                        } else {
                            for (index_type j=0;j<n;++j){
                                rightEVect[j,i]  =cast(ComplexTypeOf!(T))(rE[j,i]+1i*rE[j,i+1]);
                                rightEVect[j,i+1]=cast(ComplexTypeOf!(T))(rE[j,i]-1i*rE[j,i+1]);
                            }
                        }
                        ++i;
                    }
                    ++i;
                }
            }
            if (lEPtr !is null){
                index_type i=0;
                while(i<n) {
                    if (wi[i]==0){
                        for (index_type j=0;j<n;++j){
                            leftEVect[j,i]=cast(ComplexTypeOf!(T))lE[j,i];
                        }
                    } else {
                        if(i==n) throw new Exception("unexpected eigenvalues sequence",__FILE__,__LINE__);
                        if (lE.ptrI(0,i) is (cast(T*)(leftEVect.ptrI(0,i+1))))
                        {
                            memcpy(work.startPtrArray,lE.ptrI(0,i),2*n*T.sizeof);
                            for (index_type j=0;j<n;++j){
                                leftEVect[j,i]  =cast(ComplexTypeOf!(T))(work[j]+1i*work[j+n]);
                                leftEVect[j,i+1]=cast(ComplexTypeOf!(T))(work[j]-1i*work[j+n]);
                            }
                        } else {
                            for (index_type j=0;j<n;++j){
                                leftEVect[j,i]  =cast(ComplexTypeOf!(T))(lE[j,i]+1i*lE[j,i+1]);
                                leftEVect[j,i+1]=cast(ComplexTypeOf!(T))(lE[j,i]-1i*lE[j,i+1]);
                            }
                        }
                        ++i;
                    }
                    ++i;
                }
            }
        }
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine");
        if (info>0) throw new LinAlgException("Eigenvalues did not converge");
        return eigenval;
    }
    
    /// singular value decomposition
    ///  a=dot(u[Range(0,-1),Range(0,vt.shape[0])],repeat(s,vt.shape[0],-1)*vt) if vt.shape[0]<=u.shape[0]
    ///  a=dot(u*repeat(s,u.shape[0],0),vt[Range(0,u.shape[0])]) if vt.shape[0]>=u.shape[0]
    /// with square orthogonal u,v and singular values s, the larger of u,vt can be reduced to rectangular
    /// (as the other vectors are not really well defined)
    /// to do: switch to 'O' method, to spare a matrix
    NArray!(RealTypeOf!(T),1) svd(T,S=RealTypeOf!(T))(NArray!(T,2)a,
        NArray!(T,2)u=nullNArray!(T,2),NArray!(S,1)s=nullNArray!(S,1),
        NArray!(T,2)vt=nullNArray!(T,2))
    in{
        static assert(isBlasType!(T),"non blas type "~T.stringof~" not supported");
        static assert(is(RealTypeOf!(T)==S),"singular values are real");
        index_type mn=min(a.shape[0],a.shape[1]);
        if (!isNullNArray(u)){
            assert(u.shape[0]==a.shape[0],"invalid shape[0] for u");
            assert(u.shape[1]==a.shape[0] || u.shape[1]==mn,"invalid shape[1] for u");
        }
        if (!isNullNArray(vt)){
            assert(vt.shape[0]==a.shape[1] || vt.shape[0]==mn,"invalid shape[0] for vt");
            assert(vt.shape[1]==a.shape[1],"invalid shape[1] for vt");
        }
        if (!isNullNArray(s)){
            assert(s.shape[0]==mn,"invalid shape for s");
        }
    }
    body{
        index_type m=a.shape[0],n=a.shape[1],mn=min(m,n);
        a=a.dup(true);
        auto myS=s;
        if (isNullNArray(s) || s.bStrides[0]!=cast(index_type)RealTypeOf!(T).sizeof){
            myS=empty!(RealTypeOf!(T))(mn,true);
        }
        if (mn==cast(index_type)0) return s;
        char jobz='N';
        T * uPtr=null,vtPtr=null;
        auto myU=u,myVt=vt;
        f_int lda= cast(f_int)(a.bStrides[1]/cast(index_type)T.sizeof);
        if (lda==1) lda=a.shape[0];
        f_int ldu= cast(f_int)1;
        f_int ldvt=cast(f_int)1;
        if (!isNullNArray(u) || !isNullNArray(vt)){
            if (isNullNArray(u) || u.bStrides[0]!=cast(index_type)T.sizeof || u.bStrides[1]<=0 ){
                index_type[2] uShape=m;
                if (!isNullNArray(u)) uShape[1]=mn;
                myU=empty!(T)(uShape,true);
            }
            uPtr=myU.startPtrArray;
            if (isNullNArray(vt) || vt.bStrides[0]!=cast(index_type)T.sizeof || vt.bStrides[1]<=0){
                index_type[2] vtShape=n;
                if (!isNullNArray(vt)) vtShape[0]=mn;
                myVt=empty!(T)(vtShape,true);
            }
            vtPtr=myVt.startPtrArray;
            jobz='A';
            if (myU.shape[1]!=m) jobz='S';
            if (myVt.shape[0]!=n) jobz='S';
            ldu= cast(f_int)(myU.bStrides[1]/cast(index_type)T.sizeof);
            ldvt=cast(f_int)(myVt.bStrides[1]/cast(index_type)T.sizeof);
            if (ldu==1) ldu=myU.shape[0];
            if (ldvt==1) ldvt=myVt.shape[0];
        }
        f_int info;
        T tmpWork;
        scope NArray!(f_int,1) iwork=empty!(f_int)(8*mn);
        static if (isComplexType!(T)){
            scope NArray!(RealTypeOf!(T),1) rwork=empty!(RealTypeOf!(T))(jobz=='N'?7*mn:5*(mn*mn+mn));
            DLapack.gesdd(jobz, cast(f_int) m, cast(f_int) n,
                a.startPtrArray, lda, myS.startPtrArray, uPtr, ldu,
                vtPtr, ldvt, &tmpWork, cast(f_int)-1,
                rwork.startPtrArray, iwork.startPtrArray, info);
            if (info==0){
                f_int lwork=cast(f_int)tmpWork.re+cast(f_int)1;
                scope NArray!(T,1) work=empty!(T)(lwork);
                DLapack.gesdd(jobz, cast(f_int) m, cast(f_int) n,
                    a.startPtrArray, lda, myS.startPtrArray, uPtr, ldu,
                    vtPtr, ldvt, work.startPtrArray, lwork,
                    rwork.startPtrArray, iwork.startPtrArray, info);
            }            
        } else {
            DLapack.gesdd(jobz, cast(f_int)m, cast(f_int)n, a.startPtrArray, lda,
                myS.startPtrArray, uPtr, ldu, vtPtr, ldvt,
                &tmpWork, cast(f_int)(-1), iwork.startPtrArray, cast(f_int)info);
            if (info==0){
                f_int lwork=cast(f_int)tmpWork.re+cast(f_int)1;
                scope NArray!(T,1) work=empty!(T)(lwork);
                DLapack.gesdd(jobz, cast(f_int)m, cast(f_int) n, a.startPtrArray, lda,
                    myS.startPtrArray, uPtr, ldu, vtPtr, ldvt,
                    work.startPtrArray, lwork, iwork.startPtrArray, info);
            }
        }
        if (!isNullNArray(u) && u.startPtrArray!=myU.startPtrArray) u[]=myU;
        if (!isNullNArray(vt) && vt.startPtrArray!=myVt.startPtrArray) vt[]=myVt;
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine gesdd");
        if (info>0) throw new LinAlgException("svd decomposition did not converge");
        return myS;
    }
    
    /// eigenvaules for hermitian matrix
    NArray!(RealTypeOf!(T),1)eigh(T)(NArray!(T,2)a,MStorage storage=MStorage.up,
        NArray!(RealTypeOf!(T),1)ev=nullNArray!(RealTypeOf!(T),1),
        NArray!(T,2)eVect=nullNArray!(T,2),EigRange range=EigRange(),
        NArray!(f_int,2)supportEVect=nullNArray!(f_int,2),
        RealTypeOf!(T) abstol=cast(RealTypeOf!(T))0)
    in {
        assert(a.shape[0]==a.shape[1],"a has to be square");
        assert(isNullNArray(ev) || ev.shape[0]==a.shape[0],"ev has incorret shape");
        if (!isNullNArray(eVect)){
            index_type m=a.shape[0];
            if (range.kind=='I') m=range.toI-range.fromI+1;
            assert(eVect.shape[0]==a.shape[0] && (eVect.shape[1]<=a.shape[0] && eVect.shape[1]>=m),
                "eVect has invalid shape");
        }
        assert(isNullNArray(supportEVect) || supportEVect.shape[0]==2 && supportEVect.shape[1]==a.shape[0],
            "supportEVect has incorrect shape");
    }
    body {
        index_type n=a.shape[0];
        f_int m=cast(f_int)n;
        if (range.kind=='I') m=cast(f_int)(range.toI-range.fromI+1);
        auto myEv=ev;
        if (isNullNArray(ev) || myEv.bStrides[0]!=cast(index_type)RealTypeOf!(T).sizeof){
            myEv=empty!(RealTypeOf!(T))(n);
        }
        if (n==0) return myEv;
        a=a.dup(true);
        f_int lda=a.bStrides[1]/cast(index_type)T.sizeof;
        T* eVectPtr=null;
        auto myEVect=eVect;
        f_int ldEVect=cast(f_int)1;
        if (!isNullNArray(eVect)) {
            if (eVect.bStrides[0]!=T.sizeof || eVect.bStrides[1]<=cast(index_type)0){
                myEVect=empty!(T)(eVect.shape);
            }
            eVectPtr=myEVect.startPtrArray;
            ldEVect=cast(f_int)(myEVect.bStrides[1]/cast(index_type)T.sizeof);
            if (ldEVect==cast(f_int)1) ldEVect=cast(f_int)myEVect.shape[0];
        }
        auto isuppz=supportEVect;
        if (isNullNArray(supportEVect) || (!(supportEVect.flags&ArrayFlags.Fortran))){
            isuppz=empty!(f_int)([2,max(1,cast(index_type)m)],true);
        }
        T tmpWork;
        f_int tmpIWork;
        f_int info=0;
        static if (isComplexType!(T)){
            RealTypeOf!(T) tmpRWork;
            DLapack.heevr((eVectPtr is null)?'N':'V', range.kind,(storage==MStorage.up)?'U':'L', 
                cast(f_int)n, a.startPtrArray, lda, cast(RealTypeOf!(T))range.fromV,
                cast(RealTypeOf!(T))range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, 
                isuppz.startPtrArray, &tmpWork, cast(f_int)(-1),  &tmpRWork, cast(f_int)(-1),
                &tmpIWork, cast(f_int)(-1), info);
            if (info==0){
                f_int lwork=cast(f_int)abs(tmpWork)+cast(f_int)1;
                f_int lrwork=cast(f_int)abs(tmpRWork)+cast(f_int)1;
                f_int liwork=cast(f_int)abs(tmpIWork)+cast(f_int)1;
                scope iwork=empty!(f_int)(liwork);
                scope work=empty!(T)(lwork);
                scope rwork=empty!(RealTypeOf!(T))(lrwork);
                DLapack.heevr((eVectPtr is null)?'N':'V', range.kind,(storage==MStorage.up)?'U':'L', 
                    cast(f_int)n, a.startPtrArray, lda, cast(RealTypeOf!(T))range.fromV,
                    cast(RealTypeOf!(T))range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                    abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, 
                    isuppz.startPtrArray, work.startPtrArray, lwork,  rwork.startPtrArray, lrwork,
                    iwork.startPtrArray, liwork, info);
            }
        } else {
            /+writeOut(sout("a:").call,a);sout("\n");// pippo
            writeOut(sout("eVect:").call,eVect);sout("\n");// pippo
            writeOut(sout("supportEVect:").call,supportEVect);sout("\n");// pippo+/
            assert(false,"buggy!");
            /+Trace.formatln("DLapack.syevr({},{},{},{},{},{},{},{},{},{},\n{},{},{},{},{},{},{},{},{},{}, {});",(eVectPtr is null)?'N':'V', range.kind, (storage==MStorage.up)?'U':'L',
                cast(f_int) n, a.startPtrArray,
                lda, cast(T)range.fromV, cast(T)range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, isuppz.startPtrArray,
                &tmpWork, cast(f_int)(-1), &tmpIWork, cast(f_int)(-1), info);+/ // pippo
            DLapack.syevr((eVectPtr is null)?'N':'V', range.kind, (storage==MStorage.up)?'U':'L',
                cast(f_int) n, a.startPtrArray,
                lda, cast(T)range.fromV, cast(T)range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, isuppz.startPtrArray,
                &tmpWork, cast(f_int)(-1), &tmpIWork, cast(f_int)(-1), info);
            if (info==0){
                f_int lwork=cast(f_int)abs(tmpWork)+cast(f_int)1;
                f_int liwork=cast(f_int)abs(tmpIWork)+cast(f_int)1;
                scope iwork=empty!(f_int)(liwork);
                scope work=empty!(T)(lwork);
                /+ Trace.formatln("DLapack.syevr({},{},{},{},{},{},{},{},{},{},\n{},{},{},{},{},{},{},{},{},{}, {});",(eVectPtr is null)?'N':'V', range.kind, (storage==MStorage.up)?'U':'L',
                    cast(f_int) n, a.startPtrArray,
                    lda, cast(T)range.fromV, cast(T)range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                    abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, isuppz.startPtrArray,
                    work.startPtrArray, lwork, iwork.startPtrArray, liwork, info);+/ // pippo
                DLapack.syevr((eVectPtr is null)?'N':'V', range.kind, (storage==MStorage.up)?'U':'L',
                    cast(f_int) n, a.startPtrArray,
                    lda, cast(T)range.fromV, cast(T)range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                    abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, isuppz.startPtrArray,
                    work.startPtrArray, lwork, iwork.startPtrArray, liwork, info);
                // Trace.formatln("done");//pippo
            }
        }
        if (!isNullNArray(ev) && ev.startPtrArray!=myEv.startPtrArray) ev[]=myEv; // avoid?
        if (!isNullNArray(eVect) && myEVect.startPtrArray!=eVect.startPtrArray) eVect[]=myEVect;
        if (!isNullNArray(supportEVect) && supportEVect.startPtrArray!=isuppz.startPtrArray) supportEVect[]=isuppz;
        if (m!=cast(f_int)n) myEv=myEv[Range(m)];
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine syevr/heevr");
        if (info>0) throw new LinAlgException("eigenvalue decomposition did not converge");
        return myEv;
    }
    
}
