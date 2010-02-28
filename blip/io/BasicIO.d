/// basic IO definitions
module blip.io.BasicIO;
import blip.t.util.Convert: formatFloat;
import blip.t.core.Array: find;
import blip.t.core.Traits: isStaticArrayType;
import blip.text.UtfUtils: convertToString;

/// extent of a slice of a buffer
enum SliceExtent{ Partial, Maximal, ToEnd }
/// end of file marker
enum :size_t{Eof=size_t.max}

/// a delegate that will write out to a character sink
alias void delegate(void delegate(char[]))  OutWriter;
/// a delegate that will write out to a binary sink
alias void delegate(void delegate(void[]))  BinWriter;
/// a delegate that reads in from a character source
alias size_t delegate(char[], SliceExtent slice,out bool iterate)  OutReader;
/// a handler of OutReader, returns true if something was read
alias bool delegate(OutReader) OutReaderHandler;
/// a delegate that reads in from a binary source
alias size_t delegate(ubyte[], SliceExtent slice,out bool iterate) BinReader;
/// a handler of BinReader, returns true if something was read
alias bool delegate(BinReader) BinReaderHandler;
/// a character sink
alias void delegate(char[]) CharSink;
/// a binary sink
alias void delegate(void[]) BinSink;
/// a basic character reader (can be used to build more advanced objects that can handle OutReader, see blip.io.BufferIn)
alias size_t delegate(char[])  CharRead;
/// a basic character reader (can be used to build more advanced objects that can handle OutReader and BinReader)
alias size_t delegate(void[]) BinRead;

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

/// sample output string
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
private size_t parseInt(char[]s,ref int i){
    size_t res=0;
    if (s.length>0 && s[0]>='0' && s[0]<='9'){
        i=0;
        foreach(c;s){
            if (s[0]<'0' || s[0]>'9') break;
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
    char[] tt="                ";
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
    static if(is(S[0]==char[])){
        int width=0;
        void delegate(char[]) sink;
        static if(is(V==typeof(sink))){
            sink=sink1;
        } else {
            sink=delegate void(char[] s){ sink1(s); };
        }
        auto startC=find(args[0],',')+1;
        if (startC<args[0].length && parseInt(args[0][startC..$],width)>0){
            if (width<0) assert(0,"unsupported negative width");// (alloc storage and do it?)
            sink=delegate void(char[] s){
                sink1(s);
                if (s.length>width){
                    width=0;
                } else {
                    width-=s.length;
                }
            };
        }
        scope(exit){
            writeSpace(sink1,width);
        }
    } else {
        alias sink1 sink;
    }
    static if (is(T S:S[])){
        static if(is(S==char)){
            sink(v);
        } else static if(is(S==wchar)||is(S==dchar)){
            char[] s;
            if (t.length<128){
                char[256] buf;
                s=convertToString!(char)(t,buf);
            } else {
                s=convertToString!(char)(t);
            }
            sink(s);
        } else static if(is(S==void)||is(S==ubyte)){
            auto digits="0123456789abcdef";
            char[32] buf;
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
        static if (is(S[0]==char[])){
            if (args[0].length>0){
                switch (args[0][0]){
                case 'x':
                    auto digits="0123456789abcdef";
                    char[T.sizeof*2] str;
                    for(int i=0;i<T.sizeof/4;++i){
                        auto d=(0xF & v);
                        str[str.length-i]=digits[d];
                    }
                    sink(str);
                    return;
                case 'X':
                    auto digits="0123456789ABCDEF";
                    char[T.sizeof*2] str;
                    for(int i=0;i<T.sizeof/4;++i){
                        auto d=(0xF & v);
                        str[str.length-i]=digits[d];
                    }
                    sink(str);
                    return;
                case 'd','D':
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
                default:
                }
            }
        }
        if (v<0){
            char[22] res;
            int pos=res.length-1;
            while(v<0){
                auto r=v%10;
                res[pos]=cast(char)(cast(T)'0'-r);
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
            char[22] res;
            int pos=res.length-1;
            while(v>0){
                auto r=v%10;
                res[pos]=cast(char)(cast(T)'0'+r);
                v=cast(T)(v/10);
                --pos;
            }
            sink(res[pos+1..$]);
        }
    } else static if (is(T==bool)){
        if (v){
            sink("1");
        } else {
            sink("0");
        }
    } else static if (is(T==float)||is(T==double)||is(T==real)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==char[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v,prec));
    } else static if (is(T==ifloat)||is(T==idouble)||is(T==ireal)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==char[])){
            if (args[0].length>1){
                parseInt(args[0][1..$],prec);
            }
        }
        sink(formatFloat(buf,v.im,prec));
        sink("*1i");
    } else static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
        char[40] buf;
        int prec=6;
        static if (is(S[0]==char[])){
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
                sink("<");
                sink(T.stringof);
                sink(" *NULL*>");
                return;
            }
        }
        static if(is(typeof(v.desc(sink,args)))){
            v.desc(sink,args);
        } else static if(is(typeof(v.desc(sink.call,args)))){
            v.desc(sink.call,args);
        } else static if(is(typeof(v.desc(sink)))){
            v.desc(sink);
        } else static if(is(typeof(v.desc(sink.call)))){
            v.desc(sink.call);
        } else static if (is(typeof(v.toString()))){
            sink(v.toString);
        }else{
            static assert(0,"unsupported type in writeOut "~T.stringof);
        }
    }
}

/// helper to easily dump out data
struct Dumper(T){
    T call;
    Dumper opCall(U)(U u){
        static if(is(U==void delegate(T))){
            u(call);
        } else static if (is(typeof(call(u)))){
            call(u);
        } else static if (is(typeof((*call)(u)))){
            (*call)(u);
        } else static if (is(typeof(writeOut(call,u)))){ 
            writeOut(call,u);
        } else static if (is(typeof(writeOut(*call,u)))){ 
            writeOut(*call,u);
        } else {
            static assert(0,"Dumper!("~T.stringof~") cannot handle "~U.stringof);
        }
        return *this;
    }
}
/// ditto
Dumper!(T) dumper(T)(T c){
    static if(is(typeof(c is null))){
        assert(!(c is null),"dumper cannot be null");
    }
    Dumper!(T) res;
    res.call=c;
    return res;
}
/// helper to easily dump out data that controls that it receives a pointer like el
Dumper!(T) dumperP(T)(T c){
    static if(is(typeof(c is null))){
        assert(!(c is null),"dumper cannot be null");
        Dumper!(T) res;
        res.call=c;
        return res;
    } else {
        static assert(0,"non pointer like argument "~T.stringof);
    }
}

