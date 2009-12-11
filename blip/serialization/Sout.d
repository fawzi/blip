/// serializer to Stdout
module blip.serialization.Sout;
import blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import blip.io.Console;

Serializer Sout;
static this(){
    Sout=new JsonSerializer!()(sout);
}