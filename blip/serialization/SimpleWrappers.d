/// custom wrappers that write out or read simple basic types (arrays, associative arrays)
/// these types are "invisible" in the sense that in the serialized form they are indistinguishible
/// from arrays and associative arrays
module blip.serialization.SimpleWrappers;
import blip.serialization.SerializationBase;

// wrapper to write out an array
struct LazyArray(T) {
    ulong size; /// output size
    int delegate(int delegate(ref T)) loopOp; /// output loop
    void delegate(T) addOp; /// add one element
    void delegate(size_t l) setLen; /// set the length (before addition with a guess, after with real size)
    
    /// if you just want to write out this is all that is needed
    this(int delegate(int delegate(ref T)) loop,ulong size=ulong.max){
        this.size=size;
        this.loopOp=loopOp;
    }
    /// if you just want to readin this is all that is needed
    this(void delegate(T) addOp,void delegate(size_t l) setLen=null){
        this.addOp=addOp;
        this.setLen=setLen;
    }
    /// initialize a complete (input/output) wrapper
    this(int delegate(int delegate(ref T)) loop,void delegate(T) addOp,
        ulong size=ulong.max,void delegate(size_t l) setLen=null){
        this.size=size;
        this.loopOp=loopOp;
        this.addOp=addOp;
        this.setLen=setLen;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("LazyArray!("~T.stringof~")");// use T.mangleof?
        metaI.kind=TypeKind.CustomK;
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        if (loopOp is null) s.serializationError("LazyArray missing loopOp",__FILE__,__LINE__);
        auto ac=s.writeArrayStart(null,size());
        version(PseudoFieldMetaInfo){
            FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                getSerializationInfoForType!(T)());
        } else {
            FieldMetaInfo elMetaInfo=null;
        }
        elMetaInfo.pseudo=true;
        loopOp(delegate int(ref T el){
            s.writeArrayEl(ac,{ s.field(elMetaInfo, el); } );
            return 0;
        });
        s.writeArrayEnd(ac);
    }
    Serializable preUnserialize(Unserializer s){ return this; }
    Serializable postUnserialize(Unserializer s){ return this; }
    void unserialize(Unserializer s){
        if (addOp is null) s.serializationError("LazyArray missing addOp",__FILE__,__LINE__);
        FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
            getSerializationInfoForType!(T)());
        elMetaInfo.pseudo=true;
        auto ac=readArrayStart(fieldMeta);
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
    void delegate(size_t l) setLen; /// set the length (before addition with a guess, after with real size)
    
    /// if you just want to write out this is all that is needed
    this(int delegate(int delegate(ref K,ref V)) loop,ulong size=ulong.max){
        this.size=size;
        this.loopOp=loopOp;
    }
    /// if you just want to readin this is all that is needed
    this(void delegate(K,V) addOp,void delegate(size_t l) setLen=null){
        this.addOp=addOp;
        this.setLen=setLen;
    }
    /// initialize a complete (input/output) wrapper
    this(int delegate(int delegate(ref K,ref V)) loop,void delegate(K,V) addOp,
        ulong size=ulong.max,void delegate(size_t l) setLen=null){
        this.size=size;
        this.loopOp=loopOp;
        this.addOp=addOp;
        this.setLen=setLen;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("LazyAA!("~T.stringof~")");// use T.mangleof?
        metaI.kind=TypeKind.CustomK;
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        if (loopOp is null) s.serializationError("LazyAA missing loopOp",__FILE__,__LINE__);
        version(PseudoFieldMetaInfo){
            FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
            keyMetaInfo.pseudo=true;
            FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
            valMetaInfo.pseudo=true;
        }
        auto ac=writeDictStart(fieldMeta,t.length,
            is(K==char[])||is(K==wchar[])||is(K==dchar[]));
        loopOp(delegate int(ref K key, ref V value){
            version(SerializationTrace) Stdout.formatln("X serializing associative array entry").newline;
            version(PseudoFieldMetaInfo){
                writeEntry(ac,{ s.field!(K)(&keyMetaInfo, key); },
                    { s.field(&valMetaInfo, value); });
            } else {
                writeEntry(ac,{ s.field!(K)(cast(FieldMetaInfo*)null, key); },
                    { s.field(cast(FieldMetaInfo*)null, value); });
            }
        });
        writeDictEnd(ac);
    }
    Serializable preUnserialize(Unserializer s){ return this; }
    Serializable postUnserialize(Unserializer s){ return this; }
    void unserialize(Unserializer s){
        if (addOp is null) s.serializationError("LazyAA missing addOp",__FILE__,__LINE__);
        FieldMetaInfo keyMetaInfo=FieldMetaInfo("key","",getSerializationInfoForType!(K)());
        keyMetaInfo.pseudo=true;
        FieldMetaInfo valMetaInfo=FieldMetaInfo("val","",getSerializationInfoForType!(V)());
        valMetaInfo.pseudo=true;
        K key;
        V value;
        auto ac=readDictStart(fieldMeta,is(K==char[])||is(K==wchar[])||is(K==dchar[]));
        if (setLen !is null) {
            setLen(ac.sizeHint()); // use ac.length?
        }
        int iPartial=0;
        while (readEntry(ac,
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

