/*******************************************************************************
    Various utilities to convert methods that write to FormatOutput!(T),
    stream and writers to strings
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.text.Stringify;
import tango.io.stream.Format;
import tango.io.device.Array;
import tango.text.convert.Format;
import tango.text.convert.Layout;
import blip.TemplateFu: nArgs;
import blip.BasicModels;

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

/// A FormatOutput!(T) instance that collects all the writes into a string
class StringIO(T=char): FormatOutput!(T){
    private Array buf;
    /// creates a Stringify object
    this(bool flush=false,uint size = 1024, uint increment = 1024){
        buf=new Array(size,increment);
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
/// (FormatOutput!(T) instead of StringIO!(T))
T[] getString(T)(FormatOutput!(T) p){
    StringIO!(T) s=cast(StringIO!(T))p;
    assert(s,"FormatOutput!(T) not castable to StringIO");
    return s.getString();
}

debug(UnitTest){
    unittest{
        char[] s=getString((new Stringify())("Stringify test:")(1)(2.0)(3L).newline);
        assert(s=="Stringify test:12.003\n","unexpected string by Stringify");
    }
}

T[] printToString(T)(void delegate(FormatOutput!(T))w){
    StringIO!(T) s=new StringIO!(T)();
    w(s);
    return s.getString();
}

T[] printToString(T)(FormatOutput!(T) delegate(FormatOutput!(T))w){
    StringIO!(T) s=new StringIO!(T)();
    w(s);
    return s.getString();
}

/// returns true if the string representation of a and b is the same
/// useful for debugging and comparing read in floats to the one that were outputted
bool eqStr(T)(T a,T b){
    if (a is b) return 1;
    auto aStr=getString(writeDesc!(T)(new Stringify(),a));
    auto bStr=getString(writeDesc!(T)(new Stringify(),b));
    return aStr==bStr;
}
