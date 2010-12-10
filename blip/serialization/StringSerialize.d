/// a simple serializer to string (for debugging)
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
module blip.serialization.StringSerialize;
import blip.serialization.JsonSerialization;
import blip.serialization.SBinSerialization;
import blip.serialization.SerializationBase;
import blip.container.GrowableArray;
public import blip.Comp;

/// utility method to serialize just one object to an array of the given type
U[] serializeToArray(T,U=char)(T t,U[] buf=cast(U[])null){
    U[256] buf2;
    LocalGrowableArray!(U) arr;
    if (buf.length>0){
        arr.init(buf,0,GASharing.GlobalNoFree);
    } else {
        arr.init(buf2,0,GASharing.Local);
    }
    serializeToSink(&arr.appendArr,t);
    return arr.takeData();
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
    string toString(){
        static if (is(typeof(*T.init)==struct))
            return cast(string)serializeToArray(*this);
        else
            return cast(string)serializeToArray(this);
    }
    
    void desc(void delegate(cstring) sink){
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

