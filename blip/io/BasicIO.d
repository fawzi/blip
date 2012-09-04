
/// becomes a template. I have choosen char[], but most basic things still are templates,
/// so even using wchar or dchar as native types should not be too difficult.
/// It might be a good idea to rename char[] string, so that one could switch
/// the choosen type more easily later.
///
/// == Blip overview: Formatted and debug output (from blip.io.BasicIO) ==
/// 
/// Tango and phobos have quite different i/o approaches, and io is something that you will
/// use in some place in any program, so blip took the obvious approach:
/// 
/// it introduces a third approach ;-)
/// 
/// Things are not so bad though, because it introduces a very light weight approach that can
/// be wrapped around other approaches, or used "natively".
/// 
///  * based on CharSink, i.e. a void delegate(in cstring)
///     * easy to define new sinks and wrap around things
///     * can be used also a low level without introducing dependencies
///  * writeOut(sink,obj,args) is a template that tries to write out obj to sink, formatting it using args.
///   to make an object work with writeOut you should define void desc(CharSink,args) in it.
///   Basic types are already supported.
///  * there is a Dumper struct that wraps CharSink and similar objects (with very low overhead) and makes them nicer to use (wisper style calling, automatic use of writeOut).
///    The dumper struct can be easily be created with the dumper(sink) function
///  * blip.io.Console defines some dumpers: sout (standard out, thread safe) serr (standard error, thread safe), and also unsafe versions
///  * blip.container.GrowableArray defines a structure to collects several additions
///    (lGrowableArray can be used to create a local version of it).
///    With it it offers some useful helper functions:
///     * collectAppender(void delegate(CharSink) appender) collects all appends done by appender and returns them as array
///     * sinkTogether(sink,void delegate(CharSink) appender) sinks all appends done by appender at once into the given sink
///  * A formatting function like tango's format is not present.
///    This mainly because one should decide if a template (easier but more bloat) or a
///    variadic function should be used. Still it should be easy to add:
///    using {} to signal arguments, if one uses the following format
///    "[argNr]:formattingOptions[,width]" in the curly braces, then "formattingOptions[,width]"
///    can be forwarded to writeOut...
/// 
/// For example:
/// {{{
/// import blip.io.BasicIO; // CharSink,writeOut,dumper...
/// import blip.io.Console; // sout,serr
/// import blip.container.GrowableArray; // sinkTogether, ...
/// 
/// class A{
///     this (){}
///     void desc(CharSink s){
///         s("<class A@")(cast(void*)this)(">");
///     }
/// }
/// 
/// void main(){
///     for (int i=0;i<3;++i){
///         sout("Hello world ")(i)("\n");
///     }
///     A a=new A(),nullA;
///     sinkTogether(sout,delegate void(CharSink s){
///         dumper(s)("All this text with a:")(a)(" and nullA:")(nullA)(" is guaranteed to be outputted together\n");
///     });
///     char[128] buf;
///     auto collector=lGrowableArray(buf,0);
///     collector("bla");
///     collector(" and bla ");
///     collector(&a.desc);
///     writeOut(&collector.appendArr,nullA);
///     char[] heapAllocStr=collector.takeData;
///     sout(heapAllocStr)("\n");
///     char[] heapAllocStr2=collectAppender(delegate void(CharSink sink){
///         dumper(sink)("An easier way to collect data:")([1,2,4])(" in a heap allocated string (for example to generate an exception message)\n");
///     });
///     sout(heapAllocStr2);
/// }
/// }}}
/// will output something like
/// {{{
/// Hello world 0
/// Hello world 1
/// Hello world 2
/// All this text with a:<class A@2109344> and nullA:<A *NULL*> is guaranteed to be outputted together
/// bla and bla <class A@2109344><A *NULL*>
/// An easier way to collect data:[1,2,4] in a heap allocated string (for example to generate an exception message)
/// }}}
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
module blip.io.BasicIO;
import blip.util.TangoConvert: formatFloat;
import blip.core.Array: find;
import blip.core.Traits: isStaticArrayType,isAssocArrayType;
import blip.util.TemplateFu: nArgs;
import blip.text.UtfUtils: convertToString;
import blip.Comp;

/// extent of a slice of a buffer
enum SliceExtent{ Partial, Maximal, ToEnd }
/// end of file marker
enum :size_t{Eof=size_t.max}

/// a character sink
alias void delegate(in cstring) CharSink;
/// a binary sink
alias void delegate(in void[]) BinSink;
/// a delegate that will write out to a character sink
alias void delegate(scope void delegate(in cstring))  OutWriter;
/// a delegate that will write out to a binary sink
alias void delegate(scope void delegate(in void[]))  BinWriter;

/// a basic character reader (can be used to build more advanced objects that can handle CharReader, see blip.io.BufferIn)
alias size_t delegate(char[]) CharRead;
/// a basic binary reader (can be used to build more advanced objects that can handle CharReader and BinReader)
alias size_t delegate(void[]) BinRead;
/// a delegate that reads in from a character source
alias size_t delegate(char[], SliceExtent slice,out bool iterate) CharReader;
/// a delegate that reads in from a binary source
alias size_t delegate(void[], SliceExtent slice,out bool iterate) BinReader;
/// a handler of CharReader, returns true if something was read
alias bool delegate(CharReader) CharReaderHandler;
/// a handler of BinReader, returns true if something was read
alias bool delegate(BinReader) BinReaderHandler;

/// io exception
class BIOException: Exception{
    this(string msg,string file, long line,Exception next=null){
        super(msg,file,line,next);
    }
}
/// exception when the buffer is too small
class SmallBufferException:BIOException{
    this(string msg,string fileN,long lineN,Exception next=null){
        super(msg,fileN,lineN,next);
    }
}

/// output stream
interface OutStreamI{
    void rawWriteStr(in cstring);
    void rawWriteStr(in cstringw);
    void rawWriteStr(in cstringd);
    void rawWriteStrC(in cstring);
    void rawWriteStrW(in cstringw);
    void rawWriteStrD(in cstringd);
    void rawWrite(in void[]);
    CharSink charSink();
    BinSink  binSink();
    void flush();
    void close();
    void desc(scope CharSink s);
}

/// a reader of elements of type T
interface Reader(T){
    /// read some data into the given buffer
    size_t readSome(T[]);
    /// character reader handler
    bool handleReader(scope size_t delegate(T[], SliceExtent slice,out bool iterate) r);
    /// shutdown the input source
    void shutdownInput();
    void desc(CharSink s);
}

/// one or more readers
interface MultiReader{
    enum Mode{ Binary=1, Char=2, Wchar=4, Dchar=8 }
    /// returns the modes this reader supports
    uint modes();
    /// returns the native modes of this reader (less overhead)
    uint nativeModes();
    Reader!(char)  readerChar();
    Reader!(wchar) readerWchar();
    Reader!(dchar) readerDchar();
    Reader!(void)  readerBin();
    void shutdownInput();
    void desc(CharSink s);
}


/// helper to build closures
struct OutW(S...){
    S args;
    static OutWriter closure(S args){
        auto res=new OutW;
        // some compilers don't like static array assignements
        foreach(i,U;S){
            static if(isStaticArrayType!(U)){
                res.args[i][]=args[i];
            } else {
                res.args[i]=args[i];
            }
        }
        return &res.call;
    }
    void call(scope void delegate(in cstring)sink){
        writeOut!(void delegate(in cstring),S)(sink,this.args);
    }
}

/// returns the operation that writes out the first argument, with the following as format
/// this allocates on the heap, avoid its use if speed is important
OutWriter outWriter(T,S...)(T v,S args){
    return OutW!(T,S).closure(v,args);
}
/// parses an integer
private size_t parseInt(T)(T[]s,ref int i){
    size_t res=0;
    if (s.length>0 && s[0]>='0' && s[0]<='9'){
        i=0;
        foreach(c;s){
            if (c<'0' || c>'9') break;
            res=true;
            int d=cast(int)(c-'0');
            i*=10;
            i+=d;
            res+=1;
        }
    }
    return res;
}
/// writes out the given amount of space
void writeSpace(S)(S s,int amount){
    string tt="                ";
    int l=cast(int)tt.length;
    while(amount>l){
        s(tt);
        amount-=l;
    }
    if (amount>0){
        s(tt[0..amount]);
    }
}
// this is to write out a value (for debugging and similar purposes)
void writeOut(V,T,S...)(scope V sink1,T v,S args){
    static if(is(typeof(sink1 is null))){
        assert(!(sink1 is null),"null sink in writeOut");
    }
    static if (is(typeof(sink1(" "c)))){
        alias const(char) Char;
    } else static if (is(typeof(sink1(" "w)))){
        alias const(wchar) Char;
    } else static if (is(typeof(sink1(" "d)))){
        alias const(dchar) Char;
    } else {
        static assert(0,"invalid sink in writeOut");
    }
    alias UnqualAll!(Char) UChar;
    static if(is(UnqualAll!(S[0])==UChar[])){
        int width=0;
        void delegate(Char[]) sink;
        static if(is(V==typeof(sink))){
            sink=sink1;
        } else {
            sink=delegate void(Char[] s){ sink1(s); };
        }
        auto startC=find(args[0],',')+1;
        if (startC<args[0].length && parseInt(args[0][startC..$],width)>0){
            if (width<0) assert(0,"unsupported negative width");// (alloc storage and do it?)
            sink=delegate void(Char[] s){
                sink1(s);
                if (s.length>width){
                    width=0;
                } else {
                    width-=s.length;
                }
            };
        }
        alias sink sinkDlg;
        scope(exit){
            writeSpace(sink1,width);
        }
    } else {
        alias sink1 sink;
        static if (is(typeof(sink1) == void delegate(Char[]))){
            alias sink1 sinkDlg;
        } else {
            void delegate(Char[]) sinkDlg=delegate void(Char[]s){ sink1(s); };
        }
    }
    alias UnqualAll!(T) TT;
    static if (is(T U:U[])){
        static if(is(UnqualAll!(U)==UChar)){
            sink(v);
        } else static if(is(U==char)||is(U==wchar)||is(U==dchar)){
            if (v.length<128){
                Char[256] buf;
                auto s=convertToString!(Char)(v,buf);
                sink(s);
            } else {
                auto s=convertToString!(Char)(v);
                sink(s);
            }
        } else static if(is(U==void)||is(U==ubyte)){
            auto digits=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
            cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
            cast(Char)'a',cast(Char)'b',cast(Char)'c',cast(Char)'d',cast(Char)'e',cast(Char)'f'];
            UChar[32] buf;
            size_t ii=0;
            auto p=cast(ubyte*)v.ptr;
            for(int i=0;i<v.length;++i){
                if (ii==buf.length) {
                    ii=0;
                    sink(buf);
                }
                auto d=(*p);
                buf[ii]=digits[(d>>4)];
                ++ii;
                buf[ii]=digits[(d&0xF)];
                ++ii;
                ++p;
            }
            sink(buf[0..ii]);
        } else {
            sink("[");
            foreach (i,el;v){
                if (i!=0) sink(",");
                writeOut(sink,el,args);
            }
            sink("]");
        }
    } else static if (isAssocArrayType!(TT)){
        sink("[");
        int notFirst=false;
        foreach (k,t;v){
            if (notFirst) sink(",");
            notFirst=true;
            writeOut(sink,k);
            sink(":");
            writeOut(sink,t);
        }
        sink("]");
	} else static if (is(TT==char)){
        sink((&v)[0..1]);
    } else static if(is(TT==wchar)||is(TT==dchar)){
        sink(cast(cstring)[v]);
    } else static if (is(TT==byte)||is(TT==ubyte)||is(TT==short)||is(TT==ushort)||
        is(TT==int)||is(TT==uint)||is(TT==long)||is(TT==ulong))
    {
        bool sign=true;
        static if (is(UnqualAll!(S[0]):UChar[])){
            if (args[0].length>0){
                switch (args[0][0]){
                case 'x':
                    const digits=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
                    cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
                    cast(Char)'a',cast(Char)'b',cast(Char)'c',cast(Char)'d',cast(Char)'e',cast(Char)'f'];
                    UChar[T.sizeof*2] str;
                    auto val=v;
                    for(int i=1;i<=cast(int)T.sizeof*2;++i){
                        auto d=cast(int)(0xF & val);
                        str[str.length-i]=digits[d];
                        val>>=4;
                    }
                    sink(str);
                    return;
                case 'X':
                    const digitsU=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
                    cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
                    cast(Char)'A',cast(Char)'B',cast(Char)'C',cast(Char)'D',cast(Char)'E',cast(Char)'F'];
                    UChar[T.sizeof*2] strU;
                    auto valU=v;
                    for(int i=1;i<=T.sizeof*2;++i){
                        auto dU=cast(int)(0xF & valU);
                        strU[strU.length-i]=digitsU[dU];
                        valU>>=4;
                    }
                    sink(strU);
                    return;
                case 'd','D':
                    static if(is(typeof(delegate(){ auto x=args[0][1];}))){
                        if (args[0].length>1 && args[0][1]>='0' && args[0][1]<='9'){
                            int w1=cast(int)(args[0][1]-'0');
                            for (size_t ii=2;ii<args[0].length && args[0][ii]>='0' && args[0][ii]<='9';++ii)
                            {
                                w1=10*w1+cast(int)(args[0][ii]-'0');
                            }
                            auto v2=v;
                            int w2=0;
                            if (v2<0) ++w2;
                            while (v2!=0){
                                v2/=10;
                                ++w2;
                            }
                            if (w2<w1 && v<0){
                                sink("-");
                                sign=false;
                            }
                            for(int ii=w2;ii<w1;++ii){
                                sink("0");
                            }
                        }
                    }
                default:
                }
            }
        }
	TT v2=v;
        if (v2<0){
            UChar[22] res;
            int pos=res.length-1;
            while(v2<0){
                auto r=v2%10;
                res[pos]=cast(Char)(cast(T)'0'-r);
                v2=cast(T)(v2/10);
                --pos;
            }
            if (sign){
                res[pos]='-';
            } else {
                ++pos;
            }
            sink(res[pos..$]);
        } else if (v==0){
            sink("0");
        } else {
            UChar[22] res;
            int pos=res.length-1;
            while(v2>0){
                auto r=v2%10;
                res[pos]=cast(Char)(cast(T)'0'+r);
                v2=cast(T)(v2/10);
                --pos;
            }
            sink(res[pos+1..$]);
        }
    } else static if (is(TT==bool)){
        if (v){
            sink([cast(Char)'1']);
        } else {
            sink([cast(Char)'0']);
        }
    } else static if (is(TT==float)||is(TT==double)||is(TT==real)){
        char[40] buf;
        int prec=6;
        static if (is(UnqualAll!(S[0])==UChar[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v,prec));
    } else static if (is(TT==ifloat)||is(TT==idouble)||is(TT==ireal)){
        char[40] buf;
        int prec=6;
        static if (is(UnqualAll!(S[0])==UChar[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v.im,prec));
        sink("*1i");
    } else static if (is(TT==cfloat)||is(TT==cdouble)||is(TT==creal)){
        char[40] buf;
        int prec=6;
        static if (is(UnqualAll!(S[0])==UChar[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        auto res=formatFloat(buf,v.re,prec);
        sink(res);
        res=formatFloat(buf,v.im,prec);
        if (res[0]=='-'||res[0]=='+'){
            sink(res);
            sink("*1i");
        } else {
            sink("+");
            sink(res);
            sink("*1i");
        }
    } else static if (is(TT==void*)){
        static if (nArgs!(S)==0){
            writeOut(sink,cast(size_t)v,"x");
        } else {
            writeOut(sink,cast(size_t)v,args);
        }
    } else static if (is(TT:int)){
        writeOut(sink,cast(int)v);
    } else {
        static if (is(typeof(v is null))){
            if (v is null) {
                sink([cast(Char)'<']);
                sink(convertToString!(Char)(T.stringof));
                sink(convertToString!(Char)(" *NULL*>"));
                return;
            }
        }
        static if(is(typeof(v.desc(sink,args)))){
            v.desc(sink,args);
        } else static if(is(typeof(v.desc(sink.call,args)))){
            v.desc(sink.call,args);
        } else static if(is(typeof(v.desc(sinkDlg,args)))){
            v.desc(sinkDlg,args);
        } else static if(is(typeof(v.desc(sink)))){
            v.desc(sink);
        } else static if(is(typeof(v.desc(sink.call)))){
            v.desc(sink.call);
        } else static if(is(typeof(v.desc(sinkDlg)))){
            v.desc(sinkDlg);
        } else static if(is(typeof(v.writeOut(sinkDlg)))){
            v.writeOut(sinkDlg);
        } else static if((nArgs!(S)==0 || (nArgs!(S)==1 && is(S[0]==Char[]))) && 
            (is(typeof(v(sink))) || is(typeof(v(delegate void(in cstring c){ }))) 
            || is(typeof(v(delegate void(in cstringw c){ })))
            || is(typeof(v(delegate void(in cstringd c){ }))) ) )
        {
            static if (is(typeof(v(sink)))){
                v(sink);
            } else static if (is(typeof(v(sinkDlg)))){
                v(sinkDlg);
            } else static if (is(typeof(v(delegate void(in cstring c){ })))){
                v(delegate void(in cstring c){ writeOut(sink,c); });
            } else static if (is(typeof(v(delegate void(in cstringw c){ })))){
                v(delegate void(in cstringw c){ writeOut(sink,c); });
            } else static if (is(typeof(v(delegate void(in cstringd c){ }))) ){
                v(delegate void(in cstringd c){ writeOut(sink,c); });
            } else static assert(0,"internal writeOut error");
        } else static if (is(typeof(sink(v.toString())))){
            sink(v.toString());
        } else static if (is(typeof(writeOut(sink,v.toString())))){
            writeOut(sink,v.toString());
        } else static if (is(TT U==typedef)){
            writeOut(sink1,cast(U)v,args);
        } else static if (is(T == function)){
            sink(convertToString!(Char)("function@"));
            writeOut(sink,cast(void*)v);
        } else static if (is(T==delegate)){
            sink(convertToString!(Char)("delegate("));
            writeOut(sink,cast(void*)v.ptr);
            sink(",");
            writeOut(sink,cast(void*)v.funcptr);
            sink(")");
        } else {
            static assert(0,"unsupported type in writeOut "~T.stringof);
        }
    }
}

/// helper to easily dump out data
struct Dumper(T){
    T call;
    Dumper opCall(U...)(U u){
        static if(is(U==void delegate(T))){
            u(call);
        } else static if (is(typeof(call(u)))){
            call(u);
        } else static if (is(typeof((*call)(u)))){
            (*call)(u);
        } else static if (is(typeof(writeOut!(T,U)(call,u)))){ 
            writeOut!(T,U)(call,u);
        } else static if (is(typeof(writeOut!(typeof(*call),U)(*call,u)))){ 
            writeOut!(typeof(*call),U)(*call,u);
        } else {
            static assert(0,"Dumper!("~T.stringof~") cannot handle "~U.stringof);
        }
        return this;
    }
}

/// ditto
Dumper!(T) dumperNP(T)(T c){
    static if(is(typeof(c is null))){
        assert(!(c is null),"dumper cannot be null");
    }
    Dumper!(T) res;
    res.call=c;
    return res;
}
/// helper to easily dump out data that controls that it receives a pointer like el
Dumper!(T) dumper(T)(T c){
    static if(is(typeof(c is null))){
        assert(!(c is null),"dumper cannot be null");
        Dumper!(T) res;
        res.call=c;
        return res;
    } else {
        static assert(0,"non pointer like argument "~T.stringof);
    }
}

/// fills out outBuf, or throws an exception
void readExact(TInt,TOut)(scope size_t delegate(TInt[]) rSome,TOut[]outBuf){
    static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
    static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
    enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}
    
    if (outBuf.length%TInt.sizeof!=0){
        throw new BIOException("external size needs to be a multiple of internal size",__FILE__,__LINE__);
    }

    auto outLen=outBuf.length*OutToIn;
    auto outPtr=cast(TInt*)outBuf.ptr;
    size_t readTot=0;
    while(readTot!=outLen){
        auto readNow=rSome(outPtr[readTot..outLen]);
        if (readNow==Eof){
            throw new BIOException("unexpected Eof in readExact",__FILE__,__LINE__);
        }
        readTot+=readNow;
    }
}

/// utility function that outputs the given string indenting it
/// (i.e. adding indent after each newline)
void sinkIndented(T,U,V)(T[] indent,scope void delegate(U[]) s,V[] str){
    static assert(is(UnqualAll!(T)==UnqualAll!(U)) && is(UnqualAll!(T)==UnqualAll!(V)));
    size_t i0=0;
    foreach(i,c;str){
        if (c=='\n'){
            s(str[i0..i+1]);
            i0=i+1;
            s(indent);
        }
        if (c=='\r'){
            throw new Exception("carriage return not supported in sinkIndented",__FILE__,__LINE__);
        }
    }
    s(str[i0..$]);
}
/// utility function that forwards the indented writer to the sink
/// (i.e. adding indent after each newline)
void indentWriter(T,U,V)(T[] indent,scope void delegate(U[]) sink,scope void delegate(scope void delegate(V[])) writer){
    static assert(is(UnqualAll!(T)==UnqualAll!(U)) && is(V==U));
    writer(delegate void(V[] str){
        sinkIndented!(T,U,V)(indent,sink,str);
    });
}
