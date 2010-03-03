/// buffered input from a basic reader
/// author: Fawzi
module blip.io.BufferIn;
import blip.io.BasicIO;
import blip.text.UtfUtils;
import blip.t.stdc.string: memmove,memcpy;
import blip.t.math.Math: min;

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
    
    this(size_t delegate(TInt[]) basicReader,TBuf[] buf,size_t encodingOverhead=ulong.sizeof/TInt.sizeof,void delegate() shutdown=null){
        assert(buf.length>encodingOverhead,"buf too small");
        this.buf=buf;
        bufPos=0;
        bufLen=0;
        _read=basicReader;
        slice=SliceExtent.Partial;
        _shutdownInput=shutdown;
    }
    this(size_t delegate(TInt[]) basicReader,size_t bufLen=512,size_t encodingOverhead=0){
        this(basicReader,new TBuf[](bufLen),encodingOverhead);
    }
    
    void loadMore(bool insist=true){
        if (slice==SliceExtent.ToEnd) return;
        if (bufLen+encodingOverhead<buf.length){
            if (bufPos+bufPos+encodingOverhead>buf.length) compact();
            auto readNow=_read(buf[bufPos+bufPos..buf.length]);
            if (readNow==Eof) {
                slice=SliceExtent.ToEnd;
                return;
            } else if (readNow!=0){
                bufLen+=readNow;
            } else {
                compact();
                while(readNow==0 && readNow!=Eof && insist){
                    readNow=_read(buf[bufPos+bufPos..buf.length]);
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
            bufLen-=outBuf.length;
            bufPos+=outBuf.length;
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
        size_t readNow;
        if (outLen>buf.length/2){
            readNow=_read(outPtr[bufLen..outLen]);
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
        if (readNow==Eof){
            slice=SliceExtent.ToEnd;
            if (readTot!=0){
                throw new BIOException("partial read at end of file",__FILE__,__LINE__);
            }
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
    
    bool handleReaderT(TOut)(size_t delegate(TOut[], SliceExtent slice,out bool iterate) r){
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
            if (slice!=SliceExtent.ToEnd || bufOut.length==bufOut1.length)
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
    bool handleReader(size_t delegate(TInt[], SliceExtent slice,out bool iterate) r){
        return handleReaderT!(TInt)(r);
    }
    
    /// a reader that reinterprets the memory
    static final class ReinterpretReader(T):Reader!(T){
        BufferIn buf;
        
        this(BufferIn buf){
            this.buf=buf;
        }

        /// exact reader 
        size_t readSome(T[] t){
            this.buf.readSomeT!(T)(t);
        }
        
        ///  reader handler
        bool handleReader(size_t delegate(T[], SliceExtent slice,out bool iterate) r){
            return this.buf.handleReaderT!(T)(r);
        }
        
        void shutdownInput(){
            this.buf.shutdownInput();
        }
    }
    
    /// returns a reader that reinterprets the memory
    ReinterpretReader!(T) reinterpretReader(T)(){
        return new ReinterpretReader!(T)(this);
    }
}

/// a class that supports all reading streams on the top of a binary stream
/// convenient, but innerently unsafe
final class MixedSource/+: MultiReader+/{
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
    this(size_t delegate(void[]) basicReader){
        this(new BufferIn!(void)(basicReader));
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
    
    this(size_t delegate(T[])r){
        this(new BufferIn!(T)(r));
    }
    this(bool delegate(size_t delegate(T[], SliceExtent slice,out bool iterate)) reader){
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
    
}

