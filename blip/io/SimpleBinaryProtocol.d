/// a d implementation of the simple binary protocol available as C files
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
module blip.io.SimpleBinaryProtocol;
import blip.io.BasicIO;
import blip.core.Traits;
import blip.container.GrowableArray;
version(TrackSBP){
    import blip.io.Console;
}

enum SBP_SIZES{
    endian_buf_size=1024
}

enum SBP_KIND{
    kind_raw=0,         // binary blob
    kind_char=1,        // characters
    kind_int_small=2,   // small endian 4 bytes integers
    kind_double_small=3 // small endian doubles
}

version (BigEndian){
    enum:bool{ swapBits=true }
} else {
    enum:bool{ swapBits=false }
}

int sbpInit(){
    return 0;
}

int sbpEnd(){
    return 0;
}

void sbpSendHeader(BinSink sink, int kind, ulong len){
    ulong buf[2];
    byte* bufPos=(cast(byte*)buf.ptr)+4;
    byte* pos;
    static if (swapBits){
        pos=cast(byte*)&kind;
        bufPos[3]=pos[0];
        bufPos[2]=pos[1];
        bufPos[1]=pos[2];
        bufPos[0]=pos[3];
        bufPos+=4;
        pos=cast(byte*)&len;
        bufPos[7]=pos[0];
        bufPos[6]=pos[1];
        bufPos[5]=pos[2];
        bufPos[4]=pos[3];
        bufPos[3]=pos[4];
        bufPos[2]=pos[5];
        bufPos[1]=pos[6];
        bufPos[0]=pos[7];
        bufPos+=8;
    } else {
        *(cast(uint*)bufPos)=kind;
        bufPos+=4;
        *(cast(ulong*)bufPos)=len;
    }
    sink((cast(byte*)buf.ptr)[4..16]);
    version(TrackSBP){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("sbpSendHeader kind:")(kind)(" len:")(len)("\n");
        });
    }
}

void sbpSendArr(T)(BinSink sink,T[]arr){
    static if (swapBits){
        switch(T.sizeof){
        case 1:
            sink(arr);
            break;
        case 4:
            sbpSendInvert4(sink,arr);
            break;
        case 8:
            sbpSendInvert8(sink,arr);
            break;
        default:
            throw new Exception("unsupported byte size",__FILE__,__LINE);
        }
    } else {
        sink(arr);
    }
}

void sbpSendInvert4(T)(BinSink sink,T[]arr){
    const size_t bufSize=endian_buf_size+4;
    uint _buf[endian_buf_size/4];
    byte* buf=cast(byte*)_buf.ptr;
    byte* bufPos=buf;
    byte* bufEnd=bufPos+bufSize-4;
    byte* pos=cast(byte*)arr.ptr;
    byte* end=pos+arr.length*T.sizeof;
    while (pos<end){
        bufPos[3]=pos[0];
        bufPos[2]=pos[1];
        bufPos[1]=pos[2];
        bufPos[0]=pos[3];
        bufPos+=4;
        pos+=4;
        if (bufPos>=bufEnd){
            sink(buf[0..(bufPos-buf)]);
            bufPos=buf;
        }
    }
    sink(buf[0..(bufPos-buf)]);
}

int sbpSendInvert8(T)(BinSink sink, T[]arr){
    static assert(T.sizeof==8);
    const int bufSize=endian_buf_size+8;
    ulong _buf[bufSize/8];
    byte* buf=cast(byte*)_buf.ptr;
    byte* bufPos=buf;
    byte* bufEnd=bufPos+bufSize-8;
    byte* pos=cast(byte*)arr.ptr;
    byte* end=pos+arr.length*T.sizeof;
    while (pos<end){
        bufPos[7]=pos[0];
        bufPos[6]=pos[1];
        bufPos[5]=pos[2];
        bufPos[4]=pos[3];
        bufPos[3]=pos[4];
        bufPos[2]=pos[5];
        bufPos[1]=pos[6];
        bufPos[0]=pos[7];
        bufPos+=8;
        pos+=8;
        if (bufPos>=bufEnd){
            sink(buf[0..(bufPos-buf)]);
            bufPos=buf;
        }
    }
    sink(buf[0..(bufPos-buf)]);
}

void sbpSend(T)(BinSink sink,T[] t){
    static if (is(T==void)||is(T==byte)||is(T==ubyte)){
        sbpSendHeader(sink,SBP_KIND.kind_raw,t.length*T.sizeof);
        sbpSendArr(sink,t);
    } else static if (is(T==char)){
        sbpSendHeader(sink,SBP_KIND.kind_char,t.length*T.sizeof);
        sbpSendArr(sink,t);
    } else static if (is(T==int)){
        sbpSendHeader(sink,SBP_KIND.kind_int_small,t.length*T.sizeof);
        sbpSendArr(sink,t);
    } else static if (is(T==double)){
        sbpSendHeader(sink,SBP_KIND.kind_double_small,t.length*T.sizeof);
        sbpSendArr(sink,t);
    } else {
        static assert(0,"unsupported type "~T.stringof);
    }
}

//////// receiving ///////

alias void delegate(void[]) ReadExact;

void sbpReadHeader(ReadExact rIn, ref uint kind, ref ulong len){
    ulong[2] buf;
    ulong nodata=0;
    byte* bufPos=(cast(byte*)buf.ptr)+4, endBuf=bufPos+16;
    byte* pos;
    rIn(bufPos[0..12]);
    if (swapBits){
        pos=cast(byte*)&kind;
        pos[0]=bufPos[3];
        pos[1]=bufPos[2];
        pos[2]=bufPos[1];
        pos[3]=bufPos[0];
        bufPos+=4;
        pos=cast(byte*)&len;
        pos[0]=bufPos[7];
        pos[1]=bufPos[6];
        pos[2]=bufPos[5];
        pos[3]=bufPos[4];
        pos[4]=bufPos[3];
        pos[5]=bufPos[2];
        pos[6]=bufPos[1];
        pos[7]=bufPos[0];
    } else {
        kind=*(cast(uint*)bufPos);
        bufPos+=4;
        len=*(cast(ulong*)bufPos);
    }
    version(TrackSBP){
        sinkTogether(sout,delegate void(scope CharSink s){
            dumper(s)("sbpReadHeader kind:")(kind)(" len:")(len)("\n");
        });
    }
}

void sbpReadArr(T)(ReadExact rIn,T[]arr){
    static if (swapBits){
        switch(T.sizeof){
        case 1:
            rIn(arr);
            break;
        case 4:
            sbpReadInvert4(rIn,arr);
            break;
        case 8:
            sbpReadInvert8(rIn,arr);
        default:
            throw new Exception("unsupported byte size",__FILE__,__LINE);
        }
    } else {
        rIn(arr);
    }
}

void sbpSkip(ReadExact rIn,ulong len){
    // we don't use seek because it is not always supported
    const size_t bufSize=SBP_SIZES.endian_buf_size;
    char buf[bufSize];
    ulong readBTot=0;
    while(readBTot!=len){
        ulong toRead=len-readBTot;
        if (toRead>bufSize) toRead=bufSize;
        rIn(buf[0..cast(size_t)toRead]);
        readBTot+=toRead;
    }
}

int sbpReadInvert4(T)(ReadExact rIn,T[] arr){
    const size_t bufSize=endian_buf_size+4;
    uint _buf[bufSize/4];
    byte* bufPos=cast(byte*)_buf.ptr;
    byte *pos=cast(byte*)arr.ptr;
    byte* posEnd=pos+arr.length*T.sizeof;
    assert(arr.length*T.sizeof %4==0);
    while (pos!=posEnd){
        byte *bufPos2;
        size_t toRead=posEnd-pos;
        if (toRead>bufSize-4) toRead=bufSize-4;
        rIn(bufPos[0..toRead]);
        byte*end=bufPos+toRead;
        if (end >= (cast(byte*)_buf.ptr)+4){
            end-=4;
            for (bufPos=cast(byte*)_buf.ptr;bufPos<end;bufPos+=4){
                pos[0]=bufPos[3];
                pos[1]=bufPos[2];
                pos[2]=bufPos[1];
                pos[3]=bufPos[0];
                pos+=4;
            }
            end+=4;
        }
        bufPos2=cast(byte*)_buf.ptr;
        while (bufPos<end){
            *bufPos2=*bufPos;
            ++bufPos;++bufPos2;
        }
        bufPos=bufPos2;
    }
    return 0;
}

void sbpReadInvert8(T)(ReadExact rIn, T[] arr){
    const int bufSize=endian_buf_size+8;
    ulong _buf[bufSize/8];
    byte* bufPos=cast(byte*)_buf.ptr;
    byte* bufEnd=bufPos+bufSize-8;
    byte* pos=cast(byte*)arr.ptr;
    byte* posEnd=pos+arr.length*T.sizeof;
    
    while (pos!=posEnd){
        byte *bufPos2;
        size_t toRead=posEnd-pos;
        if (toRead>bufSize-8) toRead=bufSize-8;
        rIn(bufPos[0..toRead]);
        char*end=bufPos+toRead;
        if (end>cast(byte*)(&_buf[1])){
            end-=8;
            for (bufPos=cast(byte*)_buf.ptr;bufPos<end;bufPos+=8){
                pos[0]=bufPos[7];
                pos[1]=bufPos[6];
                pos[2]=bufPos[5];
                pos[3]=bufPos[4];
                pos[4]=bufPos[3];
                pos[5]=bufPos[2];
                pos[6]=bufPos[1];
                pos[7]=bufPos[0];
                pos+=8;
            }
            end+=8;
        }
        bufPos2=cast(byte*)_buf.ptr;
        while (bufPos<end){
            *bufPos2=*bufPos;
            ++bufPos;++bufPos2;
        }
        bufPos=bufPos2;
    }
    return 0;
}

///////

DynamicArrayType!(T) sbpRead(T)(ReadExact rIn,T arr,bool strict=true){
    ulong rcvLen;
    uint kind;
    DynamicArrayType!(T) res=arr;
    sbpReadHeader(rIn,kind,rcvLen);
    static if (is(T U:U[])){
        if (strict){
            if (arr.length*U.sizeof != rcvLen){
                throw new Exception(collectIAppender(delegate void(scope CharSink s){
                    dumper(s)("unexpected byte size, ")(arr.length)("*")(U.sizeof)("vs")(rcvLen)("\n");
                }));
            }
        } else if (arr.length*U.sizeof<rcvLen){
            res=new U[](rcvLen/U.sizeof);
        } else {
            res=arr[0..rcvLen/U.sizeof];
        }
        static if (is(U==void)||is(U==byte)||is(U==ubyte)){
            if (kind!=SBP_KIND.kind_raw) throw new Exception("expected type raw",__FILE__,__LINE__);
            sbpReadArr(rIn,res);
        } else static if (is(U==char)){
            if (kind!=SBP_KIND.kind_char) throw new Exception("expected type char",__FILE__,__LINE__);
            sbpReadArr(rIn,res);
        } else static if (is(U==int)){
            if (kind!=SBP_KIND.kind_int_small) throw new Exception("expected type int",__FILE__,__LINE__);
            sbpReadArr(rIn,res);
        } else static if (is(U==double)){
            if (kind!=SBP_KIND.kind_double_small) throw new Exception("expected type double",__FILE__,__LINE__);
            sbpReadArr(rIn,res);
        } else {
            static assert(false,"non supported type "~T.stringof);
        }
    } else {
        static assert(false,"non supported type "~T.stringof);
    }
    return res;
}

