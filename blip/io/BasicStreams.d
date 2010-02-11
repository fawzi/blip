module blip.io.BasicStreams;
import blip.io.BasicIO;

/// basic stream based on a binary sink, no encoding conversion for strings, dangerous to mix!
final class BasicBinStream: OutStreamI{
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
        this.sink(s);
    }
    void rawWriteStr(dchar[]s){
        this.sink(s);
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

/// basic stream based on a string sink, uses the type T as native type, the others are converted
final class BasicStrStream(T=char): OutStreamI{
    void delegate(T[]) sink;
    void delegate() _flush;
    this(void delegate(T[]) s,void delegate()f=null){
        this.sink=s;
        this._flush=f;
    }
    void rawWrite(void[] a){ // written in hex format
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
            return this.sink;
        } else {
            return &this.writeStr!(char); // cast(void delegate(char[]))rawWriteStr does not work on older compilers
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
}

/// basic stream based on a binary sink, no encoding conversion for strings, dangerous to mix!
final class BufferedBinStream: OutStreamI{
    BinSink _sink;
    void delegate() _flush;
    ubyte[] buf;
    size_t content;

    this(BinSink s,size_t bufDim=512, void delegate()f=null){
        this(s,new ubyte[](bufDim),f);
    }
    this(BinSink s,ubyte[] buf,void delegate()f=null){
        this._sink=s;
        this.buf=buf;
        this._flush=f;
        this.content=0;
    }
    void sink(void[]data){
        synchronized(this){
            if (data.length<=buf.length-content){
                buf[content..content+data.length]=cast(ubyte[])data;
                content+=data.length;
            } else {
                if (content<buf.length/2){
                    auto nread=buf.length-content;
                    buf[content..$]=cast(ubyte[])data[0..nread];
                    sink(buf);
                    if(data.length-nread>buf.length){
                        sink(data[nread..$]);
                        content=0;
                    } else {
                        content=data.length-nread;
                        buf[0..content]=cast(ubyte[])data[nread..$];
                    }
                } else {
                    sink(buf[0..content]);
                    if(data.length>buf.length){
                        sink(data);
                        content=0;
                    } else {
                        content=data.length;
                        buf[0..data.length]=cast(ubyte[])data;
                    }
                }
            }
        }
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
        this.sink(s);
    }
    void rawWriteStr(dchar[]s){
        this.sink(s);
    }
    CharSink charSink(){
        return &this.rawWriteStrD; // cast(void delegate(char[]))rawWriteStr does not work on older compilers
    }
    BinSink binSink(){
        return &this.sink;
    }
    void flush(){
        synchronized(this){
            sink(buf[0..content]);
            content=0;
        }
        if (_flush!is null) _flush();
    }
}

/// basic stream based on a string sink, uses the type T as native type, the others are converted
final class BufferedStrStream(T=char): OutStreamI{
    void delegate(T[]) _sink;
    void delegate() _flush;
    T[] buf;
    size_t content;
    
    this(CharSink s,size_t bufDim=512,void delegate()f=null){
        this(s,new T[](bufDim),f);
    }
    
    this(CharSink s,T[] buf,void delegate()f=null){
        this._sink=s;
        this.buf=buf;
        this._flush=f;
        this.content=0;
    }
    
    void sink(T[]data){
        synchronized(this){
            if (data.length<=buf.length-content){
                buf[content..content+data.length]=data;
                content+=data.length;
            } else {
                if (content<buf.length/2){
                    auto nread=buf.length-content;
                    buf[content..$]=data[0..written];
                    sink(buf);
                    if(data.length-nread>buf.length){
                        sink(data[nread..$]);
                        content=0;
                    } else {
                        content=data.length-nread;
                        buf[0..content]=data[nread..$];
                    }
                } else {
                    sink(buf[0..content]);
                    if(data.length>buf.length){
                        sink(data);
                        content=0;
                    } else {
                        content=data.length;
                        buf[0..data.length]=data;
                    }
                }
            }
        }
    }
    
    void rawWrite(void[] a){ // written in hex format
        writeOut(&this.sink,(cast(ubyte*)a.ptr)[0..a.length],"x");
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
            return &this.sink;
        } else {
            return &this.writeStr!(char); // cast(void delegate(char[]))rawWriteStr does not work on older compilers
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
}
