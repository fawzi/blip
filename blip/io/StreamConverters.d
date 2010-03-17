/// helpers to convert basic tango streams to stream usable in blip
module blip.io.StreamConverters;
import tango.io.model.IConduit;
import tango.core.Array: find;
import blip.text.UtfUtils: cropRight;
import blip.container.GrowableArray;
import blip.io.BasicIO: BIOException, SliceExtent,SmallBufferException,MultiReader,Reader;
import BIO=blip.io.BasicIO;
import tango.io.stream.Buffered;
import blip.io.IOArray;

final class StreamWriter{
    OutputStream writer;
    this(OutputStream s){
        writer=s;
    }
    final void writeExact(void[] src){
        auto written=writer.write(src);
        if (written!=src.length){
            if (written==OutputStream.Eof){
                throw new Exception("unexpected Eof",__FILE__,__LINE__);
            }
            uint countEmpty=0;
            while (1){
                auto writtenNow=writer.write(src[written..$]);
                if (writtenNow==OutputStream.Eof){
                    throw new Exception("unexpected Eof",__FILE__,__LINE__);
                } else if (writtenNow==0){
                    if (countEmpty==100)
                        throw new Exception("unexpected suspension",__FILE__,__LINE__);
                    else
                        ++countEmpty;
                } else {
                    countEmpty=0;
                }
                written+=writtenNow;
                if (written>=src.length) break;
            }
        }
    }

    final void writeExactSync(void[] src){
        synchronized(writer){
            writeExact(src);
        }
    }
    final void flush(){
        writer.flush;
    }
}

void delegate(void[]) binaryDumper(OutputStream s){
    auto res=new StreamWriter(s);
    return &res.writeExact;
}

class StreamStrWriter(T){
    OutputStream writer;
    this(OutputStream s){
        writer=s;
    }
    final void writeStr(T[] src){
        auto written=writer.write(src);
        if (written!=src.length*T.sizeof){
            if (written==OutputStream.Eof){
                throw new Exception("unexpected Eof",__FILE__,__LINE__);
            }
            uint countEmpty=0;
            while (1){
                auto writtenNow=writer.write(src[written..$]);
                if (writtenNow==OutputStream.Eof){
                    throw new Exception("unexpected Eof",__FILE__,__LINE__);
                } else if (writtenNow==0){
                    if (countEmpty==100)
                        throw new Exception("unexpected suspension",__FILE__,__LINE__);
                    else
                        ++countEmpty;
                } else {
                    countEmpty=0;
                }
                written+=writtenNow;
                if (written>=src.length*T.sizeof) break;
            }
        }
    }
    final void writeStrFlushNl(T[] src){
        writeStr(src);
        if (find(src,'\n')!=src.length) writer.flush();
    }
    final void writeStrFlush(T[] src){
        writeStr(src);
        writer.flush();
    }    
    final void writeStrSync(char[] src){
        synchronized(writer){
            writeStr(src);
        }
    }
    final void writeStrSyncFlushNl(T[] src){
        writeStrSync(src);
        if (find(src,'\n')!=src.length) writer.flush();
    }
    final void writeStrSyncFlush(T[] src){
        writeStrSync(src);
        writer.flush();
    }
    void flush(){
        writer.flush();
    }
}

void delegate(T[]) strDumperT(T)(OutputStream s){
    auto res=new StreamStrWriter!(T)(s);
    return &res.writeStr;
}

void delegate(T[]) strDumperSyncT(T)(OutputStream s){
    auto res=new StreamStrWriter!(T)(s);
    return &res.writeStrSync;
}

alias strDumperT!(char) strDumper;
alias strDumperSyncT!(char) strDumperSync;

class ReadHandler(T):Reader!(T){
    BufferedInput buf;
    InputStream arr; // stopgap measure to pass around tango objects (IOArray in particular)
    size_t maxTranscodingOverhead;
    this(BufferedInput b,size_t maxTranscodingOverhead=6){
        buf=b;
        this.maxTranscodingOverhead=maxTranscodingOverhead;
    }
    this(InputStream i,size_t maxTranscodingOverhead=6){
        buf=cast(BufferedInput)i.input;
        if (buf is null){
            arr=i; // hack just for now to pass the IOArray around... the handler is non functional...
            if (arr is null){
                throw new BIOException("invalid input stream (only BufferedInput subclasses are supported)",__FILE__,__LINE__);
            }
        }
        this.maxTranscodingOverhead=maxTranscodingOverhead;
    }
    /// handles a reader
    bool handleReader(size_t delegate (T[],SliceExtent,out bool iterate) scan)
    {
        SliceExtent sliceE=SliceExtent.Partial;
        if (buf !is null){
            if (buf.position == 0 && buf.capacity-buf.limit <=maxTranscodingOverhead){
                sliceE=SliceExtent.Maximal;
            }
        } else {
            sliceE=SliceExtent.ToEnd;
        }
        size_t nonGrow=maxTranscodingOverhead;
        bool matchSuccess=false;
        bool iter=false;
        do {
            while (buf.reader(delegate size_t(void[] rawData)
                    {
                        T[] data=cropRight((cast(T*)rawData.ptr)[0..rawData.length/T.sizeof]);
                        if (sliceE==SliceExtent.ToEnd && data.length!=rawData.length)
                            throw new BIOException("invalid utf data at the end of file",__FILE__,__LINE__);
                        auto res=scan(data,sliceE,iter);
                        if (res != BIO.Eof){
                            matchSuccess=matchSuccess || (res!=0);
                            return T.sizeof*res;
                        } else {
                            return IOStream.Eof;
                        }
                    }) is IOStream.Eof)
            {
                if (sliceE!=SliceExtent.Partial) {
                    if (sliceE==SliceExtent.ToEnd) {
                        return false;
                    } else {
                        throw new SmallBufferException("match needs more space, but buffer is not large enough",__FILE__,__LINE__);
                    }
                }
                if (buf.position != 0){
                    buf.compress;
                }
                auto oldWriteable=buf.capacity-buf.limit;
                // read another chunk of data
                if (buf.populate() is IOStream.Eof) {
                    sliceE=SliceExtent.ToEnd;
                } else if (buf.capacity-buf.limit <= maxTranscodingOverhead) {
                    sliceE=SliceExtent.Maximal;
                } else if (oldWriteable==buf.capacity-buf.limit){
                    // did not grow
                     // worst case should read at least a byte per read attempt,
                     // so transcoding might not happen before maxTranscodingOverhead iterations
                    if (nonGrow==0){
                        throw new BIOException("did not grow and space available bigger than maxTranscodingOverhead",__FILE__,__LINE__);
                    }
                    --nonGrow;
                } else {
                    nonGrow=maxTranscodingOverhead;
                }
            }
        } while(iter);
        return matchSuccess;
    }
    /// read
    size_t readSome(T[] a){
        return buf.read(a);
    }
    /// shutdown the input source (also closes the input)
    void shutdownInput(){
        buf.close();
    }
}

Reader!(T) toReaderT(T)(InputStream i){
    return new ReadHandler!(T)(i);
}

alias toReaderT!(char) toReaderChar;

bool delegate(size_t delegate(T[],SliceExtent,out bool)) readHandlerT(T)(InputStream i){
    auto h=new ReadHandler!(T)(i);
    return &h.handleReader;
}

alias readHandlerT!(char) strReaderHandler;
alias readHandlerT!(void) binaryReaderHandler;

/// a class that supports all reading streams on the top of a binary stream
/// convenient, but innerently unsafe
final class MultiInput: MultiReader{
    Reader!(char)   _readerChar;
    Reader!(wchar)  _readerWchar;
    Reader!(dchar)  _readerDchar;
    Reader!(void)   _readerBin;
    uint _modes=MultiReader.Mode.Binary|MultiReader.Mode.Char|
        MultiReader.Mode.Wchar|MultiReader.Mode.Dchar;
    uint _nativeModes=MultiReader.Mode.Binary|MultiReader.Mode.Char|
        MultiReader.Mode.Wchar|MultiReader.Mode.Dchar;
    
    this(InputStream inStream){
        _readerBin  =new ReadHandler!(void)(inStream);
        _readerChar =new ReadHandler!(char)(inStream);
        _readerWchar=new ReadHandler!(wchar)(inStream);
        _readerDchar=new ReadHandler!(dchar)(inStream);
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
}


final class ConduitEmulator: IConduit
{
    void delegate(void[]) sink;
    void delegate() _flush;
    void delegate() _close;
    size_t delegate(void[]) basicReader;
    
    this(void delegate(void[]) s,size_t delegate(void[]) r,
        void delegate() _flush=null,void delegate() _close=null){
        sink=s;
        basicReader=r;
        this._flush=_flush;
        this._close=_close;
    }
    // inputStream
    size_t read (void[] dst){
        return basicReader(cast(void[])dst);
    }

    void[] load (size_t max = -1){
        if (basicReader is null) return null;
        ubyte[256] buf;
        ubyte[256] buf1;
        auto a=lGrowableArray(buf,0,GASharing.Local);
        while(true){
            size_t l=basicReader(buf1);
            if (l==IOStream.Eof){
                return a.takeData();
            } else {
                a(buf1[0..l]);
            }
        }
    }

    InputStream input (){
        return this;
    }

    long seek (long offset, Anchor anchor = Anchor.Begin){
        throw new BIOException("seeking not supported",__FILE__,__LINE__);
    }

    IConduit conduit (){
        return this;
    }

    IOStream flush (){
        if (_flush!is null)
            _flush();
        return this;
    }

    void close (){
        if (_close!is null)
            _close();
    }

    interface Mutator {}

    size_t bufferSize (){
        return 512;
    }

    char[] toString (){
        return "ConduitEmulator";
    }

    bool isAlive (){
        return true;
    }

    void detach (){ }

    void error (char[] msg){
        sink(msg);
    }

    interface Seek {}

    size_t write (void[] src){
        sink(src);
        return src.length;
    }

    OutputStream copy (InputStream src, size_t max = -1){
        ubyte[512] buf;
        while (true){
            auto l=src.read(buf);
            if (l==IOStream.Eof) break;
            sink(buf[0..l]);
        }
        return this;
    }

    OutputStream output (){
        return this;
    }
}


