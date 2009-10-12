/// a simple serializer to string (for debugging)
/// author: fawzi
module blip.serialization.StringSerialize;
import blip.text.Stringify;
import blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import tango.io.stream.Format;

/// serializes to string
class StringSerializeT(T=char){
  /// direct access to the underlying formatter
  StringIO!(T) formatter;
  Serializer serializer;
  this(){
    formatter=new StringIO!(T)();
    serializer=new JsonSerializer!(T)(formatter);
  }
  /// serializes the argument
  StringSerializeT opCall(T)(T t){
    serializer(t);
    return this;
  }
  /// returns what has been written so far as string (and clears the stored string)
  T[] getString(){
    auto res=formatter.getString().dup;
    formatter.clear();
    return res;
  }
}

alias StringSerializeT!() StringSerialize;

/// utility method to serialize just one object to string
char[] serializeToString(T)(T t){
  scope s=new StringSerialize();
  s(t);
  return s.getString();
}

FormatOutput!(T) serializeToFormatter(U,T)(FormatOutput!(T)formatter,U t){
    scope serializer=new JsonSerializer!(T)(formatter);
    serializer(t);
    return serializer;
}

template printOut(){
    char[] toString(){
        static if (is(typeof(*T.init)==struct))
            return serializeToString(*this);
        else
            return serializeToString(this);
    }
    
    FormatOutput!(char)desc(FormatOutput!(char)f){
        static if (is(typeof(*T.init)==struct))
            serializeToFormatter(f,*this);
        else
            serializeToFormatter(f,this);
    }
}
