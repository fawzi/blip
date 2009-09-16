/// a simple serializer to string (for debugging)
/// author: fawzi
module blip.serialization.StringSerialize;
import blip.text.Stringify;
import blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;

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
