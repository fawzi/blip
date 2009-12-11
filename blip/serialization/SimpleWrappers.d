/// custom wrappers that write out or read simple basic types (arrays, associative arrays)
/// these types are "invisible" in the sense that in the serialized form they are indistinguishible
/// from arrays and associative arrays
module blip.serialization.SimpleWrappers;
import blip.serialization.SerializationBase;
version(SerializationTrace) import blip.io.Console;

// wrapper to write out an array
struct LazyArray(T) {
    ulong size; /// output size
    int delegate(int delegate(ref T)) loopOp; /// output loop
    void delegate(T) addOp; /// add one element
    void delegate(ulong l) setLen; /// set the length (before addition with a guess, after with real size)
    
    /// if you just want to write out this is all that is needed
    static LazyArray opCall(int delegate(int delegate(ref T)) loopOp,ulong size=ulong.max){
        LazyArray res;
        res.size=size;
        res.loopOp=loopOp;
        return res;
    }
    /// if you just want to readin this is all that is needed
    static LazyArray opCall(void delegate(T) addOp,void delegate(ulong l) setLen=null){
        LazyArray res;
        res.addOp=addOp;
        res.setLen=setLen;
        return res;
    }
    /// initialize a complete (input/output) wrapper
    static LazyArray opCall(int delegate(int delegate(ref T)) loopOp,void delegate(T) addOp,
        ulong size=ulong.max,void delegate(ulong l) setLen=null){
        LazyArray res;
        res.size=size;
        res.loopOp=loopOp;
        res.addOp=addOp;
        res.setLen=setLen;
        return res;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(*this))("LazyArray!("~T.stringof~")");// use T.mangleof?
        metaI.kind=TypeKind.CustomK;
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        if (loopOp is null) s.serializationError("LazyArray missing loopOp",__FILE__,__LINE__);
        auto ac=s.writeArrayStart(null,size);
        FieldMetaInfo *elMetaInfoP=null;
        version(PseudoFieldMetaInfo){
            FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                getSerializationInfoForType!(T)());
            elMetaInfo.pseudo=true;
            elMetaInfoP=&elMetaInfo;
        }
        loopOp(delegate int(ref T el){
            s.writeArrayEl(ac,{ s.field(elMetaInfoP, el); } );
            return 0;
        });
        s.writeArrayEnd(ac);
    }
    void unserialize(Unserializer s){
        if (addOp is null) s.serializationError("LazyArray missing addOp",__FILE__,__LINE__);
        FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
            getSerializationInfoForType!(T)());
        elMetaInfo.pseudo=true;
        auto ac=s.readArrayStart(null);
        if (setLen !is null) {
            setLen(ac.sizeHint()); // use ac.length?
        }
        size_t pos=0;
        while(s.readArrayEl(ac,
            {
                T el=T.init;
                s.field(&elMetaInfo, el);
                addOp(el);
            } )) { }
        if (setLen !is null) {
            setLen(ac.length);
        }
    }
}

// wrapper to write out an associative array
struct LazyAA(K,V) {
    ulong size; /// output size
    int delegate(int delegate(ref K,ref V)) loopOp; /// output loop
    void delegate(K,V) addOp; /// add one element
    void delegate(ulong l) setLen; /// set the length (before addition with a guess, after with real size)
    
    /// if you just want to write out this is all that is needed
    static LazyAA opCall(int delegate(int delegate(ref K,ref V)) loopOp,ulong size=ulong.max){
        LazyAA res;
        res.size=size;
        res.loopOp=loopOp;
        return res;
    }
    /// if you just want to readin this is all that is needed
    static LazyAA opCall(void delegate(K,V) addOp,void delegate(ulong l) setLen=null){
        LazyAA res;
        res.addOp=addOp;
        res.setLen=setLen;
        return res;
    }
    /// initialize a complete (input/output) wrapper
    static LazyAA opCall(int delegate(int delegate(ref K,ref V)) loopOp,void delegate(K,V) addOp,
        ulong size=ulong.max,void delegate(ulong l) setLen=null){
        LazyAA res;
        res.size=size;
        res.loopOp=loopOp;
        res.addOp=addOp;
        res.setLen=setLen;
        return res;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(*this))("LazyAA!("~K.stringof~","~V.stringof~")");// use T.mangleof?
        metaI.kind=TypeKind.CustomK;
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }

    void serialize(Serializer s){
        if (loopOp is null) s.serializationError("LazyAA missing loopOp",__FILE__,__LINE__);
        FieldMetaInfo *valMetaInfoP=null;
        version(PseudoFieldMetaInfo){
            FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
            keyMetaInfo.pseudo=true;
            FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
            valMetaInfo.pseudo=true;
            valMetaInfoP=&valMetaInfo;
        }
        auto ac=s.writeDictStart(null,size,
            is(K==char[])||is(K==wchar[])||is(K==dchar[]));
        loopOp(delegate int(ref K key, ref V value){
            version(SerializationTrace) sout("X serializing associative array entry\n");
            version(PseudoFieldMetaInfo){
                s.writeEntry(ac,{ s.field!(K)(&keyMetaInfo, key); },
                    { s.field(&valMetaInfo, value); });
            } else {
                s.writeEntry(ac,{ s.field!(K)(cast(FieldMetaInfo*)null, key); },
                    { s.field(cast(FieldMetaInfo*)null, value); });
            }
            return 0;
        });
        s.writeDictEnd(ac);
    }

    void unserialize(Unserializer s){
        if (addOp is null) s.serializationError("LazyAA missing addOp",__FILE__,__LINE__);
        FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
        keyMetaInfo.pseudo=true;
        FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
        valMetaInfo.pseudo=true;
        K key;
        V value;
        auto ac=s.readDictStart(null,is(K==char[])||is(K==wchar[])||is(K==dchar[]));
        if (setLen !is null) {
            setLen(ac.sizeHint()); // use ac.length?
        }
        int iPartial=0;
        while (s.readEntry(ac,
            {
                s.field!(K)(&keyMetaInfo, key);
                if(++iPartial==2){
                    iPartial=0;
                    addOp(key,value);
                }
            },{
                s.field!(V)(&valMetaInfo, value);
                if(++iPartial==2){
                    iPartial=0;
                    addOp(key,value);
                }
            })) { key=K.init; value=V.init; }
        if (setLen !is null) {
            setLen(ac.length);
        }
    }
}

