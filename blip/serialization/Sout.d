/// a serializer to Stdout
/// author: fawzi
module blip.serialization.Sout;
import blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import tango.io.Stdout;

/// the serializer to Stdout
Serializer Sout;
static this(){
    Sout=new JsonSerializer!()(Stdout);
}
