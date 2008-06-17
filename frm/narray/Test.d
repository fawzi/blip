module frm.narray.Test;
import frm.narray.NArray;
import frm.TemplateFu;
import tango.io.Stdout;

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


unittest{
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
    a4.printData(Stdout("a4:"),"{,6}",10,"   ").newline;
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
}