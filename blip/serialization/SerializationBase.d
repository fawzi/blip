/// serialization support
/// built borrowing heavily from xpose binary serialization by h3r3tic, but adding protocol
/// like support (inspired by Kris tango Reader/Writer), and support for json and xml like
/// serializations.
/// The serialization can remove cycles. Support for serialization can be added either by hand
/// or via xpose
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
module blip.serialization.SerializationBase;
import blip.serialization.Handlers;
import tango.core.Tuple;
import blip.core.Variant;
import blip.io.Console;
import blip.io.BasicIO;
import blip.BasicModels;
import tango.util.container.HashSet;
import tango.text.Util;
import blip.util.TemplateFu;
import tango.text.Regex;
import blip.container.GrowableArray;
import blip.util.Grow;
public import blip.core.Traits;

version(SerializationTrace){
    version=STrace;
} else version(UnserializationTrace){
    version=STrace;
} else version(SRegistryTrace){
    version=STrace;
}

/// basic exception for serialization errors
class SerializationException: Exception{
    char[] pos;
    this(char[]msg,char[] pos,char[]file,long line,Exception next=null){
        super(msg,file,line,next);
        this.pos=pos;
    }
    void writeOutMsg(void delegate(char[]s)sink){
        sink(msg);
        if (pos.length){
            sink(" parsing ");
            sink(pos);
        }
    }
}

// version PseudoFieldMetaInfo generates fields for arrays and associative arrays,
// speeding up the getting of meta info if the elements are not subclasses, but seems to
// give a compiler error when raising exceptions with gdc (the unwinding mechanism fails)
// version=PseudoFieldMetaInfo

/// serialization level (if a field has to be serialized or not)
enum SerializationLevel{
    normalLevel=0,
    debugLevel=10,
    never=20
}
/// meta informations for fields
struct FieldMetaInfo {
    bool pseudo; /// if true this is a pseudo field of array or dictionary
    char[] name; /// name of the propety
    ClassMetaInfo metaInfo; /// expected meta info (used if not class)
    SerializationLevel serializationLevel; /// when to serialize
    char[] doc; /// documentation of the field
    /// creates a field meta info (normally one uses ClassMetaInfo.addFieldOfType)
    static FieldMetaInfo opCall(char[] name,char[] doc,ClassMetaInfo metaInfo,
        SerializationLevel l=SerializationLevel.normalLevel)
    {
        FieldMetaInfo res;
        res.name = name;
        res.metaInfo=metaInfo;
        res.doc=doc;
        res.serializationLevel=l;
        res.pseudo=false;
        return res;
    }
    /// describes a field meta info
    void desc(void delegate(char[]) s){
        s("<FieldMetaInfo name:'"); s(name); s("',");
        s("level:"); writeOut(s,serializationLevel); s(",");
        s("metaInfo:"); s((metaInfo is null) ? "*NULL*"[] : metaInfo.className); s(">");
    }
    char[][]citationKeys(){
        char[][] res=[];
        foreach(m; Regex(r"\[[a-zA-Z]\w*\]").search(doc))
            res~=m.match(0);
        return res;
    }
}
/// returns the typeid of the given type
template typeKindForType(T){
    static if(isCoreType!(T)){
        const typeKindForType=TypeKind.PrimitiveK;
    } else static if(is(T==class)){
        const typeKindForType=TypeKind.ClassK;
    } else static if(is(T:T[])){
        const typeKindForType=TypeKind.ArrayK;
    } else static if(isAssocArrayType!(T)){
        static if (is(KeyTypeOfAA!(T)==char[])||is(KeyTypeOfAA!(T)==wchar[])||is(KeyTypeOfAA!(T)==dchar[])){
            const typeKindForType=TypeKind.DictK;
        } else {
            const typeKindForType=TypeKind.AAK;
        }
    } else static if(is(T==struct)){
        const typeKindForType=TypeKind.StructK;
    } else static if (is(typeof(*T.init))){
        const typeKindForType=typeKindForType!(typeof(*T.init));
    } else {
        const typeKindForType=TypeKind.UndefK;
    }
}

enum TypeKind{
    PrimitiveK,
    ClassK,
    ArrayK,
    DictK,
    AAK,
    StructK,
    CustomK,
    ArrayElK,
    AAKeyK,
    AAValK,
    VoidPtr,
    UndefK
}

struct ExternalSerializationHandlers{
    void function (Serializer s,ClassMetaInfo mInfo,void* o) preSerialize;
    void function (Serializer s,ClassMetaInfo mInfo,void* o) serialize;
    void function (Serializer s,ClassMetaInfo mInfo,void* o) postSerialize;
    void* function (Unserializer s,ClassMetaInfo mInfo,void* o) preUnserialize;
    void  function (Unserializer s,ClassMetaInfo mInfo,void* o) unserialize;
    void* function (Unserializer s,ClassMetaInfo mInfo,void* o) postUnserialize;
}

/// meta informations for a class
class ClassMetaInfo {
    char[] className;
    ClassMetaInfo superMeta;
    FieldMetaInfo[] fields;
    TypeKind kind;
    TypeInfo ti;
    ClassInfo ci;
    void* function (ClassMetaInfo mInfo) allocEl;
    ExternalSerializationHandlers * externalHandlers;
    /// return the field with the given local index
    FieldMetaInfo *opIndex(int i){
        if (i>=0 && i<fields.length){
            return &(fields[i]);
        } else {
            return null;
        }
    }
    /// returns the field with the given name
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
    /// adds a field to the meta info
    void addField(FieldMetaInfo f){
        assert(fieldNamed(f.name) is null,"field names have to be unique");
        fields~=f;
    }
    /// adds a field with given name and type
    void addFieldOfType(T)(char[] name,char[] doc,
        SerializationLevel sLevel=SerializationLevel.normalLevel){
        addField(FieldMetaInfo(name,doc,getSerializationInfoForType!(T)(),sLevel));
    }
    /// constructor (normally use createForType)
    this(char[] className,ClassMetaInfo superMeta,TypeInfo ti,ClassInfo ci,TypeKind kind,void* function(ClassMetaInfo)allocEl){
        this.className=className;
        this.superMeta=superMeta;
        this.ti=ti;
        this.ci=ci;
        this.kind=kind;
        this.allocEl=allocEl;
    }
    /// creates a new meta info for the given type and registers it
    /// if no name is given, T.mangleof is used.
    /// normally this is the best way to create a new MetaInfo
    static ClassMetaInfo createForType(T)(char[]name="",
        void *function(ClassMetaInfo) allocEl=cast(void *function(ClassMetaInfo))null){
        static if(is(T==class)){
            ClassInfo newCi=T.classinfo;
            if (name.length==0){
                name=newCi.name; // should be nicer, but has it issues with templates???
            }
            ClassMetaInfo newSuperMeta=null;
            static if(is(T U==super)){
                foreach(S;U){
                    static if (is(S == class)){
                        newSuperMeta=getSerializationInfoForType!(S)();
                    }
                }
            }
        } else {
            ClassMetaInfo newSuperMeta=null;
            ClassInfo newCi=null;
        }
        TypeInfo newTi=typeid(T);
        if (name.length==0){
            name=T.mangleof;
        }
        static if (is(T==class)) { // do for all types? increases size...
            static if (is(typeof(new T()))){
                if (allocEl is null) {
                    allocEl=function void*(ClassMetaInfo mI){
                        return cast(void*)(new T);
                    };
                }
            } else {
                assert(allocEl !is null,"cannot allocate automatically, and no allocator given for "~T.stringof~" name:"~name);
            }
        }
        auto res=new ClassMetaInfo(name,newSuperMeta,newTi,newCi,typeKindForType!(T),allocEl);
        SerializationRegistry().register!(T)(res);
        return res;
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
    /// description (for debugging purposes)
    void desc(void delegate(char[]) sink){
        auto s=dumper(sink);
        s("<ClassMetaInfo@"); writeOut(sink,cast(void*)this); s("\n");
        s(" className:'")(className)("',\n");
        s(" kind:")(kind)(",\n");
        s(" superMeta:")(superMeta is null ? "*NULL*" : superMeta.className)("\n");
        s(" ti:")(ti is null ? "*NULL*" : ti.toString)("@")(cast(void*)ti)("\n");
        s(" ci:")(ci is null ? "*NULL*" : ci.toString)("@")(cast(void*)ci)("\n");
        s(" allocEl:")(allocEl is null ? "*NULL*" : "*ASSOCIATED*")("@")(cast(void*)allocEl)("\n");
        foreach(field;fields){
            writeOut(sink,field);
            sink("\n");
        }
        s(">\n");
    }
    int opApply(int delegate(ref FieldMetaInfo *) loopBody){
        if (superMeta){
            if (auto r=superMeta.opApply(loopBody)) return r;
        }
        FieldMetaInfo *f=fields.ptr;
        for(size_t i=fields.length;i!=0;--i){
            if (auto r=loopBody(f)) return r;
            ++f;
        }
        return 0;
    }
}

/// interface of the objetcs that can be serialized
interface Serializable{
    ClassMetaInfo getSerializationMetaInfo();
    // the actual serialization function;
    void serialize(Serializer s);
    /// pre serializer hook, useful to (for example) lock the structure and guarantee a consistent snapshot
    void preSerialize(Serializer s);
    /// post serializer hook, useful to (for example) unlock the structure
    /// guaranteed to be called if preSerialize ended sucessfully
    void postSerialize(Serializer s);
    /// pre unserialization hook
    /// might substitute the object with a proxy used for the unserialization and acquire locks
    Serializable preUnserialize(Unserializer s);
    /// unserialize an object
    void unserialize(Unserializer s);
    /// post unserialization hook 
    /// if a proxy was used it needs to reestablish the correct  object type and release any
    /// lock acquired by preUnserialize
    Serializable postUnserialize(Unserializer s);
}

/// returns the meta info for the given type
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
    } else static if (is(T==void*)){
        return voidPtrMetaInfo;
    } else static if (is(typeof(*T))){
        return getSerializationInfoForType!(typeof(*T))();
    } else {
        auto res=SerializationRegistry().getMetaInfo(typeid(T));
        static if (is(T U==typedef)){
            if (res is null){
                return getSerializationInfoForType!(U)();
            }
        }
        static if (is(T U==enum)){
            if (res is null){
                return getSerializationInfoForType!(U)();
            }
        }
        return res;
    }
}
/// returns the serialization for the given variable
ClassMetaInfo getSerializationInfoForVar(T)(T t){
    static if (is(T==class)){
        return SerializationRegistry().getMetaInfo(t.classinfo);
    } else static if (is(T==struct)){
        return SerializationRegistry().getMetaInfo(typeid(T));
    } else static if (is(T==Serializable)){
        return t.getSerializationMetaInfo();
    } else static if (is(T==interface)){
        return SerializationRegistry().getMetaInfo((cast(Object)t).classinfo);
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
        // return SerializationRegistry().getMetaInfo(typeid(T));
        static assert(0,"unsupported type "~T.stringof); 
    }
}

// various metaInfo (for completeness, not really needed)
ClassMetaInfo arrayMetaInfo;
ClassMetaInfo aaMetaInfo;
ClassMetaInfo dictMetaInfo;
ClassMetaInfo voidPtrMetaInfo;
static this(){
    arrayMetaInfo=new ClassMetaInfo("array",null,null,null,TypeKind.ArrayK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each array type?
    aaMetaInfo=new ClassMetaInfo("aa",null,null,null,TypeKind.AAK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each aa type?
    dictMetaInfo=new ClassMetaInfo("dict",null,null,null,TypeKind.DictK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each dict type?
    voidPtrMetaInfo=new ClassMetaInfo("voidPtr",null,null,null,TypeKind.VoidPtr,
        cast(void* function(ClassMetaInfo))null);
    SerializationRegistry().register!(int[])(arrayMetaInfo);
    SerializationRegistry().register!(int[int])(aaMetaInfo);
    SerializationRegistry().register!(int[char[]])(dictMetaInfo);
    SerializationRegistry().register!(void*)(voidPtrMetaInfo);
}

char[] coreTypesMetaInfoMixStr(){
    char[] res="".dup;
    foreach(T;CoreTypes){
        res~="ClassMetaInfo "~strForCoreType!(T)~"MetaInfo;\n";
    }
    res~="static this(){\n";
    foreach(T;CoreTypes){
        res~=strForCoreType!(T)~"MetaInfo=new ClassMetaInfo(\""~T.stringof~"\",null,typeid("~T.stringof~"),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);\n";
        res~="SerializationRegistry().register!("~T.stringof~")("~strForCoreType!(T)~"MetaInfo);\n";
    }
    res~="}\n";
    return res;
}

mixin(coreTypesMetaInfoMixStr());

/// struct that helps the reading of an array and dictionaries
struct PosCounter{
    ulong pos,length;
    Variant data;
    static PosCounter opCall(ulong length){
        PosCounter ac;
        ac.length=length;
        ac.pos=0;
        return ac;
    }
    void next(){
        assert(pos<length || length==ulong.max);
        ++pos;
    }
    void end(){
        assert(pos==length || length==ulong.max);
        length=pos;
    }
    bool atEnd(){
        assert(length!=ulong.max,"asked atEnd with undefined length");
        return pos<length;
    }
    ulong sizeHint(){
        if (length==ulong.max){
            return 0; // change?
        } else {
            return length;
        }
    }
}

class SerializationRegistry {
    ClassMetaInfo[Object] type2metaInfos;
    ClassMetaInfo[char[]] name2metaInfos;

    Object keyOf(T)() {
        static if (is(T == class)) {
            return T.classinfo;
        } else static if (is(T==void*)){
            return voidPtrMetaInfo;
        } else {
            return typeid(T);
        }
    }
    
    
    void register(T)(ClassMetaInfo metaInfo) {
        assert(metaInfo!is null,"attempt to register null metaInfo");
        version(STrace) {
            sout(collectAppender(delegate(CharSink s){
                s("Registering "); s(metaInfo.className);
                s(" in the serialization factory "~keyOf!(T).toString~" ("~T.stringof~")");
            }));
        }
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

    ClassMetaInfo getMetaInfo(char[] name) {
        synchronized(this){
            auto ptr = name in name2metaInfos;
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

/// serializer
/// some methods have no classinfo for performance reasons, if you really need it file a ticket explaining why 
class Serializer {
    typedef size_t classId;
    typedef size_t objectId;
    WriteHandlers handlers;
    void delegate(Serializer) rootObjStartCallback;
    void delegate(Serializer) rootObjEndCallback;
    void delegate(Serializer) serializerCloseCallback;
    
    objectId[void*]             ptrToObjectId;
    objectId                    lastObjectId;
    Variant[char[]]             context;
    SerializationLevel serializationLevel;
    bool removeCycles;
    bool structHasId;
    bool recursePtr;
    /// if default values can be dropped (or all elements have to be serialized in any case)
    bool canDropDefaults(){
        return !handlers.binary();
    }
    enum AutoReset:int {
        None,
        ResetCache,
        ResetCounters,
    }
    AutoReset autoReset;

    this(WriteHandlers h=null) {
        ptrToObjectId[null] = cast(objectId)0;
        lastObjectId=cast(objectId)1;
        handlers=h;
        removeCycles=true;
        structHasId=false;
        recursePtr=false;
        autoReset=AutoReset.ResetCache;
    }
    /// resets the cache used to remove cycles (but not the counter)
    void resetObjCache(){
        ptrToObjectId=null;
        ptrToObjectId[null] = cast(objectId)0;
    }
    /// resets objectId counter (and the mapping pointer->objectId) used to remove cycles
    void resetObjIdCounter(){
        ptrToObjectId=null;
        ptrToObjectId[null] = cast(objectId)0;
        lastObjectId=cast(objectId)1;
    }
    /// closes the serializer, after this it one could recyle the serializer
    void close(){
        if (serializerCloseCallback){
            serializerCloseCallback(this);
        }
    }
    /// flushes the underlying stream
    void flush(){
        handlers.flush();
    }
    /// writes the given root object
    /// if it is a pointer (and not void*) then it is indirected once before feeding it on
    /// (to handle this in structs better)
    /// you should only use the field method to write in the serialization methods
    typeof(this) opCall(T)(T o) {
        if (rootObjStartCallback){
            rootObjStartCallback(this);
        }
        writeStartRoot();
        static if(isStaticArrayType!(T)){
            auto arr=o[];
            field!(typeof(arr))(cast(FieldMetaInfo *)null,arr);
        } else static if(is(typeof(*o)) && is(T==typeof(*o)*)){
            field!(typeof(*o))(cast(FieldMetaInfo *)null,*o);
        } else {
            field!(T)(cast(FieldMetaInfo *)null,o);
        }
        writeEndRoot();
        if (rootObjEndCallback){
            rootObjEndCallback(this);
        }
        switch(autoReset){
            case AutoReset.None:
            break;
            case AutoReset.ResetCache:
            resetObjCache();
            break;
            case AutoReset.ResetCounters:
            resetObjIdCounter();
            break;
            default:
                throw new Exception("unknown AutoReset value",__FILE__,__LINE__);
        }
        return this;
    }
    
    /// writes out a string identifying the protocol version
    void writeProtocolVersion() { }
    void writeStartRoot() { }
    void writeEndRoot() { }
    
    /// removes the object from the register of known objects (that is used to remove loops)
    void unregisterObject(Object o){
        ptrToObjectId.remove(cast(void*)o);
    }
    /// allows the serilizer to treat some instances specially
    /// if it returns true then it is assumed that ptr was serialized
    bool specialInstance(void *ptr){
        return false;
    }
    /// writes out a custom field
    final void customField(FieldMetaInfo *fieldMeta, void delegate() realWrite){
        version(SerializationTrace) {
            sout(collectAppender(delegate(CharSink s){
                s("X customField("); s(fieldMeta is null?"*NULL*":fieldMeta.name); s(") starting\n");
            }));
            scope(exit) {
                sout(collectAppender(delegate(CharSink s){
                    s("X customField("); s(fieldMeta is null?"*NULL*":fieldMeta.name); s(") finished\n");
                }));
            }
        }
        if (fieldMeta !is null && fieldMeta.serializationLevel>serializationLevel) return;
        writeCustomField(fieldMeta,realWrite);
    }
    /// writes out a field of type t
    void field(T)(FieldMetaInfo *fieldMeta, ref T t) {
        version(SerializationTrace) {
            sout(collectAppender(delegate void(CharSink s){
                s("X field!("~T.stringof~")(");
                s(fieldMeta is null?"*NULL*":fieldMeta.name);
                s(","); writeOut(s,cast(void*)&t); s(") starting\n");
            }));
            scope(exit) {
                sout(collectAppender(delegate void(CharSink s){
                    s("X field!("~T.stringof~")(");
                    s(fieldMeta is null?"*NULL*":fieldMeta.name);
                    s(","); writeOut(s,cast(void*)&t); s(") finished\n");
                }));
            }
        }
        if (fieldMeta !is null && fieldMeta.serializationLevel>serializationLevel) return;
        static if (isCoreType!(T)){
            version(SerializationTrace) sout("X coreType\n");
            writeCoreType(fieldMeta, { handlers.handle(t); },&t);
        } else static if (is(T == interface) && !is(T==Serializable)) {
            static assert(is(T:Serializable),"serializing an interface "~T.stringof~" non derived from Serializable");
            version(SerializationTrace) sout("X interface->"~T.stringof~"(Serializable)\n");
            auto o=cast(Serializable)t;
            field!(Serializable)(fieldMeta,o);
        } else {
            static if(is(T==class)||is(T==Serializable)||(isPointerType!(T) && is(typeof(*T.init)==struct))){
                version(SerializationTrace) sout("X check if already serialized\n");
                // check for cycles
                static if(is(T==class)||is(T==Serializable)) {
                    void* ptr=cast(void *)cast(Object)t;
                } else static if (isPointerType!(T)) {
                    void* ptr=cast(void*)t;
                    structHasId=true;
                } else {
                    static assert(0);
                }
                if (ptr is null){
                    writeNull(fieldMeta);
                    return;
                }
                if (specialInstance(ptr)) return;
                if (removeCycles && (fieldMeta is null || fieldMeta.metaInfo is null
                    || fieldMeta.metaInfo.kind != TypeKind.CustomK)){
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
                version(SerializationTrace) sout("X non serialized object\n");
            }
            static if (is(T == class) || is(T==Serializable)) {
                version(SerializationTrace) sout("X serializing class\n");
                assert(SerializationRegistry().getMetaInfo(t.classinfo)!is null, 
                    "No class metaInfo registered for type '"
                    ~t.classinfo.name~"'("~T.stringof~")");
                ClassMetaInfo metaInfo;
                if (fieldMeta!is null && fieldMeta.metaInfo!is null) {
                    metaInfo=fieldMeta.metaInfo;
                    if (metaInfo.classinfo != t.classinfo) metaInfo=null;
                }
                // try first over the Serializable interface.
                // this is faster but migh fail if a subclass has an external handler
                // so this is disallowed
                Serializable sObj=cast(Serializable)t;
                if (sObj!is null){
                    version(SerializationTrace) sout("X using serializable interface\n");
                    metaInfo=sObj.getSerializationMetaInfo();
                    if (metaInfo.ci != t.classinfo){
                        version(SerializationTrace) {
                            sout(collectAppender(delegate void(CharSink s){
                                s("X metaInfo:");
                                writeOut(s,metaInfo);
                                s("\n");
                            }));
                            sout(collectAppender(delegate void(CharSink s){
                                s("t.classinfo:"); s(t.classinfo.name); s("@");
                                writeOut(s,cast(void*)t.classinfo);
                                s("\n");
                            }));
                        }
                        assert(0,"No subclass metaInfo defined for type '"
                            ~t.classinfo.name~"'("~T.stringof~")");
                    }
                    void realWrite1(){
                        sObj.preSerialize(this);
                        scope(exit) sObj.postSerialize(this);
                        sObj.serialize(this);
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(SerializationTrace) sout("X serializing as custom field\n");
                        assert(T.classinfo is t.classinfo,"subclasses not supported for custom writers");
                        writeCustomField(fieldMeta,&realWrite1);
                    } else {
                        static if(is(T==Serializable)){
                            writeObject(fieldMeta,metaInfo,lastObjectId,
                                true, &realWrite1, cast(Object)t); // try to handle IUnknown interfaces?
                        } else {
                            writeObject(fieldMeta,metaInfo,lastObjectId,
                                T.classinfo !is t.classinfo, &realWrite1, t);
                        }
                    }
                } else {
                    if (metaInfo is null){
                        metaInfo = SerializationRegistry().getMetaInfo(t.classinfo);
                        assert(metaInfo!is null);
                    }
                    if (metaInfo.externalHandlers){
                        version(SerializationTrace) sout("X using external handlers\n");
                        ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                        void realWrite2(){
                            if (h.preSerialize){
                                h.preSerialize(this,metaInfo,cast(void*)t);
                            }
                            scope(exit){
                                if (h.postSerialize){
                                    h.postSerialize(this,metaInfo,cast(void*)t);
                                }
                            }
                            assert(h.serialize);
                            h.serialize(this,metaInfo,cast(void*)t);
                        }
                        if (metaInfo.kind==TypeKind.CustomK){
                            version(SerializationTrace) sout("X serializing as custom field\n");
                            assert(T.classinfo is t.classinfo,"subclasses not supported for custom writers");
                            writeCustomField(fieldMeta,&realWrite2);
                        } else {
                            static if(is(T==Serializable)){
                                writeObject(fieldMeta,metaInfo,lastObjectId,
                                    true, &realWrite2, cast(Object)t); // try to handle IUnknown interfaces?
                            } else {
                                writeObject(fieldMeta,metaInfo,lastObjectId,T.classinfo !is t.classinfo, 
                                    &realWrite2, t);
                            }
                        }
                    } else {
                        version(SerializationTrace) sout("X using serialize methods\n");
                        static if(is(typeof(T.init.serialize(this)))){
                            void realWrite3(){
                                static if(is(typeof(T.init.preSerialize(this)))){
                                    t.preSerialize(this);
                                }
                                scope(exit){
                                    static if(is(typeof(T.init.postSerialize(this)))){
                                        t.postSerialize(this);
                                    }
                                }
                                t.serialize(this);
                            }
                            if (metaInfo.kind==TypeKind.CustomK){
                                version(SerializationTrace) sout("X serializing as custom field\n");
                                assert(T.classinfo is t.classinfo,"subclasses not supported for custom writers");
                                writeCustomField(fieldMeta,&realWrite3);
                            } else {
                                static if(is(T==Serializable)){
                                    writeObject(fieldMeta,metaInfo,lastObjectId,
                                        true, &realWrite3, cast(Object)t); // try to handle IUnknown  interfaces?
                                } else {
                                    writeObject(fieldMeta,metaInfo,lastObjectId,T.classinfo !is t.classinfo, 
                                        &realWrite3,t);
                                }
                            }
                        } else {
                            assert(0,"no serialization function for "
                                ~t.classinfo.name~"'("~T.stringof~")");
                        }
                    }
                }
            }
            else static if (is(T == struct)) {
                version(SerializationTrace) sout("X serializing struct\n");
                objectId objId=cast(objectId)0;
                if (structHasId){
                    version(SerializationTrace) sout("struct has id\n");
                    objId=lastObjectId;
                    structHasId=false;
                }
                ClassMetaInfo metaInfo;
                if (fieldMeta !is null && fieldMeta.metaInfo!is null) {
                    metaInfo=fieldMeta.metaInfo;
                } else {
                    metaInfo = SerializationRegistry().getMetaInfo(typeid(T));
                }
                assert (metaInfo !is null, 
                    "No metaInfo registered for struct '"
                    ~typeid(T).toString~"'("~T.stringof~")");
                if (metaInfo.externalHandlers){
                    version(SerializationTrace) sout("X using external handlers\n");
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    void realWrite4(){
                        if (metaInfo.externalHandlers.preSerialize){
                            h.preSerialize(this,metaInfo,cast(void*)&t);
                        }
                        assert(h.serialize!is null,"missing serialization callback in externalHandlers of "~T.stringof);
                        h.serialize(this,metaInfo,cast(void*)&t);
                        if (metaInfo.externalHandlers.postSerialize){
                            h.postSerialize(this,metaInfo,cast(void*)&t);
                        }
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(SerializationTrace) sout("X serializing as custom field\n");
                        writeCustomField(fieldMeta,&realWrite4);
                    } else {
                        writeStruct(fieldMeta,metaInfo,objId,
                            &realWrite4, &t);
                    }
                } else {
                    version(SerializationTrace) sout("X using serialize methods\n");
                    static if(is(typeof(t.serialize(this)))){
                        void realWrite5(){
                            static if(is(typeof(t.preSerialize(this)))){
                                t.preSerialize(this);
                            }
                            t.serialize(this);
                            static if(is(typeof(t.postSerialize(this)))){
                                t.postSerialize(this);
                            }
                        }
                        if (metaInfo.kind==TypeKind.CustomK){
                            version(SerializationTrace) sout("X serializing as custom field\n");
                            writeCustomField(fieldMeta,&realWrite5);
                        } else {
                            writeStruct(fieldMeta,metaInfo,objId,
                                &realWrite5,&t);
                        }
                    } else {
                        assert(0,"no serialization function for "
                            ~typeid(T).toString~"'("~T.stringof~")");
                    }
                }
            }
            else static if (isArrayType!(T)) {
                version(SerializationTrace) sout("X serializing array\n");
                FieldMetaInfo *elMetaInfoP=null;
                version(PseudoFieldMetaInfo){
                    FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                        getSerializationInfoForType!(ElementTypeOfArray!(T))());
                    elMetaInfo.pseudo=true;
                    elMetaInfoP=&elMetaInfo;
                }
                auto ac=writeArrayStart(fieldMeta,t.length);
                foreach (ref x; t) {
                    version(SerializationTrace) sout("X serializing array element\n");
                    writeArrayEl(ac,{ this.field(elMetaInfoP, x); } );
                }
                writeArrayEnd(ac);
            }
            else static if (isAssocArrayType!(T)) {
                version(SerializationTrace) sout("X serializing associative array\n");
                alias KeyTypeOfAA!(T) K;
                alias ValTypeOfAA!(T) V;
                version(PseudoFieldMetaInfo){
                    FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
                    keyMetaInfo.pseudo=true;
                    FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
                    valMetaInfo.pseudo=true;
                }
                auto ac=writeDictStart(fieldMeta,t.length,
                    is(K==char[])||is(K==wchar[])||is(K==dchar[]));
                foreach (key, inout value; t) {
                    version(SerializationTrace) sout("X serializing associative array entry\n");
                    version(PseudoFieldMetaInfo){
                        writeEntry(ac,{ this.field!(K)(&keyMetaInfo, key); },
                            { this.field(&valMetaInfo, value); });
                    } else {
                        writeEntry(ac,{ this.field!(K)(cast(FieldMetaInfo*)null, key); },
                            { this.field(cast(FieldMetaInfo*)null, value); });
                    }
                }
                writeDictEnd(ac);
            } else static if (isPointerType!(T)) {
                version(SerializationTrace) sout("X serializing pointer\n");
                if (t is null){
                    writeNull(fieldMeta);
                    return;
                }
                static if (is(typeof(*t)==struct)||is(isArrayType!(typeof(*t)))||is(typeof(*t)==class)){
                    this.field!(typeof(*t))(fieldMeta, *t);
                } else {
                    static if (is(typeof(*t))){
                        if (recursePtr){
                            // it is not guaranteed that reading in will recover the same situation that was dumped...
                            version(SerializationTrace) sout("X recursing pointer\n");
                            this.field!(typeof(*t))(fieldMeta, *t);
                        } else {
                            version(SerializationTrace) sout("X debug pointer\n");
                            writeDebugPtr(fieldMeta,cast(void*)t);
                        }
                    } else {
                        version(SerializationTrace) sout("X debug pointer\n");
                        writeDebugPtr(fieldMeta,cast(void*)t);
                    }
                }
            } else static if (is(T==OutWriter)) {
                writeOutWriter(fieldMeta,t);
            } else static if (is(T==BinWriter)) {
                writeBinWriter(fieldMeta,t);
            } else {
                /// try to get meta info
                auto metaInfo=getSerializationInfoForType!(T)();
                if (metaInfo is null){
                    serializationError("Error: no meta info and external handlers for field of type "~T.stringof,__FILE__,__LINE__);
                } else if (metaInfo.externalHandlers is null){
                    // this might be a typedef/enum
                    static if (is(T U==typedef)){
                        version(SerializationTrace) sout("X recursing typedef "~T.stringof~"\n");
                        field!(U)(fieldMeta,*cast(U*)&t);
                    } else static if (is(T U==enum)){
                        version(SerializationTrace) sout("X recursing enum "~T.stringof~"\n");
                        field!(U)(fieldMeta,*cast(U*)&t);
                    } else {
                        serializationError("Error: no meta info and external handlers for field of type "~T.stringof,__FILE__,__LINE__);
                    }
                } else {
                    version(SerializationTrace) sout("X using external handlers\n");
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    void realWrite6(){
                        if (h.preSerialize){
                            h.preSerialize(this,metaInfo,cast(void*)&t);
                        }
                        assert(h.serialize);
                        h.serialize(this,metaInfo,cast(void*)&t);
                        if (h.postSerialize){
                            h.postSerialize(this,metaInfo,cast(void*)&t);
                        }
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(SerializationTrace) sout("X serializing as custom field\n");
                        writeCustomField(fieldMeta,&realWrite6);
                    } else {
                        writeStruct(fieldMeta,metaInfo,cast(objectId)0,
                            &realWrite6, &t);
                    }
                }
            }
        }
    }
    /// writes a curstom text writer
    void writeOutWriter(FieldMetaInfo *field, OutWriter w){
        handlers.handle(w);
    }
    /// writes a curstom binary writer
    void writeBinWriter(FieldMetaInfo *field, BinWriter w){
        handlers.handle(w);
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
    PosCounter writeArrayStart(FieldMetaInfo *field, ulong l){
        return PosCounter(l);
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
    PosCounter writeDictStart(FieldMetaInfo *field, ulong l, 
        bool stringKeys=false) {
        return PosCounter(l);
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
        bool isSubclass, void delegate() realWrite, Object o){
        realWrite();
    }
    /// writes a Proxy
    void writeProxy(FieldMetaInfo *field, objectId objId){
        assert(0,"unimplemented");
    }
    /// write Struct
    void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite,void *t){
        realWrite();
    }
    /// writes a core type
    void writeCoreType(FieldMetaInfo *field,void delegate() realWrite, void *t){
        realWrite();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    void serializationError(char[]msg,char[]filename,long line,Exception e=null){
        throw new SerializationException(msg,"",filename,line,e);
    }
}

/// unserializer
/// some methods have no classinfo for performance reasons, if you really need it file a ticket explaining why 
class Unserializer {
    typedef size_t classId;
    typedef size_t objectId;
    ReadHandlers handlers;

    void*[objectId]             objectIdToPtr;
    objectId                    lastObjectId;
    Variant[char[]]             context;
    SerializationLevel serializationLevel;
    bool recoverCycles=true;
    bool readStructProxy;
    bool recursePtr=false;
    void delegate(Unserializer) rootObjStartCallback;
    void delegate(Unserializer) rootObjEndCallback;
    void delegate(Unserializer) unserializerCloseCallback;
    
    struct StackEntry{
        TypeKind kind;
        char[] labelToRead;
        int iFieldRead;
        ClassMetaInfo metaInfo;
        HashSet!(char[]) missingLabels;
        Variant value;
        static StackEntry opCall(TypeKind k,Variant value,ClassMetaInfo metaInfo){
            StackEntry res;
            res.kind=k;
            res.value=value;
            res.metaInfo=metaInfo;
            res.iFieldRead=0;
            return res;
        }
        void setMissingLabels(FieldMetaInfo *mismatchCheck=null){
            missingLabels=new HashSet!(char[])();
            int i=0;
            --iFieldRead;
            foreach(f;metaInfo){
                if (i>iFieldRead){
                    missingLabels.add(f.name);
                } else if (i==iFieldRead){
                    missingLabels.add(f.name);
                    assert(mismatchCheck is null || mismatchCheck is f,"field mismatch check failure");
                }
                ++i;
            }
        }
    }
    StackEntry[] stack;
    int nStack;
    
    int push(T)(T el,ClassMetaInfo metaInfo){
        if (nStack==stack.length){
            stack.length=stack.length+stack.length/2+5;
        }
        stack[nStack]=StackEntry(typeKindForType!(T),Variant(el),metaInfo);
        ++nStack;
        return nStack;
    }
    
    bool canDropDefaults(){
        return false;
    }
    
    T pop(T)(int handle){
        assert(nStack==handle && nStack>0);
        --nStack;
        T res=stack[nStack].value.get!(T)();
        stack[nStack].value=Variant(null);
        return res;
    }

    void voidPop(int handle){
        assert(nStack==handle && nStack>0);
        --nStack;
        stack[nStack].value=Variant(null);
    }
    
    StackEntry *top(){
        assert(nStack>0);
        return &(stack[nStack-1]);
    }
    
    this(ReadHandlers h=null) {
        objectIdToPtr[cast(objectId)0] = null;
        lastObjectId=cast(objectId)1;
        handlers=h;
        recoverCycles=true;
        readStructProxy=false;
    }
    /// resets objectId counter (and the mapping objectId->pointer) used to recover cycles
    void resetObjIdCounter(){
        objectIdToPtr=null;
        objectIdToPtr[cast(objectId)0] = null;
        lastObjectId=cast(objectId)1;
    }
    
    /// reads the string identifying the protocol version, returns true if the present
    /// unserializer handles the protocol, false if it can't or it did not recognize
    /// the version string
    bool readProtocolVersion() { return false; }

    /// writes the given root object
    /// you should only use the field method to write in the serialization methods
    typeof(this) opCall(T)(ref T o) {
        if (rootObjStartCallback !is null){
            rootObjStartCallback(this);
        }
        readStartRoot();
        field!(T)(cast(FieldMetaInfo *)null,o);
        readEndRoot();
        if (rootObjEndCallback !is null){
            rootObjEndCallback(this);
        }
        return this;
    }
    /// reads a custom field
    final void customField(FieldMetaInfo *fieldMeta, void delegate() readOp){
        version(SerializationTrace) {
            sout(collectAppender(delegate void(CharSink s){
                s("Y customField("); s(fieldMeta is null?"*NULL*"[]:fieldMeta.name); s(") starting\n");
            }));
            scope(exit) {
                sout(collectAppender(delegate void(CharSink s){
                    s("> customField("); s(fieldMeta is null?"*NULL*":fieldMeta.name); s(") finished\n");
                }));
            }
        }
        if (fieldMeta !is null) {
            if (fieldMeta.serializationLevel>serializationLevel) {
                version(UnserializationTrace) sout("Y skip (above serialization level)\n");
                return;
            }
            if (nStack>0){
                auto stackTop=top;
                auto lab=stackTop.labelToRead;
                if (lab.length>0 && (!fieldMeta.pseudo)){
                    if (lab!=fieldMeta.name) {
                        version(UnserializationTrace) sout("Y skip field (non selected)\n");
                        return;
                    } else {
                        version(UnserializationTrace) sout("Y selected field\n");
                    }
                }
                ++stackTop.iFieldRead;
            }
        }
        readCustomField(fieldMeta,readOp);
    }
    
    /// main method writes out an object with the given field info
    /// this method cannot be overridden, but call all other methods that can be
    void field(T)(FieldMetaInfo *fieldMeta, ref T t) {
        version(UnserializationTrace) {
            sout(collectAppender(delegate void(CharSink s){
                s("Y field!("~T.stringof~")("); s(fieldMeta is null ? "*NULL*"[] : fieldMeta.name);
                s(","); writeOut(s,cast(void*)&t); s(") starting unserialization\n");
            }));
            scope(exit) {
                sout(collectAppender(delegate void(CharSink s){
                    s("Y field!("~T.stringof~")("); s(fieldMeta is null ? "*NULL*"[] : fieldMeta.name);
                    s(","); writeOut(s,cast(void*)&t); s(") finished unserialization\n");
                }));
            }
        }
        if (fieldMeta !is null) {
            if (fieldMeta.serializationLevel>serializationLevel) {
                version(UnserializationTrace) sout("Y skip (above serialization level)\n");
                return;
            }
            if (nStack>0){
                auto stackTop=top;
                auto lab=stackTop.labelToRead;
                if ( lab.length>0 && (!fieldMeta.pseudo)){
                    if (lab!=fieldMeta.name) {
                        version(UnserializationTrace) sout("Y skip field (non selected)\n");
                        return;
                    } else {
                        version(UnserializationTrace) sout("Y selected field\n");
                    }
                }
                ++stackTop.iFieldRead;
            }
        }
        static if (isCoreType!(T)){
            readCoreType(fieldMeta, { handlers.handle(t); });
            version(UnserializationTrace) {
                sout(collectAppender(delegate void(CharSink s){
                    s("Y readValue:"); writeOut(s,t); s("\n");
                }));
            }
        } else static if (is(T == interface) && !is(T==Serializable)) {
            static assert(is(T:Serializable),"unserialization of interface "~T.stringof~" not derived from Serializable");
            auto o=cast(Serializable)cast(Object)t;
            field!(Serializable)(fieldMeta,o);
            t=cast(T)cast(Object)o;
            if (o !is null && t is null){
                serializationError("error unserialized object cannot be casted to "~T.stringof~
                    " from "~(cast(Object)o).classinfo.name,__FILE__,__LINE__);
            }
            version(UnserializationTrace) sout("Y readInterfaceObject\n");
        } else {
            ClassMetaInfo metaInfo;
            objectId oid;
            static if(is(T==class)||is(T==Serializable)||
                (isPointerType!(T) && is(typeof(*t)==struct)))
            {
                if (!(fieldMeta&&fieldMeta.metaInfo&&fieldMeta.metaInfo.kind==TypeKind.CustomK)){
                    void *v=cast(void*)t;
                    if (maybeReadProxy(fieldMeta,metaInfo,oid,v)){
                        static if (is(T==Serializable)){
                            t=cast(T)cast(Object)v;
                        } else {
                            t=cast(T)v;
                        }
                        version(UnserializationTrace) sout("Y read proxy\n");
                        return;
                    }
                    readStructProxy=is(typeof(*T.init)==struct);
                    version(UnserializationTrace) sout("Y read no proxy\n");
                }
            }
            static if (is(T == class) || is(T==Serializable)) {
                if (metaInfo is null){
                    if (fieldMeta !is null && fieldMeta.metaInfo!is null) {
                        metaInfo=fieldMeta.metaInfo;
                    } else {
                        if (is(T==Serializable)){
                            serializationError("read no class name, and object is only known by interface",
                                __FILE__,__LINE__);
                        }
                        metaInfo = SerializationRegistry().getMetaInfo(T.classinfo);
                    }
                }
                if (metaInfo.kind==TypeKind.CustomK){
                    t=cast(T)instantiateClass(metaInfo);
                } else {
                    t=cast(T)readAndInstantiateClass(fieldMeta,metaInfo,oid,cast(Object)t);
                    version(UnserializationTrace) {
                        sout(collectAppender(delegate void(CharSink s){
                            s("Y instantiated object of class "); s(metaInfo.className);
                            s(" ("~T.stringof~") at "); writeOut(s,cast(void*)t); s("\n");
                        }));
                    }
                    assert(metaInfo!is null,
                        "metaInfo not set by readAndInstantiateClass ("~T.stringof~")");
                    assert(t!is null," object not allocated by readAndInstantiateClass ("
                        ~T.stringof~")");
                    assert(metaInfo.ci == (cast(Object)t).classinfo,"error in meta info of type '"
                        ~(cast(Object)t).classinfo.name~"'("~T.stringof~") got to "~metaInfo.ci.name);
                    if (recoverCycles && oid!=cast(objectId)0) {
                        objectIdToPtr[oid]=cast(void*)cast(Object)t;
                    }
                }
                int handle=push(t,metaInfo);
                scope(exit) voidPop(handle);
                // try first over the Serializable interface.
                // this is faster but migh fail if a subclass has an external handler
                // so this is disallowed
                Serializable sObj=cast(Serializable)t;
                if (sObj!is null){
                    version(UnserializationTrace) sout("Y using Serializable interface\n");
                    sObj=sObj.preUnserialize(this);
                    top().value=Variant(cast(Object)sObj);
                    version(UnserializationTrace) {
                        sout(collectAppender(delegate void(CharSink s){
                            s("Y after preUnserialize obj is at ");
                            writeOut(s,cast(void*)cast(Object)sObj);
                            s("\n");
                        }));
                    }
                    scope(exit) {
                        sObj=sObj.postUnserialize(this);
                        t=cast(T)cast(Object)sObj;
                        version(UnserializationTrace) {
                            sout(collectAppender(delegate void(CharSink s){
                                s("Y after postUnserialize obj is at ");
                                writeOut(s,cast(void*)cast(Object)sObj);
                                s("\n");
                            }));
                        }
                    }
                    void realRead1(){
                        sObj.unserialize(this);
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(UnserializationTrace) sout("Y as customField\n");
                        readCustomField(fieldMeta,&realRead1);
                    } else {
                        readObject(fieldMeta,metaInfo,
                            &realRead1, cast(Object)sObj);
                    }
                } else {
                    if (metaInfo.externalHandlers){
                        version(UnserializationTrace) sout("Y using externalHandlers\n");
                        ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                        assert(h.unserialize!is null,"externalHandlers with null unserialize");
                        if (h.preUnserialize){
                            t=cast(T)cast(Object)h.preUnserialize(this,metaInfo,cast(void*)t);
                            top().value=Variant(t);
                        }
                        scope(exit){
                            if (h.postUnserialize){
                                t=cast(T)cast(Object)h.postUnserialize(this,metaInfo,cast(void*)t);
                            }
                        }
                        void realRead2(){
                            h.unserialize(this,metaInfo,cast(void*)t);
                        }
                        if (metaInfo.kind==TypeKind.CustomK){
                            version(UnserializationTrace) sout("Y as customField\n");
                            readCustomField(fieldMeta,&realRead2);
                        } else {
                            readObject(fieldMeta,metaInfo,&realRead2, cast(Object)t);
                        }
                    } else {
                        version(UnserializationTrace) sout("Y using unserialize methods\n");
                        static if(is(typeof(T.init.preUnserialize(this)))){
                            t=cast(T)cast(Object)t.preUnserialize(this);
                            top().value=Variant(t);
                        }
                        scope(exit){
                            static if(is(typeof(T.init.postUnserialize(this)))){
                                t=cast(T)cast(Object)t.postUnserialize(this);
                                top().value=Variant(t);
                            }
                        }
                        void realRead3(){
                            t.unserialize(this);
                        }
                        static if(is(typeof(T.init.unserialize(this)))){
                            if (metaInfo.kind==TypeKind.CustomK){
                                version(UnserializationTrace) sout("Y as customField\n");
                                readCustomField(fieldMeta,&realRead3);
                            } else {
                                readObject(fieldMeta,metaInfo,&realRead3,cast(Object)t);
                            }
                        } else {
                            assert(0,"no unserialization function for "
                                ~t.classinfo.name~"'("~T.stringof~")");
                        }
                        version(UnserializationTrace) {
                            sout(collectAppender(delegate void(CharSink s){
                                s("Y did read object now at ");
                                writeOut(s,cast(void*)t); s("\n");
                            }));
                        }
                    }
                }
                version(UnserializationTrace) {
                    sout(collectAppender(delegate void(CharSink s){
                        s("Y did read object now at ");
                        writeOut(s,cast(void*)t); s("\n");
                    }));
                }
            }
            else static if (is(T == struct)) {
                version(UnserializationTrace) sout("Y reading struct\n");
                if (metaInfo is null){
                    if (fieldMeta!is null && fieldMeta.metaInfo!is null) {
                        metaInfo=fieldMeta.metaInfo;
                    } else {
                        if (is(T==Serializable)){
                            serializationError("read no class name, and object is only known by interface",
                                __FILE__,__LINE__);
                        }
                        metaInfo = SerializationRegistry().getMetaInfo(typeid(T));
                    }
                }
                if ((!readStructProxy) && metaInfo.kind!=TypeKind.CustomK){
                    void *v;
                    version(UnserializationTrace) sout("Y will try proxy\n");
                    if (maybeReadProxy(fieldMeta,metaInfo,oid,v)){
                        serializationError("read proxy for non pointer struct",__FILE__,__LINE__);
                        // simply copy it if non null?
                    }
                    version(UnserializationTrace) sout("Y tried proxy\n");
                }
                if (metaInfo is null){
                    if (fieldMeta!is null && fieldMeta.metaInfo!is null) {
                        metaInfo=fieldMeta.metaInfo;
                    } else {
                        metaInfo = SerializationRegistry().getMetaInfo(typeid(T));
                    }
                }
                auto handle=push(t,metaInfo);
                scope(exit) voidPop(handle);
                assert (metaInfo !is null, 
                    "No metaInfo registered for struct '"
                    ~typeid(T).toString~"'("~T.stringof~")");
                if (metaInfo.externalHandlers){
                    version(UnserializationTrace) sout("Y using external handlers\n");
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    assert(h.unserialize!is null,"externalHandlers without valid unserialize");
                    if (h.preUnserialize){
                        h.preUnserialize(this,metaInfo,cast(void*)&t);
                    }
                    scope(exit){
                        if (h.postUnserialize){
                            h.postUnserialize(this,metaInfo,cast(void*)&t);
                        }
                    }
                    void realRead4(){
                        h.unserialize(this,metaInfo,cast(void*)&t);
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(UnserializationTrace) sout("Y as customField\n");
                        readCustomField(fieldMeta,&realRead4);
                    } else {
                        readStruct(fieldMeta,metaInfo,&realRead4, &t);
                    }
                } else {
                    version(UnserializationTrace) sout("Y using serialization methods\n");
                    static if(is(typeof(T.init.preUnserialize(this)))){
                        t.preUnserialize(this);
                    }
                    scope(exit){
                        static if(is(typeof(T.init.postUnserialize(this)))){
                            t.postUnserialize(this);
                        }
                    }
                    static if(is(typeof(t.unserialize(this)))){
                        void realRead5(){
                            t.unserialize(this);
                        }
                    } else {
                        throw new Exception("no external handlers and no internal unserialize, cannot unserialize "~T.stringof,__FILE__,__LINE__);
                        void realRead5(){
                        }
                    }
                    static if (is(typeof(T.init.unserialize(this)))){
                        if (metaInfo.kind==TypeKind.CustomK){
                            version(UnserializationTrace) sout("Y as customField\n");
                            readCustomField(fieldMeta,&realRead5);
                        } else {
                            readStruct(fieldMeta,metaInfo,&realRead5,&t);
                        }
                    } else {
                        assert(0,"no unserialization function for "
                            ~typeid(T).toString~"'("~T.stringof~")");
                    }
                }
            }
            else static if (isArrayType!(T)) {
                version(UnserializationTrace) {
                    sout(collectAppender(delegate void(CharSink s){
                        s("Y unserializing array: "); s(fieldMeta?fieldMeta.name:"*NULL*");
                        writeOut(s,typeid(T)); s("\n");
                    }));
                }
                FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                    getSerializationInfoForType!(ElementTypeOfArray!(T))());
                elMetaInfo.pseudo=true;
                auto ac=readArrayStart(fieldMeta);
                static if (!isStaticArrayType!(T)) {
                    if (t.length==0)
                        t=new T(cast(size_t)ac.sizeHint());
                }
                size_t pos=0;
                while(readArrayEl(ac,
                    {
                        if (t.length==pos) {
                            static if (isStaticArrayType!(T)) {
                                serializationError("unserialized more elements than size of static array",__FILE__,__LINE__);
                            } else {
                                t.length=growLength(pos,T.sizeof);
                            }
                        }
                        this.field(&elMetaInfo, t[pos]);
                        ++pos;
                    } )) { }
                t.length=pos;
            }
            else static if (isAssocArrayType!(T)) {
                version(UnserializationTrace) sout("Y unserializing associative array\n");
                alias KeyTypeOfAA!(T) K;
                alias ValTypeOfAA!(T) V;
                FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
                keyMetaInfo.pseudo=true;
                FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
                valMetaInfo.pseudo=true;
                K key;
                V value;
                auto ac=readDictStart(fieldMeta,is(K==char[])||is(K==wchar[])||is(K==dchar[]));
                int iPartial=0;
                while (readEntry(ac,
                    {
                        this.field!(K)(&keyMetaInfo, key);
                        if(++iPartial==2){
                            iPartial=0;
                            t[key]=value;
                        }
                    },{
                        this.field!(V)(&valMetaInfo, value);
                        if(++iPartial==2){
                            iPartial=0;
                            t[key]=value;
                        }
                    })) { key=K.init; value=V.init; }
            } else static if (isPointerType!(T)) {
                version(UnserializationTrace) sout("Y unserializing pointer\n");
                static if (is(typeof(*T.init)==struct)||is(isArrayType!(typeof(*T.init)))||is(typeof(*T.init)==class)){
                    static if(is(typeof(*T.init)==struct)){
                        if (t is null){
                            t=new typeof(*T.init);
                        }
                    }
                    version(UnserializationTrace) sout("Y pointer to struct or class\n");
                    this.field!(typeof(*t))(fieldMeta, *t);
                } else {
                    static if (is(typeof(*t))){
                        if (recursePtr){
                            // it is not guaranteed that reading in will recover the same situation that was dumped...
                            version(UnserializationTrace) sout("Y recursing pointer\n");
                            if (t is null){
                                t=new typeof(*T.init);
                            }
                            this.field!(typeof(*t))(fieldMeta, *t);
                        } else {
                            version(UnserializationTrace) sout("Y debug pointer\n");
                            readDebugPtr(fieldMeta,cast(void**)&t);
                        }
                    } else {
                        version(UnserializationTrace) sout("Y debug pointer\n");
                        readDebugPtr(fieldMeta,cast(void**)&t);
                    }
                }
            } else static if (is(T==CharReader)) {
                readCharReader(fieldMeta,t);
            } else static if (is(T==BinReader)) {
                readBinReader(fieldMeta,t);
            } else {
                // try to get meta info
                metaInfo=getSerializationInfoForType!(T)();
                if (metaInfo is null || metaInfo.externalHandlers is null){
                    serializationError("Error: no meta info and external handlers for field of type "~T.stringof,__FILE__,__LINE__);
                } else {
                    version(UnserializationTrace) sout("Y using external handlers\n");
                    ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                    assert(h.unserialize!is null,"externalHandlers without valid unserialize");
                    if (h.preUnserialize){
                        h.preUnserialize(this,metaInfo,cast(void*)&t);
                    }
                    scope(exit){
                        if (h.postUnserialize){
                            h.postUnserialize(this,metaInfo,cast(void*)&t);
                        }
                    }
                    void realRead6(){
                        h.unserialize(this,metaInfo,cast(void*)&t);
                    }
                    if (metaInfo.kind==TypeKind.CustomK){
                        version(UnserializationTrace) sout("Y as customField\n");
                        readCustomField(fieldMeta,&realRead6);
                    } else {
                        readStruct(fieldMeta,metaInfo,&realRead6, &t);
                    }
                }
            }
        }
    }
    
    void readStartRoot() { }
    void readEndRoot() { }
    /// closes the serializer, after this it one could recyle the serializer
    void close(){
        if (unserializerCloseCallback){
            unserializerCloseCallback(this);
        }
    }
    
    /// reads with a generic text reader
    void readCharReader(FieldMetaInfo f,CharReader r){
        handlers.handle(r);
    }
    /// reads with a generic binary reader
    void readCharReader(FieldMetaInfo f,BinReader r){
        handlers.handle(r);
    }
    /// reads something that has a custom write operation
    void readCustomField(FieldMetaInfo *field, void delegate()readOp){
        readOp();
    }
    /// write a pointer (for debug purposes)
    void readDebugPtr(FieldMetaInfo *field,void** o){
        assert(0,"unimplemented");
    }
    /// reads the start of an array
    PosCounter readArrayStart(FieldMetaInfo *field){
        return PosCounter(ulong.max);
    }
    /// reads an element of the array (or its end)
    /// returns true if an element was read
    bool readArrayEl(ref PosCounter ac, void delegate() readEl) {
        if (ac.atEnd()) return false;
        ac.next();
        readEl();
        return true;
    }
    /// start of a dictionary
    PosCounter readDictStart(FieldMetaInfo *field, bool stringKeys=false) {
        auto res=PosCounter(ulong.max);
        res.data=Variant(stringKeys);
        return res;
    }
    /// writes an entry of the dictionary
    bool readEntry(ref PosCounter ac, void delegate() readKey,void delegate() readVal) {
        if (ac.atEnd()) return false;
        ac.next();
        readKey();
        readVal();
        return true;
    }
    /// returns the object with the given objId
    void setPtrFromId(objectId objId,ref void*o){
        void** resPtr=objId in objectIdToPtr;
        if (resPtr is null){
            if (!recoverCycles)
                serializationError("unserializing stream containing proxies without recoverCycles",
                    __FILE__,__LINE__);
            serializationError("cannot recover object with id "~ctfe_i2a(cast(size_t)objId),
                __FILE__,__LINE__);
        }
        o=*resPtr;
    }
    /// reads a Proxy or null
    bool maybeReadProxy(FieldMetaInfo *field,ref ClassMetaInfo metaI, ref objectId oid, ref void *t){
        return false;
    }
    /// reads the class of a serialized object and instantiate it
    /// called immediately after maybeReadProxy
    Object readAndInstantiateClass(FieldMetaInfo *field, ref ClassMetaInfo metaI,
        ref objectId oid,Object o){
        assert(0,"unimplemented");
    }
    /// helper for instantiation
    Object instantiateClass(ClassMetaInfo metaI){
        assert(metaI!is null,"no meta info to instantiate");
        Object res;
        if (metaI.allocEl is null) {
            res=metaI.ci.create();
        } else {
            res=cast(Object)metaI.allocEl(metaI);
        }
        assert(res!is null,"allocation of "~metaI.className~" failed");
        return res;
    }
    void readObject(FieldMetaInfo *field, ClassMetaInfo metaInfo,
        void delegate() unserializeF,Object o){
        assert(0,"unimplemented");
    }
    void readStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo,void delegate() unserializeF,void*t){
        assert(0,"unimplemented");
    }
    /// reads a core type
    void readCoreType(FieldMetaInfo *field,void delegate() realRead){
        realRead();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    void serializationError(char[]msg,char[]filename,long line,Exception next=null){
        throw new SerializationException(msg,collectAppender(&handlers.parserPos),filename,line,next);
    }
}
