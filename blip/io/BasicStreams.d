/// basic "high level" streams
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
module blip.io.BasicStreams;
import blip.io.BasicIO;
import blip.Comp;
import blip.text.UtfUtils: convertToString;


/// basic stream based on a binary sink, no encoding conversion for strings, dangerous to mix!
final class BasicBinStream: OutStreamI{
    BinSink sink;
    void delegate() _flush;
    void delegate() _close;
    string dsc;
    void delegate(CharSink) dscWriter;
    
    void _writeDsc(CharSink s){
        s(dsc);
    }
    this(string dsc,BinSink s,void delegate()f=null,void delegate()c=null,void delegate(CharSink)dscW=null){
        this.sink=s;
        this._flush=f;
        this._close=c;
        this.dsc=dsc;
        if (dscW !is null){
            this.dscWriter=dscW;
        } else {
            this.dscWriter=&_writeDsc;
        }
    }
    this(void delegate(CharSink)dscW,BinSink s,void delegate()f=null,void delegate()c=null){
        this("",s,f,c,dscW);
    }
    
    void rawWrite(void[] a){
        this.sink(a);
    }
    void rawWriteStrC(cstring s){
        this.sink(s);
    }
    void rawWriteStrW(cstringw s){
        this.sink(s);
    }
    void rawWriteStrD(cstringd s){
        this.sink(s);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    void rawWriteStr(cstring s){
        this.sink(s);
    }
    void rawWriteStr(cstringw s){
        this.sink(s);
    }
    void rawWriteStr(cstringd s){
        this.sink(s);
    }
    CharSink charSink(){
        return &this.rawWriteStrC; // cast(void delegate(cstring))rawWriteStr does not work on older compilers
    }
    BinSink binSink(){
        return sink;
    }
    void flush(){
        if (_flush!is null){
            _flush();
        }
    }
    void close(){
        flush();
        if (_close!is null){
            _close();
        }
    }
    void desc(CharSink s){
        dscWriter(s);
    }
}

/// basic stream based on a string sink, uses the type T as native type, the others are converted
final class BasicStrStream(T=char): OutStreamI{
    void delegate(Const!(T)[]) sink;
    void delegate() _flush;
    void delegate() _close;
    string dsc;
    void delegate(CharSink) dscWriter;
    
    void _writeDsc(CharSink s){
        s(dsc);
    }
    this(string dsc,void delegate(Const!(T)[]) s,void delegate()f=null,void delegate()c=null,OutWriter dscW=null){
        this.sink=s;
        this._flush=f;
        this._close=c;
        this.dsc=dsc;
        if (dscW!is null){
            this.dscWriter=dscW;
        } else {
            this.dscWriter=&_writeDsc;
        }
    }
    this(OutWriter dsc,void delegate(Const!(T)[]) s,void delegate()f=null,void delegate()c=null){
        this("",s,f,c,dsc);
    }
    void rawWrite(void[] a){ // written in hex format
        writeOut(this.sink,(cast(ubyte*)a.ptr)[0..a.length],"x");
    }
    /// writes a raw string
    void writeStr(U)(U data){
        alias Unqual!(U) V;
        static if (is(V==T[])){
            sink(data);
        } else static if (is(V==char[])||is(V==wchar[])||is(V==dchar[])){
            if (data.length<240){
                T[256] buf;
                auto s=convertToString!(T)(data,buf);
                sink(s);
            } else {
                scope T[] s=convertToString!(T)(data);
                sink(s);
            }
        } else {
            static assert(0,U.stringof~" is not supported by BasicStrStream!("~T.stringof~").writeStr");
        }
    }
    // alias writeStr!(char)  rawWriteStrC;
    // alias writeStr!(wchar) rawWriteStrW;
    // alias writeStr!(dchar) rawWriteStrD;
    void rawWriteStrC(cstring s){
        writeStr(s);
    }
    void rawWriteStrW(cstringw s){
        writeStr(s);
    }
    void rawWriteStrD(cstringd s){
        writeStr(s);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    void rawWriteStr(cstring s){
        writeStr(s);
    }
    void rawWriteStr(cstringw s){
        writeStr(s);
    }
    void rawWriteStr(cstringd s){
        writeStr(s);
    }
    void flush(){
        if (_flush!is null) _flush();
    }
    CharSink charSink(){
        static if (is(T==char)){
            return this.sink;
        } else {
            return &this.writeStr!(Const!(char)[]); // cast(void delegate(cstring))rawWriteStr does not work on older compilers
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
    void close(){
        if (_close!is null)
            _close();
    }
    void desc(CharSink s){
        dscWriter(s);
    }
}

/// buffered stream based on a binary sink, no encoding conversion for strings, dangerous to mix!
/// allow it to accept also a size_t delegate(void[]) ? it could be slightly more efficient,
/// avoiding some suspensions...
/// cannot be used by several threads/tasks at once!
final class BufferedBinStream: OutStreamI{
    BinSink _sink;
    void delegate() _flush;
    void delegate() _close;
    ubyte[] buf;
    size_t content;
    string dsc;
    void delegate(CharSink) dscWriter;
    
    void _writeDsc(CharSink s){
        s(dsc);
    }

    this(string dsc,BinSink s,size_t bufDim=512, void delegate()f=null, void delegate()c=null){
        this(dsc,s,new ubyte[](bufDim),f,c);
    }
    this(string dsc,BinSink s,ubyte[] buf,void delegate()f=null, void delegate()c=null,OutWriter dscW=null){
        this._sink=s;
        this.buf=buf;
        this._flush=f;
        this._close=c;
        this.content=0;
        this.dsc=dsc;
        if (dscW!is null){
            this.dscWriter=dscW;
        } else {
            this.dscWriter=&_writeDsc;
        }
    }
    this(OutWriter dsc,BinSink s,size_t bufDim=512, void delegate()f=null, void delegate()c=null){
        this("",s,new ubyte[](bufDim),f,c,dsc);
    }
    this(OutWriter dsc,BinSink s,ubyte[] buf,void delegate()f=null, void delegate()c=null){
        this("",s,buf,f,c,dsc);
    }
    
    void sink(void[]data){
        if (data.length<=buf.length-content){
            buf[content..content+data.length]=cast(ubyte[])data;
            content+=data.length;
        } else {
            if (content<buf.length/2){
                auto nread=buf.length-content;
                buf[content..$]=cast(ubyte[])data[0..nread];
                _sink(buf);
                if(data.length-nread>buf.length){
                    _sink(data[nread..$]);
                    content=0;
                } else {
                    content=data.length-nread;
                    buf[0..content]=cast(ubyte[])data[nread..$];
                }
            } else {
                _sink(buf[0..content]);
                if(data.length>buf.length){
                    _sink(data);
                    content=0;
                } else {
                    content=data.length;
                    buf[0..data.length]=cast(ubyte[])data;
                }
            }
        }
    }
    void rawWrite(void[] a){
        this.sink(a);
    }
    void rawWriteStrC(cstring s){
        this.sink(s);
    }
    void rawWriteStrW(cstringw s){
        this.sink(s);
    }
    void rawWriteStrD(cstringd s){
        this.sink(s);
    }
    void rawWriteStr(cstring s){
        this.sink(s);
    }
    void rawWriteStr(cstringw s){
        this.sink(s);
    }
    void rawWriteStr(cstringd s){
        this.sink(s);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    CharSink charSink(){
        return &this.rawWriteStrC; // cast(void delegate(cstring))rawWriteStr does not work on older compilers
    }
    BinSink binSink(){
        return &this.sink;
    }
    void flush(){
        _sink(buf[0..content]);
        content=0;
        if (_flush!is null) _flush();
    }
    void close(){
        if (_close!is null)
            _close();
    }
    void desc(CharSink s){
        dscWriter(s);
    }
}

/// basic stream based on a string sink, uses the type T as native type, the others are converted
final class BufferedStrStream(T=char): OutStreamI{
    void delegate(Const!(T)[]) _sink;
    void delegate() _flush;
    void delegate() _close;
    Const!(T)[] buf;
    size_t content;
    string dsc;
    
    this(string dsc,CharSink s,size_t bufDim=512,void delegate()f=null,void delegate()c=null){
        this(dsc,s,new T[](bufDim),f,c);
    }
    
    this(string dsc,CharSink s,T[] buf,void delegate()f=null,void delegate()c=null,OutWriter dscW=null){
        this._sink=s;
        this.buf=buf;
        this._flush=f;
        this._close=c;
        this.content=0;
        this.dsc=dsc;
        if (dscW!is null){
            this.dscWriter=dscW;
        } else {
            this.dscWriter=&_writeDsc;
        }
    }
    this(OutWriter dsc,CharSink s,size_t bufDim=512,void delegate()f=null,void delegate()c=null){
        this("",s,new T[](bufDim),f,c,dsc);
    }
    
    this(OutWriter dsc,CharSink s,T[] buf,void delegate()f=null,void delegate()c=null){
        this("",s,buf,f,c,dsc);
    }
    
    void sink(Const!(T)[]data){
        synchronized(this){
            if (data.length<=buf.length-content){
                buf[content..content+data.length]=data;
                content+=data.length;
            } else {
                if (content<buf.length/2){
                    auto nread=buf.length-content;
                    buf[content..$]=data[0..written];
                    _sink(buf);
                    if(data.length-nread>buf.length){
                        _sink(data[nread..$]);
                        content=0;
                    } else {
                        content=data.length-nread;
                        buf[0..content]=data[nread..$];
                    }
                } else {
                    _sink(buf[0..content]);
                    if(data.length>buf.length){
                        _sink(data);
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
        alias Unqual!(U) V;
        static if (is(V==T[])){
            sink(data);
        } else static if (is(V==char[])||is(V==wchar[])||is(V==dchar[])){
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
    // alias writeStr!(char)  rawWriteStrC;
    // alias writeStr!(wchar) rawWriteStrW;
    // alias writeStr!(dchar) rawWriteStrD;
    void rawWriteStrC(cstring s){
        writeStr(s);
    }
    void rawWriteStrW(cstringw s){
        writeStr(s);
    }
    void rawWriteStrD(cstringd s){
        writeStr(s);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    void rawWriteStr(cstring s){
        writeStr(s);
    }
    void rawWriteStr(cstringw s){
        writeStr(s);
    }
    void rawWriteStr(cstringd s){
        writeStr(s);
    }
    void flush(){
        if (_flush!is null) _flush();
    }
    CharSink charSink(){
        static if (is(T==char)){
            return &this.sink;
        } else {
            return &this.writeStr!(char); // cast(void delegate(cstring))rawWriteStr does not work on older compilers
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
    void close(){
        if (_close!is null)
            _close();
    }
    void desc(CharSink s){
        dscWriter(s);
    }
}
