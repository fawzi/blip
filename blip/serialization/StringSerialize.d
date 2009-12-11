/// a simple serializer to string (for debugging)
/// author: fawzi
module blip.serialization.StringSerialize;
import blip.serialization.JsonSerialization;
import blip.serialization.SBinSerialization;
import blip.serialization.SerializationBase;
import blip.container.GrowableArray;

/// utility method to serialize just one object to an array of the given type
U[] serializeToArray(T,U=char)(T t,U[] buf=cast(U[])null){
    U[256] buf2;
    scope GrowableArray!(U) arr;
    if (buf.length>0){
        arr=new GrowableArray!(U)(buf,0,GASharing.GlobalNoFree);
    } else {
        arr=new GrowableArray!(U)(buf2,0,GASharing.Local);
    }
    serializeToSink(&arr.appendArr,t);
    return arr.takeData(true);
}

void serializeToSink(U,T)(void delegate(T[]) sink,U t){
    static if (is(T==char)||is(T==wchar)||is(T==dchar)){
        auto s=new JsonSerializer!(T)(sink);
        s(t);
    } else static if (is(T==ubyte)||is(T==void)){
        void delegate(void[]) sink2;
        sink2.funcptr=cast(typeof(sink2.funcptr))sink.funcptr;
        sink2.ptr=cast(typeof(sink2.ptr))sink.ptr;
        auto s=new SBinSerializer(sink2);
        s(t);
    } else {
        static assert(0,"unsupported sink type "~T.stringof);
    }
}

// useful to be mixed in in serializable objects to give desc and toString...
template printOut(){
    char[] toString(){
        static if (is(typeof(*T.init)==struct))
            return serializeToArray(*this);
        else
            return serializeToArray(this);
    }
    
    void desc(void delegate(char[]) sink){
        static if (is(typeof(*T.init)==struct))
            serializeToSink(sink,*this);
        else
            serializeToSink(sink,this);
    }
}

/// returns true if the string representation of a and b is the same
/// useful for debugging and comparing read in floats to the one that were outputted
bool eqStr(T)(T a,T b){
    static if (is(T:cfloat)||is(T:cdouble)||is(T:creal)) {
        if (a==b) return 1;
    } else {
        if (a is b) return 1;
    }
    char[128] buf1,buf2;
    auto aStr=serializeToArray(a,buf1);
    auto bStr=serializeToArray(b,buf2);
    return aStr==bStr;
}

