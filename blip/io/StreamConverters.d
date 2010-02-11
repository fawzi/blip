/// helpers to convert basic tango streams to stream usable in blip
module blip.io.StreamConverters;
import tango.io.model.IConduit: OutputStream;
import tango.core.Array: find;

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

