/// some text utilities (trim, contains)
///
/// wrapping of a tango module
module blip.text.Utils;
public import tango.text.Util:trim,contains;

/// escapes a string with a c like notation
void cEscapeString(scope void delegate(in char[])outF,char[] str){
    size_t wrote=0;
    foreach(i,c;str){
        switch (c){
        case '\\','\"':
            outF(str[wrote..i]);
            outF("\\");
            wrote=i;
            break;
        case '\n':
            outF(str[wrote..i]);
            outF("\\n");
            wrote=i+1;
            break;
        case '\r':
            outF(str[wrote..i]);
            wrote=i+1;
            break;
        default:
            break;
        }
    }
    outF(str[wrote..$]);
}
