module blip.text.TextParser;
import tango.io.stream.Buffer;
import Integer=tango.text.convert.Integer;
import Float=tango.text.convert.Float;
protected import tango.io.device.Conduit : InputFilter, InputBuffer, InputStream;
import Utf=tango.text.convert.Utf;
import tango.text.json.JsonEscape: unescape,escape;
import tango.core.Traits: RealTypeOf, ImaginaryTypeOf, ElementTypeOfArray;
import tango.io.Stdout;
import tango.math.Math;
import tango.io.model.IConduit;
import tango.io.stream.Format;
import tango.text.Regex;
import blip.text.Stringify;

/// returns the number of code points in the string str, raise if str contains invalid or 
/// partial characters (but does not explicitly validate)
size_t nCodePoints(T)(T[] str){
    static if (is(T==char)){ // optimized for mostly ascii content
        T* p=str.ptr;
        size_t l=str.length;
        size_t n=0;
        bool charLoop(T* pEnd){
            while (p!=pEnd){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T* pEnd){
            while (p!=pEnd){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)!=0) break;
            }
            return false;
        }
        if (l<8){
            if (charLoop(p+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        } else {
            T* pEnd=cast(T*)((cast(size_t)(str.ptr+l))&(~cast(size_t)7));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
            while (p<pEnd){
                if ((*(cast(int*)p))&0x80808080 ==0){
                    p+=4;
                    n+=4;
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        }
        return n;
    } else static if (is(T==wchar)){
        T* p=str.ptr;
        size_t n=0;
        bool charLoop(T*pEnd){
            while(p!=pEnd){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T*pEnd){
            while(p!=pEnd && ((cast(size_t)p)&7)!=0){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
            }
            return false;
        }
        size_t l=str.length;
        if (l<4){
            if (charLoop(p+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        } else {
            T*pEnd=cast(T*)((cast(size_t)(p+l))&(~(cast(size_t)7)));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
            while (p!=pEnd){
                int i= *(cast(int*)p);
                if ((i&0xF800_0000) != 0xD800_0000 && (i&0xF800) != 0xD800){
                    p+=2;
                    n+=2;
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        }
        return n;
    } else static if (is(T==dchar)) {
        return str.length;
    } else {
        static assert(0,"unexpected char type "~T.stringof);
    }
}

template convertToString(T=char){
    T[]convertToString(S)(S[]src,T[]dest=null){
        static if(is(T==S)){
            return src;
        } else static if(is(T==char)){
            return Utf.toString(src,dest);
        } else static if(is(T==wchar)){
            return Utf.toString16(src,dest);
        } else static if(is(T==dchar)){
            return Utf.toString32(src,dest);
        } else {
            static assert(0,"unexpected char type "~T.stringof);
        }
    }
}

debug(UnitTest){
    unittest{
        assert("abcè"w==cast(wchar[])"abcè","cast char->wchar are expected to work");
        assert(("abcè"d==cast(dchar[])"abcè"),"cast char->dchar are expected to work");
        assert("abcè"w=="abcè","comparison wchar,char are expected to work");
        assert(("abcè"d=="abcè"),"comparison dchar,char are expected to work");
        
        assert(nCodePoints("abc")==3);
        assert(nCodePoints("åbôd")==4);
        assert(nCodePoints("abc"w)==3);
        assert(nCodePoints("åbôd"w)==4);
        assert(nCodePoints("abc"d)==3);
        assert(nCodePoints("åbôd"d)==4);

        assert(nCodePoints("abcabcabcabc")==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc")==23);
        assert(nCodePoints("abcabcabcabc"w)==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc"w)==23);
        assert(nCodePoints("abcabcabcabc"d)==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc"d)==23);
    }
}

/// scans until it has the requested number of code points in the string str
/// raises if str contains invalid or contains partial characters (but does not explicitly validate)
size_t scanCodePoints(T)(T[] str,size_t nn){
    static if (is(T==char)){ // optimized for mostly ascii content
        T* p=str.ptr;
        size_t l=str.length;
        size_t n=0;
        bool charLoop(T* pEnd){
            while (p!=pEnd && n!=nn){
                if ((*p)&0x80){ // use the stride table instead?
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T* pEnd){
            while (p!=pEnd && n!=nn){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)!=0) break;
            }
            return false;
        }
        if (l<8){
            if (charLoop(p+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        } else {
            T* pEnd=cast(T*)((cast(size_t)(str.ptr+l))&(~cast(size_t)7));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
            while (p<pEnd){
                if ((*(cast(int*)p))&0x80808080 ==0){
                    p+=4;
                    n+=4;
                    if(n>=nn){
                        return cast(size_t)((p-str.ptr)-n+nn);
                    }
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        }
        if (n<nn) return IOStream.Eof;
        return cast(size_t)(p-str.ptr);
    } else static if (is(T==wchar)){
        T* p=str.ptr;
        size_t n=0;
        bool charLoop(T*pEnd){
            while(p!=pEnd && n!=nn){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T*pEnd){
            while(p!=pEnd && ((cast(size_t)p)&7)!=0 && n!=nn){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
            }
            return false;
        }
        size_t l=str.length;
        if (l<4){
            if (charLoop(p+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        } else {
            T*pEnd=cast(T*)((cast(size_t)(p+l))&(~(cast(size_t)7)));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
            while (p!=pEnd){
                int i= *(cast(int*)p);
                if ((i&0xF800_0000) != 0xD800_0000 && (i&0xF800) != 0xD800){
                    p+=2;
                    n+=2;
                    if(n>=nn){
                        return ((n>nn)?p-str.ptr-1:p-str.ptr);
                    }
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        }
        if (n<nn) return IOStream.Eof;
        return p-str.ptr;
    } else static if (is(T==dchar)) {
        if (str.length<nn) return IOStream.Eof;
        return nn;
    } else {
        static assert(0,"unsexpected char type "~T.stringof);
    }
}

/// extent of a slice of a buffer
enum SliceExtent{ Partial, Maximal, ToEnd }

/// a class that does a stream parser, for things in which white space amount
/// is not relevant (it is just a separator)
/// The source stream with which you initialize this is supposed to be valid UTF in
/// the native encoding of type T
/// this is quite geared toward the need of json deserialization
class TextParser(T) : InputFilter 
{
    private InputBuffer     source;
    protected T[]           slice;
    size_t maxTranscodingOverhead;
    bool skipMore;
    bool skippedWhitespace;
    T[] delims;
    long line,col;
    long oldLine,oldCol;
    
    /// position of the parsed token
    FormatOutput!(T) parserPos(FormatOutput!(T)s){
        s(cast(T[])"line:")(oldLine)(cast(T[])" col:")(oldCol)(cast(T[])" token:\"")(escape(slice))(cast(T[])"\"").newline;
        s(cast(T[])"context:<<")(cast(T[])source.slice)(">>").newline;
        return s;
    }
    /// ditto
    T[] parserPos(){
        scope s=new StringIO!(T)();
        return getString(parserPos(s));
    }
    /// exception during parsing (adds parser position info)
    class ParsingException:Exception{
        this(TextParser p,char[]desc,char[]filename,long line){
            super(desc~" parsing "~convertToString!()(p.parserPos()),filename,line);
        }
    }
    /// exception for when the cached part is too small
    class SmallCacheException:ParsingException{
        this(TextParser p,char[]desc,char[]filename,long line){
            super(p,desc,filename,line);
        }
    }
    /// raises a parse exception
    void parseError(char[]desc,char[]filename,long line){
        throw new ParsingException(this,desc,filename,line);
    }
    /// raises a SmallCacheException
    void smallCacheError(char[]desc,char[]filename,long line){
        throw new SmallCacheException(this,desc,filename,line);
    }
    /// updates the position of the parser in the file
    void updatePos(T[] str){
        oldLine=line;
        oldCol=col;
        foreach(c;str){
            if (c=='\n'){
                ++line; col=0;
            } else {
                ++col;
            }
        }
    }
    /// scans the contents and is supposed to set slice to something non zero if
    /// it has success
    final bool next (size_t delegate (T[],SliceExtent) scan,bool setSlice=true)
    {
        if (!skippedWhitespace) skipWhitespace();
        SliceExtent sliceE=SliceExtent.Partial;
        BufferInput buf=cast(BufferInput)source;
        if (buf !is null){
            if (buf.position == 0 && buf.capacity-buf.limit <=maxTranscodingOverhead){
                sliceE=SliceExtent.Maximal;
            }
        } else {
            sliceE=SliceExtent.ToEnd;
        }
        size_t nonGrow=maxTranscodingOverhead;
        bool matchSuccess=false;
        while (source.read(delegate size_t(void[] rawData)
                {
                    T[] data=Utf.cropRight((cast(T*)rawData.ptr)[0..rawData.length/T.sizeof]);
                    auto res=scan(data,sliceE);
                    if (res != Eof){
                        if (setSlice) slice=data[0..res];
                        updatePos(data[0..res]);
                        matchSuccess=res!=0;
                        return T.sizeof*res;
                    } else {
                        if (setSlice) slice=[];
                        return Eof;
                    }
                }) is Eof)
        {
            if (sliceE!=SliceExtent.Partial) {
                if (sliceE==SliceExtent.ToEnd) {
                    return false;
                } else {
                    smallCacheError("match needs more space, but buffer is not large enough",__FILE__,__LINE__);
                }
            }
            if (buf.position != 0){
                buf.compress;
            }
            auto oldWriteable=buf.capacity-buf.limit;
            // read another chunk of data
            if (buf.readMore() is Eof) {
                sliceE=SliceExtent.ToEnd;
            } else if (buf.capacity-buf.limit <= maxTranscodingOverhead) {
                sliceE=SliceExtent.Maximal;
            } else if (oldWriteable==buf.capacity-buf.limit){
                // did not grow
                 // worst case should read at least a byte per read attempt,
                 // so transcoding might not happen before maxTranscodingOverhead iterations
                if (nonGrow==0){
                    smallCacheError("did not grow and space available bigger than maxTranscodingOverhead",__FILE__,__LINE__);
                }
                --nonGrow;
            } else {
                nonGrow=maxTranscodingOverhead;
            }
        }
        skippedWhitespace=false;
        return matchSuccess;
    }
    /// returns a separator
    T[] getSeparator(bool raise=false){
        auto res=next(delegate size_t(T[]data,SliceExtent se){
            if (data.length==0) {
                switch(se){
                case SliceExtent.Partial:
                    return Eof;
                case SliceExtent.Maximal:
                    smallCacheError("no characters in buffer",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    return 0;
                }
                return 0;
            }
            auto c=data[0];
            for (size_t j=0;j!=delims.length;++j){
                if (delims[j]==c) return 1;
            }
            return 0;
        });
        if (raise && !res) parseError("no characters in buffer",__FILE__,__LINE__);
        return slice;
    }
    /// returns the next token if one tokenizes with just string and separators
    T[]nextToken(){
        T[] str;
        if (!getSeparator())
            if (!next(&scanString))
                return null;
        return slice;
    }
    /// check if the scan function would give a match without actually reading it
    /// (discards the previous matches though)
    bool check(size_t delegate(T[],SliceExtent) scan){
        bool success=false;
        next(delegate size_t(T[] data, SliceExtent se){
            auto res=scan(data,se);
            if (res == Eof){
                return Eof;
            } else {
                success=res!=0;
                return 0;
            }
        });
        return success;
    }
    /// scans up to the regexp, slice is set to the scanned part excluding the regexp
    final bool scanToRegexp(RegExpT!(T) regex){
        return next(delegate size_t(T[]data,SliceExtent se){
                if (regex.test (data))
                {
                    size_t start = regex.registers_[0];
                    size_t finish = regex.registers_[1];
                    slice=data[0..start];
                    return finish; 
                }
                return Eof;
            },false);
    }
    /// matches a regexp, slice is set to the matched part (i.e. to the regexp)
    final bool matchRegexp(RegExpT!(T) regexp){
        assert(0,"unimplemented");
    }
    
    /// scans whitespace (for skipWhitespace)
    protected size_t scanWhitespace (T[] data,SliceExtent se){
        skipMore=false;
        for(size_t i=0;i!=data.length;++i){
            auto c=data[i];
            if (!(c==' '||c=='\t'||c=='\r'||c=='\n')){
                return i;
            }
        }
        switch(se){
            case SliceExtent.Partial : return Eof;
            case SliceExtent.Maximal :
                skipMore=true;
            case SliceExtent.ToEnd :
                return data.length;
        }
        parseError("invalid SliceExtent",__FILE__,__LINE__);
    }
    /// skips whitespace
    bool skipWhitespace(){
        bool didSkip=false;
        do {
            skippedWhitespace=true;
            if (next(&scanWhitespace) && source.slice.length!=0) {
                didSkip=true;
            }
        } while (skipMore);
        skippedWhitespace=true;
        return didSkip;
    }
    /// reads n codepoints
    T[] readNCodePoints(size_t n){
        if (!next(delegate size_t(T[] data,SliceExtent se){
            return scanCodePoints(data,n);
        }))
        return slice;
    }
    /// scans an int string (base 10, accept also hex?)
    protected size_t scanInt (T[] data,SliceExtent se){
        size_t i=0;
        auto c=data[i];
        if (data.length>0 && c=='+' || c=='-') ++i;
        for(;i!=data.length;++i){
            c=data[i];
            if (c<'0'||c>'9'){
                return i;
            }
        }
        switch(se){
            case SliceExtent.Partial : return Eof;
            case SliceExtent.Maximal :
            smallCacheError("int did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
            case SliceExtent.ToEnd :
                return data.length;
        }
        parseError("invalid SliceExtent",__FILE__,__LINE__);
    }
    /// scans a float string
    protected size_t scanFloat(T[] data,SliceExtent se){
        size_t i=0;
        if (data.length>0 && data[i]=='+' || data[i]=='-') ++i;
        for(;i!=data.length;++i){
            if (data[i]<'0'||data[i]>'9') break;
        }
        if (data[i]=='.') ++i;
        for(;i!=data.length;++i){
            if (data[i]<'0'||data[i]>'9') break;
        }
        if (data.length>i && (data[i]=='e'||data[i]=='E'||data[i]=='d'||data[i]=='D')){
            ++i;
            if (data.length>i && (data[i]=='+' || data[i]=='-')) ++i;
            for(;i!=data.length;++i){
                if (data[i]<'0'||data[i]>'9') break;
            }
        }
        if (i<data.length) return i;
        switch(se){
            case SliceExtent.Partial : return Eof;
            case SliceExtent.Maximal :
            smallCacheError("float did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
            case SliceExtent.ToEnd :
                return data.length;
        }
        parseError("invalid SliceExtent",__FILE__,__LINE__);
    }
    /// scans either a double quoted string or a token delimited by whitespace and ,;:{}
    protected size_t scanString (T[] data,SliceExtent se){
        size_t i=0;
        if (data.length>0 && data[i]=='"'){
            ++i;
            bool quote=false;
            bool found=false;
            for(;i!=data.length;++i){
                if (quote)
                    quote=false;
                else if (data[i]=='"') {
                    found=true;
                    ++i;
                    break;
                } else {
                    quote=data[i]=='\\';
                }
            }
            if (found) return i;
            switch(se){
                case SliceExtent.Partial : return Eof;
                case SliceExtent.Maximal :
                smallCacheError("quoted string did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd :
                parseError("quoted string was not closed before EOF",__FILE__,__LINE__);
            }
        } else {
            for(;i!=data.length;++i){
                auto c=data[i];
                if (c==' '||c=='\t'||c=='\r'||c=='\n'){
                    return i;
                }
                for (size_t j=0;j!=delims.length;++j){
                    if (delims[j]==c) return i;
                }
            }
            switch(se){
                case SliceExtent.Partial : return Eof;
                case SliceExtent.Maximal :
                smallCacheError("string did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd :
                    return data.length;
            }
        }
        parseError("invalid SliceExtent",__FILE__,__LINE__);
    }
    /// if longLived is true the result is guaranteed not to contain slices of the buffer
    /// (that might become invalid)
    void readValue(U)(ref U t,bool longLived=true){
        static if(is(U==byte)||is(U==ubyte)||is(U==short)||is(U==ushort)
            ||is(U==int)||is(U==uint)||is(U==long)||is(U==ulong))
        {
            if (!next(&scanInt)) parseError("error scanning int",__FILE__,__LINE__);
            assert(slice.length>0,"error slice too small");
            static if (is(U==ubyte)||is(U==ushort)||is(U==uint)||is(U==ulong)){
                if(slice[0]=='-') parseError("negative unsigned value",__FILE__,__LINE__);
            }
            static if (is(U==byte)||is(U==ubyte)||is(U==short)||is(U==ushort)||is(U==int)){
                t=cast(U)Integer.toInt(slice);
            } else static if (!is(U==ulong)){
                t=cast(U)Integer.toLong(slice);
            } else {
                if(slice[0]=='+') slice=slice[1..$];
                t=Integer.convert(slice);
            }
        } else static if(is(U==float)||is(U==double)||is(U==real)) {
            if (!next(&scanFloat)) parseError("error scanning float",__FILE__,__LINE__);
            assert(slice.length>0,"error slice too small");
            static if (is(U==float)||is(U==double)||is(U==real)){
                t=cast(U)Float.toFloat(slice);
            } else static if (!is(U==ulong)){
                t=cast(U)Integer.toLong(slice);
            } else {
                if(slice[0]=='+') slice=slice[1..$];
                t=Integer.convert(slice);
            }
        } else static if (is(U==ifloat)||is(U==idouble)||is(U==ireal)){
            RealTypeOf!(U) a;
            readValue(a);
            if (!next(delegate size_t(T[] data,SliceExtent se)
                {
                    if(data.length>0 && (data[0]=='i'||data[0]=='I')){
                        return 1;
                    } else if (data.length<3){
                        return Eof;
                    } else if (data[0..3]==cast(T[])"*1i")
                    return Eof;
                })) parseError("expected an i of *1i suffix for imaginary numbers",__FILE__,__LINE__);
            t=cast(U)(a*1i);
        } else static if (is(U==cfloat)||is(U==cdouble)||is(U==creal)){
            RealTypeOf!(U) a;
            readValue(a);
            skipWhitespace();
            if (!next(delegate size_t(T[] data,SliceExtent se)
                {
                    if(data.length>0 && (data[0]=='+' || data[0]=='-')){
                        return 1;
                    }
                    return Eof;
                }))
            {
                parseError("expected real *plus* imaginary for complex number",
                    __FILE__,__LINE__);
            }
            skipWhitespace();
            ImaginaryTypeOf!(U) b;
            readValue(b);
            t=cast(U)(a+b);
        } else static if(is(U==bool)) { // validation should be tighter?
            if (!next(&scanString)) parseError("error scanning bool",__FILE__,__LINE__);
            assert(slice.length>0,"error slice too small");
            if (slice[0]=='0' && slice.length==1 ||
                slice[0]=='f' || slice[0]=='n'||slice[0]=='F' || slice[0]=='N'){
                t=false;
            } else if (slice[0]=='1' && slice.length==1 ||
                slice[0]=='t' || slice[0]=='y' || slice[0]=='j' || slice[0]=='s' ||
                slice[0]=='T' || slice[0]=='Y' || slice[0]=='J' || slice[0]=='S'){
                t=true;
            } else {
                parseError("unexpected token for boolean: "~slice,
                    __FILE__,__LINE__);
            }
        } else static if(is(U==T[])) {
            if (!next(&scanString)) parseError("error scanning string",__FILE__,__LINE__);
            if (slice.length>0 && slice[0]=='"'){
                t=unescape(slice[1..$-1]);
            } else {
                t=slice;
            }
            if(longLived) t=t.dup;
        } else static if(is(U==char[])||is(U==wchar[])||is(U==dchar[])) {
            alias ElementTypeOfArray!(U) S;
            T[] str;
            readValue(str,false);
            static if (is(S==char)){
                t=Utf.toString(str,t);
            } else static if (is(S==wchar)){
                t=Utf.toString16(str,t);
            } else static if (is(S==dchar)){
                t=Utf.toString32(str,t);
            } else {
                static assert(0,"unsupported str type "~S.stringof);
            }
        } else {
            T.triggerError;
            // static assert(0,"unsupported type "~U.stringof);
        }
    }
    
    /// skips the given string from the input
    bool skipString(T[]str,bool raise=true){
        if (next(delegate size_t(T[] data,SliceExtent se){
            if (str.length>data.length) {
                switch(se){
                case SliceExtent.Partial:
                    return Eof;
                case SliceExtent.Maximal:
                    smallCacheError("skipString string is larger than buffer window ("~Integer.toString(data.length)~"<"~Integer.toString(str.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    return 0;
                }
            }
            if (str == data[0..str.length]){
                return str.length;
            } else {
                return 0;
            }
        })){
            return true;
        } else {
            if (raise) parseError("failed to skip string '"~convertToString!()(str)~"'",__FILE__,__LINE__);
            return false;
        }
    }
    /// skips the given string from the input, which might be quoted or not in the text
    bool skipString2(T[]str,bool raise=true){
        if(next(delegate size_t(T[] data,SliceExtent se){
            if (str.length>data.length){
                switch(se){
                case SliceExtent.Partial:
                    return Eof;
                case SliceExtent.Maximal:
                    parseError("skipString2 string is larger than buffer window ("~Integer.toString(data.length)~"<"~Integer.toString(str.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    return 0;
                }
            }
            if (str == data[0..str.length]){
                return str.length;
            } else {
                if (data[0]=='"'){
                    auto str2=escape(str);
                    if (data.length<str.length+2){
                        switch(se){
                        case SliceExtent.Partial:
                            return Eof;
                        case SliceExtent.Maximal:
                            smallCacheError("skipString string is larger than buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
                        case SliceExtent.ToEnd:
                            return 0;
                        }
                    }
                    if (data[1..str2.length+1]==str2){
                        return str2.length+2;
                    }
                }
                return 0;
            }
        })){
            return true;
        } else {
            if (raise) parseError("failed to skip string2 '"~convertToString!()(str)~"'",__FILE__,__LINE__);
            return false;
        }
    }

    /// Instantiate with a buffer
    this(InputStream stream = null,T[]delims=cast(T[])",;:{}[]",size_t maxTranscodingOverhead=6)
    {       
        super (stream);
        if (stream)
            set (stream);
        this.maxTranscodingOverhead=maxTranscodingOverhead;
        this.delims=delims;
    }

    /// Set the provided stream as the scanning source
    TextParser set (InputStream stream)
    {
        assert (stream);
        source = BufferInput.create (stream);
        super.source = source;
        slice=[];
        return this;
    }

    /// Return the current token as a slice of the content
    final T[] get ()
    {
        return slice;
    }
    /// easy to use wisper interface
    TextParser opCall(U)(ref U t){
        readValue!(U)(t);
        return this;
    }
}

debug(UnitTest){
    import tango.io.device.Array;
    unittest{
        auto p=new TextParser!(char)(new Array("12tz_rk tt 23.4 +7.2i \t6.4+3.2i \"a string with space\" \"escapedString\\\"\"\n"));
        int i;
        real r;
        ireal ir;
        creal cr;
        char[] s;
        wchar[] ws;
        dchar[] ds;
        p(i);
        assert(i==12);
        p(s)(ws);
        assert(s=="tz_rk");
        assert(ws=="tt"w);
        p(r)(ir)(cr);
        assert(abs(r-23.4)<1.e-10);
        assert(abs(ir-7.2i)<1.e-10);
        assert(abs(cr-(6.4+3.2i))<1.e-10);
        p(s)(ds);
        assert(s=="a string with space");
        assert(ds==`escapedString"`d);
    }
}

