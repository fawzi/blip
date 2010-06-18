/// basic IO definitions
/// one has to choose one basic string type for "normal" output, otherwise *everything*
/// becomes a template. I have choosen char[], but most basic things still are templates,
/// so even using wchar or dchar as native types should not be too difficult.
/// It might be a good idea to rename char[] string, so that one could switch
/// the choosen type more easily later.
module blip.io.BasicIO;
import blip.t.util.Convert: formatFloat;
import blip.t.core.Array: find;
import blip.t.core.Traits: isStaticArrayType;
import blip.text.UtfUtils: convertToString;

/// extent of a slice of a buffer
enum SliceExtent{ Partial, Maximal, ToEnd }
/// end of file marker
enum :size_t{Eof=size_t.max}

/// a character sink
alias void delegate(char[]) CharSink;
/// a binary sink
alias void delegate(void[]) BinSink;
/// a delegate that will write out to a character sink
alias void delegate(void delegate(char[]))  OutWriter;
/// a delegate that will write out to a binary sink
alias void delegate(void delegate(void[]))  BinWriter;

/// a basic character reader (can be used to build more advanced objects that can handle CharReader, see blip.io.BufferIn)
alias size_t delegate(char[]) CharRead;
/// a basic binary reader (can be used to build more advanced objects that can handle CharReader and BinReader)
alias size_t delegate(void[]) BinRead;
/// a delegate that reads in from a character source
alias size_t delegate(char[], SliceExtent slice,out bool iterate) CharReader;
/// a delegate that reads in from a binary source
alias size_t delegate(void[], SliceExtent slice,out bool iterate) BinReader;
/// a handler of CharReader, returns true if something was read
alias bool delegate(CharReader)CharReaderHandler;
/// a handler of BinReader, returns true if something was read
alias bool delegate(BinReader) BinReaderHandler;

/// io exception
class BIOException: Exception{
    this(char[]msg,char[] file, long line){
        super(msg,file,line);
    }
}
/// exception when the buffer is too small
class SmallBufferException:BIOException{
    this(char[]msg,char[]fileN,long lineN){
        super(msg,fileN,lineN);
    }
}

/// output stream
interface OutStreamI{
    void rawWriteStr(char[]);
    void rawWriteStr(wchar[]);
    void rawWriteStr(dchar[]);
    void rawWrite(void[]);
    CharSink charSink();
    BinSink  binSink();
    void flush();
    void close();
}

/// a reader of elements of type T
interface Reader(T){
    /// read some data into the given buffer
    size_t readSome(T[]);
    /// character reader handler
    bool handleReader(size_t delegate(T[], SliceExtent slice,out bool iterate) r);
    /// shutdown the input source
    void shutdownInput();
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
    void call(void delegate(char[])sink){
        writeOut!(void delegate(char[]),S)(sink,this.args);
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
    const char[] tt="                ";
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
void writeOut(V,T,S...)(V sink1,T v,S args){
    static if(is(typeof(sink1 is null))){
        assert(!(sink1 is null),"null sink in writeOut");
    }
    static if (is(typeof(sink1(" ")))){
        alias char Char;
    } else static if (is(typeof(sink1(" "w)))){
        alias wchar Char;
    } else static if (is(typeof(sink1(" "d)))){
        alias dchar Char;
    } else {
        static assert(0,"invalid sink in writeOut");
    }
    static if(is(S[0]==Char[])){
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
    static if (is(T U:U[])){
        static if(is(U==Char)){
            sink(v);
        } else static if(is(U==char)||is(U==wchar)||is(U==dchar)){
            char[] s;
            if (t.length<128){
                Char[256] buf;
                s=convertToString!(Char)(t,buf);
            } else {
                s=convertToString!(Char)(t);
            }
            sink(s);
        } else static if(is(U==void)||is(U==ubyte)){
            auto digits=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
            cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
            cast(Char)'a',cast(Char)'b',cast(Char)'c',cast(Char)'d',cast(Char)'e',cast(Char)'f'];
            Char[32] buf;
            size_t ii=0;
            auto p=cast(ubyte*)v.ptr;
            for(int i=0;i<v.length;++i){
                if (ii==buf.length) {
                    ii=0;
                    sink(buf);
                }
                auto d=(0xF & (*p));
                buf[ii]=digits[d];
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
    } else static if (is(T K:T[K])){
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
    } else static if (is(T==char)){
        sink((&v)[0..1]);
    } else static if(is(T==wchar)||is(T==dchar)){
        sink(cast(char[])[v]);
    } else static if (is(T==byte)||is(T==ubyte)||is(T==short)||is(T==ushort)||
        is(T==int)||is(T==uint)||is(T==long)||is(T==ulong))
    {
        bool sign=true;
        static if (is(S[0]:Char[])){
            if (args[0].length>0){
                switch (args[0][0]){
                case 'x':
                    const digits=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
                    cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
                    cast(Char)'a',cast(Char)'b',cast(Char)'c',cast(Char)'d',cast(Char)'e',cast(Char)'f'];
                    Char[T.sizeof*2] str;
                    auto val=v;
                    for(int i=1;i<=T.sizeof*2;++i){
                        auto d=(0xF & val);
                        str[str.length-i]=digits[d];
                        val>>=4;
                    }
                    sink(str);
                    return;
                case 'X':
                    const digitsU=[cast(Char)'0',cast(Char)'1',cast(Char)'2',cast(Char)'3',cast(Char)'4',
                    cast(Char)'5',cast(Char)'6',cast(Char)'7',cast(Char)'8',cast(Char)'9',
                    cast(Char)'A',cast(Char)'B',cast(Char)'C',cast(Char)'D',cast(Char)'E',cast(Char)'F'];
                    Char[T.sizeof*2] strU;
                    auto valU=v;
                    for(int i=1;i<=T.sizeof*2;++i){
                        auto dU=(0xF & valU);
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
        if (v<0){
            char[22] res;
            int pos=res.length-1;
            while(v<0){
                auto r=v%10;
                res[pos]=cast(Char)(cast(T)'0'-r);
                v=cast(T)(v/10);
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
            Char[22] res;
            int pos=res.length-1;
            while(v>0){
                auto r=v%10;
                res[pos]=cast(Char)(cast(T)'0'+r);
                v=cast(T)(v/10);
                --pos;
            }
            sink(res[pos+1..$]);
        }
    } else static if (is(T==bool)){
        if (v){
            sink([cast(Char)'1']);
        } else {
            sink([cast(Char)'0']);
        }
    } else static if (is(T==float)||is(T==double)||is(T==real)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==Char[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v,prec));
    } else static if (is(T==ifloat)||is(T==idouble)||is(T==ireal)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==Char[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v.im,prec));
        sink("*1i");
    } else static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==Char[])){
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
    } else static if (is(T==void*)){
        writeOut(sink,cast(size_t)v,args);
    } else static if (is(T:int)){
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
        } else static if (is(typeof(v.toString()))){
            sink(v.toString);
        } else static if (is(T U==typedef)){
            writeOut(sink1,cast(U)v,args);
        } else{
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
        return *this;
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
void readExact(TInt,TOut)(size_t delegate(TInt[]) rSome,TOut[]outBuf){
    static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
    static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
    enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}
    
    if (outBuf.length%TInt.sizeof!=0){
        throw new BIOException("external size needs to be a multiple of internal size",__FILE__,__LINE__);
    }

    auto outLen=outBuf.length*OutToIn;
    auto outPtr=cast(TBuf*)outBuf.ptr;
    size_t readTot=0;
    while(readTot!=outLen){
        auto readNow=rSome(outPtr[readTot..outLen]);
        if (readNow==Eof){
            throw new BIOException("unexpected Eof in readExact",__FILE__,__LINE__);
        }
        readTot+=readNow;
    }
}
