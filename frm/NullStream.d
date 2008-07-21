/*******************************************************************************
    A stream that ignores all that is written to it
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.NullStream;
import tango.io.model.IConduit;
class NullStream: OutputStream {
    this(){}

    uint write (void[] src){
        return src.length;
    }

    OutputStream copy (InputStream src){
        if (src !is null){
            ubyte[512] buf;
            uint count;
            do {
                count = src.read(buf[]);
            } while(count != Eof)
        }
        return this;
    }
    
    // alias IConduit.Eof Eof;
    
    IConduit conduit () { return null; } // ok??

    void close () { } // do something to avoid successive writes?

    OutputStream flush () { return this; }
}