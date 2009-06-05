/*******************************************************************************
    Basic linear algebra on NArrays
    at the moment only dot is available without blas/lapack
     inv        --- Inverse of a square matrix
     solve      --- Solve a linear system of equations
     det        --- Determinant of a square matrix
     eig        --- Eigenvalues and vectors of a square matrix
     eigh       --- Eigenvalues and eigenvectors of a Hermitian matrix
     svd        --- Singular value decomposition of a matrix
     
     nice to add:
     dgesvx/zgesvx (advanced linear solvers)
     cholesky   --- Cholesky decomposition of a matrix
     optimize lapack based calls for contiguous inputs
    
    copyright:      Copyright (c) 2008. Fawzi Mohamed
    license:        Apache 2.0
    version:        Initial release: July 2008
    author:         Fawzi Mohamed
*******************************************************************************/
module blip.narray.LinAlg;
//import tango.io.Stdout;
import blip.narray.BasicTypes;
import blip.narray.BasicOps;
import tango.math.Math:min,max;
import tango.core.Traits:isComplexType,isImaginaryType,ComplexTypeOf,RealTypeOf;

version(no_blas){ 
    version(no_lapack){ }
    else {
        static assert(false,"lapack needs blas");
    }
} else {
    import DBlas=gobo.blas.DBlas;
    public import gobo.blas.Types;
}
version(no_lapack){ }
else {
    import DLapack=gobo.lapack.DLapack;
}

class LinAlgException:Exception{
    this(char[] err){
        super(err);
    }
}

/// dot product between tensors (reduces a single axis) with scaling and
/// already present storage target
NArray!(S,rank3)dot(T,int rank1,U,int rank2,S,int rank3)
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
NArray!(typeof(T.init*U.init),rank1+rank2-2)dot(T,int rank1,U,int rank2)
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
    return dot!(T,rank1,U,rank2,S,rank3)(a,b,res,cast(S)1,cast(S)0,axis1,axis2);
}

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
    NArray!(T,2) solve(T)(NArray!(T,2)a,NArray!(T,2)b,NArray!(T,2)x=null)
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        if (x !is null){
            assert(a.shape[1]==x.shape[0],"incompatible shapes a-x");
            assert(x.shape[1]==b.shape[1],"incompatible shapes b-x");
        }
    }
    body {
        a=a.dup(true);
        scope ipiv=NArray!(f_int,1).empty([a.shape[0]]);
        f_int info;
        if (x is null) x=empty!(T)(b.shape,true);
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
    NArray!(T,1) solve(T)(NArray!(T,2)a,NArray!(T,1)b,NArray!(T,1)x=null)
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        assert(x is null || x.shape[0]==b.shape[0],"incompatible shapes b-x");
    }
    body {
        scope NArray!(T,2) b1=repeat(b,1,-1);
        if (x is null) x=zeros!(T)(b.shape,true);
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
    NArray!(ComplexTypeOf!(T),1) eig(T)(NArray!(T,2)a,NArray!(ComplexTypeOf!(T),1) ev=null,
        NArray!(ComplexTypeOf!(T),2)leftEVect=null,NArray!(ComplexTypeOf!(T),2)rightEVect=null)
    in {
        static assert(isBlasType!(T),"only blas types accepted");
        assert(a.shape[0]==a.shape[1],"matrix a has to be square");
        if (ev !is null) {
            assert(a.shape[0]==ev.shape[0],"ev has an incorrect size");
        }
        if (rightEVect !is null) {
            assert(a.shape[0]==rightEVect.shape[0],"invalid size for rightEVect");
            assert(a.shape[0]==rightEVect.shape[1],"invalid size for rightEVect");
        }
        if (leftEVect !is null) {
            assert(a.shape[0]==leftEVect.shape[0],"invalid size for leftEVect");
            assert(a.shape[0]==leftEVect.shape[1],"invalid size for leftEVect");
        }
    }
    body {
        scope NArray!(T,2) a1=a.dup(true);
        NArray!(T,2) lE,rE;
        T* lEPtr=null,rEPtr=null;
        f_int lELd=1,rELd=1;
        if (leftEVect !is null){
            if (leftEVect.flags & ArrayFlags.Fortran) {
                lE=NArray!(T,2)([T.sizeof,T.sizeof*a.shape[0]],leftEVect.shape,
                    cast(T*)leftEVect.startPtrArray,leftEVect.newFlags,leftEVect.newBase);
            } else {
                lE=NArray!(T,2).empty(leftEVect.shape,true);
            }
            lEPtr=lE.startPtrArray;
            lELd=lE.bStrides[1]/cast(index_type)T.sizeof;
        }
        if (rightEVect !is null){
            if (rightEVect.flags & ArrayFlags.Fortran) {
                rE=NArray!(T,2)([T.sizeof,T.sizeof*a.shape[0]],rightEVect.shape,
                    cast(T*)rightEVect.startPtrArray,rightEVect.newFlags,rightEVect.newBase);
            } else {
                rE=empty!(T)(rightEVect.shape,true);
            }
            rEPtr=rE.startPtrArray;
            rELd=rE.bStrides[1]/cast(index_type)T.sizeof;
        }
        NArray!(ComplexTypeOf!(T),1) eigenval=ev;
        if (eigenval is null || is(T==ComplexTypeOf!(T)) && (!(eigenval.flags&ArrayFlags.Fortran))) {
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
            
            if (leftEVect ! is null && leftEVect.startPtrArray != lE.startPtrArray) leftEVect[]=lE;
            if (rightEVect !is null && rightEVect.startPtrArray != rE.startPtrArray) rightEVect[]=rE;
            if (ev !is null && ev.startPtrArray != eigenval.startPtrArray) ev[]=eigenval;
        } else {
            scope NArray!(RealTypeOf!(T),1) wr = empty!(RealTypeOf!(T))(n);
            scope NArray!(RealTypeOf!(T),1) wi = empty!(RealTypeOf!(T))(n);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, wr.startPtrArray, wi.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                &workTmp, lwork, info);
            lwork = cast(int)abs(workTmp)+1;
            scope NArray!(T,1) work = empty!(T)(lwork);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, wr.startPtrArray, wi.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                work.startPtrArray, lwork, info);
            for (int i=0;i<n;++i)
                eigenval[i]=cast(ComplexTypeOf!(T))(wr[i]+wi[i]*1i);
            if (rEPtr !is null){
                index_type i=n-1;
                while(i>=0) {
                    if (wi[i]==0){
                        for (index_type j=n-1;j>=0;--j){
                            rightEVect[j,i]=cast(ComplexTypeOf!(T))(rE[j,i]);
                        }
                        --i;
                    } else {
                        for (index_type j=n-1;j>=0;--j){
                            rightEVect[j,i-1]=cast(ComplexTypeOf!(T))(rE[j,i-1]+1i*rE[j,i]);
                            rightEVect[j,i]=cast(ComplexTypeOf!(T))(rE[j,i-1]-1i*rE[j,i]);
                        }
                        i-=2;
                    }
                }
            }
            if (lEPtr !is null){
                index_type i=n-1;
                while(i>=0) {
                    if (wi[i]==0){
                        for (index_type j=n-1;j>=0;--j){
                            leftEVect[j,i]=cast(ComplexTypeOf!(T))lE[j,i];
                        }
                        --i;
                    } else {
                        for (index_type j=n-1;j>=0;--j){
                            leftEVect[j,i-1]=cast(ComplexTypeOf!(T))(lE[j,i-1]+1i*lE[j,i]);
                            leftEVect[j,i]=cast(ComplexTypeOf!(T))(lE[j,i-1]-1i*lE[j,i]);
                        }
                        i-=2;
                    }
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
    NArray!(RealTypeOf!(T),1) svd(T,S=RealTypeOf!(T))(NArray!(T,2)a,NArray!(T,2)u=null,
        NArray!(S,1)s=null,NArray!(T,2)vt=null)
    in{
        static assert(is(RealTypeOf!(T)==S),"singular values are real");
        index_type mn=min(a.shape[0],a.shape[1]);
        if (u !is null){
            assert(u.shape[0]==a.shape[0],"invalid shape[0] for u");
            assert(u.shape[1]==a.shape[0] || u.shape[1]==mn,"invalid shape[1] for u");
        }
        if (vt !is null){
            assert(vt.shape[0]==a.shape[1] || vt.shape[0]==mn,"invalid shape[0] for vt");
            assert(vt.shape[1]==a.shape[1],"invalid shape[1] for vt");
        }
        if (s !is null){
            assert(s.shape[0]==mn,"invalid shape for s");
        }
    }
    body{
        index_type m=a.shape[0],n=a.shape[1],mn=min(m,n);
        a=a.dup(true);
        auto myS=s;
        if (s is null || s.bStrides[0]!=cast(index_type)RealTypeOf!(T).sizeof){
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
        if (u !is null || vt !is null){
            if (u is null || u.bStrides[0]!=cast(index_type)T.sizeof || u.bStrides[1]<=0 ){
                index_type[2] uShape=m;
                if (u !is null) uShape[1]=mn;
                myU=empty!(T)(uShape,true);
            }
            uPtr=myU.startPtrArray;
            if (vt is null || vt.bStrides[0]!=cast(index_type)T.sizeof || vt.bStrides[1]<=0){
                index_type[2] vtShape=n;
                if (vt !is null) vtShape[0]=mn;
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
        if (u !is null && u.startPtrArray!=myU.startPtrArray) u[]=myU;
        if (vt !is null && vt.startPtrArray!=myVt.startPtrArray) vt[]=myVt;
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine gesdd");
        if (info>0) throw new LinAlgException("svd decomposition did not converge");
        return myS;
    }
    
    /// eigenvaules for hermitian matrix
    NArray!(RealTypeOf!(T),1)eigh(T)(NArray!(T,2)a,MStorage storage=MStorage.up,
        NArray!(RealTypeOf!(T),1)ev=null,NArray!(T,2)eVect=null,
        EigRange range=EigRange(),NArray!(f_int,2)supportEVect=null,
        RealTypeOf!(T) abstol=cast(RealTypeOf!(T))0)
    in {
        assert(a.shape[0]==a.shape[1],"a has to be square");
        assert(ev is null || ev.shape[0]==a.shape[0],"ev has incorret shape");
        if (eVect !is null){
            index_type m=a.shape[0];
            if (range.kind=='I') m=range.toI-range.fromI+1;
            assert(eVect.shape[0]==a.shape[0] && (eVect.shape[1]<=a.shape[0] && eVect.shape[1]>=m),
                "eVect has invalid shape");
        }
        assert(supportEVect is null || supportEVect.shape[0]==2 && supportEVect.shape[1]==a.shape[0],
            "supportEVect has incorrect shape");
    }
    body {
        index_type n=a.shape[0];
        f_int m=cast(f_int)n;
        if (range.kind=='I') m=cast(f_int)(range.toI-range.fromI+1);
        auto myEv=ev;
        if (ev is null || myEv.bStrides[0]!=cast(index_type)RealTypeOf!(T).sizeof){
            myEv=empty!(RealTypeOf!(T))(n);
        }
        if (n==0) return myEv;
        a=a.dup(true);
        f_int lda=a.bStrides[1]/cast(index_type)T.sizeof;
        T* eVectPtr=null;
        auto myEVect=eVect;
        f_int ldEVect=cast(f_int)1;
        if (eVect !is null) {
            if (eVect.bStrides[0]!=T.sizeof || eVect.bStrides[1]<=cast(index_type)0){
                myEVect=empty!(T)(eVect.shape);
            }
            eVectPtr=myEVect.startPtrArray;
            ldEVect=cast(f_int)(myEVect.bStrides[1]/cast(index_type)T.sizeof);
            if (ldEVect==cast(f_int)1) ldEVect=cast(f_int)myEVect.shape[0];
        }
        auto isuppz=supportEVect;
        if (supportEVect is null || (!(supportEVect.flags&ArrayFlags.Fortran))){
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
                DLapack.syevr((eVectPtr is null)?'N':'V', range.kind, (storage==MStorage.up)?'U':'L',
                    cast(f_int) n, a.startPtrArray,
                    lda, cast(T)range.fromV, cast(T)range.toV, cast(f_int)range.fromI, cast(f_int)range.toI,
                    abstol, m, myEv.startPtrArray, eVectPtr, ldEVect, isuppz.startPtrArray,
                    work.startPtrArray, lwork, iwork.startPtrArray, liwork, info);
            }
        }
        if (ev !is null && ev.startPtrArray!=myEv.startPtrArray) ev[]=myEv; // avoid?
        if (eVect !is null && myEVect.startPtrArray!=eVect.startPtrArray) eVect[]=myEVect;
        if (supportEVect !is null && supportEVect.startPtrArray!=isuppz.startPtrArray) supportEVect[]=isuppz;
        if (m!=cast(f_int)n) myEv=myEv[Range(m)];
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine syevr/heevr");
        if (info>0) throw new LinAlgException("eigenvalue decomposition did not converge");
        return myEv;
    }
    
}
