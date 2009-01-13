module testSerial;
import tango.io.Stdout;
import blip.serialization.Handlers;
import blip.serialization.Serialization;
import blip.rtest.RTest;
import tango.io.device.Array;
import tango.io.model.IConduit;

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
        if (auto oo=cast(B)other){
            return a==oo.a && b==oo.b && c==oo.c && d==oo.d && e==oo.e && f==oo.f &&
                g==oo.g && h==oo.h && i==oo.i && l==oo.l && m==oo.m && n==oo.n &&
                o==oo.o && p==oo.p && q==oo.q && r==oo.r && s==oo.s && t==oo.t &&
                u==oo.u && v==oo.v && z==oo.z;
        }
        return 0;
    }
    void randomize(Rand r,int idx,ref int nEl, ref bool acceptable){
        Randomizer.init(r,idx,nEl,acceptable)(a)(b)(c)(d)(e)(f)(g)(h)(i)(l)
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
    auto buf=new Array(1000,1000);
    auto js2=new JsonSerializer!()(new FormatOutput!(char)(buf));
    js2(a);
    auto jus=new JsonUnserializer!()(buf);
    A sOut;
    Stdout("XXXXXX Unserialization start").newline;
    jus(sOut);
    Stdout("XXXXXX Unserialization end").newline;
    Stdout("-----").newline;
    js(a);
    Stdout("--").newline;
    js(sOut);
    Stdout("-----").newline;
    buf.seek(0,IOStream.Anchor.Begin);
    Stdout(cast(char[])buf.slice).newline;
    Stdout("-----").newline;
    assert(a==sOut,"unserial error 1");
    
}