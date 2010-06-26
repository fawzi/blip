/// Stream parser for string based parsing, especially for things where
/// white space amount is not relevant
///
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
module blip.text.TextParser;
import tango.io.stream.Buffered;
import Integer=tango.text.convert.Integer;
import Float=tango.text.convert.Float;
protected import tango.io.device.Conduit : InputFilter, InputBuffer, InputStream;
import tango.text.json.JsonEscape: unescape,escape;
import blip.core.Traits: RealTypeOf, ImaginaryTypeOf, ElementTypeOfArray;
import blip.math.Math;
import tango.io.model.IConduit;
import tango.text.Regex;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import blip.text.UtfUtils;
import blip.BasicModels;
import blip.io.StreamConverters: ReadHandler,toReaderChar;

/// a class that does a stream parser, for things in which white space amount
/// is not relevant (it is just a separator)
/// The source stream with which you initialize this is supposed to be valid UTF in
/// the native encoding of type T
/// this is quite geared toward the need of json deserialization
/// it is not really a parser but can be used to build one
/// regexp could be used to represent most scan functions, unfortunately it does not work
class TextParser(T) : InputFilter 
{
    private InputBuffer     source;
    protected T[]           slice;
    size_t maxTranscodingOverhead;
    bool skippedWhitespace;
    bool newlineIsSpace; /// newline counts as space
    T[] delims;
    long line,col;
    long oldLine,oldCol,charPos,oldCharPos;
    enum CommentType{ None, Whitespace, Line } // add nested comments?
    CommentType inComment;
    bool skipComments;
    
/+    /// gives back the current slice (deprecated in favor of peek)
    void unget(){
        line=oldLine;
        col=oldCol;
        source.seek (-cast(long)max(slice.length,charPos-oldCharPos), IOStream.Anchor.Current);
        charPos=oldCharPos;
        slice=slice[0..0];
    }+/
    
    /// position of the parsed token
    void parserPos(void delegate(char[]) s){
        dumper(s)("line:")(oldLine)(" col:")(oldCol)(" token:\"")(convertToString!(char)(escape(slice)))("\"\n");
        auto txt=cast(T[])source.slice;
        if (txt.length>250) txt=txt[0..250];
        txt=cropRight(txt);
        dumper(s)("next text:...<<")(convertToString!(char)(txt))(">>...\n");
    }
    /// exception during parsing (adds parser position info)
    static class ParsingException:Exception{
        this(TextParser p,char[]desc,char[]filename,long line,Exception next=null){
            super(collectAppender(delegate void(CharSink s){ s(desc); s(" parsing "); p.parserPos(s); }),filename,line,next);
        }
    }
    /// exception for when the cached part is too small
    static class SmallCacheException:ParsingException{
        this(TextParser p,char[]desc,char[]filename,long line){
            super(p,desc,filename,line);
        }
    }
    /// exception for when eof is found unexpectedly
    static class EofException:ParsingException{
        this(TextParser p,char[]desc,char[]filename,long line){
            super(p,desc,filename,line);
        }
    }
    /// raises a parse exception
    void parseError(char[]desc,char[]filename,long line,Exception next=null){
        throw new ParsingException(this,desc,filename,line,next);
    }
    /// raises a SmallCacheException
    void smallCacheError(char[]desc,char[]filename,long line){
        throw new SmallCacheException(this,desc,filename,line);
    }
    /// updates the position of the parser in the file
    void updatePos(T[] str){
        oldLine=line;
        oldCol=col;
        oldCharPos=charPos;
        charPos+=str.length;
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
        BufferedInput buf=cast(BufferedInput)source;
        if (buf !is null){
            if (buf.position == 0 && buf.capacity-buf.limit <=maxTranscodingOverhead){
                sliceE=SliceExtent.Maximal;
            }
        } else {
            sliceE=SliceExtent.ToEnd;
        }
        size_t nonGrow=maxTranscodingOverhead;
        bool matchSuccess=false;
        while (source.reader(delegate size_t(void[] rawData)
                {
                    T[] data=cropRight((cast(T*)rawData.ptr)[0..rawData.length/T.sizeof]);
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
            if (buf.populate() is Eof) {
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
                default:
                    throw new Exception("unknown slice extent",__FILE__,__LINE__);
                }
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
        size_t i=0;
        if (inComment==CommentType.Line){
            for(;i!=data.length;++i){
                auto c=data[i];
                if (c=='\n'||c=='\r'){
                    inComment=CommentType.None;
                    break;
                }
            }
        }
        for(;i!=data.length;++i){
            auto c=data[i];
            if (!(c==' '||c=='\t'||(newlineIsSpace &&(c=='\r'||c=='\n')))){
                if (skipComments && c=='#'){
                    inComment=CommentType.Line;
                    ++i;
                    for(;i!=data.length;++i){
                        c=data[i];
                        if (c=='\n'||c=='\r') {
                            inComment=CommentType.None;
                            break;
                        }
                    }
                } else{
                    inComment=CommentType.None;
                    return i;
                }
            }
        }
        switch(se){
            case SliceExtent.Partial : return Eof;
            case SliceExtent.Maximal :
                if (inComment==CommentType.None) inComment=CommentType.Whitespace;
            case SliceExtent.ToEnd :
                return data.length;
            default:
                throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
        }
    }
    /// skips whitespace
    bool skipWhitespace(){
        bool didSkip=false;
        do {
            skippedWhitespace=true;
            if (next(&scanWhitespace) && source.slice.length!=0) {
                didSkip=true;
            }
        } while (inComment!=CommentType.None);
        skippedWhitespace=true;
        return didSkip;
    }
    /// skips a newline
    bool skipNewline(bool shouldThrow=true){
        if (next(delegate size_t(T[]data,SliceExtent se){
            if (data.length<2){
                switch(se){
                    case SliceExtent.Partial : return Eof;
                    case SliceExtent.Maximal :
                    smallCacheError("Newline did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
                    case SliceExtent.ToEnd :
                        if (data.length==0){
                            return 0;
                        } else if (data[0]=='\n' || data[0]=='\r') return 1;
                    default:
                        throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
                }
            } else {
                if (data[0]=='\n'){
                    if (data[1]=='\r') return 2;
                    return 1;
                }
                if (data[0]=='\r'){
                    return 1;
                }
            }
            return 0;
        }) && source.slice.length!=0) {
            return true;
        }
        if (shouldThrow) parseError("no newline when expected",__FILE__,__LINE__);
        return false;
    }
    /// skips the given number of lines, returns the left over lines
    size_t skipLines(size_t nlines,bool shouldThrow=true){
        bool checkCr=false;
        while (1){
            if (!next(delegate size_t(T[]t,SliceExtent se){
                    size_t i=0;
                    for (;i<t.length;++i){
                        if (t[i]=='\r' || checkCr){
                            if (checkCr){
                                checkCr=false;
                                if (nlines==0){
                                    if (t[i]=='\r'){
                                        return i+1;
                                    } else {
                                        return i;
                                    }
                                }
                            } else {
                                --nlines;
                                if (nlines==0) break;
                            }
                        }
                        if (t[i]=='\n') {
                            --nlines;
                            checkCr=true;
                            if (nlines==0) break;
                        }
                    }
                    if (checkCr && i+1<t.length){
                        checkCr=false;
                        if (t[i+1]=='\r'){
                            return i+2;
                        } else {
                            return i+1;
                        }
                    }
                    if (nlines==0 && ! checkCr) return i+1;
                    switch(se){
                        case SliceExtent.Partial :
                        return Eof;
                        case SliceExtent.Maximal :
                        return t.length;
                        case SliceExtent.ToEnd :
                            if (nlines==0 || nlines==1) { // accept missing newline at end of file
                                nlines=0;
                                checkCr=false;
                                return t.length;
                            }
                            if (shouldThrow) {
                                throw new EofException(this,"unexpected EOF",__FILE__,__LINE__);
                            }
                            return t.length;
                        default:
                            throw new ParsingException(this,"unknown SliceExtent",__FILE__,__LINE__);
                    }
                }))
            {
                if (nlines==0 && ! checkCr){
                    return 0;
                }
                if (shouldThrow) parseError("no newline when expected",__FILE__,__LINE__);
                return nlines;
            }
            if (nlines==0 && ! checkCr){
                return 0;
            }
        }
        return nlines; // what should be done with checkCr ??? anyway being here will probably be treated as an error...
    }
    /// scans a line
    protected size_t scanLine (T[] data,SliceExtent se){
        size_t i=0;
        bool checkCr=false;
        for(;i!=data.length;++i){
            auto c=data[i];
            if (c=='\r'){
                return i+1;
            }
            if (c=='\n'){
                if (i+1<data.length){
                    if (data[i+1]=='\r'){
                        return i+2;
                    } else {
                        return i+1;
                    }
                } else{
                    break;
                }
            }
        }
        switch(se){
            case SliceExtent.Partial : return Eof;
            case SliceExtent.Maximal :
                smallCacheError("line did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
            case SliceExtent.ToEnd :
                return data.length;
            default:
            parseError("invalid SliceExtent",__FILE__,__LINE__);
        }
        assert(false);
    }
    /// returns the next line (as slice in local storage)
    T[]nextLine(){
        T[] str;
        if (!next(&scanLine))
            return null;
        return slice;
    }
    /// reads n codepoints
    T[] readNCodePoints(size_t n,bool skipSpace=true){
        if (!skipSpace){
            skippedWhitespace=true;
        }
        if (!next(delegate size_t(T[] data,SliceExtent se){
            return scanCodePoints(data,n);
        })) parseError("could not read n codepoints",__FILE__,__LINE__);
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
            default:
                parseError("invalid SliceExtent",__FILE__,__LINE__);
        }
        assert(false);
    }
    /// scans a float string
    protected size_t scanFloat(T[] data,SliceExtent se){
        size_t i=0;
        if (data.length==0) return Eof;
        T c=data[i];
        if (c=='n'||c=='N'){ // nan
            if (++i==data.length) return Eof;
            if (data[i]!='a' && data[i]!='A') return 0;
            if (++i==data.length) return Eof;
            if (data[i]!='n' && data[i]!='N') return 0;
            return ++i;
        }
        if (c=='+' || c=='-') ++i;
        if (i==data.length) return Eof;
        c=data[i];
        if (c=='i'||c=='I'){ // inf 
            if (++i==data.length) return Eof;
            if (data[i]!='n' && data[i]!='N') return 0;
            if (++i==data.length) return Eof;
            if (data[i]!='f' && data[i]!='F') return 0;
            return ++i;
        }
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
            default:
                parseError("invalid SliceExtent",__FILE__,__LINE__);
        }
        assert(false);
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
                default:
                    throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
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
                if (skipComments && c=='#') return i;
            }
            switch(se){
                case SliceExtent.Partial : return Eof;
                case SliceExtent.Maximal :
                smallCacheError("string did not terminate within buffer window ("~Integer.toString(data.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd :
                    return data.length;
                default:
                    throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
            }
        }
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
                    if (data.length==0) return Eof;
                    if (data[0]=='i'||data[0]=='I'){
                        return 1;
                    } else if (data.length<3){
                        return Eof;
                    } else if (data[0..3]==cast(T[])"*1i"){
                        return 3;
                    }
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
            int signB=1;
            if (slice=="-") signB=-1;
            skipWhitespace();
            ImaginaryTypeOf!(U) b;
            readValue(b);
            t=cast(U)(a+signB*b);
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
            if (next(&scanString)) {
                if (slice.length>0 && slice[0]=='"'){
                    t=unescape(slice[1..$-1]);
                } else {
                    t=slice;
                }
                if(longLived) t=t.dup;
            } else {
                t=[];
                //parseError("error scanning string",__FILE__,__LINE__);
            }
        } else static if(is(U==char[])||is(U==wchar[])||is(U==dchar[])) {
            alias ElementTypeOfArray!(U) S;
            T[] str;
            readValue(str,false);
            t=convertToString!(S)(str,t);
        } else {
            T.triggerError;
            static assert(0,"unsupported type "~U.stringof);
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
                default:
                    throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
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
    /// but must be delimited (i.e. a does not skip aa)
    bool skipString2(T[]str,bool raise=true){
        if(next(delegate size_t(T[] data,SliceExtent se){
            if (str.length>=data.length){
                switch(se){
                case SliceExtent.Partial:
                    return Eof;
                case SliceExtent.Maximal:
                    parseError("skipString2 string is larger than buffer window ("~Integer.toString(data.length)~"<"~Integer.toString(str.length)~")",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    if (data.length==str.length &&data==str) return str.length;
                    return 0;
                default:
                    throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
                }
            }
            if (str == data[0..str.length]){
                T c=data[str.length];
                if (c==' '|| c=='\t'|| c=='\r'|| c=='\n')
                    return str.length;
                for (size_t j=0;j!=delims.length;++j){
                    if (delims[j]==c) return str.length;
                }
                return 0; // non delimited string
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
                        default:
                            throw new Exception("unknown SliceExtent",__FILE__,__LINE__);
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

    /// Instantiate with a Reader
    this(Reader!(T) reader = null,T[]delims=cast(T[])",;:{}[]",size_t maxTranscodingOverhead=6,
        bool skipComments=true, bool newlineIsSpace=true)
    {
        auto tReader=cast(ReadHandler!(T))reader;
        if (tReader is null){
            assert(0,"at the moment only tango based readers are accepted (should change soon)");
        }
        auto iStr=((tReader.buf is null)?cast(InputStream)tReader.arr:cast(InputStream)tReader.buf);
        super(iStr);
        if (iStr)
            setS(iStr);
        this.maxTranscodingOverhead=maxTranscodingOverhead;
        this.delims=delims;
        this.skipComments=skipComments;
        this.newlineIsSpace=newlineIsSpace;
    }

    /+/// Instantiate with a buffer
    this(InputStream stream = null,T[]delims=cast(T[])",;:{}[]",size_t maxTranscodingOverhead=6,
        bool skipComments=true, bool newlineIsSpace=true)
    {       
        super (stream);
        if (stream)
            setS(stream);
        this.maxTranscodingOverhead=maxTranscodingOverhead;
        this.delims=delims;
        this.skipComments=skipComments;
        this.newlineIsSpace=newlineIsSpace;
    }+/

    /// Set the provided stream as the scanning source
    TextParser setS(InputStream stream)
    {
        assert (stream);
        source = BufferedInput.create (stream);
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
    TextParser opCall(U)(ref U t,bool longLived=true){
        readValue!(U)(t,longLived);
        return this;
    }
    
    /// helper structure to peek 
    struct Peeker{
        T[] peekedSlice;
        size_t delegate (T[] data,SliceExtent se) scanner;
        bool noRaise;
        bool didRaise=false;
        size_t scan(T[] data,SliceExtent se){
            size_t res;
            if (noRaise){
                try{
                    res=scanner(data,se);
                } catch (Exception e){
                    didRaise=true;
                    peekedSlice=data;
                    return 0;
                }
            } else {
                res=scanner(data,se);
            }
            if (res==Eof)
                return Eof;
            peekedSlice=data[0..res];
            return 0;
        }
    }
    /// peeks what is found by the given scanner. If noRaise is true exception are catched,
    /// if zeroOnFail is false when an exception is raised the full slice evaluated at that moment is
    /// returned (useful to get the beginning of a very long line that overflows the buffer)
    char[] peek(size_t delegate (T[] data,SliceExtent se) scanner,bool noRaise=true,bool zeroOnFail=true){
        Peeker p;
        p.scanner=scanner;
        p.noRaise=noRaise;
        next(&p.scan);
        if (!p.didRaise){
            return p.peekedSlice;
        } else {
            if (zeroOnFail){
                return "";
            } else {
                return p.peekedSlice;
            }
        }
    }
}

/// if s is a quoted string unescapes it
T[] maybeUnescape(T)(T[] s){
    if (s.length>1 && s[0]=='"' && s[$-1]=='"'){
        return unescape(s[1..$-1]);
    } else {
        return s;
    }
}

debug(UnitTest){
    import blip.io.IOArray;
    unittest{
        auto p=new TextParser!(char)(toReaderChar(new IOArray("åbôdåbôåbôdåbôdåbôd 12tz_rk tt 23.4 +7.2i \t6.4+3.2i \"a string with space\" \"escapedString\\\"\"\na,b#comment\nc\n")));
        int i;
        real r;
        ireal ir;
        creal cr;
        char[] s;
        wchar[] ws;
        dchar[] ds;
        s=p.readNCodePoints(4);
        assert(s=="åbôd");
        s=p.readNCodePoints(3);
        assert(s=="åbô");
        s=p.readNCodePoints(12);
        assert(s=="åbôdåbôdåbôd");
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
        p(s);
        assert(s=="a");
        s=p.getSeparator();
        assert(s==",");
        p(s);
        assert(s=="b");
        p(s);
        assert(s=="c");
    }
}

