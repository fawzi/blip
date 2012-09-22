/// buffered input from a basic reader
/// author: Fawzi
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
module blip.io.BufferIn;
import blip.io.BasicIO;
import blip.text.UtfUtils;
import blip.stdc.string: memmove;
import blip.math.Math: min;
import blip.container.GrowableArray;
import blip.Comp;
version(TrackBInReadSome) import blip.io.Console;

/// a reader that reinterprets the memory
final class ReinterpretReader(U,T):Reader!(T){
    BufferIn!(U) buf;
    
    this(BufferIn!(U) buf){
        this.buf=buf;
        this.dsc=dsc;
    }
    

    /// reader 
    size_t readSome(T[] t){
        return this.buf.readSomeT!(T)(t);
    }
    
    ///  reader handler
    bool handleReader(scope size_t delegate(in T[], SliceExtent slice,out bool iterate) r){
        return this.buf.handleReaderT!(T)(r);
    }
    
    void shutdownInput(){
        this.buf.shutdownInput();
    }
    
    void desc(scope CharSink s){
        s("ReinterpretReader!(");s(U.stringof); s(","); s(T.stringof); s(")(");
        writeOut(s,buf); s(")");
    }
}

final class BufferIn(TInt):Reader!(TInt){
    static if(is(TInt==void)){
        alias ubyte TBuf;
    } else {
        alias TInt TBuf;
    }
    TBuf[] buf;
    size_t bufPos;
    size_t bufLen;
    size_t delegate(TInt[]) _read;
    SliceExtent slice;
    size_t encodingOverhead;
    void delegate() _shutdownInput;
    string dsc;
    void delegate(scope CharSink) dscWriter;
    
    void _writeDesc(scope CharSink s){
        s(dsc);
    }
    
    this(void delegate(scope CharSink) dscW,size_t delegate(TInt[]) basicReader,TBuf[] buf,size_t encodingOverhead=ulong.sizeof/TInt.sizeof,void delegate() shutdown=null,size_t bufLen=0,size_t bufPos=0){
        this("",basicReader,buf,encodingOverhead,shutdown,bufLen,bufPos,dscW);
    }
    this(string dsc,size_t delegate(TInt[]) basicReader,TBuf[] buf,size_t encodingOverhead=ulong.sizeof/TInt.sizeof,void delegate() shutdown=null,size_t bufLen=0,size_t bufPos=0,void delegate(scope CharSink) dscW=null){
        assert(buf.length>encodingOverhead,"buf too small");
        this.buf=buf;
        this.bufPos=bufPos;
        this.bufLen=bufLen;
        this.dsc=dsc;
        if (dscW!is null){
            this.dscWriter=dscW;
        } else {
            this.dscWriter=&_writeDesc;
        }
        assert(bufPos<=buf.length && bufPos+bufLen<=buf.length,"invalid bufPos/bufLen");
        _read=basicReader;
        slice=SliceExtent.Partial;
        _shutdownInput=shutdown;
    }
    static if(is(TInt==void)){
        this(string dsc,size_t delegate(TInt[]) basicReader,TInt[] buf,size_t encodingOverhead=ulong.sizeof/TInt.sizeof,void delegate() shutdown=null,size_t bufLen=0,
            size_t bufPos=0){
            this(dsc,basicReader, cast(TBuf[])buf, encodingOverhead, shutdown, bufLen, bufPos);
        }
        this(OutWriter dsc,size_t delegate(TInt[]) basicReader,TInt[] buf,size_t encodingOverhead=ulong.sizeof/TInt.sizeof,void delegate() shutdown=null,size_t bufLen=0,
            size_t bufPos=0){
            this(dsc,basicReader, cast(TBuf[])buf, encodingOverhead, shutdown, bufLen, bufPos);
        }
    }
    this(string dsc,size_t delegate(TInt[]) basicReader,size_t bufLen=512,size_t encodingOverhead=0){
        this(dsc,basicReader,new TBuf[](bufLen),encodingOverhead);
    }
    this(OutWriter dsc,size_t delegate(TInt[]) basicReader,size_t bufLen=512,size_t encodingOverhead=0){
        this(dsc,basicReader,new TBuf[](bufLen),encodingOverhead);
    }
    
    void loadMore(bool insist=true){
        version(TrackBInReadSome){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("BufferIn@")(cast(void*)this)(",pre loadMore,")
                    ("buffer contents:\n'")(buf[bufPos..bufPos+bufLen])("'\n");
            });
            scope(exit){
                sinkTogether(sout,delegate void(scope CharSink s){
                    dumper(s)("BufferIn@")(cast(void*)this)(",post loadMore,")
                        ("buffer contents:\n'")(buf[bufPos..bufPos+bufLen])("'\n");
                });
            }
        }
        if (slice==SliceExtent.ToEnd) return;
        if (bufLen+encodingOverhead<buf.length){
            if (bufPos+bufLen+encodingOverhead>=buf.length) compact();
            while(insist){
                auto readNow=_read(buf[bufPos+bufLen..buf.length]);
                if (readNow==Eof) {
                    slice=SliceExtent.ToEnd;
                    return;
                } else if (readNow!=0){
                    bufLen+=readNow;
                    break;
                } else {
                    compact();
                }
            }
        }
        if (bufLen+encodingOverhead<buf.length){
            slice=SliceExtent.Partial;
        } else {
            slice=SliceExtent.Maximal;
        }
    }
    // in internal units
    void consumeInt(size_t amount){
        if (amount<=bufLen){
            bufPos+=amount;
            bufLen-=amount;
            return;
        }
        while(bufLen<=amount){
            amount-=bufLen;
            bufLen=0;
            bufPos=0;
            bufLen=_read(buf);
            if (bufLen==Eof){
                bufLen=0;
                slice=SliceExtent.ToEnd;
                throw new BIOException("unexpected Eof in consume",__FILE__,__LINE__);
            }
        }
        bufPos+=amount;
        bufLen-=amount;
    }

    /// consumes the given number of TOut units
    void consumeOut(TOut)(size_t amount){
        static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
        static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
        enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}
        consumeInt(amount*OutToIn);
    }
    
    void compact(){
        if (bufPos!=0){
            assert(bufPos+bufLen<=buf.length);
            memmove(buf.ptr,buf.ptr+bufPos,bufLen*TBuf.sizeof);
            bufPos=0;
        }
    }
    
    void clear(){
        bufPos=0;
        bufLen=0;
        slice=SliceExtent.Partial;
    }

    size_t readSomeT(TOut)(TOut[]outBuf){
        version(TrackBInReadSome){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("readSome started need to read ")(outBuf.length)(" ")(TOut.stringof)(",")
                    ("buffer contents:\n'")(buf[bufPos..bufPos+bufLen])("'\n");
            });
        }
        static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
        static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
        enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}
        
        if (outBuf.length%TInt.sizeof!=0){
            throw new BIOException("external size needs to be a multiple of internal size",__FILE__,__LINE__);
        }

        auto outLen=outBuf.length*OutToIn;
        auto outPtr=cast(TBuf*)outBuf.ptr;
        size_t readTot=0;
        if (outLen <=bufLen){
            outPtr[0..outLen]=buf[bufPos..bufPos+outLen];
            bufLen-=outLen;
            bufPos+=outLen;
            return outBuf.length;
        } else if (bufLen>0){
            auto rest=bufLen%OutToIn;
            auto bLen=bufLen-rest;
            if (bLen!=0){
                outPtr[0..bLen]=buf[bufPos..bufPos+bLen];
                bufLen-=bLen;
                if (bufLen==0){
                    bufPos=0;
                } else {
                    bufPos+=bLen;
                }
                return bLen/OutToIn;
            } else {
                readTot=rest;
                outPtr[0..rest]=buf[bufPos..bufPos+rest];
                bufLen=0;
                bufPos=0;
            }
        } else if (slice==SliceExtent.ToEnd) {
            return Eof;
        }
        version(TrackBInReadSome) sout("BufferIn.readSome switching to real read\n");
        size_t readNow;
        if (outLen>buf.length/2){
            readNow=_read(outPtr[readTot..outLen]);
        } else {
            if (bufPos!=0) compact(); // should never be needed...
            auto rNow=_read(buf[bufPos+bufLen..$]);
            if (rNow!=Eof){
                auto toCopy=min(rNow+bufLen,outLen-readTot);
                outPtr[readTot..readTot+toCopy]=buf[bufPos..bufPos+toCopy];
                bufLen+=rNow-toCopy;
                if (bufLen==0){
                    bufPos=0;
                } else {
                    bufPos+=toCopy;
                }
                readNow=toCopy;
            } else {
                readNow=Eof;
            }
        }
        version(TrackBInReadSome){
            sinkTogether(sout,delegate void(scope CharSink s){
                dumper(s)("readSome after realRead the buffer contents are:\n'")(buf[bufPos..bufPos+bufLen])("'\n");
            });
        }
        if (readNow==Eof){
            slice=SliceExtent.ToEnd;
            return Eof;
        }
        readTot+=readNow;
        auto rest=readTot%OutToIn;
        if (rest != 0){
            assert(bufLen==0);
            buf[0..rest]=outPtr[readTot-rest..readTot];
            bufLen=rest;
            bufPos=0;
        }
        return readTot/OutToIn; // as rest/OutToIn==0
    }
    
    bool handleReaderT(TOut)(scope size_t delegate(in TOut[], SliceExtent slice,out bool iterate) r){
        static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
        static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
        enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}

        if (bufPos%TOut.alignof!=0) compact();
        if (bufLen<encodingOverhead+buf.length/10||bufLen<TOut.sizeof) loadMore(false);
        bool readSome=false;
        while (true){
            bool iterate=false;
            TOut[] bufOut1=(cast(TOut*)(buf.ptr+bufPos))[0..bufLen/OutToIn];
            static if (is(TOut==char)||is(TOut==wchar)||is(TOut==dchar)){
                auto bufOut=cropRight(bufOut1);
            } else {
                alias bufOut1 bufOut;
            }
            if (slice==SliceExtent.ToEnd && bufOut.length!=bufOut1.length)
                throw new BIOException("invalid utf data at end of stream",__FILE__,__LINE__);
            auto consumed=r(bufOut,slice,iterate);
            switch (consumed){
            case Eof:
                switch (slice){
                case SliceExtent.Partial:
                    loadMore(true);
                    break;
                case SliceExtent.Maximal:
                    throw new BIOException("window too small to parse",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    throw new BIOException("cannot read past Eof",__FILE__,__LINE__);
                default:
                    throw new Exception("invalid SliceExtent",__FILE__,__LINE__);
                }
                break;
            case 0:
                if (!iterate){
                    return readSome;
                }
                break;
            default:
                consumeInt(consumed*OutToIn);
                if (!iterate) return true;
                readSome=true;
                if (bufPos%TOut.alignof!=0) compact();
            }
        }
    }
    
    void shutdownInput(){
        if (_shutdownInput!is null){
            _shutdownInput();
        }
    }
    
    // http://d.puremagic.com/issues/show_bug.cgi?id=3472
    // alias readSomeT!(TInt) readSome;
    // alias handleReaderT!(TInt) handleReader;
    size_t readSome(TInt[] a){
        return readSomeT!(TInt)(a);
    }
    bool handleReader(scope size_t delegate(in TInt[], SliceExtent slice,out bool iterate) r){
        return handleReaderT!(TInt)(r);
    }
    
    /// returns a reader that reinterprets the memory
    ReinterpretReader!(TInt,T) reinterpretReader(T)(){
        return new ReinterpretReader!(TInt,T)(this);
    }
    
    void desc(scope CharSink s){
        dscWriter(s);
    }
}

/// a reader that reads the contents of an array
BufferIn!(T) arrayReader(T)(string dsc,T[] a){
    auto res=new BufferIn!(T)(dsc,delegate size_t(T[] b){ return Eof; },a,0,null,a.length,0);
    res.slice=SliceExtent.ToEnd;
    return res;
}

/// a class that supports all reading streams on the top of a binary stream
/// convenient, but innerently unsafe
final class MixedSource: MultiReader {
    Reader!(char)   _readerChar;
    Reader!(wchar)  _readerWchar;
    Reader!(dchar)  _readerDchar;
    Reader!(void)   _readerBin;
    uint _modes=MultiReader.Mode.Binary|MultiReader.Mode.Char|
        MultiReader.Mode.Wchar|MultiReader.Mode.Dchar;
    uint _nativeModes=MultiReader.Mode.Binary|MultiReader.Mode.Char|
        MultiReader.Mode.Wchar|MultiReader.Mode.Dchar;
    
    this(BufferIn!(void) buf){
        _readerBin=buf;
        //_readerChar=buf.reinterpretReader!(char)();
        //_readerWchar=buf.reinterpretReader!(wchar)();
        //_readerDchar=buf.reinterpretReader!(dchar)();
    }
    this(string dsc,size_t delegate(void[]) basicReader){
        this(new BufferIn!(void)(dsc,basicReader));
    }
    this(void delegate(scope CharSink) dscW,size_t delegate(void[]) basicReader){
        this(new BufferIn!(void)(dscW,basicReader));
    }
    uint modes(){
        return _modes;
    }
    uint nativeModes(){
        return _nativeModes;
    }
    Reader!(char) readerChar(){
        assert(_readerChar!is null);
        return _readerChar;
    }
    Reader!(wchar) readerWchar(){
        assert(_readerWchar!is null);
        return _readerWchar;
    }
    Reader!(dchar) readerDchar(){
        assert(_readerDchar!is null);
        return _readerDchar;
    }
    Reader!(void)  readerBin(){
        assert(_readerBin!is null);
        return _readerBin;
    }
    void shutdownInput(){
        if (_readerChar !is null) _readerChar.shutdownInput();
        else if (_readerWchar !is null ) _readerWchar.shutdownInput();
        else if (_readerDchar !is null ) _readerDchar.shutdownInput();
        else if (_readerBin !is null ) _readerBin.shutdownInput();
    }
    void desc(scope CharSink s){
        dumper(s)("MultiReader(")(_readerChar)(",")(_readerWchar)(",")(_readerDchar)(",")(_readerBin)(")");
    }
}

/// a class that supports all character streams on the top of a character stream
/// allocates converters upon request (to do, at the moment single stream)
final class StringReader(T): MultiReader{
    Reader!(T)   mainReader;
    ubyte[] scratchBuf;
    uint lastRead; // to catch when one switches the reader type (and invalidates scratchBuf)
    Reader!(char)   _readerChar;
    Reader!(wchar)  _readerWchar;
    Reader!(dchar)  _readerDchar;
    Reader!(void)   _readerBin;
    static if(is(T==char)){
        uint _nativeModes=MultiReader.Mode.Char;
    } else static if (is(T==wchar)){
        uint _nativeModes=MultiReader.Mode.Wchar;
    } else static if (is(T==dchar)){
        uint _nativeModes=MultiReader.Mode.Dchar;
    } else {
        static assert(0,"unexpected non character type "~T.stringof~" in StringReader");
    }
    uint _modes=_nativeModes;//MultiReader.Mode.Char|MultiReader.Mode.Wchar|MultiReader.Mode.Dchar;
    
    this(string dsc,size_t delegate(T[])r){
        this(new BufferIn!(T)(dsc,r));
    }
    this(OutWriter dscW,size_t delegate(T[])r){
        this(new BufferIn!(T)(dscW,r));
    }
    this(bool delegate(scope size_t delegate(T[], SliceExtent slice,out bool iterate)) reader){
        this(r(basicReader));
    }
    this(Reader!(T) r){
        static if(is(T==char)){
            _readerChar=r;
        } else static if (is(T==wchar)){
            _readerWchar=r;
        } else static if (is(T==dchar)){
            _readerDchar=r;
        }
    }
    uint modes(){
        return _modes;
    }
    uint nativeModes(){
        return _nativeModes;
    }
    
    Reader!(char) readerChar(){
        assert(_readerChar!is null);
        return _readerChar;
    }
    Reader!(wchar) readerWchar(){
        assert(_readerWchar!is null);
        return _readerWchar;
    }
    Reader!(dchar) readerDchar(){
        assert(_readerDchar!is null);
        return _readerDchar;
    }
    Reader!(void)  readerBin(){
        assert(_readerBin!is null);
        return _readerBin;
    }
    void shutdownInput(){
        if (_readerChar !is null) _readerChar.shutdownInput();
        else if (_readerWchar !is null ) _readerWchar.shutdownInput();
        else if (_readerDchar !is null ) _readerDchar.shutdownInput();
        else if (_readerBin !is null ) _readerBin.shutdownInput();
    }
    void desc(scope CharSink s){
        dumper(s)("StringReader!(")(T.stringof)(")(")(_readerChar)(",")(_readerWchar)(",")
            (_readerDchar)(",")(_readerBin)(")");
    }
}

