/*******************************************************************************
    A stream that ignores all that is written to it
    Tango compatibility (to be removed).
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        Apache 2.0
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.io.NullStream;
import tango.io.device.Conduit;
import blip.Comp;

/// a conduit that discards its input
class NullConduit: Conduit{
    string toString (){
        return "NullConduit";
    }

    size_t bufferSize () { return 256u;}

    size_t read (void[] dst) { return Eof; }

    size_t write (void[] src) { return src.length; }

    void detach () { }
    
}

debug(UnitTest){
    unittest{
        auto a=new NullConduit();
        a.write("bla");
        a.flush();
        a.detach();
        a.write("b"); // at the moment it works, disallow?
        uint[4] b=0;
        a.read(b);
        foreach (el;b)
            assert(el==0);
    }
}

/// a stream that discards its input
/// (make it a singleton? would be slower due to locking somewhere?)
OutputStream nullStream(){
    return (new NullConduit).output;
}


debug(UnitTest){
    unittest{
        OutputStream a=nullStream();
        a.write("bla");
        a.flush();
        a.close();
        a.write("b"); // at the moment it works, disallow?
    }
}