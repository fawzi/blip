/// buffered input from a basic reader
/// author: Fawzi
module blip.io.BufferIn;

class BufferIn(TInt,TOut=TInt){
    static if (is(TInt==void)){
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
    static assert(TInt.sizeof<=TOut.sizeof,"internal size needs to be smaller than external");
    static assert(TOut.sizeof%TInt.sizeof==0,"external size needs to be a multiple of internal size");
    enum :size_t{OutToIn=TOut.sizeof/TInt.sizeof}
    
    this(size_t delegate(TInt[]) basicReader,TInt[] buf,size_t encodingOverhead=0){
        assert(buf.length>encodingOverhead+OutToIn,"buf too small");
        this.buf=buf;
        bufPos=0;
        bufLen=0;
        _read=basicReader;
        slice=SliceExtent.Partial;
    }
    this(size_t delegate(TInt[]) basicReader,size_t bufLen=512,size_t encodingOverhead=0){
        this(basicReader,new TInt[](bufLen),encodingOverhead);
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
                throw new IOException("unexpected Eof in consume",__FILE__,__LINE__);
            }
        }
        bufPos+=amount;
        bufLen-=amount;
    }
    void consumeOut(size_t amount){
        consumeInt(amount*OutToIn);
    }
    
    void compact(){
        if (bufPos!=0){
            memmove(buf.ptr,buf.ptr+bufPos,bufLen*TBuf.sizeof);
            bufPos=0;
        }
    }
    size_t readExact(TOut[]outBuf){
        auto outLen=outBuf.length*OutToIn;
        auto outPtr=cast(TBuf*)outBuf.ptr;
        if (outLen <=bufLen){
            outPtr[0..outLen]=buf[bufPos..bufPos+outLen];
            bufLen-=outBuf.length;
            bufPos+=outBuf.length;
            return;
        }
        outPtr[0..bufLen]=buf[bufPos..bufPos+bufLen];
        if (slice==SliceExtent.ToEnd) throw new IOException("unexpected Eof in readExact",__FILE__,__LINE__);
        readNow=_read(outPtr[bufLen..outLen]);
        if (readNow==Eof){
            slice=SliceExtent.ToEnd;
            throw new IOException("unexpected Eof in readExact",__FILE__,__LINE__);
        }
        auto outPos=bufLen+readNow;
        bufPos=0;
        bufLen=0;
        while(outPos<outLen){
            readNow=_read(buf);
            if (readNow==Eof){
                slice=SliceExtent.ToEnd;
                throw new IOException("unexpected Eof in readExact",__FILE__,__LINE__);
            }
            auto toCopy=outLen-outPos;
            if (toCopy>readNow){
                memcpy(outPtr+outPos,buf.ptr,readNow*TBuf.sizeof);
                outPos+=readNow;
            } else {
                memcpy(outPtr+outPos,buf.ptr,toCopy*TBuf.sizeof);
                bufPos=toCopy;
                bufLen=readNow-toCopy;
                return;
            }
        }
    }
    
    bool handleReader(size_t delegate(TOut[], SliceExtent slice,out bool iterate) r){
        if (bufPos%TOut.alignof!=0) compact();
        if (bufLen<encodingOverhead+buf.length/10||bufLen<TOut.sizeof) loadMore(false);
        bool readSome=false;
        while (true){
            bool iterate=false;
            TOut[] bufOut=(cast(TOut*)(buf.ptr+bufPos))[0..bufLen/OutToIn];
            auto consumed=r(bufOut,slice,iterate);
            switch (consumed){
            case Eof:
                switch (slice){
                case SliceExtent.Partial:
                    loadMore(true);
                    break;
                case SliceExtent.Maximal:
                    throw new IOException("window too small to parse",__FILE__,__LINE__);
                case SliceExtent.ToEnd:
                    throw new IOException("cannot read past Eof",__FILE__,__LINE__);
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
                consumeOut(consumed);
                if (!iterate) return true;
                readSome=true;
                if (bufPos%TOut.alignof!=0) compact();
            }
        }
    }
}
    