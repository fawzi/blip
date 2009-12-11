/// basic IO definitions
module blip.io.BasicIO;
import blip.t.util.Convert: formatFloat;
import blip.t.core.Array: find;
import blip.t.core.Traits: isStaticArrayType;
import blip.text.UtfUtils: convertToString;

/// extent of a slice of a buffer
enum SliceExtent{ Partial, Maximal, ToEnd }

alias void delegate(void delegate(char[]))  OutWriter;
alias void delegate(void delegate(void[]))  BinWriter;
alias size_t delegate(char[], SliceExtent slice,out bool iterate)  OutReader;
alias size_t delegate(ubyte[], SliceExtent slice,out bool iterate) BinReader;
alias void delegate(char[]) CharSink;
alias void delegate(void[]) BinSink;

interface OutStreamI{
    void rawWriteStr(char[]);
    void rawWriteStr(wchar[]);
    void rawWriteStr(dchar[]);
    void rawWrite(void[]);
    CharSink charSink();
    BinSink  binSink();
    void flush();
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
            auto spce="        ";
            while(width>0){
                auto toAdd=((spce.length<width)?spce.length:cast(size_t)width);
                sink1(spce[0..toAdd]);
                width-=toAdd;
            }
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
            res[pos]='-';
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
        } else static if (is(typeof(writeOut(call,u)))){ 
            writeOut(call,u);
        } else {
            static assert(0,"Dumper!("~T.stingof~") cannot handle "~U.stringof);
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

/// basic stream based on a binary sink
class BasicBinStream: OutStreamI{
    BinSink sink;
    void delegate() _flush;
    this(BinSink s,void delegate()f=null){
        this.sink=s;
        this._flush=f;
    }
    void rawWrite(void[] a){
        this.sink(a);
    }
    void rawWriteStrD(char[]s){
        this.sink(s);
    }
    void rawWriteStr(char[]s){
        this.sink(s);
    }
    void rawWriteStr(wchar[]s){
        this.sink(s.ptr[0..(s.length*wchar.sizeof)]);
    }
    void rawWriteStr(dchar[]s){
        this.sink(s.ptr[0..(s.length*dchar.sizeof)]);
    }
    CharSink charSink(){
        return &this.rawWriteStrD; // cast(void delegate(char[]))rawWriteStr does not work on older compilers
    }
    BinSink binSink(){
        return sink;
    }
    void flush(){
        if (_flush!is null) _flush();
    }
}

/// basic stream based on a string sink
class BasicStrStream(T=char): OutStreamI{
    void delegate(T[]) sink;
    void delegate() _flush;
    this(void delegate(T[]) s,void delegate()f=null){
        this.sink=s;
        this._flush=f;
    }
    void rawWrite(void[] a){
        writeOut(this.sink,(cast(ubyte*)a.ptr)[0..a.length],"x");
    }
    /// writes a raw string
    void writeStr(U)(U[]data){
        static if (is(U==T[])){
            sink(data);
        } else static if (is(U==char[])||is(U==wchar[])||is(U==dchar[])){
            T[] s;
            if (t.length<240){
                T[256] buf;
                s=convertToString!(T)(t,buf);
            } else {
                s=convertToString!(T)(t);
            }
            sink(s);
        }
    }
    // alias writeStr!(char)  rawWriteStr;
    // alias writeStr!(wchar) rawWriteStr;
    // alias writeStr!(dchar) rawWriteStr;
    void rawWriteStr(char[]s){
        writeStr(s);
    }
    void rawWriteStr(wchar[]s){
        writeStr(s);
    }
    void rawWriteStr(dchar[]s){
        writeStr(s);
    }
    void flush(){
        if (_flush!is null) _flush();
    }
    CharSink charSink(){
        static if (is(T==char)){
            return sink;
        } else {
            return &this.writeStr!(char); // cast(void delegate(char[]))rawWriteStr does not work on older compilers
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
}

