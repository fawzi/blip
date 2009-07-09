module testSerial;
import tango.io.Stdout;
import blip.serialization.Handlers;
import blip.serialization.Serialization;
import blip.rtest.RTest;
import tango.io.device.Array;
import tango.io.model.IConduit;
import blip.text.Stringify;
import blip.BasicModels;
import tango.core.stacktrace.TraceExceptions;
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
version(Xpose){
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
        ifloat m;
        idouble n;
        ireal o;
        cfloat p;
        cdouble q;
        creal r;
        bool s;
        byte t;
        ubyte u;
        short v;
        ushort z;
        mixin(expose!(NewSerializationExpose)(`a|b|c|d|e|f|g|h|i|l|m|n|o|p|q|r|s|t|u|v|z`));
        version(SerializationTrace){
            pragma(msg,NewSerializationExpose.handler!(0).begin(``));
            pragma(msg,NewSerializationExpose.handler!(0).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(0).end(``));
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
        mixin(expose!(NewSerializationExpose)(`
        i
        next
        `));
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
        version(SerializationTrace){
            pragma(msg,NewSerializationExpose.handler!(0).begin(``));
            pragma(msg,NewSerializationExpose.handler!(0).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(0).end(``));
            pragma(msg,NewSerializationExpose.handler!(1).begin(``));
            pragma(msg,NewSerializationExpose.handler!(1).field(``, `a`, `a`, false, ``));
            pragma(msg,NewSerializationExpose.handler!(1).end(``));
        }
        mixin(expose!(NewSerializationExpose)(`a|b|c|d|e`));
    
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
}

/// unserialization test
void testUnserial(T)(T a){
    version(UnserializationTrace) Stdout("testing unserialization of "~T.stringof).newline;
    auto buf=new Array(1000,1000);
    auto js=new JsonSerializer!()(new FormatOutput!(char)(buf));
    js(a);
    auto jus=new JsonUnserializer!()(buf);
    T sOut;
    version(UnserializationTrace) Stdout("XXXXXX Unserialization start").newline;
    jus(sOut);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(Stdout);
        Stdout("XXXXXX Unserialization end").newline;
        Stdout("original:----").newline;
        js2(a);
        Stdout("unserialized:--").newline;
        js2(sOut);
        Stdout("in the buffer:-----").newline;
        buf.seek(0,IOStream.Anchor.Begin);
        Stdout(cast(char[])buf.slice).newline;
        Stdout("-----").newline;
    }
    assert(a==sOut,"unserial error with "~T.stringof);
    version(UnserializationTrace) Stdout("passed test of unserialization of "~T.stringof).newline;
}
/// unserialization test
void testBinUnserial(T)(T a){
    version(UnserializationTrace) Stdout("testing unserialization of "~T.stringof).newline;
    auto buf=new Array(1000,1000);
    auto js=new SBinSerializer(buf);
    js(a);
    version(UnserializationTrace) {
        auto js2=new JsonSerializer!()(Stdout);
        Stdout("in the buffer:-----").newline;
        buf.seek(0,IOStream.Anchor.Begin);
        foreach (i,ub;cast(ubyte[])buf.slice){
            Stdout.format("{:x} ",ub);
            if (i%10==9) Stdout.newline;
        }
        buf.seek(0,IOStream.Anchor.Begin);
        Stdout.newline;
        Stdout("original:----").newline;
        js2(a);
        Stdout("XXXXXX Unserialization start").newline;
    }
    auto jus=new SBinUnserializer(buf);
    T sOut;
    jus(sOut);
    version(UnserializationTrace){
        Stdout("XXXXXX Unserialization end").newline;
        Stdout("unserialized:--").newline;
        js2(sOut);
        Stdout("-----").newline;
    }
    assert(a==sOut,"unserial error with "~T.stringof);
    version(UnserializationTrace) Stdout("passed test of unserialization of "~T.stringof).newline;
}

void main(){
    CoreHandlers ch;

    auto fh=new FormattedWriteHandlers(Stdout);
    auto i=4;
    fh.handle(i);
    auto s="abc".dup;
    fh.handle(s);
    Stdout.newline;
    
    auto js=new JsonSerializer!()(Stdout);
    auto r=new Rand();
    A a;
    simpleRandom(r,a);
    js.field(cast(FieldMetaInfo *)null,a);
    a.x=3;
    a.y=4;
    js.field(cast(FieldMetaInfo *)null,a);
    version (no_Xpose){
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
    
        testUnserial(a);
        testUnserial(b);
        testUnserial(c);
        testUnserial(ts);
        testBinUnserial(a);
        testBinUnserial(b);
        testBinUnserial(c);
        testBinUnserial(ts);
        Stdout("passed identity tests").newline;

        auto buf=new Array(`{ id:3,
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
        auto jus=new JsonUnserializer!()(buf);
        B b1,b2;
        version(UnserializationTrace) Stdout("XX unserial reference").newline;
        jus(b1);
        version(UnserializationTrace) Stdout("XX unserial reordered+comment+missing").newline;
        jus(b2);
        version(UnserializationTrace) Stdout("XX unserialization finished").newline;
        b2.l=b1.l;
        assert(b1==b2,"reordering+comments+missing failed");
    }
    Stdout("passed tests").newline;
}

