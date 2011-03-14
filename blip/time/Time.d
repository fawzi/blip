/// Time structures (for timestamps)
///
/// wrapping of a tango module
module blip.time.Time;
public import tango.time.Time:Time;
import blip.serialization.Serialization;

/// add serialization of Time struct...
static ClassMetaInfo timeMetaI;
/// serialization of Time struct
void serializeTime(Serializer s,ClassMetaInfo mInfo,void* o){
    assert(mInfo is timeMetaI);
    auto t=cast(Time*)o;
    auto ticks=t.ticks;
    s.field(mInfo[0],ticks);
}
/// unserialization of Time struct
void  unserializeTime(Unserializer s,ClassMetaInfo mInfo,void* o){
    assert(mInfo is timeMetaI);
    auto t=cast(Time*)o;
    long ticks;
    s.field(mInfo[0],ticks);
    *t=Time(ticks);
}
static this(){
    auto h=new ExternalSerializationHandlers;
    h.serialize=&serializeTime;
    h.unserialize=&unserializeTime;
    timeMetaI=ClassMetaInfo.createForType!(Time)("blip.Time","represents an absolute time");
    timeMetaI.addFieldOfType!(long)("ticks","the ticks since the epoch");
    timeMetaI.externalHandlers=h;
}
