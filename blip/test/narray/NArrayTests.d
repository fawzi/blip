/// module that creates an executable that extensively tests NArray
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
module blip.test.narray.NArrayTests;
import blip.narray.NArrayType;
import blip.io.Console;
import blip.rtest.RTest;
import blip.narray.NArray;
import blip.test.narray.NArraySupport;
import blip.math.random.Random: rand;
import blip.narray.NArrayConvolve;
import blip.util.TemplateFu;
import blip.parallel.smp.WorkManager;
import blip.util.TangoLogConfig;
import blip.container.GrowableArray;
import blip.math.Math: abs,min,max,sqrt;
import blip.math.IEEE: feqrel;
import blip.serialization.Serialization;
import blip.io.IOArray;
import blip.BasicModels;
import blip.core.Traits;
import blip.io.BasicIO;
import blip.io.StreamConverters;

/// returns a NArray indexed with the variables of a pLoopIdx or sLoopGenIdx
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
        index_type optimalChunkSize_i=NArray!(T,rank).defaultOptimalChunkSize;
        mixin(pLoopIdx(rank,["a"],
        "if (*aPtr0!="~NArrayInLoop("a",rank,"i")~") throw new Exception(\"pLoopIdx looping1 failed\",__FILE__,__LINE__);","i"));
    }
    {
        mixin(sLoopGenIdx(rank,["a"],
        "if (*aPtr0!="~NArrayInLoop("a",rank,"i")~") throw new Exception(\"sLoopGenIdx looping1 failed\",__FILE__,__LINE__);","i"));
    }
    index_type[rank] iPos;
    const char[] loopBody1=`
    if (did_wrap) throw new Exception("counter wrapped",__FILE__,__LINE__);
    if (a.arrayIndex(iPos)!=*aPtr0) throw new Exception("sLoopPtr failed",__FILE__,__LINE__);
    did_wrap=a.incrementArrayIdx(iPos);
    `;
    {
        bool did_wrap=false;
        iPos[]=cast(index_type)0;
        mixin(sLoopPtr(rank,["a"],loopBody1,"i"));
        if (!did_wrap) throw new Exception("incomplete loop",__FILE__,__LINE__);
    }
    const char[] loopBody2=`
    if (did_wrap) throw new Exception("counter wrapped",__FILE__,__LINE__);
    if (a.arrayIndex(iPos)!=*aPtr0) throw new Exception("sLoopIdx looping failed",__FILE__,__LINE__);
    did_wrap=a.incrementArrayIdx(iPos);
    `;
    {
        bool did_wrap=false;
        iPos[]=cast(index_type)0;
        mixin(sLoopGenIdx(rank,["a"],loopBody2,"i"));
        if (!did_wrap) throw new Exception("incomplete loop",__FILE__,__LINE__);
    }
}

void checkeq(T,int rank,S)(NArray!(T,rank) a, S x) 
{
    static assert(is(S:T[]),"compare only to array of the same type");
    int i=0;
    if (a.size != x.length) throw new Exception("error",__FILE__,__LINE__);
    foreach(i,v;a.pFlat){
        if (v!=x[i]) throw new Exception("error",__FILE__,__LINE__);
    }
}

void arangeTests(){
    if (arange(0.0,0.1,1.0)  .size!=1) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,1.1,1.0)  .size!=2) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,-0.1,-1.0).size!=1) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,-1.1,-1.0).size!=2) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,1,10)   .size!=1)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,11,10)  .size!=2)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,-1,-10) .size!=1)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,-11,-10).size!=2)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,0.9,1.0)  .size!=1) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,1.9,1.0)  .size!=2) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,-0.9,-1.0).size!=1) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0.0,-1.9,-1.0).size!=2) throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,1,10)   .size!=1)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,11,10)  .size!=2)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,-1,-10) .size!=1)     throw new Exception("error",__FILE__,__LINE__);
    if (arange(0,-11,-10).size!=2)     throw new Exception("error",__FILE__,__LINE__);
}

void test_iter()
{
    void aassert(bool v,long line){
        if (!v) throw new Exception("aassert",__FILE__,line);
    }
    alias NArray!(int,2) array;
    array a=a2NAC( [[1,2,3],[4,5,6]] );

    auto ii = a.flatIter();
    aassert(!ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+0 && ii.value == 1,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+1 && ii.value == 2,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+2 && ii.value == 3,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+3 && ii.value == 4,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+4 && ii.value == 5,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+5 && ii.value == 6,__LINE__);
    aassert(!ii.next && ii.end,__LINE__); aassert(!ii.next && ii.end,__LINE__);

    a=a.T(); // a now 3x2
    ii = a.flatIter();
    aassert(!ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+0 && ii.value == 1,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+3 && ii.value == 4,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+1 && ii.value == 2,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+4 && ii.value == 5,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+2 && ii.value == 3,__LINE__); aassert(ii.next && !ii.end,__LINE__);
    aassert(ii.ptr == a.data.ptr+5 && ii.value == 6,__LINE__); aassert(!ii.next && ii.end,__LINE__);
    aassert(!ii.next && ii.end,__LINE__);

    a=a.T(); // a now 2x3 again
    auto jj = a.T.flatIter();
    aassert(!jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+0 && jj.value == 1,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+3 && jj.value == 4,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+1 && jj.value == 2,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+4 && jj.value == 5,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+2 && jj.value == 3,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+5 && jj.value == 6,__LINE__); aassert(!jj.next && jj.end,__LINE__);
    aassert(!jj.next && jj.end,__LINE__);

    a=a.T(); // a now 3x2 again
    jj = a.T.flatIter();
    aassert(!jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+0 && jj.value == 1,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+1 && jj.value == 2,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+2 && jj.value == 3,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+3 && jj.value == 4,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+4 && jj.value == 5,__LINE__); aassert(jj.next && !jj.end,__LINE__);
    aassert(jj.ptr == a.data.ptr+5 && jj.value == 6,__LINE__); aassert(!jj.next && jj.end,__LINE__);
    aassert(!jj.next && jj.end,__LINE__);

    int[][] ainit = [[1,2,3,4],
                     [5,6,7,8],
                     [9,10,11,12]];

    a=a2NAC(ainit);
    int i=0;
    foreach(row; a) {
        checkeq(row, ainit[i]);
        i++;
    }
}

/// checks if refVal almost== v, if not prints 
bool checkResDot(U,int rank3)(NArray!(U,rank3)refVal,NArray!(U,rank3)v,int tol=8){
    bool res;
    static if(is(typeof(feqrel2(U.init,U.init)))&& is(typeof(U.mant_dig))){
        auto err=minFeqrel2(refVal,v);
        res=(err>=2*U.mant_dig/3-tol);
        if (!res) {
            sout(collectAppender(delegate void(CharSink s){
                s("error:"); writeOut(s,err); s("/"); writeOut(s,U.mant_dig); s("\n");
            }));
        }
    } else {
        res=(refVal==v);
    }
    if (!res){
        sout(collectAppender(delegate void(CharSink s){
            s("v="); writeOut(s,v); s("\n");
            s("refVal="); writeOut(s,refVal); s("\n");
        }));
    }
    return res;
}

/// checks if refVal == v, comparing their string representation 
bool checkResStr(U,int rank3)(NArray!(U,rank3)refVal,NArray!(U,rank3)v,int tol=8){
    bool res=true;
    void checkSame(U a,U b){
        if (res && !eqStr(a,b)) {
            writeOut(sout("'").call,a);
            writeOut(sout("'!='").call,b); sout("'\n");
            res=false;
        }
    }
    binaryOp!(checkSame,rank3,U,U)(refVal, v);
    return res;
}

void testSumAll(T,int rank)(NArray!(T,rank) a){
    static if (rank>0) {
        real refVal=cast(real)0;
        foreach(el;a.flatIter){
            refVal+=cast(real)el;
        }
        real dVal=sumAll!(T,rank,real)(a);
    }
    int err=feqrel2(refVal,dVal);
    if (err<2*real.mant_dig/3-6){
        sout(collectAppender(delegate void(CharSink s){
            s("refVal:"); writeOut(s,refVal); s("\n");
            s("dVal:"); writeOut(s,dVal); s("\n");
        }));
        throw new Exception("sumAll error too large",__FILE__,__LINE__);
    }
}

void testSumAxis(T,int rank)(NArray!(T,rank) a, Rand r){
    int axis=r.uniformR(rank);
    static if (rank>1) {
        auto sV=a.subView(axis);
        auto refVal=zeros!(real)(sV.view.shape);
        foreach(el;sV){
            refVal+=el /*.asType!(real)()*/;
        }
        auto dVal=sumAxis!(T,rank,real)(a,axis);
    } else static if (rank==1){
        auto refVal=sumAll!(T,rank,real)(a);
        auto dVal=sumAxis!(T,rank,real)(a,axis);
    }
    static if (rank==1){
        int err=feqrel2(refVal,dVal);
        if (err<2*real.mant_dig/3-6){
            sout(collectAppender(delegate void(CharSink s){
                s("refVal:"); writeOut(s,refVal); s("\n");
                s("dVal:"); writeOut(s,dVal); s("\n");
            }));
            throw new Exception("sumAxis error too large",__FILE__,__LINE__);
        }
    } else {
        if (!checkResDot(refVal,dVal)) throw new Exception("sumAxis value too different from reference",__FILE__,__LINE__);
    }
}

void testMultAll(T,int rank)(NArray!(T,rank) a){
    static if (rank>0) {
        real refVal=cast(real)1;
        foreach(el;a.flatIter){
            refVal*=cast(real)el;
        }
        real dVal=multiplyAll!(T,rank,real)(a);
    }
    int err=feqrel2(refVal,dVal);
    if (err<2*real.mant_dig/3-6){
        sout(collectAppender(delegate void(CharSink s){
            s("refVal:"); writeOut(s,refVal); s("\n");
            s("dVal:"); writeOut(s,dVal); s("\n");
        }));
        throw new Exception("sumAll error too large",__FILE__,__LINE__);
    }
}

void testMultAxis(T,int rank)(NArray!(T,rank) a, Rand r){
    int axis=r.uniformR(rank);
    static if (rank>1) {
        auto sV=a.subView(axis);
        auto refVal=ones!(real)(sV.view.shape);
        foreach(el;sV){
            refVal*=el /*.asType!(real)()*/;
        }
        auto dVal=multiplyAxis!(T,rank,real)(a,axis);
    } else static if (rank==1){
        auto refVal=multiplyAll!(T,rank,real)(a);
        auto dVal=multiplyAxis!(T,rank,real)(a,axis);
    }
    static if (rank==1){
        int err=feqrel2(refVal,dVal);
        if (err<2*real.mant_dig/3-6){
            sout(collectAppender(delegate void(CharSink s){
                s("refVal:"); writeOut(s,refVal); s("\n");
                s("dVal:"); writeOut(s,dVal); s("\n");
            }));
            throw new Exception("sumAxis error too large",__FILE__,__LINE__);
        }
    } else {
        if (!checkResDot(refVal,dVal)) throw new Exception("sumAxis value too different from reference",__FILE__,__LINE__);
    }
}

void testFilterMask(T,int rank)(NArray!(T,rank) a, Rand r){
    NArray!(bool,rank) mask=randNArray(r,empty!(bool)(a.shape));

    auto b=filterMask(a, mask);
    auto c=unfilterMask(b,mask);
    if (c.shape!=a.shape) throw new Exception("different shape",__FILE__,__LINE__);
    auto ia=a.flatIter, ic=c.flatIter;
    foreach (el;mask.flatIter){
        if (el){
            if (ia.value!=ic.value) throw new Exception("different values in filterMask",__FILE__,__LINE__);
        } else {
            if (ic.value!=cast(T)0) throw new Exception("non zero outside mask",__FILE__,__LINE__);
        }
        ia.next(); ic.next();
    }
}

void testAxisFilter(T,int rank)(NArray!(T,rank) a, NArray!(index_type,1)indexes){
    unaryOp!((ref index_type i){ i=abs(i)%a.shape[0]; },1,index_type)(indexes);
    auto b=axisFilter!(T,rank,NArray!(index_type,1))(a,indexes);
    auto c=zeros!(T)(a.shape);
    auto d=axisUnfilter1(c,b,indexes);
    if (c.shape!=a.shape) throw new Exception("different shape",__FILE__,__LINE__);
    foreach (el;indexes){
        if (!(a[el]==c[el])){
            writeOut(sout("b:").call,b); sout("\n");
            if (b) { b.printData(sout.call); sout("\n"); }
            writeOut(sout("c:").call,c); sout("\n");
            if (c) { c.printData(sout.call); sout("\n"); }
            writeOut(sout("d:").call,d); sout("\n");
            if (d) { d.printData(sout.call); sout("\n"); }
            throw new Exception("axisFilter failed",__FILE__,__LINE__);
        }
    }
}

void testDot1x1(T,S)(Dottable!(T,1,S,1,true,true) d){
    int tol=8;
    alias typeof(T.init*S.init) U;
    MaxPrecTypeOf!(U) refValT=cast(MaxPrecTypeOf!(U))0;
    index_type nEl=d.a.shape[0];
    for (index_type i=0;i<nEl;++i){
        refValT+=d.a[i]*d.b[i];
    }
    U refVal=cast(U)refValT;
    auto v=dot(d.a,d.b,d.axis1,d.axis2);
    static if(is(typeof(feqrel2(U.init,U.init)))&& is(typeof(U.mant_dig))){
        auto err=feqrel2(refVal,v);
        if (err<2*U.mant_dig/3-tol){
            sout("a:"); writeOut(sout.call,d.a); sout("\n");
            sout("b:"); writeOut(sout,d.b); sout("\n");
            sout("v=")(v)("\n");
            sout("refVal=")(refVal)("\n");
            sout("error:")(err)("/")(U.mant_dig)("\n");
        }
        if (err<2*U.mant_dig/3-tol) throw new Exception("error too large",__FILE__,__LINE__);
    } else {
        if (refVal!=v) throw new Exception("value different from reference",__FILE__,__LINE__);
    }
}

void testDot2x1(T,S)(Dottable!(T,2,S,1,true,true) d){
    alias typeof(T.init*S.init) U;
    auto a=d.a;
    if (d.axis1==0 || d.axis1==-2) a=d.a.T;
    auto refValT=zeros!(MaxPrecTypeOf!(U))(a.shape[0]);
    for (index_type j=0;j<a.shape[0];++j){
        for (index_type i=0;i<d.k;++i){
            refValT[j]=refValT[j]+cast(MaxPrecTypeOf!(U))(a[j,i]*d.b[i]);
        }
    }
    auto refVal=refValT.asType!(U)();
    auto v=dot(d.a,d.b,d.axis1,d.axis2);
    if (!checkResDot(refVal,v)) throw new Exception("value too different from reference",__FILE__,__LINE__);
}

void testDot1x2(T,S)(Dottable!(T,1,S,2,true,true) d){
    alias typeof(T.init*S.init) U;
    auto a=d.a;
    auto b=d.b;
    if (d.axis2==1 || d.axis2==-1) b=d.b.T;
    auto refValT=zeros!(MaxPrecTypeOf!(U))(b.shape[1]);
    for (index_type j=0;j<b.shape[1];++j){
        for (index_type i=0;i<d.k;++i){
            refValT[j]=refValT[j]+cast(MaxPrecTypeOf!(U))(a[i]*b[i,j]);
        }
    }
    auto refVal=refValT.asType!(U)();
    auto v=dot(d.a,d.b,d.axis1,d.axis2);
    if (!checkResDot(refVal,v)) throw new Exception("value too different from reference",__FILE__,__LINE__);
}

void testDot2x2(T,S)(Dottable!(T,2,S,2,true,true) d){
    alias typeof(T.init*S.init) U;
    auto a=d.a;
    if (d.axis1==0 || d.axis1==-2) a=d.a.T;
    auto b=d.b;
    if (d.axis2==1 || d.axis2==-1) b=d.b.T;
    auto refValT=zeros!(MaxPrecTypeOf!(U))([a.shape[0],b.shape[1]]);
    for (index_type i=0;i<a.shape[0];++i){
        for (index_type j=0;j<d.k;++j){
            for (index_type k=0;k<b.shape[1];++k){
                refValT[i,k]=refValT[i,k]+cast(MaxPrecTypeOf!(U))(a[i,j]*b[j,k]);
            }
        }
    }
    auto refVal=refValT.asType!(U)();
    auto v=dot(d.a,d.b,d.axis1,d.axis2);
    if (!checkResDot(refVal,v)) throw new Exception("value too different from reference",__FILE__,__LINE__);
}
version(no_lapack){ }
else {
    void testSolve2x2(T)(Dottable!(T,2,T,2,false,true,true,0,0) d,Rand r){
        int tol=9;
        auto x=randLayout(r,empty!(T)([d.a.shape[1],d.b.shape[1]]));
        try{
            x=solve(d.a,d.b,x);
            auto b2=dot(d.a,x);
            auto err=minFeqrel2(d.b,b2);
            if (err<2*T.mant_dig/3-tol) {
                if (err<1) throw new Exception("error too big",__FILE__,__LINE__);
                // check other side
                auto x2=solve(d.a,b2);
                if (!checkResDot(x,x2,tol)) throw new Exception("error too big (even in the x space)",__FILE__,__LINE__);
            }
        } catch (LinAlgException l) {
            if (feqrel2(det(d.a),cast(T)0)<=T.mant_dig/2) throw new Exception("solve failed with non 0 det",__FILE__,__LINE__);
        }
        try{
            x=solve(d.a,d.b);
            auto b2=dot(d.a,x);
            auto err=minFeqrel2(d.b,b2);
            if (err<2*T.mant_dig/3-tol) {
                if (err<1) throw new Exception("error too big2",__FILE__,__LINE__);
                // check other side
                auto x2=solve(d.a,b2);
                if (!checkResDot(x,x2,tol)) throw new Exception("error too big (even in the x space)2",__FILE__,__LINE__);
            }
        } catch (LinAlgException l) {
            if (feqrel2(det(d.a),cast(T)0)<=T.mant_dig/2) throw new Exception("solve 2 failed with non 0 det",__FILE__,__LINE__);
        }
    }

    void testSolve2x1(T)(Dottable!(T,2,T,1,false,true,true,0,0) d,Rand r){
        int tol=9;
        auto x=randLayout(r,zeros!(T)([d.a.shape[1]]));
        try{
            x=solve(d.a,d.b,x);
            auto b2=dot(d.a,x);
            auto err=minFeqrel2(d.b,b2);
            if (err<2*T.mant_dig/3-tol) {
                if (err<1) throw new Exception("error too big",__FILE__,__LINE__);
                // check other side
                auto x2=solve(d.a,b2);
                if (!checkResDot(x,x2,tol)) throw new Exception("error too big (even in the x space)",__FILE__,__LINE__);
            }
        } catch (LinAlgException l) {
            if (feqrel2(det(d.a),cast(T)0)<=T.mant_dig/2) throw new Exception("solve failed with non 0 det",__FILE__,__LINE__);
        }
        try{
            x=solve(d.a,d.b);
            auto b2=dot(d.a,x);
            auto err=minFeqrel2(d.b,b2);
            if (err<2*T.mant_dig/3-tol) {
                if (err<1) throw new Exception("error too big2",__FILE__,__LINE__);
                // check other side
                auto x2=solve(d.a,b2);
                if (!checkResDot(x,x2,tol)) throw new Exception("error too big (even in the x space)2",__FILE__,__LINE__);
            }
        } catch (LinAlgException l) {
            if (feqrel2(det(d.a),cast(T)0)<=T.mant_dig/2) throw new Exception("solve 2 failed with non 0 det",__FILE__,__LINE__);
        }
    }

    void testEig(T)(Dottable!(T,2,T,1,false,true,true,0,0) d){
        int tol=6;
        index_type n=d.k;
        auto ev=zeros!(ComplexTypeOf!(T))(n);
        auto leftEVect=zeros!(ComplexTypeOf!(T))([n,n],true);
        auto rightEVect=zeros!(ComplexTypeOf!(T))([n,n],true);
        auto ev2=eig!(T)(d.a, ev,leftEVect,rightEVect);
        auto m1=dot(d.a,rightEVect);
        auto m2=repeat(ev2,n,0)*rightEVect;
        auto diff1=norm2NA!(ComplexTypeOf!(T),2,real)(m1-m2)/n;
        m1=dot(leftEVect.H1,d.a);
        m2=leftEVect.T*repeat(ev2,n,-1);
        auto diff2=norm2NA!(ComplexTypeOf!(T),2,real)(m1-m2)/n;
        auto err1=feqrel(diff1+1.0L,1.0L);
        auto err2=feqrel(diff2+1.0L,1.0L);
        if (norm2NA!(ComplexTypeOf!(T),2,real)(rightEVect)<=0.5) throw new Exception("rightEVect too small",__FILE__,__LINE__);
        if (norm2NA!(ComplexTypeOf!(T),2,real)(leftEVect)<=0.5) throw new Exception("leftEVect too small",__FILE__,__LINE__);
        if (err1<T.mant_dig*2/3-tol){
            sout("ev:");
            ev2.printData(sout.call,"F8,10"); sout("\n");
            sout("leftEVect:");  leftEVect.printData(sout.call,"F8,10"); sout("\n");
            sout("rightEVect:"); rightEVect.printData(sout.call,"F8,10"); sout("\n");
            sout(collectAppender(delegate void(CharSink s){
                s("error"); writeOut(s,err1); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("rightEVect error too large",__FILE__,__LINE__);
        }
        if (err2<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error"); writeOut(s,err2); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("leftEVect error too large",__FILE__,__LINE__);
        }
        auto ev3=eig(d.a);
        auto diff3=norm2NA!(ComplexTypeOf!(T),1,real)(ev2-ev3)/sqrt(cast(real)n);
        auto err3=feqrel(diff3+1.0L,1.0L);
        if (err3<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error"); writeOut(s,err3); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("eigenvalues changed too much (from eval+evect)",__FILE__,__LINE__);
        }
    }

    void testSvd(T)(Dottable!(T,2,T,1,false,true,false,0,0) d){
        int tol=6;
        index_type m=d.a.shape[0],n=d.a.shape[1],mn=min(n,m);
        auto u=empty!(T)([m,mn]);
        auto vt=empty!(T)([mn,n]);
        auto s=empty!(RealTypeOf!(T))(mn);
        auto s2=svd(d.a,u,s,vt);
        NArray!(T,2) a2;
        if (n<=m){
            a2=dot(u[Range(0,-1),Range(0,n)],repeat(s2,n,-1)*vt);
        } else {
            a2=dot(u*repeat(s2,m,0),vt[Range(0,m)]);
        }
        auto diff1=norm2NA!(T,2,real)(d.a-a2)/n;

        auto m1=dot(u.H,u);
        diag(m1)-=cast(T)1;
        auto diff2=norm2NA!(T,2,real)(m1)/n;

        auto m2=dot(vt,vt.H);
        diag(m2)-=cast(T)1;
        auto diff3=norm2NA!(T,2,real)(m1)/n;

        auto err1=feqrel(diff1+1.0L,1.0L);
        auto err2=feqrel(diff2+1.0L,1.0L);
        auto err3=feqrel(diff3+1.0L,1.0L);
        if (err1<T.mant_dig*2/3-tol){
            d.a.printData(sout("a:").call,"F8"); sout("\n");
            u.printData(sout("u:").call,"F8"); sout("\n");
            s.printData(sout("s:").call,"F8"); sout("\n");
            vt.printData(sout("vt:").call,"F8"); sout("\n");
            sout(collectAppender(delegate void(CharSink s){
                s("error1"); writeOut(s,err1); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("svd does not recover a",__FILE__,__LINE__);
        }
        if (err2<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error2"); writeOut(s,err2); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("u non orthogonal",__FILE__,__LINE__);
        }
        if (err3<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error3"); writeOut(s,err3); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("vt non orthogonal",__FILE__,__LINE__);
        }
        auto s3=svd(d.a);
        auto diff4=norm2NA!(RealTypeOf!(T),1,real)(s2-s3)/sqrt(cast(real)n);
        auto err4=feqrel(diff4+1.0L,1.0L);
        if (err3<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error4"); writeOut(s,err4); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("singular values changed too much (from svd(u,s,vt))",__FILE__,__LINE__);
        }
    }

    void testEigh(T)(Dottable!(T,2,T,1,false,true,true,0,0) d){
        ///  a=dot(u[Range(0,-1),Range(0,vt.shape[0])],repeat(s,vt.shape[0],0)*vt) if vt.shape[0]<=u.shape[0]
        ///  a=dot(u*repeat(s,u.shape[0],-1),vt[Range(0,u.shape[0])]) if vt.shape[0]>=u.shape[0]
        int tol=6;
        index_type n=d.k;
        d.a=hermitize(d.a);
        auto ev=zeros!(RealTypeOf!(T))(n);
        auto eVect=zeros!(T)([n,n],true);
        auto ev2=eigh!(T)(d.a, MStorage.up,ev,eVect);
        auto m1=dot(d.a,eVect);
        auto m2=repeat(ev2,n,0)*eVect;
        auto diff1=norm2NA!(T,2,real)(m1-m2)/n;
        auto m3=dot(eVect.H,eVect);
        auto dd=diag(m3);
        dd-=cast(T)1;
        auto diff2=norm2NA!(T,2,real)(m3)/n;
        auto err1=feqrel(diff1+1.0L,1.0L);
        auto err2=feqrel(diff2+1.0L,1.0L);
        if (err1<T.mant_dig*2/3-tol){
            d.a.printData(sout("a:").call,"F8"); sout("\n");
            ev.printData(sout("ev:").call,"F8"); sout("\n");
            eVect.printData(sout("eVect:").call,"F8"); sout("\n");
            sout(collectAppender(delegate void(CharSink s){
                s("error1"); writeOut(s,err1); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("diagonalization error too large",__FILE__,__LINE__);
        }
        if (err2<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error2"); writeOut(s,err2); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("non orto eVect error too large",__FILE__,__LINE__);
        }
        auto ev3=eigh(d.a);
        auto diff3=norm2NA!(RealTypeOf!(T),1,real)(ev2-ev3)/sqrt(cast(real)n);
        auto err3=feqrel(diff3+1.0L,1.0L);
        if (err3<T.mant_dig*2/3-tol){
            sout(collectAppender(delegate void(CharSink s){
                s("error"); writeOut(s,err3); s("/"); writeOut(s,T.mant_dig); s("\n");
            }));
            throw new Exception("hermitian eigenvalues changed too much (from eval+evect)",__FILE__,__LINE__);
        }
    }
}

void testConvolveNN(T,int rank,Border border)(NArray!(T,rank)inA,NArray!(T,rank)kernel){
    auto refVal=convolveNNRef!(T,rank,border)(kernel,inA);
    auto v=convolveNN!(T,rank,border)(kernel,inA);
    if (!checkResDot(refVal,v)) throw new Exception("value too different from reference",__FILE__,__LINE__);
    refVal=convolveNNRef!(T,rank,border)(kernel,inA,refVal);
    v=convolveNN!(T,rank,border)(kernel,inA,v);
    if (!checkResDot(refVal,v)) throw new Exception("value too different from reference2",__FILE__,__LINE__);
}

void testSerial(T,int rank)(NArray!(T,rank)a){
    auto buf=new IOArray(1000,1000);
    auto s=new JsonSerializer!(char)(strDumper(buf));
    auto u=new JsonUnserializer!(char)(toReaderT!(char)(buf));
    s(a);
    NArray!(T,rank) b;
    u(b);
    if (!checkResStr(a,b)){
        buf.seek(0,buf.Anchor.Begin);
        sout("b:"); writeOut(sout.call,b); sout("\n");
        sout("buf:<<")(cast(char[])buf.slice)(">>\n");
        throw new Exception("different string values",__FILE__,__LINE__);
    }
}

// private mixin testInit!() autoInitTst;

TestCollection narrayRTst1(T,int rank)(TestCollection superColl){
    TestCollection coll=new TestCollection("NArray!("~T.stringof~","~ctfe_i2a(rank)~")",
        __LINE__,__FILE__,superColl);
    autoInitTst.testNoFail("loopCheck1",(NArray!(T,rank) x){checkLoop1!(T,rank)(x);},
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testSumAll",(NArray!(T,rank) d){ testSumAll!(T,rank)(d); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testSumAxis",(NArray!(T,rank) d,Rand r){ testSumAxis!(T,rank)(d,r); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testMultAll",(NArray!(T,rank) d){ testMultAll!(T,rank)(d); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testMultAxis",(NArray!(T,rank) d,Rand r){ testMultAxis!(T,rank)(d,r); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testFilterMask",(NArray!(T,rank) d,Rand r){ testFilterMask!(T,rank)(d,r); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testAxisFilter",(NArray!(T,rank) d,NArray!(index_type,1) idxs){ testAxisFilter!(T,rank)(d,idxs); },
        __LINE__,__FILE__,coll);
    autoInitTst.testNoFail("testSerial",(NArray!(T,rank) d){ testSerial!(T,rank)(d); },
        __LINE__,__FILE__,coll);
    static if (is(T==int) && rank<4){
        autoInitTst.testNoFail("testConvolveNN1b0",(NArray!(T,rank)a){
            index_type[rank] kShape=3; testConvolveNN!(T,rank,Border.Same)(a,ones!(T)(kShape)); },
            __LINE__,__FILE__,coll,TestSize(100/rank));
        autoInitTst.testNoFail("testConvolveNNb0",
            (NArray!(T,rank)a,SizedRandomNArray!(int,ctfe_powI(3,rank)) flatK){
                index_type[rank] kShape=3; auto kernel=reshape(flatK.arr,kShape);
                testConvolveNN!(T,rank,Border.Same)(a,kernel);
            },__LINE__,__FILE__,coll,TestSize(100/rank));
        autoInitTst.testNoFail("testConvolveNN1b+",(NArray!(T,rank)a){
            index_type[rank] kShape=3; testConvolveNN!(T,rank,Border.Increase)(a,ones!(T)(kShape)); },
            __LINE__,__FILE__,coll,TestSize(100/rank));
        autoInitTst.testNoFail("testConvolveNNb+",
            (NArray!(T,rank)a,SizedRandomNArray!(int,ctfe_powI(3,rank)) flatK){
                index_type[rank] kShape=3; auto kernel=reshape(flatK.arr,kShape);
                testConvolveNN!(T,rank,Border.Increase)(a,kernel);
            },__LINE__,__FILE__,coll,TestSize(100/rank));
        autoInitTst.testNoFail("testConvolveNN1b-",(NArray!(T,rank)a){
            index_type[rank] kShape=3; testConvolveNN!(T,rank,Border.Decrease)(a,ones!(T)(kShape)); },
            __LINE__,__FILE__,coll,TestSize(100/rank));
        autoInitTst.testNoFail("testConvolveNNb-",
            (NArray!(T,rank)a,SizedRandomNArray!(int,ctfe_powI(3,rank)) flatK){
                index_type[rank] kShape=3; auto kernel=reshape(flatK.arr,kShape);
                testConvolveNN!(T,rank,Border.Decrease)(a,kernel);
            },__LINE__,__FILE__,coll,TestSize(100/rank));
    }
    static if (rank==1){
        autoInitTst.testNoFail("testDot1x1",(Dottable!(T,1,T,1,true,true) d){ testDot1x1!(T,T)(d); },
            __LINE__,__FILE__,coll);
        autoInitTst.testNoFail("testDot1x2",(Dottable!(T,1,T,2,true,true) d){ testDot1x2!(T,T)(d); },
            __LINE__,__FILE__,coll);
    }
    static if (rank==2){
        autoInitTst.testNoFail("testDot2x1",(Dottable!(T,2,T,1,true,true) d){ testDot2x1!(T,T)(d); },
            __LINE__,__FILE__,coll);
        autoInitTst.testNoFail("testDot2x2",(Dottable!(T,2,T,2,true,true) d){ testDot2x2!(T,T)(d); },
            __LINE__,__FILE__,coll);
        version(no_lapack){ }
        else {
            static if (isBlasType!(T)){
                autoInitTst.testNoFail("testSolve2x1",(Dottable!(T,2,T,1,false,true,true,0,0) d,Rand r)
                    { testSolve2x1!(T)(d,r); },__LINE__,__FILE__,coll);
                autoInitTst.testNoFail("testSolve2x2",(Dottable!(T,2,T,2,false,true,true,0,0) d,Rand r)
                    { testSolve2x2!(T)(d,r); },__LINE__,__FILE__,coll);
                autoInitTst.testNoFail("testEig",(Dottable!(T,2,T,1,false,true,true) d){ testEig!(T)(d); },
                    __LINE__,__FILE__,coll);
                //autoInitTst.testNoFail("testEigh",(Dottable!(T,2,T,1,false,true,true) d){ testEigh!(T)(d); },
                //    __LINE__,__FILE__,coll); // pippo to fix...
                autoInitTst.testNoFail("testSvd",(Dottable!(T,2,T,1,false,true,false) d){ testSvd!(T)(d); },
                    __LINE__,__FILE__,coll);
            }
        }
    }
    return coll;
}

void doNArrayFixTests(){
    NArray!(int,1) a1=a2NAC([1,2,3,4,5,6]);
    NArray!(int,1) a2=NArray!(int,1).zeros([6]);
    auto a3=NArray!(int,2).zeros([5,6]);
    auto a4=NArray!(int,3).zeros([2,3,4]);
    if (a1==a2) throw new Exception("should be different",__FILE__,__LINE__);
    a2[]=a1;
    a4[1,1,1]=10;
    foreach (i,ref v;a4.sFlat){
        v=cast(int)i;
    }
    if (a1!=a2) throw new Exception("should be equal",__FILE__,__LINE__);
    checkLoop1(a1);
    checkLoop1(a2);
    checkLoop1(a3);
    checkLoop1(a4);
    auto a5=a3[1,Range(0,6,2)];
    a5[]=a1[Range(0,3)];
    checkeq(a3[0],[0,0,0,0,0,0]);
    checkeq(a3[1],[1,0,2,0,3,0]);
    checkeq(a3[2],[0,0,0,0,0,0]);
    checkeq(a4[0,Range(1,3),Range(1,4,2)],[5,7,9,11]);
    if (collectAppender(delegate void(CharSink s){ s("a4:"); a4.printData(s,",6",10,"   "); s("\n");})!=
`a4:[[[0     ,1     ,2     ,3     ],
     [4     ,5     ,6     ,7     ],
     [8     ,9     ,10    ,11    ]],
    [[12    ,13    ,14    ,15    ],
     [16    ,17    ,18    ,19    ],
     [20    ,21    ,22    ,23    ]]]
`)
    throw new Exception("NArray.printData wrote unexpected value",__FILE__,__LINE__);
    arangeTests;
    test_iter;
    auto a6=a4.dup;
    unaryOp!((inout int x){x*=2;},3,int)(a6);
    foreach (i,j,k,v;a4.pFlat){
        if (2*v!=a6[i,j,k]) throw new Exception("error",__FILE__,__LINE__);
    }
    auto large1=reshape(arange(150),[15,10]);
    auto large2=large1[Range(10)];
    auto l2=large2.dup;
    auto large3=l2.T;
    if ((large2.flags&ArrayFlags.Large)==0) throw new Exception("error",__FILE__,__LINE__);
    unaryOp!((inout int x){x*=32;},2,int)(large2);
    foreach (i,j,v;large2.pFlat){
        if (v!=32*l2[i,j]) throw new Exception("error",__FILE__,__LINE__);
    }
    binaryOp!((inout int x, int y){x/=y+1;},2,int,int)(large2,large3);
    foreach (i,j,v;large2.pFlat){
        if (v!=(32*l2[i,j])/(large3[i,j]+1)) throw new Exception("error",__FILE__,__LINE__);
    }
    foreach (i,j,ref v;a3.pFlat){
        v+=i+j;
    }
    auto r32=dot(a3,a2);
    auto t=zeros!(int)(r32.shape);
    for (int i=0;i<a3.shape[0];++i)
        for (int j=0;j<a3.shape[1];++j)
            t[i]=t[i]+a3[i,j]*a2[j];
    foreach (i,v;r32){
        if (v!=t[i]) throw new Exception("error",__FILE__,__LINE__);
    }
    NArray!(double,2) a=NArray!(double,2).ones([3,4]);
    auto b=axisFilter(a,2,[3,2,1,1,0]);
}

/// all NArray tests (a template to avoid compilation and instantiation unless really requested)
TestCollection narrayTests()(TestCollection superColl=null){
    TestCollection coll=new TestCollection("NArray",__LINE__,__FILE__,superColl);
    autoInitTst.testNoFailF("fixTests",&doNArrayFixTests,__LINE__,__FILE__,coll);
    version(Windows){
        pragma(msg,"WARNING on windows due to limitations on the number of symbols per module only a subset of the tests is performed "~__FILE__~":"~ctfe_i2a(__LINE__));
        sout("WARNING\non windows due to limitations on the number of symbols per module only a subset of the tests is performed ")(__FILE__)(":")(__LINE__)("\n");
        narrayRTst1!(float,1)(coll);
        narrayRTst1!(float,2)(coll);
    } else {
        narrayRTst1!(int,1)(coll);
        narrayRTst1!(int,2)(coll);
        narrayRTst1!(int,3)(coll);
        narrayRTst1!(float,1)(coll);
        narrayRTst1!(float,2)(coll);
        narrayRTst1!(float,3)(coll);
        narrayRTst1!(double,1)(coll);
        narrayRTst1!(double,2)(coll);
        narrayRTst1!(double,3)(coll);
        narrayRTst1!(real,1)(coll);
        narrayRTst1!(real,2)(coll);
        narrayRTst1!(real,3)(coll);
        narrayRTst1!(cfloat,1)(coll);
        narrayRTst1!(cfloat,2)(coll);
        narrayRTst1!(cfloat,3)(coll);
        narrayRTst1!(cdouble,1)(coll);
        narrayRTst1!(cdouble,2)(coll);
        narrayRTst1!(cdouble,3)(coll);
    }
    return coll;
}
