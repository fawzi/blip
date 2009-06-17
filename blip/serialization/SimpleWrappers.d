module blip.serialization.SimpleWrappers;

struct LazyArray(T): Serializable {
    ulong size;
    int delegate(int delegate(ref T)) loopOp;
    this(int delegate(int delegate(ref T)) loop,ulong size=ulong.max){
        this.size=size;
        this.loopOp=loopOp;
    }
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("LazyArray!("~T.stringof~")");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void preSerialize(Serializer s){ }
    void postSerialize(Serializer s){ }
    void serialize(Serializer s){
        auto ac=s.writeArrayStart(null,size());
        mixin(sLoopPtr(rank,[""],`s.writeArrayEl(ac,{ s.field(cast(FieldMetaInfo*)null, *Ptr0); } );`,"i"));
        s.writeArrayEnd(ac);
    }
    if (is(T:Object)|| is(T:interface)){
        
    }
    
}