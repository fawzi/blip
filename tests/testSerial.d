/// tests the serialization facility of blip
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
module testSerial;
import blip.io.Console;
import blip.serialization.Handlers;
import blip.serialization.Serialization;
import blip.rtest.RTest;
import blip.io.IOArray;
import tango.io.model.IConduit;
import blip.container.GrowableArray;
import blip.BasicModels;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }
import blip.io.StreamConverters;
import blip.io.BasicIO;
import blip.io.BufferIn;

version(Xpose){
    public import blip.serialization.SerializationExpose;
}

class A: Serializable{
    int x;
    int y;
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("AKlass");
        //("AKlass",null,typeid(typeof(this)),typeof(this).classinfo,typeKindForType!(typeof(this)));
        //SerializationRegistry().register!(typeof(this))(metaI);
        metaI.addFieldOfType!(int)("x","an int called x");
        metaI.addFieldOfType!(int)("y","an int field called y");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        s.field(metaI[0],x);
        s.field(metaI[1],y);
    }
    void randomize(Rand r){
        r(x)(y);
    }
    static A randomGenerate(Rand r){
        A res=new A();
        res.randomize(r);
        return res;
    }
    Serializable preUnserialize(Unserializer s){
        return this;
    }
    /// unserialize an object
    void unserialize(Unserializer s){
        s.field(metaI[0],x);
        s.field(metaI[1],y);
    }
    Serializable postUnserialize(Unserializer s){
        return this;
    }
    override int opEquals(Object other){
        if (auto oo=cast(A)other){
            return x==oo.x && y==oo.y;
        }
        return 0;
    }
}

struct FExp{
    int f(int i){
        return i*(i-1)/2;
    }
    int i=4;
    int max=100;
    int opApply(int delegate(ref int) loopOp){
        while(i>0 && i<max){
            int res=loopOp(i);
            if (res) return res;
            i=f(i);
        }
        return 0;
    }
    int opApply(int delegate(ref int,ref int) loopOp){
        while(i>0 && i<max){
            int j=f(i);
            int res=loopOp(i,j);
            if (res) return res;
            i=j;
        }
        return 0;
    }
    int next(){
        if (i<=0 || i>=max) throw new Exception("at end",__FILE__,__LINE__);
        int res=i;
        i=f(i);
        return res;
    }
    bool atEnd(){
        return i<=0||i>=max;
    }
}

class B:A{
    int a;
    uint b;
    long c;
    ulong d;
    char[] e;
    wchar[] f;
    dchar[] g;
    float h;
    double i;
    real l;
    version(noComplex){
        float m;
        double n;
        real o;
        float p;
        double q;
        real r;
    } else {
        ifloat m;
        idouble n;
        ireal o;
        cfloat p;
        cdouble q;
        creal r;
    }
    bool s;
    byte t;
    ubyte u;
    short v;
    ushort z;
    version(Xpose){
        mixin(expose!(NewSerializationExpose)(`a|b|c|d|e|f|g|h|i|l|m|n|o|p|q|r|s|t|u|v|z`));
    } else {
        mixin(serializeSome("",`a|b|c|d|e|f|g|h|i|l|m|n|o|p|q|r|s|t|u|v|z`));
    }
    version(SerializationTrace){
        version(Xpose){
            pragma(msg,NewSerializationExpose.handler!(0).begin(``));
            pragma(msg,NewSerializationExpose.handler!(0).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(0).end(``));
        }
    }
    override int opEquals(Object other){
        if (this.classinfo !is other.classinfo) return 0;
        if (auto oo=cast(B)other){
            return super.opEquals(other) &&
                a==oo.a && b==oo.b && c==oo.c && d==oo.d && e==oo.e && f==oo.f &&
                g==oo.g && eqStr(h,oo.h) && eqStr(i,oo.i) && eqStr(l,oo.l) && 
                eqStr(m,oo.m) && eqStr(n,oo.n) && eqStr(o,oo.o) && eqStr(p,oo.p) &&
                eqStr(q,oo.q) && eqStr(r,oo.r) && s==oo.s && t==oo.t &&
                u==oo.u && v==oo.v && z==oo.z;
        }
        return 0;
    }
    void randomize(Rand rr,int idx,ref int nEl, ref bool acceptable){
        super.randomize(rr);
        Randomizer.init(rr,idx,nEl,acceptable)(a)(b)(c)(d)(e)(f)(g)(h)(i)(l)
            (m)(n)(o)(p)(q)(r)(s)(t)(u)(v)(z).end(nEl,acceptable);
    }
    static B randomGenerate(Rand r,int idx,ref int nEl, ref bool acceptable){
        auto res=new B();
        res.randomize(r,idx,nEl,acceptable);
        return res;
    }
}

class C{
    int i;
    C next;
    this(){ }
    version(Xpose){
        mixin(expose!(NewSerializationExpose)(`
        i
        next
        `));
    } else {
        mixin(serializeSome("",`
        i: an integer
        next
        `));
    }
    override int opEquals(Object o){
        if (o.classinfo !is this.classinfo) return 0;
        C oo=cast(C)o;
        int res= i==oo.i;
        if (next is null){
            res = res && oo.next is null;
        } else {
            res = res && (oo.next !is null) && oo.next.i==next.i;
        }
        return res;
    }
}

struct TestStruct{
    int[] a;
    int[][] b;
    int[char[]] c;
    int[int] d;
    A[] e;
    version(Xpose){
        version(SerializationTrace){
            pragma(msg,NewSerializationExpose.handler!(0).begin(``));
            pragma(msg,NewSerializationExpose.handler!(0).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(0).end(``));
            pragma(msg,NewSerializationExpose.handler!(1).begin(``));
            pragma(msg,NewSerializationExpose.handler!(1).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(1).end(``));
        }
        mixin(expose!(NewSerializationExpose)(`a|b|c|d|e`));
    } else {
        mixin(serializeSome("",`a|b|c|d|e`));
    }

    void randomize(Rand r,int idx,ref int nEl, ref bool acceptable){
        Randomizer.init(r,idx,nEl,acceptable)(a)(b)(c)(d)(e).end(nEl,acceptable);
    }
    static TestStruct randomGenerate(Rand r,int idx,ref int nEl, ref bool acceptable){
        TestStruct res;
        res.randomize(r,idx,nEl,acceptable);
        return res;
    }
    int opEquals(TestStruct s){
        auto res= a==s.a && b==s.b && c.length==s.c.length && d.length==s.d.length && e==s.e;
        if (res){
            foreach(k,v;c){
                auto v2=k in s.c;
                if (v2 is null || (*v2)!=v) return 0;
            }
            foreach(k,v;d){
                auto v2=k in s.d;
                if (v2 is null || (*v2)!=v) return 0;
            }
            return 1;
        }
        return 0;
    }
}

void testUnserial(T)(T a){
    testJsonUnserial!(T)(a);
    testBinUnserial!(T)(a);
    testBin2Unserial!(T)(a);
}
/// unserialization test
void testJsonUnserial(T)(T a){
    version(UnserializationTrace) sout("testing unserialization of "~T.stringof~"\n");
    auto buf=new IOArray(1000,1000);
    auto js=new JsonSerializer!()(strDumper(buf));
    js(a);
    auto jus=new JsonUnserializer!()(toReaderT!(char)(buf));
    T sOut;
    version(UnserializationTrace) sout("XXXXXX Unserialization start\n");
    jus(sOut);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("XXXXXX Unserialization end\n");
        sout("original:----\n");
        js2(a);
        sout("unserialized:--\n");
        js2(sOut);
        sout("in the buffer:-----\n");
        buf.seek(0,IOStream.Anchor.Begin);
        sout(cast(char[])buf.slice)("\n");
        sout("-----\n");
    }
    assert(a==sOut,"unserial error with "~T.stringof);
    version(UnserializationTrace) sout("passed test of unserialization of "~T.stringof~"\n");
}
/// unserialization test
void testBinUnserial(T)(T a){
    version(UnserializationTrace) sout("testing unserialization of "~T.stringof~"\n");
    auto buf=new IOArray(1000,1000);
    auto js=new SBinSerializer(binaryDumper(buf));
    js(a);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("in the buffer:-----\n");
        buf.seek(0,IOStream.Anchor.Begin);
        char[128] buf2;
        auto arr=lGrowableArray!(char)(buf2,0);
        foreach (i,ub;cast(ubyte[])buf.slice){
            writeOut(&arr.appendArr,ub);
            arr(" ");
            if (i%10==9) {
                arr("\n");
                sout(arr.data);
                arr.clearData;
            }
        }
        arr("\n");
        sout(arr.data);
        buf.seek(0,IOStream.Anchor.Begin);
        sout("original:----\n");
        js2(a);
        sout("XXXXXX Unserialization start\n");
    }
    auto jus=new SBinUnserializer(toReaderT!(void)(buf));
    T sOut;
    jus(sOut);
    version(UnserializationTrace){
        sout("XXXXXX Unserialization end\n");
        sout("unserialized:--\n");
        js2(sOut);
        sout("-----\n");
    }
    assert(a==sOut,"unserial error with "~T.stringof);
    version(UnserializationTrace) sout("passed test of unserialization of "~T.stringof~"\n");
}

void testBin2Unserial(T)(T a){
    version(UnserializationTrace) sout("testing unserialization of "~T.stringof~"\n");
    ubyte[256] _buf;
    auto buf=lGrowableArray(_buf,0);
    auto js=new SBinSerializer(&buf.appendVoid);
    js(a);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("in the buffer:-----\n");
        char[128] buf2;
        auto arr=lGrowableArray!(char)(buf2,0);
        foreach (i,ub;cast(ubyte[])buf.data){
            writeOut(&arr.appendArr,ub);
            arr(" ");
            if (i%10==9) {
                arr("\n");
                sout(arr.data);
                arr.clearData;
            }
        }
        arr("\n");
        sout(arr.data);
        sout("original:----\n");
        js2(a);
        sout("XXXXXX Unserialization start\n");
    }
    auto reader=arrayReader(cast(void[])buf.data);
    auto jus=new SBinUnserializer(reader);
    T sOut;
    jus(sOut);
    version(UnserializationTrace){
        sout("XXXXXX Unserialization end\n");
        sout("unserialized:--\n");
        js2(sOut);
        sout("-----\n");
    }
    assert(a==sOut,"unserial error with "~T.stringof);
    version(UnserializationTrace) sout("passed test of unserialization of "~T.stringof~"\n");
}

void testUnserial2(T,U)(void delegate(void function(T,U)) testF){
    testF(function void(T a,U b){ testJsonUnserial2!(T,U)(a,b); });
    testF(function void(T a,U b){ testBinUnserial2!(T,U)(a,b); });
    testF(function void(T a,U b){ testBin2Unserial2!(T,U)(a,b); });
}

/// unserialization test2 Json
void testJsonUnserial2(T,U)(T a,ref U sOut){
    version(UnserializationTrace) sout("testing json unserialization of "~T.stringof~"\n");
    auto buf=new IOArray(1000,1000);
    auto js=new JsonSerializer!()(strDumper(buf));
    js(a);
    auto jus=new JsonUnserializer!()(toReaderT!(char)(buf));
    version(UnserializationTrace) sout("XXXXXX Unserialization start\n");
    jus(sOut);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("XXXXXX Unserialization end\n");
        sout("in the buffer:-----\n");
        buf.seek(0,IOStream.Anchor.Begin);
        sout(cast(char[])buf.slice);
        sout("\n-----\n");
    }
    version(UnserializationTrace) sout("json unserialization of "~T.stringof~"\n");
}
/// unserialization test2 Bin
void testBinUnserial2(T,U)(T a,ref U b){
    version(UnserializationTrace) sout("testing binary unserialization of "~T.stringof~"\n");
    auto buf=new IOArray(1000,1000);
    auto js=new SBinSerializer(binaryDumper(buf));
    js(a);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("in the buffer:-----\n");
        buf.seek(0,IOStream.Anchor.Begin);
        char[128] buf2;
        auto arr=lGrowableArray!(char)(buf2,0);
        foreach (i,ub;cast(ubyte[])buf.slice){
            writeOut(&arr.appendArr,ub);
            arr(" ");
            if (i%10==9) {
                arr("\n");
                sout(arr.data);
                arr.clearData;
            }
        }
        arr("\n");
        sout(arr.data);
        buf.seek(0,IOStream.Anchor.Begin);
        sout("----\n");
        sout("XXXXXX Unserialization start\n");
    }
    auto jus=new SBinUnserializer(toReaderT!(void)(buf));
    jus(b);
    version(UnserializationTrace){
        sout("XXXXXX Unserialization end\n");
    }
    version(UnserializationTrace) sout("binary test of unserialization of "~T.stringof~"\n");
}
/// unserialization test2 Bin2
void testBin2Unserial2(T,U)(T a,ref U b){
    version(UnserializationTrace) sout("testing binary unserialization of "~T.stringof~"\n");
    ubyte[256] _buf;
    auto buf=lGrowableArray(_buf,0);
    auto js=new SBinSerializer(&buf.appendVoid);
    js(a);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(sout);
        sout("in the buffer:-----\n");
        char[128] buf2;
        auto arr=lGrowableArray!(char)(buf2,0);
        foreach (i,ub;cast(ubyte[])buf.data){
            writeOut(&arr.appendArr,ub);
            arr(" ");
            if (i%10==9) {
                arr("\n");
                sout(arr.data);
                arr.clearData;
            }
        }
        arr("\n");
        sout(arr.data);
        sout("----\n");
        sout("XXXXXX Unserialization start\n");
    }
    auto reader=arrayReader(cast(void[])buf.data);
    auto jus=new SBinUnserializer(reader);
    jus(b);
    version(UnserializationTrace){
        sout("XXXXXX Unserialization end\n");
    }
    version(UnserializationTrace) sout("binary test of unserialization of "~T.stringof~"\n");
}

void main(){
    CoreHandlers ch;
    auto fh=new FormattedWriteHandlers!(char)(sout.call);
    auto i=4;
    fh.handle(i);
    auto s="abc".dup;
    fh.handle(s);
    sout("\n");
    
    auto js=new JsonSerializer!()(sout);
    auto r=new Rand();
    A a;
    simpleRandom(r,a);
    js.field(cast(FieldMetaInfo *)null,a);
    a.x=3;
    a.y=4;
    js.field(cast(FieldMetaInfo *)null,a);
    testUnserial(a);
    
    void testLazyArray(void function(LazyArray!(int),LazyArray!(int)) testF){
        FExp fExp;
        FExp fExp2;
        auto arrayIn=LazyArray!(int)(cast(int delegate(int delegate(ref int)))&fExp.opApply);
        auto arrayOut=LazyArray!(int)(delegate void(int i){
                auto val=fExp2.next();
                if (i!=val) {
                    sout(collectAppender(delegate void(CharSink s){
                        s("ERROR: read "); writeOut(s,i); s(" vs "); writeOut(s,val); s("\n");
                    }));
                    throw new Exception("unexpected value",__FILE__,__LINE__);
                }
            });
        testF(arrayIn,arrayOut);
        if (!fExp2.atEnd()) throw new Exception("incomplete read",__FILE__,__LINE__);
    }

    void testLazyAA(void function(LazyAA!(int,int),LazyAA!(int,int)) testF){
        FExp fExp;
        FExp fExp2;
        auto arrayIn=LazyAA!(int,int)(cast(int delegate(int delegate(ref int,ref int)))&fExp.opApply);
        auto arrayOut=LazyAA!(int,int)(delegate void(int k,int v){
                auto kR=fExp2.next();
                auto vR=fExp2.i;
                if (k!=kR || v!=vR) {
                    sout(collectAppender(delegate void(CharSink s){
                        s("keys:"); writeOut(s,k); s(" vs "); writeOut(s,kR);
                        s(" vals:"); writeOut(s,v); s(" vs "); writeOut(s,vR); s("\n");
                    }));
                    throw new Exception("unexpected value",__FILE__,__LINE__);
                }
            });
        testF(arrayIn,arrayOut);
        if (!fExp2.atEnd()) throw new Exception("incomplete read",__FILE__,__LINE__);
    }
    
    testUnserial2(&testLazyArray);
    testUnserial2(&testLazyAA);
    
    A b=new B();
    
    js(b);
    B bb;
    simpleRandom(r,bb);
    js.resetObjIdCounter();
    (cast(B)b).a=1;
    js(b);
    js(bb);
    TestStruct ts;
    simpleRandom(r,ts);
    js(ts);
    C c,d;
    c=new C();
    d=new C();
    c.i=0;
    d.i=2;
    c.next=d;
    d.next=c;
    js(c);
    b=bb;

    testUnserial(b);
    testUnserial(c);
    testUnserial(ts);
    sout("passed identity tests\n");

    version(noComplex){ }
    else {
    auto buf=new IOArray(`{ id:3,
      x:36331662,
      y:504414800,
      a:-1894881897,
      b:2942220189,
      c:-8297515914883251209,
      d:17869291317653118063,
      e:",Oc0C  4-",
      f:"Esdn   ?a,uc&n[4c}k",
      g:"FSP}N,'SgtA",
      h:3.18,
      i:0.28,
      l:-1.00,
      m:-1.39*1i,
      n:-2.34*1i,
      o:-0.91*1i,
      p:-1.95-1.53*1i,
      q:1.46+1.23*1i,
      r:1.75+3.26*1i,
      s:false,
      t:-49,
      u:185,
      v:31268,
      z:19578
    }

    {
      x:36331662,
      y:504414800,
      b:2942220189, # b has been moved
      a:-1894881897,
      c:-8297515914883251209,
      d:17869291317653118063,
      e:",Oc0C  4-",
      f:"Esdn   ?a,uc&n[4c}k",
      g:"FSP}N,'SgtA",
      h:3.18,
      i:0.28, # l is missing
      m:-1.39*1i,
      n:-2.34*1i,
      o:-0.91*1i,
      p:-1.95-1.53*1i,
      q:1.46+1.23*1i,
      r:1.75+3.26*1i,
      s:false,
      t:-49,
      u:185,
      v:31268,
      z:19578
    }
    `);
    auto jus=new JsonUnserializer!()(toReaderT!(char)(buf));
    B b1,b2;
    version(UnserializationTrace) sout("XX unserial reference\n");
    jus(b1);
    version(UnserializationTrace) sout("XX unserial reordered+comment+missing\n");
    jus(b2);
    version(UnserializationTrace) sout("XX unserialization finished\n");
    b2.l=b1.l;
    assert(b1==b2,"reordering+comments+missing failed");
    }
    
    sout("passed tests\n");
}

