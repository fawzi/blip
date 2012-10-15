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
import tango.text.Regex: Regex;
import blip.container.GrowableArray;
import blip.util.Grow;
public import blip.core.Traits;
import blip.Comp;

version(SerializationTrace){
    version=STrace;
} else version(UnserializationTrace){
    version=STrace;
} else version(SRegistryTrace){
    version=STrace;
}

/// basic exception for serialization errors
class SerializationException: Exception{
    string pos;
    this(string msg,string pos,string file,long line,Exception next=null){
        super(msg,file,line,next);
        this.pos=pos;
    }
    void writeOutMsg(scope void delegate(in cstring)sink){
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
    string name; /// name of the propety
    ClassMetaInfo metaInfo; /// expected meta info (used if not class)
    SerializationLevel serializationLevel; /// when to serialize
    string doc; /// documentation of the field
    /// creates a field meta info (normally one uses ClassMetaInfo.addFieldOfType)
    this(string fieldName,string documentation,ClassMetaInfo typeMetaInfo,
        SerializationLevel l=SerializationLevel.normalLevel)
    {
        name = fieldName;
        metaInfo=typeMetaInfo;
        doc=documentation;
        serializationLevel=l;
        pseudo=false;
    }
    /// describes a field meta info
    void desc(scope void delegate(in cstring) s){
        s("<FieldMetaInfo name:'"); s(name); s("',");
        s("level:"); writeOut(s,serializationLevel); s(",");
        s("metaInfo:"); s((metaInfo is null) ? "*NULL*"[] : metaInfo.className); s(">");
    }
    string []citationKeys(){
        string [] res=[];
        foreach(m; Regex(r"\[[a-zA-Z]\w*\]").search(doc))
            res~=m.match(0).idup;
        return res;
    }
}
/// returns the typeid of the given type
template typeKindForType(TT){
    alias UnqualAll!(TT) T;
    static if(isCoreType!(T)){
        enum typeKindForType=TypeKind.PrimitiveK;
    } else static if(is(T==class)){
        enum typeKindForType=TypeKind.ClassK;
    } else static if(is(T:T[])){
        enum typeKindForType=TypeKind.ArrayK;
    } else static if(isAssocArrayType!(T)){
        alias UnqualAll!(KeyTypeOfAA!(T)) kType;
        static if (is(kType==char[])||is(kType==wchar[])||is(kType==dchar[])){
            enum typeKindForType=TypeKind.DictK;
        } else {
            enum typeKindForType=TypeKind.AAK;
        }
    } else static if(is(T==struct)){
        enum typeKindForType=TypeKind.StructK;
    } else static if (is(typeof(*T.init))){
        enum typeKindForType=typeKindForType!(typeof(*T.init));
    } else {
        enum typeKindForType=TypeKind.UndefK;
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
    string className;
    ClassMetaInfo superMeta;
    FieldMetaInfo[] fields;
    TypeKind kind;
    TypeInfo ti;
    ClassInfo ci;
    void* function (ClassMetaInfo mInfo) allocEl;
    ExternalSerializationHandlers * externalHandlers;
    string doc;
    /// return the field with the given local index
    FieldMetaInfo *opIndex(int i){
        if (i>=0 && i<fields.length){
            return &(fields[i]);
        } else {
            return null;
        }
    }
    /// returns the field with the given name
    FieldMetaInfo *fieldNamed(in cstring name){
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
    void addFieldOfType(T)(string name,string doc,
        SerializationLevel sLevel=SerializationLevel.normalLevel){
        ClassMetaInfo tMI=getSerializationInfoForType!(UnqualAll!(T))();
        FieldMetaInfo fMI=FieldMetaInfo(name,doc,tMI,sLevel);
        addField(fMI);
    }
    /// constructor (normally use createForType)
    this(string className,string doc,ClassMetaInfo superMeta,TypeInfo ti,ClassInfo ci,TypeKind kind,void* function(ClassMetaInfo)allocEl){
        this.className=className;
        this.superMeta=superMeta;
        this.ti=ti;
        this.ci=ci;
        this.kind=kind;
        this.allocEl=allocEl;
        this.doc=doc;
    }
    /// creates a new meta info for the given type and registers it
    /// if no name is given, T.mangleof is used.
    /// normally this is the best way to create a new MetaInfo
    static ClassMetaInfo createForType(TT)(string name="",string doc="",
        void *function(ClassMetaInfo) allocEl=cast(void *function(ClassMetaInfo))null){
         alias UnqualAll!(TT) T;
        static if(is(T==class)){
            ClassInfo newCi=T.classinfo;
            if (name.length==0){
                name=newCi.name; // should be nicer, but has it issues with templates???
            }
            ClassMetaInfo newSuperMeta=null;
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
        auto res=new ClassMetaInfo(name,doc,newSuperMeta,newTi,newCi,typeKindForType!(T),allocEl);
        static if(is(T==class)){
            static if(is(T U==super)){
                foreach(S;U){
                    static if (is(S == class)){
                        static if (__traits(compiles,delegate void(S s,Serializer ser,Unserializer u){
                                    s.serialize(ser); s.unserialize(u); }) ){
                            SerializationRegistry().addDelayedLookup(S.classinfo,&res.superMeta,name);
                        }
                    }
                }
            }
        }
        SerializationRegistry().register!(T)(res);
        return res;
    }
    /// number of local fields
    int nLocalFields(){ return cast(int)fields.length; }
    /// total number of fields
    int nTotFields(){
        if (superMeta){
            return superMeta.nTotFields()+cast(int)fields.length;
        }
        return cast(int)fields.length;
    }
    /// description (for debugging purposes)
    void desc(scope void delegate(in cstring) sink){
        auto s=dumper(sink);
        s("<ClassMetaInfo@"); writeOut(sink,cast(void*)this); s("\n");
        s(" className:'")(className)("',\n");
        s(" kind:")(kind)(",\n");
        s(" superMeta:")(superMeta is null ? "*NULL*" : superMeta.className)("\n");
        s(" ti:")(ti is null ? "*NULL*" : ti.toString)("@")(cast(void*)ti)("\n");
        s(" ci:")(ci is null ? "*NULL*" : ci.toString)("@")(cast(void*)ci)("\n");
        s(" allocEl:")(allocEl is null ? "*NULL*" : "*ASSOCIATED*")("@")(cast(void*)allocEl)("\n");
        s(" doc:\"")(doc)("\"\n");
        foreach(field;fields){
            writeOut(sink,field);
            sink("\n");
        }
        s(">\n");
    }
    int opApply(scope int delegate(ref FieldMetaInfo *) loopBody){
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
    override equals_t opEquals(Object o2){
        return this is o2;
    }
    override int opCmp(Object o2){
        return (((cast(void*)this)<(cast(void*)o2))?-1:(this is o2)?0:1);
    }
    hash_t toHash() @trusted{
        static if (hash_t.sizeof < size_t.sizeof){
            return rt_hash_str(&this,size_t.sizeof);
        } else {
            union P2H{
                void* ptr;
                hash_t hash;
            }
            P2H w;
            w.ptr=cast(void*)this;
            return w.hash;
        }
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

// various metaInfo (for completeness, not really needed)
__gshared ClassMetaInfo arrayMetaInfo;
__gshared ClassMetaInfo stringMetaInfo;
__gshared ClassMetaInfo aaMetaInfo;
__gshared ClassMetaInfo dictMetaInfo;
__gshared ClassMetaInfo voidPtrMetaInfo;
shared static this(){
    arrayMetaInfo=new ClassMetaInfo("array","an array",null,null,null,TypeKind.ArrayK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each array type?
    stringMetaInfo=new ClassMetaInfo("string","a string",null,null,null,TypeKind.ArrayK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each array type?
    aaMetaInfo=new ClassMetaInfo("aa","an associative array",null,null,null,TypeKind.AAK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each aa type?
    dictMetaInfo=new ClassMetaInfo("dict","a dictionary",null,null,null,TypeKind.DictK,
        cast(void* function(ClassMetaInfo))null); // use a different type for each dict type?
    voidPtrMetaInfo=new ClassMetaInfo("voidPtr","a pointer",null,null,null,TypeKind.VoidPtr,
        cast(void* function(ClassMetaInfo))null);
    SerializationRegistry().register!(int[])(arrayMetaInfo);
    SerializationRegistry().register!(char[])(stringMetaInfo);
    SerializationRegistry().register!(int[int])(aaMetaInfo);
    SerializationRegistry().register!(int[string ])(dictMetaInfo);
    SerializationRegistry().register!(void*)(voidPtrMetaInfo);
}

string coreTypesMetaInfoMixStr(){
    string res="";
    foreach(T;CoreTypes){
        res~="__gshared ClassMetaInfo "~strForCoreType!(T)~"MetaInfo;\n";
    }
    res~="shared static this(){\n";
    foreach(T;CoreTypes){
        res~=strForCoreType!(T)~"MetaInfo=new ClassMetaInfo(\""~T.stringof~"\",\"\",null,typeid("~T.stringof~"),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);\n";
        res~="SerializationRegistry().register!("~T.stringof~")("~strForCoreType!(T)~"MetaInfo);\n";
    }
    res~="}\n";
    return res;
}

// ---- start mixin manual expansion -----
__gshared ClassMetaInfo boolMetaInfo;
__gshared ClassMetaInfo byteMetaInfo;
__gshared ClassMetaInfo ubyteMetaInfo;
__gshared ClassMetaInfo shortMetaInfo;
__gshared ClassMetaInfo ushortMetaInfo;
__gshared ClassMetaInfo intMetaInfo;
__gshared ClassMetaInfo uintMetaInfo;
__gshared ClassMetaInfo longMetaInfo;
__gshared ClassMetaInfo ulongMetaInfo;
__gshared ClassMetaInfo floatMetaInfo;
__gshared ClassMetaInfo doubleMetaInfo;
__gshared ClassMetaInfo realMetaInfo;
__gshared ClassMetaInfo ifloatMetaInfo;
__gshared ClassMetaInfo idoubleMetaInfo;
__gshared ClassMetaInfo irealMetaInfo;
__gshared ClassMetaInfo cfloatMetaInfo;
__gshared ClassMetaInfo cdoubleMetaInfo;
__gshared ClassMetaInfo crealMetaInfo;
__gshared ClassMetaInfo binaryBlobMetaInfo;
__gshared ClassMetaInfo charStrMetaInfo;
__gshared ClassMetaInfo wcharStrMetaInfo;
__gshared ClassMetaInfo dcharStrMetaInfo;
__gshared ClassMetaInfo binaryBlob2MetaInfo;
shared static this(){
    boolMetaInfo=new ClassMetaInfo("bool","",null,typeid(bool),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(bool)(boolMetaInfo);
    byteMetaInfo=new ClassMetaInfo("byte","",null,typeid(byte),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(byte)(byteMetaInfo);
    ubyteMetaInfo=new ClassMetaInfo("ubyte","",null,typeid(ubyte),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ubyte)(ubyteMetaInfo);
    shortMetaInfo=new ClassMetaInfo("short","",null,typeid(short),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(short)(shortMetaInfo);
    ushortMetaInfo=new ClassMetaInfo("ushort","",null,typeid(ushort),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ushort)(ushortMetaInfo);
    intMetaInfo=new ClassMetaInfo("int","",null,typeid(int),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(int)(intMetaInfo);
    uintMetaInfo=new ClassMetaInfo("uint","",null,typeid(uint),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(uint)(uintMetaInfo);
    longMetaInfo=new ClassMetaInfo("long","",null,typeid(long),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(long)(longMetaInfo);
    ulongMetaInfo=new ClassMetaInfo("ulong","",null,typeid(ulong),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ulong)(ulongMetaInfo);
    floatMetaInfo=new ClassMetaInfo("float","",null,typeid(float),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(float)(floatMetaInfo);
    doubleMetaInfo=new ClassMetaInfo("double","",null,typeid(double),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(double)(doubleMetaInfo);
    realMetaInfo=new ClassMetaInfo("real","",null,typeid(real),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(real)(realMetaInfo);
    ifloatMetaInfo=new ClassMetaInfo("ifloat","",null,typeid(ifloat),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ifloat)(ifloatMetaInfo);
    idoubleMetaInfo=new ClassMetaInfo("idouble","",null,typeid(idouble),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(idouble)(idoubleMetaInfo);
    irealMetaInfo=new ClassMetaInfo("ireal","",null,typeid(ireal),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ireal)(irealMetaInfo);
    cfloatMetaInfo=new ClassMetaInfo("cfloat","",null,typeid(cfloat),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(cfloat)(cfloatMetaInfo);
    cdoubleMetaInfo=new ClassMetaInfo("cdouble","",null,typeid(cdouble),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(cdouble)(cdoubleMetaInfo);
    crealMetaInfo=new ClassMetaInfo("creal","",null,typeid(creal),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(creal)(crealMetaInfo);
    binaryBlobMetaInfo=new ClassMetaInfo("ubyte[]","",null,typeid(ubyte[]),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(ubyte[])(binaryBlobMetaInfo);
    charStrMetaInfo=new ClassMetaInfo("char[]","",null,typeid(char[]),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(char[])(charStrMetaInfo);
    wcharStrMetaInfo=new ClassMetaInfo("wchar[]","",null,typeid(wchar[]),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(wchar[])(wcharStrMetaInfo);
    dcharStrMetaInfo=new ClassMetaInfo("dchar[]","",null,typeid(dchar[]),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(dchar[])(dcharStrMetaInfo);
    binaryBlob2MetaInfo=new ClassMetaInfo("void[]","",null,typeid(void[]),null,TypeKind.PrimitiveK,cast(void *function (ClassMetaInfo c))null);
    SerializationRegistry().register!(void[])(binaryBlob2MetaInfo);
}
// ---- end mixin manual expansion ----- 
// mixin(coreTypesMetaInfoMixStr());

/// returns the meta info for the given type
ClassMetaInfo getSerializationInfoForType(TT)(){
    alias UnqualAll!(TT) T;
    static if (is(T==class)){
        return SerializationRegistry().getMetaInfo(T.classinfo);
    } else static if (is(T==struct)){
        return SerializationRegistry().getMetaInfo(typeid(T));
    } else static if (is(T==Serializable)){
        return SerializationRegistry().getMetaInfo(Serializable.classinfo);
    } else static if (is(T==interface)){
        return SerializationRegistry().getMetaInfo(Object.classinfo);
    } else static if (is(T UU:UU[])){
        alias UnqualAll!(UU) U;
        static if (is(U:char)||is(U:wchar)||is(U:dchar)){
            return stringMetaInfo;
        } else {
            return arrayMetaInfo;
        }
    } else static if (isAssocArrayType!(T)){
        return aaMetaInfo;
    } else static if (isCoreType!(T)){
        // ---- start static foreach and mixin manual expansion ----
        static if (is(T==bool))
            return boolMetaInfo;
        else static if (is(T==byte))
            return byteMetaInfo;
        else static if (is(T==ubyte))
            return ubyteMetaInfo;
        else static if (is(T==short))
            return shortMetaInfo;
        else static if (is(T==ushort))
            return ushortMetaInfo;
        else static if (is(T==int))
            return intMetaInfo;
        else static if (is(T==uint))
            return uintMetaInfo;
        else static if (is(T==long))
            return longMetaInfo;
        else static if (is(T==ulong))
            return ulongMetaInfo;
        else static if (is(T==float))
            return floatMetaInfo;
        else static if (is(T==cfloat))
            return cfloatMetaInfo;
        else static if (is(T==ifloat))
            return ifloatMetaInfo;
        else static if (is(T==double))
            return doubleMetaInfo;
        else static if (is(T==idouble))
            return idoubleMetaInfo;
        else static if (is(T==cdouble))
            return cdoubleMetaInfo;
        else static if (is(T==real))
            return realMetaInfo;
        else static if (is(T==ireal))
            return irealMetaInfo;
        else static if (is(T==creal))
            return crealMetaInfo;
        else static if (is(T==ubyte[]))
            return bynaryBlobMetaInfo;
        else static if (is(T==void[]))
            return bynaryBlob2MetaInfo;
        else static if (is(T==char[]))
            return charStrMetaInfo;
        else static if (is(T==wchar[]))
            return wcharStrMetaInfo;
        else static if (is(T==dchar[]))
            return dcharStrMetaInfo;
        else 
            static assert(0,"unexpected type as core type:"~T.stringof);
        // ---- end static foreach and mixin manual expansion ----
/+
     // dmd 2.060 bug, so the previous explicit workaround...
        foreach(V;CoreTypes){
            static if(is(T==V)){
                mixin("return "~strForCoreType!(V)~"MetaInfo;");
            }
        }+/
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
    assert(0);
}

/// returns the serialization for the given variable
ClassMetaInfo getSerializationInfoForVar(TT)(TT t){
    alias UnqualAll!(TT) T;
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
    ClassMetaInfo[string ] name2metaInfos;
    static struct PendingLookup{
        ClassMetaInfo *target;
        Object key;
        string context;
        PendingLookup * next;
    }
    PendingLookup[Object] pendingLookups;

    Object keyOf(T)() {
        static if (is(T == class)) {
            return T.classinfo;
        } else static if (is(T==void*)){
            return voidPtrMetaInfo;
        } else {
            return typeid(T);
        }
    }
    
    /// adds a (possibly) delayed lookup
    void addDelayedLookup(Object key, ClassMetaInfo *target, string context){
        synchronized(this){
            ClassMetaInfo *mInfo= key in type2metaInfos;
            if (mInfo !is null){
                *target = *mInfo;
                return;
            }
            PendingLookup *lk=key in pendingLookups;
            if (lk is null){
                PendingLookup pl=PendingLookup(target,key,context);
                pendingLookups[key]=pl;
            } else {
                PendingLookup *pl2=new PendingLookup;
                *pl2=PendingLookup(target,key,context,lk.next);
                lk.next=pl2;
            }
        }
    }

    /// writes out the pending lookups
    void writeOutPendingLookups(scope CharSink sink, string indent=""){
        auto s=dumper(sink);
        s("pendingLookups:{");
        bool hasSome=false;
        synchronized(this){
            foreach(k,v;pendingLookups){
                if (hasSome) s(",");
                hasSome=true;
                s("\n")(indent);
                s("  { key:@")(cast(void*)v.key)(", target:@")(cast(void*)v.target)(", context:`")(v.context)("` }");
                auto n=v.next;
                while (n !is null){
                    s(",\n")(indent);
                    s("  { key:@")(cast(void*)n.key)(", target:@")(cast(void*)n.target)(", context:`")(n.context)("` }");
                    n=n.next;
                }
            }
        }
        if (hasSome) {
            s("\n")(indent);
        }
        s("}");
    }

    /// registers the given meta info for the type T
    void register(T)(ClassMetaInfo metaInfo) {
        assert(metaInfo!is null,"attempt to register null metaInfo");
        Object key = keyOf!(T); // use the content of metaInfo???
        version(STrace) {
            sinkTogether(sout,delegate(scope CharSink s){
                    dumper(s)("Registering ")(metaInfo.className)(" in the serialization factory ")
                        (key.toString)(" @")(cast(void*)key)(" (")(T.stringof)(")\n");
                });
        }
        synchronized(this){
            ClassMetaInfo *oldInfo=metaInfo.className in name2metaInfos;
            if (oldInfo!is null){
                if (oldInfo.ci is metaInfo.ci && oldInfo.ti is metaInfo.ti) return; // ignore double registation (tipically from multiple instance of the same template with the same parameter)
                // exception in static constructors might be tricky...
                // so we also print out
                sout("Registering duplicated name:"~metaInfo.className~"\n");
                throw new Exception(collectIAppender(delegate void(scope CharSink s){
                            dumper(s)("Registering duplicated name in SerializationRegistry@")(cast(void*)this)(":")(metaInfo.className)
                                (", oldVal:")(*oldInfo)(" newVal:")(metaInfo)("\n");
                        }),__FILE__,__LINE__);
            }
            PendingLookup *lk=key in pendingLookups;
            if (lk !is null){
                *lk.target=metaInfo;
                auto n=lk.next;
                while (n !is null) {
                    *n.target=metaInfo;
                    auto old=n;
                    n=n.next;
                    clear(old); // malloc and really free?
                }
                pendingLookups.remove(key);
            }
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

    ClassMetaInfo getMetaInfo(string name) {
        synchronized(this){
            auto ptr = name in name2metaInfos;
            if (ptr is null) return null;
            return *ptr;
        }
    }
    
    static typeof(this) opCall() {
        static __gshared typeof(this) instance;
        if (instance is null) instance = new typeof(this);
        return instance;
    }
}

template isBasicType(T) {
    enum bool isBasicType =
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
    alias size_t classId;
    alias size_t objectId;
    WriteHandlers handlers;
    void delegate(Serializer) rootObjStartCallback;
    void delegate(Serializer) rootObjEndCallback;
    void delegate(Serializer) serializerCloseCallback;
    
    objectId[void*]             ptrToObjectId;
    objectId                    lastObjectId;
    Variant[string ]             context;
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
        handlers.close();
    }
    /// flushes the underlying stream
    void flush(){
        handlers.flush();
    }
    /// writes the given root object
    /// if it is a pointer (and not void*) then it is indirected once before feeding it on
    /// (to handle this in structs better)
    /// you should only use the field method to write in the serialization methods
    typeof(this) opCall(S...)(S o) {
        if (rootObjStartCallback){
            rootObjStartCallback(this);
        }
        writeStartRoot();
        foreach(i,T;S){
            if (i!=0) writeTupleSpacer();
            static if(isStaticArrayType!(T)){
                auto arr=o[i][];
                field!(typeof(arr))(cast(FieldMetaInfo *)null,arr);
            } else static if(is(typeof(*o[i])) && is(T==typeof(*o[i])*)){
                field!(typeof(*o[i]))(cast(FieldMetaInfo *)null,*o[i]);
            } else {
                field!(T)(cast(FieldMetaInfo *)null,o[i]);
            }
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
    void writeTupleSpacer() { }
    
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
    final void customField(FieldMetaInfo *fieldMeta, scope void delegate() realWrite){
        version(SerializationTrace) {
            sout(collectIAppender(delegate(scope CharSink s){
                s("X customField("); s(fieldMeta is null?"*NULL*":fieldMeta.name); s(") starting\n");
            }));
            scope(exit) {
                sout(collectIAppender(delegate(scope CharSink s){
                    s("X customField("); s(fieldMeta is null?"*NULL*":fieldMeta.name); s(") finished\n");
                }));
            }
        }
        if (fieldMeta !is null && fieldMeta.serializationLevel>serializationLevel) return;
        writeCustomField(fieldMeta,realWrite);
    }
    /// writes out a field of type t
    void field(TT)(FieldMetaInfo *fieldMeta, ref TT t) {
        alias UnqualAll!(TT) T;
        fieldT!(T)(fieldMeta,*cast(T*)&t);
    }
    void fieldT(T)(FieldMetaInfo *fieldMeta, ref T t) {
        version(SerializationTrace) {
            sout(collectIAppender(delegate void(scope CharSink s){
                s("X fieldT!("~T.stringof~")(");
                s(fieldMeta is null?"*NULL*":fieldMeta.name);
                s(","); writeOut(s,cast(const(void)*)&t); s(") starting\n");
            }));
            scope(exit) {
                sout(collectIAppender(delegate void(scope CharSink s){
                    s("X fieldT!("~T.stringof~")(");
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
            fieldT!(Serializable)(fieldMeta,o);
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
                            sout(collectIAppender(delegate void(scope CharSink s){
                                s("X metaInfo:");
                                writeOut(s,metaInfo);
                                s("\n");
                            }));
                            sout(collectIAppender(delegate void(scope CharSink s){
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
                alias UnqualAll!(K) K2;
                alias ValTypeOfAA!(T) V;
                version(PseudoFieldMetaInfo){
                    FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
                    keyMetaInfo.pseudo=true;
                    FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
                    valMetaInfo.pseudo=true;
                }
                auto ac=writeDictStart(fieldMeta,(*cast(V[immutable(K)]*)&t).length,
                    is(K2==char[])||is(K2==wchar[])||is(K2==dchar[]));
                foreach (key, ref value; t) {
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
    void writeCustomField(FieldMetaInfo *field, scope void delegate()writeOp){
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
    void writeArrayEl(ref PosCounter ac, scope void delegate() writeEl) {
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
    void writeEntry(ref PosCounter ac, scope void delegate() writeKey,scope void delegate() writeVal) {
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
        bool isSubclass, scope void delegate() realWrite, Object o){
        realWrite();
    }
    /// writes a Proxy
    void writeProxy(FieldMetaInfo *field, objectId objId){
        assert(0,"unimplemented");
    }
    /// write Struct
    void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        scope void delegate() realWrite,const(void)*t){
        realWrite();
    }
    /// writes a core type
    void writeCoreType(FieldMetaInfo *field,scope void delegate() realWrite, void *t){
        realWrite();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    void serializationError(string msg,string filename,long line,Exception e=null){
        throw new SerializationException(msg,"",filename,line,e);
    }
}

/// unserializer
/// some methods have no classinfo for performance reasons, if you really need it file a ticket explaining why 
class Unserializer {
    alias size_t classId;
    alias size_t objectId;
    ReadHandlers handlers;

    void*[objectId]             objectIdToPtr;
    objectId                    lastObjectId;
    Variant[string ]             context;
    SerializationLevel serializationLevel;
    bool recoverCycles=true;
    bool readStructProxy;
    bool recursePtr=false;
    void delegate(Unserializer) rootObjStartCallback;
    void delegate(Unserializer) rootObjEndCallback;
    void delegate(Unserializer) unserializerCloseCallback;
    
    struct StackEntry{
        TypeKind kind;
        string labelToRead;
        int iFieldRead;
        ClassMetaInfo metaInfo;
        HashSet!(string ) missingLabels;
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
            missingLabels=new HashSet!(string )();
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
    typeof(this) opCall(S...)(ref S o) {
        if (rootObjStartCallback !is null){
            rootObjStartCallback(this);
        }
        readStartRoot();
        foreach(i,T;S){
            if (i!=0) readTupleSpacer();
            field!(UnqualAll!(T))(cast(FieldMetaInfo *)null,*cast(UnqualAll!(T)*)&(o[i]));
        }
        readEndRoot();
        if (rootObjEndCallback !is null){
            rootObjEndCallback(this);
        }
        return this;
    }
    /// reads a custom field
    final void customField(FieldMetaInfo *fieldMeta, scope void delegate() readOp){
        version(SerializationTrace) {
            sout(collectIAppender(delegate void(scope CharSink s){
                s("Y customField("); s(fieldMeta is null?"*NULL*"[]:fieldMeta.name); s(") starting\n");
            }));
            scope(exit) {
                sout(collectIAppender(delegate void(scope CharSink s){
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
    void field(TT)(FieldMetaInfo *fieldMeta, ref TT t) {
        alias UnqualAll!(TT) T;
        fieldT!(T)(fieldMeta, *cast(T*)&t);
    }
    void fieldT(T)(FieldMetaInfo *fieldMeta, ref T t) {
        version(UnserializationTrace) {
            sout(collectIAppender(delegate void(scope CharSink s){
                s("Y fieldT!("~T.stringof~")("); s(fieldMeta is null ? "*NULL*"[] : fieldMeta.name);
                s(","); writeOut(s,cast(void*)&t); s(") starting unserialization\n");
            }));
            scope(exit) {
                sout(collectIAppender(delegate void(scope CharSink s){
                    s("Y fieldT!("~T.stringof~")("); s(fieldMeta is null ? "*NULL*"[] : fieldMeta.name);
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
                sout(collectIAppender(delegate void(scope CharSink s){
                    s("Y readValue:"); writeOut(s,t); s("\n");
                }));
            }
        } else static if (is(T == interface) && !is(T==Serializable)) {
            static assert(is(T:Serializable),"unserialization of interface "~T.stringof~" not derived from Serializable");
            auto o=cast(Serializable)cast(Object)t;
            fieldT!(Serializable)(fieldMeta,o);
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
                bool didPre=false;
                int handle=int.max;
                void delegate() rrRead,doPost;
                void allocT(){
                    didPre=true;
                    if (metaInfo.kind==TypeKind.CustomK){
                        t=cast(T)instantiateClass(metaInfo);
                    } else {
                        t=cast(T)readAndInstantiateClass(fieldMeta,metaInfo,oid,cast(Object)t);
                        version(UnserializationTrace) {
                            sout(collectIAppender(delegate void(scope CharSink s){
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
                    handle=push(t,metaInfo);
                }
                scope(exit){
                    if (didPre){
                        doPost();
                        voidPop(handle);
                        version(UnserializationTrace) {
                            sout(collectIAppender(delegate void(scope CharSink s){
                                s("Y did read object now at ");
                                writeOut(s,cast(void*)t); s("\n");
                            }));
                        }
                    }
                }
                
                // try first over the Serializable interface.
                // this is faster but migh fail if a subclass has an external handler
                // so this is disallowed
                Serializable sObj=cast(Serializable)t;
                // serializable interface
                void realRead1(){
                    if (!didPre){
                        allocT();
                        sObj=sObj.preUnserialize(this);
                        top().value=Variant(cast(Object)sObj);
                    }
                    sObj.unserialize(this);
                }
                void post1(){
                    sObj=sObj.postUnserialize(this);
                    t=cast(T)cast(Object)sObj;
                }
                // externalHandlers
                ExternalSerializationHandlers *h=metaInfo.externalHandlers;
                void realRead2(){
                    if (!didPre){
                        allocT();
                        assert(h.unserialize!is null,"externalHandlers with null unserialize");
                        if (h.preUnserialize){
                            t=cast(T)cast(Object)h.preUnserialize(this,metaInfo,cast(void*)t);
                            top().value=Variant(t);
                        }
                    }
                    h.unserialize(this,metaInfo,cast(void*)t);
                }
                void post2(){
                    if (h.postUnserialize){
                        t=cast(T)cast(Object)h.postUnserialize(this,metaInfo,cast(void*)t);
                    }
                }
                void realRead3(){
                    if (!didPre){
                        allocT();
                        static if(is(typeof(T.init.preUnserialize(this)))){
                            t=cast(T)cast(Object)t.preUnserialize(this);
                            top().value=Variant(t);
                        }
                    }
                    t.unserialize(this);
                }
                void post3(){
                    static if(is(typeof(T.init.postUnserialize(this)))){
                        t=cast(T)cast(Object)t.postUnserialize(this);
                        top().value=Variant(t);
                    }
                }
                if (sObj!is null){
                    version(UnserializationTrace) sout("Y using Serializable interface\n");
                    rrRead=&realRead1;
                    doPost=&post1;
                } else {
                    if (metaInfo.externalHandlers){
                        version(UnserializationTrace) sout("Y using externalHandlers\n");
                        rrRead=&realRead2;
                        doPost=&post2;
                    } else {
                        version(UnserializationTrace) sout("Y using unserialize methods\n");
                        static if(is(typeof(T.init.unserialize(this)))){
                            rrRead=&realRead3;
                            doPost=&post3;
                        } else {
                            assert(0,"no unserialization function for "
                                ~t.classinfo.name~"'("~T.stringof~")");
                        }
                    }
                }
                if (metaInfo.kind==TypeKind.CustomK){
                    version(UnserializationTrace) sout("Y as customField\n");
                    readCustomField(fieldMeta,rrRead);
                } else {
                    readObject(fieldMeta,metaInfo,rrRead, cast(Object)t);
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
                    scope(exit){
                        if (didPre && h.postUnserialize){
                            h.postUnserialize(this,metaInfo,cast(void*)&t);
                        }
                    }
                    bool didPre=false;
                    void realRead4(){
                        if (!didPre){
                            didPre=true;
                            if (h.preUnserialize){
                                h.preUnserialize(this,metaInfo,cast(void*)&t);
                            }
                        }
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
                    bool didPre=false;
                    scope(exit){
                        static if(is(typeof(T.init.postUnserialize(this)))){
                            if (didPre) t.postUnserialize(this);
                        }
                    }
                    static if(is(typeof(t.unserialize(this)))){
                        void realRead5(){
                            if (!didPre){
                                didPre=true;
                                static if(is(typeof(T.init.preUnserialize(this)))){
                                    t.preUnserialize(this);
                                }
                            }
                            t.unserialize(this);
                        }
                    } else {
                        throw new Exception("no external handlers and no internal unserialize, cannot unserialize "~T.stringof,__FILE__,__LINE__);
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
                } else static if (is(T VV:VV[])) {
                alias UnqualAll!(VV) V;
                version(UnserializationTrace) {
                    sout(collectIAppender(delegate void(scope CharSink s){
                        s("Y unserializing array: "); s(fieldMeta?fieldMeta.name:"*NULL*");
                        writeOut(s,typeid(T)); s("\n");
                    }));
                }
                auto elType=getSerializationInfoForType!(V)();
                FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",elType);
                elMetaInfo.pseudo=true;
                auto ac=readArrayStart(fieldMeta);
                bool freeOld=false;
                static if (!isStaticArrayType!(T)) {
                    if (t.length==0) {
                        t=new V[](cast(size_t)ac.sizeHint());
                        freeOld=true;
                    }
                }
                size_t pos=0;
                while(readArrayEl(ac,
                    {
                        if (t.length==pos) {
                            static if (isStaticArrayType!(T)) {
                                serializationError("unserialized more elements than size of static array",__FILE__,__LINE__);
                            } else {
                                if (freeOld){
                                    auto tOld=t.ptr;
                                    t.length=growLength(pos+1,T.sizeof);
                                    if (t.ptr !is tOld) delete tOld;
                                } else {
                                    auto tNew=new V[](growLength(pos+1,T.sizeof));
                                    tNew[0..t.length]=t;
                                    freeOld=true;
                                }
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
                alias UnqualAll!(K) K2;
                alias ValTypeOfAA!(T) V;
                FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
                keyMetaInfo.pseudo=true;
                FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
                valMetaInfo.pseudo=true;
                K2 key;
                V value;
                auto ac=readDictStart(fieldMeta,is(K2==char[])||is(K2==wchar[])||is(K2==dchar[]));
                int iPartial=0;
                while (readEntry(ac,
                    {
                        this.field!(K2)(&keyMetaInfo, key);
                        if(++iPartial==2){
                            iPartial=0;
                            t[*cast(K*)&key]=value;
                        }
                    },{
                        this.field!(V)(&valMetaInfo, value);
                        if(++iPartial==2){
                            iPartial=0;
                            t[cast(K)key]=value;
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
    void readTupleSpacer() { }
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
    void readCustomField(FieldMetaInfo *field, scope void delegate()readOp){
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
    bool readArrayEl(ref PosCounter ac, scope void delegate() readEl) {
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
    bool readEntry(ref PosCounter ac, scope void delegate() readKey,scope void delegate() readVal) {
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
            serializationError("cannot recover object with id "~ctfe_i2s(cast(size_t)objId),
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
        scope void delegate() unserializeF,Object o){
        assert(0,"unimplemented");
    }
    void readStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo,scope void delegate() unserializeF,void*t){
        assert(0,"unimplemented");
    }
    /// reads a core type
    void readCoreType(FieldMetaInfo *field,scope void delegate() realRead){
        realRead();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    void serializationError(string msg,string filename,long line,Exception next=null){
        throw new SerializationException(msg,collectIAppender(&handlers.parserPos),filename,line,next);
    }
}
