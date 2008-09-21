/*******************************************************************************
    Tests for NArray
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.narray.Test;
import frm.narray.NArray;
import frm.TemplateFu;
import tango.io.Stdout;
import frm.Stringify;
import tango.math.Math: abs,min,max;
import frm.rtest.RTest;

/// creates arrays that can be dotted with each other along the given axis
/// useful mainly for random tests
/// startAxis1 defalt should be -1, but negative default values have a bug with gdc (#2291)
class Dottable(T,int rank1,S,int rank2,bool scanAxis=false, bool randomLayout=false,
    bool square1=false,int startAxis1=0,int startAxis2=0): RandGen{
    static assert(rank1>0 && rank2>0,"ranks must be strictly positive");
    static assert(-rank1<=startAxis1 && startAxis1<rank1,"startAxis1 out of bounds");
    static assert(-rank2<=startAxis2 && startAxis2<rank2,"startAxis2 out of bounds");
    index_type k;
    int axis1,axis2;
    NArray!(T,rank1) a;
    NArray!(S,rank2) b;
    this(NArray!(T,rank1) a,NArray!(S,rank2) b,int axis1=startAxis1,int axis2=startAxis2)
    {
        assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
        assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
        assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
            "incompatible sizes");
        this.a=a;
        this.b=b;
        this.axis1=axis1;
        this.axis2=axis2;
        this.k=a.shape[((axis1<0)?(rank1+axis1):axis1)];
    }
    /// returns a random array (here with randNArray & co due to bug 2246)
    static Dottable randomGenerate(Rand r,int idx,ref int nEl,ref bool acceptable){
        const index_type maxSize=1_000_000;
        float mean=10.0f;
        index_type[rank1+rank2-1] dims;
        index_type totSize;
        do {
            static if (square1){
                index_type sz=cast(index_type)(r.gamma(mean));
                foreach (ref el;dims){
                    el=sz;
                }
            } else {
                foreach (ref el;dims){
                    el=cast(index_type)(r.gamma(mean));
                }
            }
            totSize=1;
            foreach (el;dims)
                totSize*=el;
            mean*=(cast(float)maxSize)/(cast(float)totSize);
        } while (totSize>maxSize)
        static if(scanAxis){
            int axis1=-rank1+(idx % (2*rank1));
            int axis2=-rank2+((idx / (2*rank1))%(2*rank2));
            nEl=-(4*rank1*rank2);
        } else {
            int axis1=startAxis1;
            int axis2=startAxis2;
        }
        index_type[rank1] dims1=dims[0..rank1];
        auto a=randNArray(r,NArray!(T,rank1).empty(dims1));
        static if (randomLayout) {
            if (r.uniform!(bool)()) a=randLayout(r,a);
        }
        index_type[rank2] dims2;
        int ii=rank1;
        for (int i=0;i<rank2;++i){
            if (i!=axis2 && i!=rank2+axis2){
                dims2[i]=dims[ii];
                ++ii;
            } else {
                dims2[i]=dims[((axis1<0)?(rank1+axis1):axis1)];
            }
        }
        auto b=randNArray(r,NArray!(S,rank2).empty(dims2));
        static if (randomLayout) {
            if (r.uniform!(bool)()) b=randLayout(r,b);
        }
        return new Dottable(a,b,axis1,axis2);
    }
    char[] toString(){
        return getString(printData(new Stringify()));
    }
    Print!(char) printData(Print!(char)s,char[] formatEl="{,10}", index_type elPerLine=10,
        char[] indent=""){
        s(indent)("Dottable{").newline;
        s(indent)("axis1=")(axis1).newline;
        s(indent)("axis2=")(axis2).newline;
        s(indent)("k    =")(k).newline;
        a.desc(s(indent)("a:")).newline;
        a.printData(s,formatEl,elPerLine,indent~"  ").newline;
        b.desc(s(indent)("b:")).newline;
        b.printData(s,formatEl,elPerLine,indent~"  ").newline;
        s(indent)("}").newline;
        return s;
    }
}

version(NoTests){}
else {
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
            mixin(pLoopIdx(rank,["a"],
            "assert(*aPtr0=="~NArrayInLoop("a",rank,"i")~",\"pLoopIdx looping1 failed\");","i"));
        }
        {
            mixin(sLoopGenIdx(rank,["a"],
            "assert(*aPtr0=="~NArrayInLoop("a",rank,"i")~",\"sLoopGenIdx looping1 failed\");","i"));
        }
        index_type[rank] iPos;
        const char[] loopBody1=`
        assert(!did_wrap,"counter wrapped");
        assert(a.arrayIndex(iPos)==*aPtr0,"sLoopPtr failed");
        did_wrap=a.incrementArrayIdx(iPos);
        `;
        {
            bool did_wrap=false;
            iPos[]=cast(index_type)0;
            mixin(sLoopPtr(rank,["a"],loopBody1,"i"));
            assert(did_wrap,"incomplete loop");
        }
        const char[] loopBody2=`
        assert(!did_wrap,"counter wrapped");
        assert(a.arrayIndex(iPos)==*aPtr0,"sLoopIdx looping failed");
        did_wrap=a.incrementArrayIdx(iPos);
        `;
        {
            bool did_wrap=false;
            iPos[]=cast(index_type)0;
            mixin(sLoopGenIdx(rank,["a"],loopBody2,"i"));
            assert(did_wrap,"incomplete loop");
        }
    }

    void checkeq(T,int rank,S)(NArray!(T,rank) a, S x) 
    {
        static assert(is(S:T[]),"compare only to array of the same type");
        int i=0;
        assert(a.size == x.length);
        foreach(i,v;a.pFlat){
            assert(v==x[i]);
        }
    }

    void arangeTests(){
        assert(arange(0.0,0.1,1.0)  .size==1);
        assert(arange(0.0,1.1,1.0)  .size==2);
        assert(arange(0.0,-0.1,-1.0).size==1);
        assert(arange(0.0,-1.1,-1.0).size==2);
        assert(arange(0,1,10)   .size==1);
        assert(arange(0,11,10)  .size==2);
        assert(arange(0,-1,-10) .size==1);
        assert(arange(0,-11,-10).size==2);
        assert(arange(0.0,0.9,1.0)  .size==1);
        assert(arange(0.0,1.9,1.0)  .size==2);
        assert(arange(0.0,-0.9,-1.0).size==1);
        assert(arange(0.0,-1.9,-1.0).size==2);
        assert(arange(0,1,10)   .size==1);
        assert(arange(0,11,10)  .size==2);
        assert(arange(0,-1,-10) .size==1);
        assert(arange(0,-11,-10).size==2);
    }

    void test_iter()
    {
        alias NArray!(int,2) array;
        array a=a2NA( [[1,2,3],[4,5,6]] );

        auto ii = a.flatIter();
        assert(!ii.end);
        assert(ii.ptr == a.data.ptr+0 && ii.value == 1); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+1 && ii.value == 2); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+2 && ii.value == 3); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+3 && ii.value == 4); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+4 && ii.value == 5); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+5 && ii.value == 6);
        assert(!ii.next && ii.end); assert(!ii.next && ii.end);

        a=a.T(); // a now 3x2
        ii = a.flatIter();
        assert(!ii.end);
        assert(ii.ptr == a.data.ptr+0 && ii.value == 1); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+3 && ii.value == 4); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+1 && ii.value == 2); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+4 && ii.value == 5); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+2 && ii.value == 3); assert(ii.next && !ii.end);
        assert(ii.ptr == a.data.ptr+5 && ii.value == 6); assert(!ii.next && ii.end);
        assert(!ii.next && ii.end);

        a=a.T(); // a now 2x3 again
        auto jj = a.T.flatIter();
        assert(!jj.end);
        assert(jj.ptr == a.data.ptr+0 && jj.value == 1); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+3 && jj.value == 4); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+1 && jj.value == 2); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+4 && jj.value == 5); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+2 && jj.value == 3); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+5 && jj.value == 6); assert(!jj.next && jj.end);
        assert(!jj.next && jj.end);

        a=a.T(); // a now 3x2 again
        jj = a.T.flatIter();
        assert(!jj.end);
        assert(jj.ptr == a.data.ptr+0 && jj.value == 1); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+1 && jj.value == 2); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+2 && jj.value == 3); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+3 && jj.value == 4); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+4 && jj.value == 5); assert(jj.next && !jj.end);
        assert(jj.ptr == a.data.ptr+5 && jj.value == 6); assert(!jj.next && jj.end);
        assert(!jj.next && jj.end);

        int[][] ainit = [[1,2,3,4],
                         [5,6,7,8],
                         [9,10,11,12]];

        a=a2NA(ainit);
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
            if (!res) Stdout("error:")(err)("/")(U.mant_dig).newline;
        } else {
            res=(refVal==v);
        }
        if (!res){
            Stdout("v=")(v).newline;
            Stdout("refVal=")(refVal).newline;
        }
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
            Stdout("refVal:")(refVal).newline;
            Stdout("dVal:")(dVal).newline;
            assert(false,"sumAll error too large");
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
                Stdout("refVal:")(refVal).newline;
                Stdout("dVal:")(dVal).newline;
                assert(false,"sumAxis error too large");
            }
        } else {
            assert(checkResDot(refVal,dVal),"sumAxis value too different from reference");
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
            Stdout("refVal:")(refVal).newline;
            Stdout("dVal:")(dVal).newline;
            assert(false,"sumAll error too large");
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
                Stdout("refVal:")(refVal).newline;
                Stdout("dVal:")(dVal).newline;
                assert(false,"sumAxis error too large");
            }
        } else {
            assert(checkResDot(refVal,dVal),"sumAxis value too different from reference");
        }
    }

    void testFilterMask(T,int rank)(NArray!(T,rank) a, Rand r){
        NArray!(bool,rank) mask=randNArray(r,empty!(bool)(a.shape));
    
        auto b=filterMask(a, mask);
        auto c=unfilterMask(b,mask);
        assert(c.shape==a.shape);
        auto ia=a.flatIter, ic=c.flatIter;
        foreach (el;mask.flatIter){
            if (el){
                assert(ia.value==ic.value,"different values in filterMask");
            } else {
                assert(ic.value==cast(T)0,"non zero outside mask");
            }
            ia.next(); ic.next();
        }
    }

    void testAxisFilter(T,int rank)(NArray!(T,rank) a, NArray!(index_type,1)indexes){
        unaryOp!((ref index_type i){ i=abs(i)%a.shape[0]; },1,index_type)(indexes);
        auto b=axisFilter(a,indexes);
        auto c=zeros!(T)(a.shape);
        auto d=axisUnfilter1(c,b,indexes);
        assert(c.shape==a.shape);
        foreach (el;indexes){
            if (!(a[el]==c[el])){
                b.desc(Stdout("b:")).newline;
                b.printData(Stdout).newline;
                c.desc(Stdout("c:")).newline;
                c.printData(Stdout).newline;
                d.desc(Stdout("d:")).newline;
                d.printData(Stdout).newline;
                assert(false,"axisFilter failed");
            }
        }
    }

    void testDot1x1(T,S)(Dottable!(T,1,S,1,true,true) d){
        int tol=8;
        alias typeof(T.init*S.init) U;
        real refValT=0.0L;
        index_type nEl=d.a.shape[0];
        for (index_type i=0;i<nEl;++i){
            refValT+=d.a[i]*d.b[i];
        }
        U refVal=cast(U)refValT;
        auto v=dot(d.a,d.b,d.axis1,d.axis2);
        static if(is(typeof(feqrel2(U.init,U.init)))&& is(typeof(U.mant_dig))){
            auto err=feqrel2(refVal,v);
            if (err<2*U.mant_dig/3-tol){
                d.a.desc(Stdout("a:")).newline;
                d.b.desc(Stdout("b:")).newline;
                Stdout("v=")(v).newline;
                Stdout("refVal=")(refVal).newline;
                Stdout("error:")(err)("/")(U.mant_dig).newline;
            }
            assert(err>=2*U.mant_dig/3-tol,"error too large");
        } else {
            assert(refVal==v,"value different from reference");
        }
    }

    void testDot2x1(T,S)(Dottable!(T,2,S,1,true,true) d){
        alias typeof(T.init*S.init) U;
        auto a=d.a;
        if (d.axis1==0 || d.axis1==-2) a=d.a.T;
        auto refValT=zeros!(real)(a.shape[0]);
        for (index_type j=0;j<a.shape[0];++j){
            for (index_type i=0;i<d.k;++i){
                refValT[j]=refValT[j]+cast(real)(a[j,i]*d.b[i]);
            }
        }
        auto refVal=refValT.asType!(U)();
        auto v=dot(d.a,d.b,d.axis1,d.axis2);
        assert(checkResDot(refVal,v),"value too different from reference");
    }

    void testDot1x2(T,S)(Dottable!(T,1,S,2,true,true) d){
        static int iCall;    
        alias typeof(T.init*S.init) U;
        auto a=d.a;
        auto b=d.b;
        ++iCall;
        if (d.axis2==1 || d.axis2==-1) b=d.b.T;
        auto refValT=zeros!(real)(b.shape[1]);
        for (index_type j=0;j<b.shape[1];++j){
            for (index_type i=0;i<d.k;++i){
                refValT[j]=refValT[j]+cast(real)(a[i]*b[i,j]);
            }
        }
        auto refVal=refValT.asType!(U)();
        auto v=dot(d.a,d.b,d.axis1,d.axis2);
        assert(checkResDot(refVal,v),"value too different from reference");
    }

    void testDot2x2(T,S)(Dottable!(T,2,S,2,true,true) d){
        alias typeof(T.init*S.init) U;
        auto a=d.a;
        if (d.axis1==0 || d.axis1==-2) a=d.a.T;
        auto b=d.b;
        if (d.axis2==1 || d.axis2==-1) b=d.b.T;
        auto refValT=zeros!(real)([a.shape[0],b.shape[1]]);
        for (index_type i=0;i<a.shape[0];++i){
            for (index_type j=0;j<d.k;++j){
                for (index_type k=0;k<b.shape[1];++k){
                    refValT[i,k]=refValT[i,k]+cast(real)(a[i,j]*b[j,k]);
                }
            }
        }
        auto refVal=refValT.asType!(U)();
        auto v=dot(d.a,d.b,d.axis1,d.axis2);
        assert(checkResDot(refVal,v),"value too different from reference");
    }
    version(lapack){
        void testSolve2x2(T)(Dottable!(T,2,T,2,false,true,true,0,0) d,Rand r){
            int tol=9;
            auto x=randLayout(r,empty!(T)([d.a.shape[1],d.b.shape[1]]));
            try{
                x=solve(d.a,d.b,x);
                auto b2=dot(d.a,x);
                auto err=minFeqrel2(d.b,b2);
                if (err<2*T.mant_dig/3-tol) {
                    assert(err>=1,"error too big");
                    // check other side
                    auto x2=solve(d.a,b2);
                    assert(checkResDot(x,x2,tol),"error too big (even in the x space)");
                }
            } catch (LinAlgException l) {
                assert(feqrel2(det(d.a),cast(T)0)>T.mant_dig/2,"solve failed with non 0 det");
            }
            try{
                x=solve(d.a,d.b);
                auto b2=dot(d.a,x);
                auto err=minFeqrel2(d.b,b2);
                if (err<2*T.mant_dig/3-tol) {
                    assert(err>=1,"error too big2");
                    // check other side
                    auto x2=solve(d.a,b2);
                    assert(checkResDot(x,x2,tol),"error too big (even in the x space)2");
                }
            } catch (LinAlgException l) {
                assert(feqrel2(det(d.a),cast(T)0)>T.mant_dig/2,"solve 2 failed with non 0 det");
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
                    assert(err>=1,"error too big");
                    // check other side
                    auto x2=solve(d.a,b2);
                    assert(checkResDot(x,x2,tol),"error too big (even in the x space)");
                }
            } catch (LinAlgException l) {
                assert(feqrel2(det(d.a),cast(T)0)>T.mant_dig/2,"solve failed with non 0 det");
            }
            try{
                x=solve(d.a,d.b);
                auto b2=dot(d.a,x);
                auto err=minFeqrel2(d.b,b2);
                if (err<2*T.mant_dig/3-tol) {
                    assert(err>=1,"error too big2");
                    // check other side
                    auto x2=solve(d.a,b2);
                    assert(checkResDot(x,x2,tol),"error too big (even in the x space)2");
                }
            } catch (LinAlgException l) {
                assert(feqrel2(det(d.a),cast(T)0)>T.mant_dig/2,"solve 2 failed with non 0 det");
            }
        }

        void testEig(T)(Dottable!(T,2,T,1,false,true,true,0,0) d){
            int tol=6;
            index_type n=d.k;
            auto ev=zeros!(complexType!(T))(n);
            auto leftEVect=zeros!(complexType!(T))([n,n],true);
            auto rightEVect=zeros!(complexType!(T))([n,n],true);
            auto ev2=eig!(T)(d.a, ev,leftEVect,rightEVect);
            auto m1=dot(d.a,rightEVect);
            auto m2=repeat(ev2,n,0)*rightEVect;
            auto diff1=norm2!(complexType!(T),2,real)(m1-m2)/n;
            m1=dot(leftEVect.H1,d.a);
            m2=leftEVect.T*repeat(ev2,n,-1);
            auto diff2=norm2!(complexType!(T),2,real)(m1-m2)/n;
            auto err1=feqrel(diff1+1.0L,1.0L);
            auto err2=feqrel(diff2+1.0L,1.0L);
            assert(norm2!(complexType!(T),2,real)(rightEVect)>0.5,"rightEVect too small");
            assert(norm2!(complexType!(T),2,real)(leftEVect)>0.5,"leftEVect too small");
            if (err1<T.mant_dig*2/3-tol){
                ev2.printData(Stdout("ev:"),"{:F8,10}").newline;
                leftEVect.printData(Stdout("leftEVect:"),"{:F8,10}").newline;
                rightEVect.printData(Stdout("rightEVect:"),"{:F8,10}").newline;
                Stdout("error")(err1)("/")(T.mant_dig).newline;
                assert(false,"rightEVect error too large");
            }
            if (err2<T.mant_dig*2/3-tol){
                Stdout("error")(err2)("/")(T.mant_dig).newline;
                assert(false,"leftEVect error too large");
            }
            auto ev3=eig(d.a);
            auto diff3=norm2!(complexType!(T),1,real)(ev2-ev3)/sqrt(cast(real)n);
            auto err3=feqrel(diff3+1.0L,1.0L);
            if (err3<T.mant_dig*2/3-tol){
                Stdout("error")(err2)("/")(T.mant_dig).newline;
                assert(false,"eigenvalues changed too much (from eval+evect)");
            }
        }

        void testSvd(T)(Dottable!(T,2,T,1,false,true,false,0,0) d){
            int tol=6;
            index_type m=d.a.shape[0],n=d.a.shape[1],mn=min(n,m);
            auto u=empty!(T)([m,mn]);
            auto vt=empty!(T)([mn,n]);
            auto s=empty!(realType!(T))(mn);
            auto s2=svd(d.a,u,s,vt);
            NArray!(T,2) a2;
            if (n<=m){
                a2=dot(u[Range(0,-1),Range(0,n)],repeat(s2,n,-1)*vt);
            } else {
                a2=dot(u*repeat(s2,m,0),vt[Range(0,m)]);
            }
            auto diff1=norm2!(T,2,real)(d.a-a2)/n;
    
            auto m1=dot(u.H,u);
            diag(m1)-=cast(T)1;
            auto diff2=norm2!(T,2,real)(m1)/n;
    
            auto m2=dot(vt,vt.H);
            diag(m2)-=cast(T)1;
            auto diff3=norm2!(T,2,real)(m1)/n;
    
            auto err1=feqrel(diff1+1.0L,1.0L);
            auto err2=feqrel(diff2+1.0L,1.0L);
            auto err3=feqrel(diff3+1.0L,1.0L);
            if (err1<T.mant_dig*2/3-tol){
                d.a.printData(Stdout("a:"),"{:F8}").newline;
                u.printData(Stdout("u:"),"{:F8}").newline;
                s.printData(Stdout("s:"),"{:F8}").newline;
                vt.printData(Stdout("vt:"),"{:F8}").newline;
                Stdout("error1 ")(err1)("/")(T.mant_dig).newline;
                assert(false,"svd does not recover a");
            }
            if (err2<T.mant_dig*2/3-tol){
                Stdout("error2 ")(err2)("/")(T.mant_dig).newline;
                assert(false,"u non orthogonal");
            }
            if (err3<T.mant_dig*2/3-tol){
                Stdout("error3 ")(err2)("/")(T.mant_dig).newline;
                assert(false,"vt non orthogonal");
            }
            auto s3=svd(d.a);
            auto diff4=norm2!(realType!(T),1,real)(s2-s3)/sqrt(cast(real)n);
            auto err4=feqrel(diff4+1.0L,1.0L);
            if (err3<T.mant_dig*2/3-tol){
                Stdout("error4 ")(err2)("/")(T.mant_dig).newline;
                assert(false,"singular values changed too much (from svd(u,s,vt))");
            }
        }

        void testEigh(T)(Dottable!(T,2,T,1,false,true,true,0,0) d){
            ///  a=dot(u[Range(0,-1),Range(0,vt.shape[0])],repeat(s,vt.shape[0],0)*vt) if vt.shape[0]<=u.shape[0]
            ///  a=dot(u*repeat(s,u.shape[0],-1),vt[Range(0,u.shape[0])]) if vt.shape[0]>=u.shape[0]
            int tol=6;
            index_type n=d.k;
            d.a=hermitize(d.a);
            auto ev=zeros!(realType!(T))(n);
            auto eVect=zeros!(T)([n,n],true);
            auto ev2=eigh!(T)(d.a, MStorage.up,ev,eVect);
            auto m1=dot(d.a,eVect);
            auto m2=repeat(ev2,n,0)*eVect;
            auto diff1=norm2!(T,2,real)(m1-m2)/n;
            auto m3=dot(eVect.H,eVect);
            auto dd=diag(m3);
            dd-=cast(T)1;
            auto diff2=norm2!(T,2,real)(m3)/n;
            auto err1=feqrel(diff1+1.0L,1.0L);
            auto err2=feqrel(diff2+1.0L,1.0L);
            if (err1<T.mant_dig*2/3-tol){
                d.a.printData(Stdout("a:"),"{:F8}").newline;
                ev.printData(Stdout("ev:"),"{:F8}").newline;
                eVect.printData(Stdout("eVect:"),"{:F8}").newline;
                Stdout("error1 ")(err1)("/")(T.mant_dig).newline;
                assert(false,"diagonalization error too large");
            }
            if (err2<T.mant_dig*2/3-tol){
                Stdout("error2 ")(err2)("/")(T.mant_dig).newline;
                assert(false,"non orto eVect error too large");
            }
            auto ev3=eigh(d.a);
            auto diff3=norm2!(realType!(T),1,real)(ev2-ev3)/sqrt(cast(real)n);
            auto err3=feqrel(diff3+1.0L,1.0L);
            if (err3<T.mant_dig*2/3-tol){
                Stdout("error")(err2)("/")(T.mant_dig).newline;
                assert(false,"hermitian eigenvalues changed too much (from eval+evect)");
            }
        }
    }

    private mixin testInit!() autoInitTst;

    TestCollection narrayRTst1(T,int rank)(TestCollection superColl){
        TestCollection coll=new TestCollection("NArray!("~T.stringof~","~ctfe_i2a(rank)~")",
            __LINE__,__FILE__,superColl);
        autoInitTst.testNoFail("loopCheck1",(NArray!(T,rank) x){checkLoop1!(T,rank)(x);},
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testSumAll",(NArray!(T,rank) d){ testSumAll!(T,rank)(d); },
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testSumAxis",(NArray!(T,rank) d,Rand r){ testSumAxis!(T,rank)(d,r); },
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testMultAll",(NArray!(T,rank) d){ testMultAll!(T,rank)(d); },
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testMultAxis",(NArray!(T,rank) d,Rand r){ testMultAxis!(T,rank)(d,r); },
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testFilterMask",(NArray!(T,rank) d,Rand r){ testFilterMask!(T,rank)(d,r); },
            __LINE__,__FILE__,TestSize(),coll);
        autoInitTst.testNoFail("testAxisFilter",(NArray!(T,rank) d,NArray!(index_type,1) idxs){ testAxisFilter!(T,rank)(d,idxs); },
            __LINE__,__FILE__,TestSize(),coll);
        static if (rank==1){
            autoInitTst.testNoFail("testDot1x1",(Dottable!(T,1,T,1,true,true) d){ testDot1x1!(T,T)(d); },
                __LINE__,__FILE__,TestSize(),coll);
            autoInitTst.testNoFail("testDot1x2",(Dottable!(T,1,T,2,true,true) d){ testDot1x2!(T,T)(d); },
                __LINE__,__FILE__,TestSize(),coll);
        }
        static if (rank==2){
            autoInitTst.testNoFail("testDot2x1",(Dottable!(T,2,T,1,true,true) d){ testDot2x1!(T,T)(d); },
                __LINE__,__FILE__,TestSize(),coll);
            autoInitTst.testNoFail("testDot2x2",(Dottable!(T,2,T,2,true,true) d){ testDot2x2!(T,T)(d); },
                __LINE__,__FILE__,TestSize(),coll);
            version(lapack){
                static if (isBlasType!(T)){
                    autoInitTst.testNoFail("testSolve2x1",(Dottable!(T,2,T,1,false,true,true,0,0) d,Rand r)
                        { testSolve2x1!(T)(d,r); },__LINE__,__FILE__,TestSize(),coll);
                    autoInitTst.testNoFail("testSolve2x2",(Dottable!(T,2,T,2,false,true,true,0,0) d,Rand r)
                        { testSolve2x2!(T)(d,r); },__LINE__,__FILE__,TestSize(),coll);
                    autoInitTst.testNoFail("testEig",(Dottable!(T,2,T,1,false,true,true) d){ testEig!(T)(d); },
                        __LINE__,__FILE__,TestSize(),coll);
                    autoInitTst.testNoFail("testEigh",(Dottable!(T,2,T,1,false,true,true) d){ testEigh!(T)(d); },
                        __LINE__,__FILE__,TestSize(),coll);
                    autoInitTst.testNoFail("testSvd",(Dottable!(T,2,T,1,false,true,false) d){ testSvd!(T)(d); },
                        __LINE__,__FILE__,TestSize(),coll);
                }
            }
        }
        return coll;
    }

    TestCollection rtestNArray(){
        TestCollection coll=new TestCollection("NArray",__LINE__,__FILE__);
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
        return coll;
    }

    void doNArrayTests(int nTests=1){
        NArray!(int,1) a1=a2NA([1,2,3,4,5,6]);
        NArray!(int,1) a2=NArray!(int,1).zeros([6]);
        auto a3=NArray!(int,2).zeros([5,6]);
        auto a4=NArray!(int,3).zeros([2,3,4]);
        assert(a1!=a2,"should be different");
        a2[]=a1;
        a4[1,1,1]=10;
        foreach (i,ref v;a4.sFlat){
            v=cast(int)i;
        }
        assert(a1==a2,"should be equal");
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
        //Stdout("`")(getString(a4.printData((new Stringify)("a4:"),"{,6}",10,"   ").newline))("`").newline;
        assert(getString(a4.printData((new Stringify)("a4:"),"{,6}",10,"   ").newline)==
`a4:[[[     0,     1,     2,     3],
     [     4,     5,     6,     7],
     [     8,     9,    10,    11]],
    [[    12,    13,    14,    15],
     [    16,    17,    18,    19],
     [    20,    21,    22,    23]]]
`,"NArray.printData wrote unexpected value");
        arangeTests;
        test_iter;
        auto a6=a4.dup;
        unaryOp!((inout int x){x*=2;},3,int)(a6);
        foreach (i,j,k,v;a4.pFlat){
            assert(2*v==a6[i,j,k]);
        }
        auto large1=reshape(arange(150),[15,10]);
        auto large2=large1[Range(10)];
        auto l2=large2.dup;
        auto large3=l2.T;
        assert(large2.flags&ArrayFlags.Large);
        unaryOp!((inout int x){x*=32;},2,int)(large2);
        foreach (i,j,v;large2.pFlat){
            assert(v==32*l2[i,j]);
        }
        binaryOp!((inout int x, int y){x/=y+1;},2,int,int)(large2,large3);
        foreach (i,j,v;large2.pFlat){
            assert(v==(32*l2[i,j])/(large3[i,j]+1));
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
            assert(v==t[i]);
        }
        NArray!(double,2) a=NArray!(double,2).ones([3,4]);
        auto b=axisFilter(a,2,[3,2,1,1,0]);
    
        // random tests
        // SingleRTest.defaultTestController=new TextController(TextController.OnFailure.StopAllTests,
        //     TextController.PrintLevel.AllShort);
        TestCollection narrayTsts=rtestNArray();
        narrayTsts
        .runTests(nTests);
    }

    debug(UnitTest){
        unittest{
            doNArrayTests();
        }
    }
}