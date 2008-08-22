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
import tango.math.Math: abs;
import frm.rtest.RTest;

/// creates arrays that can be dotted with each other along the given axis
/// useful mainly for random tests
/// startAxis1 defalt should be -1, but negative default values have a bug with gdc (#2291)
class Dottable(T,int rank1,S,int rank2,bool scanAxis=false, bool randomLayout=false,
    int startAxis1=0,int startAxis2=0): RandGen{
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
            foreach (ref el;dims){
                el=cast(index_type)(r.gamma(mean));
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
        s(indent)("a=");
        a.printData(s,formatEl,elPerLine,indent~"  ").newline;
        s(indent)("b=");
        b.printData(s,formatEl,elPerLine,indent~"  ").newline;
        s(indent)("}").newline;
        return s;
    }
}

/// returns a NArray indexed with the variables of a pLoopGenIdx or sLoopGenIdx
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
        mixin(pLoopGenIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"pLoopGenIdx looping1 failed\");","i"));
    }
    {
        mixin(sLoopGenIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"sLoopGenIdx looping1 failed\");","i"));
    }
    {
        mixin(sLoopGenIdx(rank,["a"],[],
        "assert(*(aBasePtr+aIdx0)=="~NArrayInLoop("a",rank,"i")~",\"sLoopGenPtr looping1 failed\");","i"));
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
        mixin(sLoopPtr(rank,["a"],[],loopBody1,"i"));
        assert(did_wrap,"incomplete loop");
    }
    const char[] loopBody2=`
    assert(!did_wrap,"counter wrapped");
    assert(a.arrayIndex(iPos)==*(aBasePtr+aIdx0),"sLoopIdx looping failed");
    did_wrap=a.incrementArrayIdx(iPos);
    `;
    {
        bool did_wrap=false;
        iPos[]=cast(index_type)0;
        mixin(sLoopIdx(rank,["a"],[],loopBody2,"i"));
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

void testDot1x1(T,S)(Dottable!(T,1,S,1,true,true) d){
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
        if (err<2*U.mant_dig/3-4){
            d.a.desc(Stdout("a:")).newline;
            d.b.desc(Stdout("b:")).newline;
            Stdout("v=")(v).newline;
            Stdout("refVal=")(refVal).newline;
            Stdout("error:")(err)("/")(U.mant_dig).newline;
        }
        assert(err>=2*U.mant_dig/3-4,"error too large");
    } else {
        assert(refVal==v,"value different from reference");
    }
}

/// checks if refVal almost== v, if not prints 
bool checkResDot(T,int rank1,S,int rank2,U,int rank3)(NArray!(T,rank1) a, NArray!(S,rank2) b,
    NArray!(U,rank3)refVal,NArray!(U,rank3)v){
    bool res;
    static if(is(typeof(feqrel2(U.init,U.init)))&& is(typeof(U.mant_dig))){
        auto err=minFeqrel2(refVal,v);
        res=(err>=2*U.mant_dig/3-4);
        if (!res) Stdout("error:")(err)("/")(U.mant_dig).newline;
    } else {
        res=(refVal==v);
    }
    if (!res){
        a.desc(Stdout("a:")).newline;
        b.desc(Stdout("b:")).newline;
        Stdout("v=")(v).newline;
        Stdout("refVal=")(refVal).newline;
    }
    return res;
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
    assert(checkResDot(d.a,d.b,refVal,v),"value too different from reference");
}

void testDot1x2(T,S)(Dottable!(T,1,S,2,true,true) d){
    alias typeof(T.init*S.init) U;
    auto a=d.a;
    auto b=d.b;
    if (d.axis2==1 || d.axis2==-1) b=d.b.T;
    auto refValT=zeros!(real)(b.shape[1]);
    for (index_type j=0;j<b.shape[1];++j){
        for (index_type i=0;i<d.k;++i){
            refValT[j]=refValT[j]+cast(real)(a[i]*b[i,j]);
        }
    }
    auto refVal=refValT.asType!(U)();
    auto v=dot(d.a,d.b,d.axis1,d.axis2);
    assert(checkResDot(d.a,d.b,refVal,v),"value too different from reference");
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
    assert(checkResDot(d.a,d.b,refVal,v),"value too different from reference");
}

private mixin testInit!() autoInitTst;

TestCollection narrayRTst1(T,int rank)(TestCollection superColl){
    TestCollection coll=new TestCollection("NArray!("~T.stringof~","~ctfe_i2a(rank)~")",
        __LINE__,__FILE__,superColl);
    autoInitTst.testNoFail("loopCheck1",(NArray!(T,rank) x){checkLoop1!(T,rank)(x);},
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
    return coll;
}

void doNArrayTests(){
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
    auto t=zeros!(int)(r32.mShape);
    for (int i=0;i<a3.mShape[0];++i)
        for (int j=0;j<a3.mShape[1];++j)
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
    narrayTsts.runTests();
}

unittest{
    doNArrayTests();
}