/*******************************************************************************
    Various utilities to convert methods that write to Print!(T),
    stream and writers to strings
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.Stringify;
import tango.io.Print;
import tango.io.Buffer;
import tango.text.convert.Format;
import tango.text.convert.Layout;
import blip.TemplateFu: nArgs;

/// Layout singleton, allocated only upon usage
class defaultFormatter(T){
    static Layout!(T) formatter;
    static this()
    {
        static if (is(T==char)) {
            formatter = tango.text.convert.Format.Format;
        } else {
            formatter = new Layout!(T);
        }
    }
}

/// A Print!(T) instance that collects all the writes into a string
class StringIO(T=char): Print!(T){
    private GrowBuffer buf;
    /// creates a Stringify object
    this(bool flush=false,uint size = 1024, uint increment = 1024){
        buf=new GrowBuffer(size,increment);
        super(defaultFormatter!(T).formatter,buf);
        super.flush = flush;
    }
    /// returns the string written so far (uses the internal buffer, further writes, clear,...
    /// will invalidate it)
    T[] getString(){
        flush();
        void[] data=buf.slice();
        assert(data.length%T.sizeof==0,"invalid (fractional) size in printToString buffer");
        T[] res=(cast(T*)data.ptr)[0..(data.length/T.sizeof)];
        return res;
    }
    /// clears the buffer (the pointer returned by getString will become invalid)
    void clear(){
        buf.clear;
    }
}

/// nice to use utf8 version of StringIO
alias StringIO!() Stringify;

/// to build expressions hiding the cast needed by non covariant return type
/// (Print!(T) instead of StringIO!(T))
T[] getString(T)(Print!(T) p){
    StringIO!(T) s=cast(StringIO!(T))p;
    assert(s,"Print!(T) not castable to StringIO");
    return s.getString();
}

debug(UnitTest){
    unittest{
        char[] s=getString((new Stringify())("Stringify test:")(1)(2.0)(3L).newline);
        assert(s=="Stringify test:12.003\n","unexpected string by Stringify");
    }
}

T[] printToString(T)(void delegate(Print!(T))w){
    StringIO!(T) s=new StringIO!(T)();
    w(s);
    return s.getString();
}

T[] printToString(T)(Print!(T) delegate(Print!(T))w){
    StringIO!(T) s=new StringIO!(T)();
    w(s);
    return s.getString();
}
