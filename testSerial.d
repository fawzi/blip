module testSerial;
import tango.io.Stdout;
import blip.serialization.Handlers;
import blip.serialization.Serialization;

class A: Serializable{
    int a;
    int b;
    static ClassMetaInfo metaI;
    static this(){
        metaI=new ClassMetaInfo("AKlass",null,typeid(typeof(this)),typeof(this).classinfo,
            typeKindForType!(typeof(this)));
        SerializationRegistry().register!(typeof(this),typeof(this))(metaI);
        metaI.addField(FieldMetaInfo("a",getSerializationInfoForType!(int)()));
        metaI.addField(FieldMetaInfo("b",getSerializationInfoForType!(int)()));
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(SerializerBase s){ }
    void postSerialize(SerializerBase s){ }
    void serialize(SerializerBase s){
        s.field(metaI[0],a);
        s.field(metaI[1],b);
    }
}

class B:A{
    double x;
    real[] y;
    mixin(expose!(NewSerializationExpose)(`
		x	name ecks
		y   name pippo
	`));
    version(SerializationTrace){
        pragma(msg,NewSerializationExpose.handler!(0).begin(``));
    	pragma(msg,NewSerializationExpose.handler!(0).field(``, `x`, `ecks`, false, ``));
    	pragma(msg,NewSerializationExpose.handler!(0).end(``));
    	pragma(msg,NewSerializationExpose.handler!(1).begin(``));
        pragma(msg,NewSerializationExpose.handler!(1).field(``, `x`, `ecks`, false, ``));
    	pragma(msg,NewSerializationExpose.handler!(1).end(``));
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
    
    JsonSerializer js=new JsonSerializer(Stdout);
    A a=new A();
    a.a=3;
    a.b=4;
    js.field(cast(FieldMetaInfo *)null,a);
    A b=new B();
    js(b);
    js.resetObjIdCounter();
    (cast(B)b).y=[1.0,3.7,8.555];
    js(b);
}