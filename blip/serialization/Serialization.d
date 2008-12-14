module blip.serialization.Serialization;
import blip.serialization.Handlers;
import xf.xpose.Expose;
import tango.io.Stdout : Stdout;
public alias xf.xpose.Expose.expose expose;
public alias xf.xpose.Expose.attribsContain attribsContain;
public alias xf.xpose.Expose.attribsGet attribsGet;
public import xf.xpose.Utils;
import tango.core.Tuple;
import tango.io.Print;
import tango.core.Variant;

alias Tuple!(bool,byte,ubyte,short,ushort,int,uint,long,ulong,
    float,double,real,ifloat,idouble,ireal,cfloat,cdouble,creal,ubyte[],
    char[],wchar[],dchar[]) CoreTypes2;

/// meta informations for fields
struct FieldMetaInfo {
    char[] name; /// name of the propety
    ClassMetaInfo metaInfo; /// expected meta info (used if not class)
    enum SerializationLevel{
        normalLevel=0,
        debugLevel=10,
        never=20
    }
    SerializationLevel serializationLevel;
    static FieldMetaInfo opCall(char[] name,ClassMetaInfo metaInfo,SerializationLevel l=SerializationLevel.normalLevel)
    {
        FieldMetaInfo res;
        res.name = name;
        res.metaInfo=metaInfo;
        res.serializationLevel=l;
        return res;
    }
}
/// returns the typeid of the given type
template typeKindForType(T){
    static if(isCoreType!(T)){
        const typeKindForType=TypeKind.PrimitiveK;
    } else static if(is(T==class)){
        const typeKindForType=TypeKind.ClassK;
    } else static if(is(T:array)){
        const typeKindForType=TypeKind.ArrayK;
    } else static if(isAssocArrayType!(T)){
        static if (is(KeyTypeOfAA!(T)==char[])||is(KeyTypeOfAA!(T)==wchar[])||is(KeyTypeOfAA!(T)==dchar[])){
            const typeKindForType=TypeKind.DictK;
        } else {
            const typeKindForType=TypeKind.AAK;
        }
    } else static if(is(T==struct)){
        const typeKindForType=TypeKind.StructK;
    } else static if (is(typeof(*T))){
        const typeKindForType=typeKindForType!(*T);
    } else {
        static assert(0,"unsupported type "~T.stringof);
    }
}

enum TypeKind{
    PrimitiveK,
    ClassK,
    ArrayK,
    DictK,
    AAK,
    StructK,
    OtherK,
    ArrayElK,
    AAKeyK,
    AAValK
}

struct ExternalSerializationHandlers{
    void function (SerializerBase s,ClassMetaInfo mInfo,void* o) preSerialize;
    void function (SerializerBase s,ClassMetaInfo mInfo,void* o) serialize;
    void function (SerializerBase s,ClassMetaInfo mInfo,void* o) postSerialize;
    void*function (SerializerBase s,ClassMetaInfo mInfo,void* o) preUnserialize;
    void function (SerializerBase s,ClassMetaInfo mInfo,void* o) unserialize;
    void function (SerializerBase s,ClassMetaInfo mInfo,void* o) postUnserialize;
}

/// meta informations for a class
class ClassMetaInfo {
    char[] className;
    ClassMetaInfo superMeta;
    FieldMetaInfo[] fields;
    TypeKind kind;
    TypeInfo ti;
    ClassInfo ci;
    ExternalSerializationHandlers * externalHandlers;
    FieldMetaInfo *opIndex(int i){
        if (i>=0 && i<fields.length){
            return &(fields[i]);
        } else {
            return null;
        }
    }
    FieldMetaInfo *fieldNamed(char[]name){
        FieldMetaInfo* res;
        foreach (ref f;fields){
            if (f.name==name) return &f;
        }
        if (superMeta){
            return superMeta.fieldNamed(name);
        } else {
            return null;
        }
    }
    void addField(FieldMetaInfo f){
        assert(fieldNamed(f.name) is null,"field names have to be unique");
        fields~=f;
    }
    this(char[] className,ClassMetaInfo superMeta,TypeInfo ti,ClassInfo ci,TypeKind kind){
        this.className=className;
        this.superMeta=superMeta;
        this.ti=ti;
        this.ci=ci;
        this.kind=kind;
    }
    /// number of local fields
    int nLocalFields(){ return fields.length; }
    /// total number of fields
    int nTotFields(){
        if (superMeta){
            return superMeta.nTotFields()+fields.length;
        }
        return fields.length;
    }
}

/// interface of the objetcs that can be serialized
interface Serializable{
    ClassMetaInfo getSerializationMetaInfo();
    // the actual serialization function;
    void serialize(SerializerBase s);
    /// pre serializer hook, useful to (for example) lock the structure and guarantee a consistent snapshot
    void preSerialize(SerializerBase s);
    /// post serializer hook, useful to (for example) unlock the structure
    /// guaranteed to be called if preSerialize ended sucessfully
    void postSerialize(SerializerBase s);
    /// allocate space for the object if s is null
/+    static Serializable preUnserialize(Unserializer s);
    /// unserialize an object
    void unserialize(Unserializer s);
    /// post unserialization hook 
    void postUnserialize(Unserializer s);+/
}

const onUnserializedFuncName = "onUnserialized";


template RefType(T) {
    static if (is(T == class)) {
        alias T RefType;
    } else {
        alias T* RefType;
    }
}


template UnrefType(T) {
    static if (is(T == class)) {
        alias T UnrefType;
    } else {
        alias typeof(*T) UnrefType;
    }
}

// various metaInfo (for completeness, not really needed)
ClassMetaInfo arrayMetaInfo;
ClassMetaInfo aaMetaInfo;
ClassMetaInfo dictMetaInfo;
static this(){
    arrayMetaInfo=new ClassMetaInfo("array",null,null,null,TypeKind.ArrayK); // use a unique type for each array type?
    aaMetaInfo=new ClassMetaInfo("aa",null,null,null,TypeKind.AAK); // use a unique type for each aa type?
    dictMetaInfo=new ClassMetaInfo("dict",null,null,null,TypeKind.DictK); // use a unique type for each dict type?
    SerializationRegistry().register!(int[],int[])(arrayMetaInfo);
    SerializationRegistry().register!(int[int],int[int])(aaMetaInfo);
    SerializationRegistry().register!(int[char[]],int[char[]])(dictMetaInfo);
}

char[] coreTypesMetaInfoMixStr(){
    char[] res="".dup;
    foreach(T;CoreTypes2){
        res~="ClassMetaInfo "~strForCoreType!(T)~"MetaInfo;\n";
    }
    res~="static this(){\n";
    foreach(T;CoreTypes){
        res~=strForCoreType!(T)~"MetaInfo=new ClassMetaInfo(\""~T.stringof~"\",null,typeid("~T.stringof~"),null,TypeKind.PrimitiveK);\n";
        res~="SerializationRegistry().register!("~T.stringof~","~T.stringof~")("~strForCoreType!(T)~"MetaInfo);\n";
    }
    res~="}\n";
    return res;
}

mixin(coreTypesMetaInfoMixStr());

ClassMetaInfo getSerializationInfoForType(T)(){
    static if (is(T==class)){
        return SerializationRegistry().getMetaInfo(T.classinfo);
    } else static if (is(T==struct)){
        return SerializationRegistry().getMetaInfo(typeid(T));
    } else static if (is(T==Serializable)){
        return SerializationRegistry().getMetaInfo(Serializable.classinfo);
    } else static if (is(T==interface)){
        return SerializationRegistry().getMetaInfo(Object.classinfo);
    } else static if (isArrayType!(T)){
        return arrayMetaInfo;
    } else static if (isAssocArrayType!(T)){
        return aaMetaInfo;
    } else static if (isCoreType!(T)){
        foreach(V;CoreTypes){
            static if(is(T==V)){
                mixin("return "~strForCoreType!(V)~"MetaInfo;");
            }
        }
    } else static if (is(typeof(*T))){
        return getSerializationInfoForType!(T)();
    } else {
        static assert(0,"unsupported type "~T.stringof); 
    }
}

template NewSerializationExpose_mix0() {
    static char[] begin(char[] target) {
        return `
        static ClassMetaInfo serializationMetaInfo;
        
        ClassMetaInfo getSerializationMetaInfo() {
            return serializationMetaInfo;
        }

        private template SerializationInitializerMix() {
            static this() {
                alias `~("" == target ? `UnrefType!(typeof(this))` : target)~` TargetType;
                ClassMetaInfo superMeta=null;
                static if (is(TargetType T==super)) {
                    foreach(U;T){
                        static if(is(U==class)){
                            superMeta=getSerializationInfoForType!(U)();
                        }
                    }
                }
                static if(is(TargetType==class)){
                    ClassInfo ci=TargetType.classinfo;
                } else {
                    ClassInfo ci=null;
                }
                serializationMetaInfo=new ClassMetaInfo(TargetType.mangleof,superMeta,typeid(TargetType),ci,
                    typeKindForType!(TargetType));
                SerializationRegistry().register!(TargetType, UnrefType!(typeof(this)))(serializationMetaInfo);
                static if(!is(TargetType==UnrefType!(typeof(this)))){
                    serializationMetaInfo.externalHandlers=new ExternalSerializationHandlers;
                    //serializationMetaInfo.externalHandlers.serialize=&serializeFunction;
                }
                
                serializationGatherFieldInfo(serializationMetaInfo);
            }
        }

        protected static void serializationGatherFieldInfo(inout ClassMetaInfo serializationMetaInfo) {`;
    }
    
    
    static char[] end(char[] target) {
        return `}  mixin SerializationInitializerMix;`;
    }
    
    
    static char[] method(char[] target, char[] name, char[] rename, char[] overload, char[] attribs) {
        return ``;
    }
    
    static char[] field(char[] target, char[] name, char[] rename, bool readOnly, char[] attribs) {
        char[] res="".dup;
        if (rename.length==0) rename=name;
        char[] fieldN="field_"~rename;
        char[] type=attribsGet(attribs,"type");
        char[] indent="    ";
        res~=indent~"FieldMetaInfo "~fieldN~";\n";
        res~=indent~"{\n";
        res~=indent~"    alias "~(target.length>0?target:"typeof(this)")~" TType;\n";
        char[] fType=attribsGet(attribs,"type");
        if (fType.length>0){
            res~=indent~"    alias "~fType~" FType;\n";
        } else {
            res~=indent~"    alias typeof(TType.init."~name~") FType;\n";
        }
        res~=indent~"    ClassMetaInfo fieldClassInfo=getSerializationInfoForType!(FType)();\n";
        if (attribsContain(`~"`"~attribs~"`"~`, "no-serial"))
            res~=indent~"    auto sLevel=FieldMetaInfo.SerializationLevel.never;\n";
        else {
            res~=indent~"    static if (is(typeof(*FType))&& (! isArrayType!(FType)) && !(is(typeof(*FType)==class)||is(typeof(*FType)==struct)||is(typeof(*FType) U== U[]))){\n";
            res~=indent~"        auto sLevel=FieldMetaInfo.SerializationLevel.debugLevel;\n";
            res~=indent~"    } else {\n";
            res~=indent~"        auto sLevel=FieldMetaInfo.SerializationLevel.normalLevel;\n";
            res~=indent~"    }\n";
        }
        res~=indent~"    "~fieldN~"=FieldMetaInfo(`"~rename~"`,fieldClassInfo,sLevel);\n";
        res~=indent~"}\n";
        res~=indent~"serializationMetaInfo.addField("~fieldN~");\n";
        return res;
    }
}


template NewSerializationExpose_mix1() {
    static char[] begin(char[] target) {
        if (target.length==0) target=`typeof(this)`;
        return
        `
        static if (is(`~target~` == class)) {
            alias typeof(super) SuperType;
            static if (!is(typeof(SuperType.init.preSerialize(SerializerBase.init)))) {
                void preSerialize(SerializerBase s){ }
            }
            static if (!is(typeof(SuperType.init.postSerialize(SerializerBase.init)))) {
                void postSerialize(SerializerBase s){ }
            }
            void serialize(SerializerBase s){
                static if (is(`~target~` T==super)){
                    static if (is(typeof(T.init.serialize(s)))){
                        static assert(`~target~`==typeof(this),"serialization in subclasses of types that implement methods to serialize have to be impemented inside the subclasses, not outside");
                        super.serialize(s);
                    }
                }
                serializeFunction(s,serializationMetaInfo,cast(void*)this);
            }
        }
        
        static void serializeFunction(SerializerBase serializer, ClassMetaInfo metaInfo, void* _this) {
            assert(metaInfo is serializationMetaInfo);
            static if (is(`~target~` T==super)){
                static if (!is(typeof(T.init.serialize(s)))){
                    if (metaInfo.superMeta !is null &&
                        metaInfo.superMeta.externalHandlers !is null){
                        assert(metaInfo.superMeta.externalHandlers.serialize !is null,
                            "null externalHandlers.serialize for class "~metaInfo.superMeta.className~"("~T.stringof~")");
                        metaInfo.superMeta.externalHandlers.serialize(serializer,metaInfo.superMeta,_this);
                    }
                }
            }
            int fieldIndex=0;
`;
    }
    
    
    static char[] end(char[] target) {
        return ` }`;
    }
    
    
    static char[] method(char[] target, char[] name, char[] rename, char[] overload, char[] attribs) {
        return ``;
    }
    
    static char[] field(char[] target, char[] name, char[] rename, bool readOnly, char[] attribs) {
        if (rename.length==0) rename=name;
        char[] fieldN="field_"~rename;
        char[] prefix = "" == target ? "(cast(RefType!(typeof(this)))_this)." : `(cast(RefType!(`~target~`))_this).`;
        char[] res=`
        {
            FieldMetaInfo *fieldMeta=serializationMetaInfo[fieldIndex];
            serializer.field(fieldMeta,`~prefix~name~`);
            ++fieldIndex;
        }
        `;
        return res;
    }

}

class SerializationRegistry {
    ClassMetaInfo[Object]                                           type2metaInfos;
    ClassMetaInfo[char[]]                                           name2metaInfos;

    Object keyOf(T)() {
        static if (is(T == class)) {
            return T.classinfo;
        } else {
            return typeid(T);
        }
    }
    
    
    void register(T, Worker)(ClassMetaInfo metaInfo) {
        assert(metaInfo!is null,"attempt to register null metaInfo");
        version(SerializationTrace) Stdout.formatln("Registering {} in the serialization factory", metaInfo.className);
        Object key = keyOf!(T);
        synchronized(this){
            name2metaInfos[metaInfo.className]=metaInfo;
            type2metaInfos[key] = metaInfo;
        }
    }    
    
    ClassMetaInfo getMetaInfo(Object ci) {
        synchronized(this){
            auto ptr = ci in type2metaInfos;
            if (ptr is null) return null;
            return *ptr;
        }
    }
    
    static typeof(this) opCall() {
        static typeof(this) instance;
        if (instance is null) instance = new typeof(this);
        return instance;
    }
}

template isBasicType(T) {
    const bool isBasicType =
        is(T == long) ||
        is(T == ulong) ||
        is(T == int) ||
        is(T == uint) ||
        is(T == short) ||
        is(T == ushort) ||
        is(T == byte) ||
        is(T == ubyte) ||
        is(T == bool) ||
        is(T == float) ||
        is(T == double) ||
        is(T == real) ||
        is(T == ifloat) ||
        is(T == idouble) ||
        is(T == ireal) ||
        is(T == cfloat) ||
        is(T == cdouble) ||
        is(T == creal) ||
        is(T == dchar) ||
        is(T == wchar) ||
        is(T == char);
}


template isArrayType(T) {
    const bool isArrayType = false;
}


template isArrayType(T : T[]) {
    const bool isArrayType = true;
}


template isAssocArrayType(T) {
    static if (is(typeof(T.keys)) && is(typeof(T.values))) {
        static if (is(T == typeof(T.values[0])[typeof(T.keys[0])])) {
            const bool isAssocArrayType = true;
        } else const bool isAssocArrayType = false;
    } else const bool isAssocArrayType = false;
}

static assert (isAssocArrayType!(char[char[]]));

    
template KeyTypeOfAA(T){
    alias typeof(T.init.keys[0]) KeyTypeOfAA;
}

template ValTypeOfAA(T){
    alias typeof(T.init.values[0]) ValTypeOfAA;
}

template isPointerType(T) {
    static if (is(typeof(*T))) const isPointerType = true;
    else const isPointerType = false;
}

/// serializer
/// some methods have no classinfo for performance reasons, if you really need it file a ticket explaining why 
class SerializerBase {
    typedef size_t classId;
    typedef size_t objectId;
    WriteHandlers handlers;
    
    objectId[void*]             ptrToObjectId;
    objectId                        lastObjectId;
    FieldMetaInfo.SerializationLevel serializationLevel;
    bool removeCycles;

    this(WriteHandlers h=null) {
        ptrToObjectId[null] = 0;
        lastObjectId=cast(objectId)1;
        handlers=h;
        removeCycles=true;
    }
    /// resets objectId counter (and the mapping pointer->objectId) used to remove cycles
    void resetObjIdCounter(){
        ptrToObjectId=null;
        ptrToObjectId[null] = 0;
        lastObjectId=cast(objectId)1;
    }
    
    /// writes the given root object
    /// you should only use the field method to write in the serialization methods
    typeof(this) opCall(T)(T o) {
        writeStartRoot();
        field!(T)(cast(FieldMetaInfo *)null,o);
        writeEndRoot();
        return this;
    }
    
    void writeStartRoot() { }
    void writeEndRoot() { }
        
    void field(T)(FieldMetaInfo *fieldMeta, ref T t) {
        version(SerializationTrace) Stdout("field!("~T.stringof~")(")(cast(void*)fieldMeta)(",")(cast(void*)&t)(") starting").newline;
        if (fieldMeta !is null && fieldMeta.serializationLevel>serializationLevel) return;
        static if (isCoreType!(T)){
            version(SerializationTrace) Stdout("pippo0").newline;
            writeCoreType(fieldMeta, { handlers.handle(t); });
        } else static if (is(T == interface) && !is(T==Serializable)) {
            version(SerializationTrace) Stdout("pippo1").newline;
            field!(Object)(fieldMeta,cast(Object)t);
        } else {
            static if(is(T==class)||is(T==Serializable)||isArrayType!(T)||isPointerType!(T)){
                version(SerializationTrace) Stdout("pippo2").newline;
                // chek for cycles
                static if(is(T==class)||is(T==Serializable)) {
                    void* ptr=cast(void *)cast(Object)t;
                } else static if (isPointerType!(T)) {
                    void* ptr=cast(void*)t;
                } else {
                    void* ptr=t.ptr;
                }
                if (ptr is null){
                    writeNull(fieldMeta);
                    return;
                }
                if (removeCycles){
                    auto objIdPtr = ptr in ptrToObjectId;
                    if (objIdPtr !is null) {
                        writeProxy(fieldMeta,*objIdPtr);
                        return;
                    }
                    ++lastObjectId;
                    ptrToObjectId[ptr] = cast(objectId)(lastObjectId);

                } else {
                    ++lastObjectId;
                }
                version(SerializationTrace) Stdout("pippo2e").newline;
            }
            
            static if (is(T == class) || is(T==Serializable)) {
                version(SerializationTrace) Stdout("pippo3").newline;
                assert(SerializationRegistry().getMetaInfo(t.classinfo)!is null, 
                    "No class metaInfo registered for type '"
                    ~t.classinfo.name~"'("~T.stringof~")");
                ClassMetaInfo metaInfo;
                if (fieldMeta) {
                    metaInfo=fieldMeta.metaInfo;
                    assert(metaInfo);
                    if (metaInfo.classinfo !is t.classinfo) metaInfo=null;
                }
                version(SerializationTrace) Stdout("pippo3.2").newline;
                // try first over the Serializable interface.
                // this is faster but migh fail if a subclass has an external handler
                // so this is disallowed
                Serializable sObj=cast(Serializable)t;
                if (sObj!is null){
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                    metaInfo=t.getSerializationMetaInfo();
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                    assert(metaInfo.ci is t.classinfo,"No subclass metaInfo defined for type '"
                    ~t.classinfo.name~"'("~T.stringof~")");
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                    sObj.preSerialize(this);
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                    scope(exit) sObj.postSerialize(this);
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                    writeObject(fieldMeta,metaInfo,lastObjectId,
                        { sObj.serialize(this); }, t);
                    version(SerializationTrace) Stdout("pippo3.3").newline;
                } else {
                    if (metaInfo is null){
                        version(SerializationTrace) Stdout("pippo4").newline;
                        metaInfo = SerializationRegistry().getMetaInfo(t.classinfo);
                        assert(metaInfo);
                        version(SerializationTrace) Stdout("pippo4").newline;
                    }
                    if (metaInfo.externalHandlers){
                        version(SerializationTrace) Stdout("pippo4").newline;
                        ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                        writeObject(fieldMeta,metaInfo,lastObjectId,
                            {
                                if (metaInfo.externalHandlers.preSerialize){
                                    h.preSerialize(this,metaInfo,cast(void*)t);
                                }
                                assert(h.serialize);
                                h.serialize(this,metaInfo,cast(void*)t);
                                if (metaInfo.externalHandlers.postSerialize){
                                    h.postSerialize(this,metaInfo,cast(void*)t);
                                }
                            }, t);
                        version(SerializationTrace) Stdout("pippo4").newline;
                    } else {
                        version(SerializationTrace) Stdout("pippo5").newline;
                        writeObject(fieldMeta,metaInfo,lastObjectId,
                            {
                                static if(is(typeof(T.init.preSerialize(this)))){
                                    t.preSerialize(this);
                                }
                                static assert(is(typeof(T.init.serialize(this))),"no serialization function for "
                                    ~t.classinfo.name~"'("~T.stringof~")");
                                t.serialize(this);
                                static if(is(typeof(T.init.postSerialize(this)))){
                                    t.postSerialize(this);
                                }
                            },t);
                        version(SerializationTrace) Stdout("pippo5").newline;
                    }
                }
            }
            else static if (is(T == struct)) {
                version(SerializationTrace) Stdout("pippo6").newline;
                ClassMetaInfo metaInfo;
                if (fieldMeta) {
                    metaInfo=fieldMeta.metaInfo;
                    assert(metaInfo);
                } else {
                    metaInfo = SerializationRegistry().getMetaInfo(typeid(T));
                }
                assert (metaInfo !is null, 
                    "No metaInfo registered for struct '"
                    ~typeid(T).name~"'("~T.stringof~")");
                if (metaInfo.externalHandlers){
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    writeStruct(fieldMeta,metaInfo,lastObjectId,
                        {
                            if (metaInfo.externalHandlers.preSerialize){
                                h.preSerialize(this,metaInfo,cast(void*)&t);
                            }
                            assert(h.serialize);
                            h.serialize(this,metaInfo,cast(void*)&t);
                            if (metaInfo.externalHandlers.postSerialize){
                                h.postSerialize(this,metaInfo,cast(void*)&t);
                            }
                        }, t);
                } else {
                    writeStruct(fieldMeta,metaInfo,lastObjectId,
                        {
                            static if(is(typeof(T.init.preSerialize(this)))){
                                t.preSerialize(this);
                            }
                            static assert(is(typeof(T.init.serialize(this))),"no serialization function for "
                                ~typeid(T).name~"'("~T.stringof~")");
                            t.serialize(this);
                            static if(is(typeof(T.init.postSerialize(this)))){
                                t.postSerialize(this);
                            }
                        },t);
                }
                version(SerializationTrace) Stdout("pippo6").newline;
            }
            else static if (isArrayType!(T)) {
                version(SerializationTrace) Stdout.formatln("serializing array field : {} {}", fieldMeta.name, typeid(T));
                auto ac=writeArrayStart(fieldMeta,t.length,lastObjectId);
                foreach (i,inout x; t) {
                    writeArrayEl(ac,{ this.field(cast(FieldMetaInfo*)null, x); } );
                }
                writeArrayEnd(ac);
            }
            else static if (isAssocArrayType!(T)) {
                alias KeyTypeOfAA!(T) K;
                auto ac=writeDictStart(fieldMeta,t.length,lastObjectId,
                    is(K==char[])||is(K==wchar[])||is(K==dchar[]));
                foreach (i,key, inout value; t) {
                    writeEntry(ac,{ this.field!(K)(i, null, key); },
                        { this.field(i, null, value); });
                }
                writeDictEnd(ac);
            } else static if (is(T==void delegate())) { // custom write function
                writeCustomField(fieldMeta,t);
            } else static if (isPointerType!(T)) {
                Stdout("pippo4").newline;
                if (t is null){
                    writeNull(fieldMeta);
                    return;
                }
                if (is(typeof(*T.init)==struct)||is(isArrayType!(typeof(*T.init)))||is(typeof(*T.init)==class)){
                    this.field!(typeof(*t))(fieldMeta, *t);
                } else {
                    if (recursePtr){
                        // it is not guaranteed that reading in will recover the same situation that was dumped...
                        this.field!(typeof(*t))(fieldMeta, *t);
                    } else {
                        writeDebugPtr(fieldMeta,cast(void*)t);
                    }
                }
            } else {
                /+ /// try to get meta info
                metaInfo=getSerializationInfoForType!(T)();
                if (metaInfo is null || metaInfo.externalHandlers is null){
                    throw Exception("Error: no meta info and external handlers for field of type "~T.stringof)
                } else {
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    writeStruct(fieldMeta,metaInfo,lastObjectId,
                        {
                            if (metaInfo.externalHandlers.preSerialize){
                                h.preSerialize(this,metaInfo,cast(void*)&t);
                            }
                            assert(h.serialize);
                            h.serialize(this,metaInfo,cast(void*)&t);
                            if (metaInfo.externalHandlers.postSerialize){
                                h.postSerialize(this,metaInfo,cast(void*)&t);
                            }
                        }, t);
                } +/
                pragma(msg, "Error: Unable to write field of type "~T.stringof);
                static assert (false, T.somerandompropertywhichwilltriggeranerror);
            }
        }
        version(SerializationTrace) Stdout("field!("~T.stringof~")(")(cast(void*)fieldMeta)(",")(cast(void*)&t)(") finished").newline;
    }
    /// writes something that has a custom write operation
    void writeCustomField(FieldMetaInfo *field, void delegate()writeOp){
        writeOp();
    }
    /// write a pointer (for debug purposes)
    void writeDebugPtr(FieldMetaInfo *field,void* o){
        assert(0,"unimplemented");
    }
    /// writes a null object/pointer
    void writeNull(FieldMetaInfo *field){
        assert(0,"unimplemented");
    }
    /// writes the start of an array of the given size
    PosCounter writeArrayStart(FieldMetaInfo *field, size_t length, objectId objId){
        return PosCounter(length);
    }
    /// writes a separator of the array
    void writeArrayEl(ref PosCounter ac, void delegate() writeEl) {
        ac.next();
        writeEl();
    }
    /// writes the end of the array
    void writeArrayEnd(ref PosCounter ac){
        ac.end();
    }
    /// start of a dictionary
    PosCounter writeDictStart(FieldMetaInfo *field, size_t length, objectId objId,
        bool stringKeys=false) {
        return PosCounter(length);
    }
    /// writes an entry of the dictionary
    void writeEntry(ref PosCounter ac, void delegate() writeKey,void delegate() writeVal) {
        ac.next();
        writeKey();
        writeVal();
    }
    /// end of dictionary
    void writeDictEnd(ref PosCounter ac) {
        ac.end();
    }
    /// writes an Object
    void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite, Object o){
        realWrite();
    }
    /// writes a Proxy
    void writeProxy(FieldMetaInfo *field, objectId objId){
        assert(0,"unimplemented");
    }
    /// write Struct
    void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite){
        realWrite();
    }
    /// writes a core type
    void writeCoreType(FieldMetaInfo *field,void delegate() realWrite){
        realWrite();
    }
}


class JsonSerializer : SerializerBase {
    int depth;
    Print!(char) writer;
    this(Print!(char)w){
        super(new FormattedWriteHandlers(w));
        writer=w;
    }
    /// indents the output
    void indent(int amount){
        for (int i=0;i<amount;++i)
            writer.stream.write("  ");
    }
    void writeField(FieldMetaInfo *field){
        if (field !is null){
            writer(",").newline;
            indent(depth);
            writer(field.name);
            writer(":");
        }
    }
    /// writes something that has a custom write operation
    override void writeCustomField(FieldMetaInfo *field, void delegate()writeOp){
        writeOp();
    }
    /// write a pointer (for debug purposes)
    override void writeDebugPtr(FieldMetaInfo *field,void* o){
        size_t u=cast(size_t)o;
        handlers.handle(u);
    }
    /// null object
    override void writeNull(FieldMetaInfo *field) {
        writeField(field);
        writer("null");
    }
    /// writes the start of an array of the given size
    override PosCounter writeArrayStart(FieldMetaInfo *field,size_t size, objectId objId){
        writeField(field);
        writer(`{ "class":"array", "id":`)(objId)(`, data=[`);
        if (size>6) writer.newline;
        ++depth;
        return PosCounter(size);
    }
    /// writes a separator of the array
    override void writeArrayEl(ref PosCounter ac, void delegate() writeEl) {
        if (ac.pos>0){
            writer(", ");
            if (ac.pos % 6 ==0) {  /// wrap lines
                writer.newline;
                indent(depth);
            }
        }
        ac.next();
        writeEl();
        
    }
    /// writes the end of the array
    override void writeArrayEnd(ref PosCounter ac) {
        ac.end();
        writer("]}");
        --depth;
    }
    /// start of a dictionary
    override PosCounter writeDictStart(FieldMetaInfo *field,size_t length, objectId objId, bool stringKeys=false) {
        writeField(field);
        if (stringKeys)
            writer(`{ "class":"dict"`);
        else
            writer(`{ "class":"associativeArray"`);
        writer(", \"id\":")(objId);
        auto res=PosCounter(length);
        res.data=Variant(stringKeys);
        ++depth;
        return res;
    }
    /// writes an entry of the dictionary
    override void writeEntry(ref PosCounter ac, void delegate() writeKey,void delegate() writeVal) {
        writer(",\n");
        ac.next();
        indent(depth);
        ++depth;
        if (ac.data.get!(bool)){
            writeKey();
            writer(":");
            writeVal();
        } else {
            writer(`{"key":`);
            writeKey();
            writer(",\n");
            indent(depth-1);
            writer(` "val":`);
            writeVal();
            writer(`}`);
        }
        --depth;
    }
    /// end of dictionary
    override void writeDictEnd(ref PosCounter ac) {
        ac.end();
        writer(`}`);
        --depth;
    }
    /// writes an Object
    override void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite, Object o){
        writeField(field);
        assert(metaInfo!is null);
        writer(`{ "class":"`)(metaInfo.className)(`"`);
        writer(`, "id":`)(objId);
        ++depth;
        realWrite();
        --depth;
        writer(`}`);
    }
    /// write ObjectProxy
    override void writeProxy(FieldMetaInfo *field, objectId objId){
        writeField(field);
        writer(`{ "class":"proxy"`);
        writer(`, "id":`)(objId)(" }");
    }
    /// write Struct
    override void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite){
        writeField(field);
        assert(metaInfo!is null);
        writer(`{ "class":"`)(metaInfo.className)(`"`);
        writer(`, "id":`)(objId);
        ++depth;
        realWrite();
        --depth;
        writer(" }");
    }
    /// writes a core type
    override void writeCoreType(FieldMetaInfo *field, void delegate() realWrite){
        writeField(field);
        realWrite();
    }

    override void writeEndRoot() {
        writer.newline;
    }

}

struct NewSerializationExpose {
	template handler(int i : 0) {
		mixin NewSerializationExpose_mix0;
	}

	template handler(int i : 1) {
		mixin NewSerializationExpose_mix1;
	}
	
	mixin HandlerStructMix;
}
