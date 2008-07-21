/*******************************************************************************
    Various utilities to convert methods that write to Print!(T),
    stream and writers to strings
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.Stringify;
import tango.io.Print;
import tango.io.stream.FormatStream;
import tango.io.Buffer;

T[] printToString(T)(void delegate(Print!(T))w){
    GrowBuffer buf=new GrowBuffer(capacity);
    Print!(T) stringIO=new FormatOutput(buf);
    w(stringIO);
    stringIO.flush();
    void[] data=buf.slice();
    assert(data.length%T.sizeof==0,"invalid (fractional) size in printToString buffer");
    T[] res=(cast(T*)data.ptr)[0..(data.length/t.sizeof)];
    return res;
}

T[] printToString(T)(Print!(T) delegate(Print!(T))w){
    GrowBuffer buf=new GrowBuffer(capacity);
    Print!(T) stringIO=new FormatOutput(buf);
    w(stringIO);
    stringIO.flush();
    void[] data=buf.slice();
    assert(data.length%T.sizeof==0,"invalid (fractional) size in printToString buffer");
    T[] res=(cast(T*)data.ptr)[0..(data.length/t.sizeof)];
    return res;
}
