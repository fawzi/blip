/*******************************************************************************
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.random.engines.KISS;
import tango.io.protocol.model.IWriter:IWritable,IWriter;
import tango.io.protocol.model.IReader:IReadable,IReader;
import Integer = tango.text.convert.Integer;
import tango.core.sync.Mutex: Mutex;

/+ Kiss99 random number generator, by Marisaglia
+ a simple RNG that passes all statistical tests
+ This is the engine, *never* use it directly, always use it though a RandomG class
+/
struct Kiss99{
    private uint kiss_x = 123456789;
    private uint kiss_y = 362436000;
    private uint kiss_z = 521288629;
    private uint kiss_c = 7654321;
    private uint nBytes = 0;
    private uint restB  = 0;
    
    const int canCheckpoint=true;
    const int canSeed=true;
    
    void skip(uint n){
        for (int i=n;i!=n;--i){
            next;
        }
    }
    ubyte nextB(){
        if (nBytes>0) {
            ubyte res=cast(ubyte)(restB & 0xFF);
            restB >>= 8;
            --nBytes;
            return res;
        } else {
            restB=next;
            ubyte res=cast(ubyte)(restB & 0xFF);
            restB >>= 8;
            nBytes=3;
            return res;
        }
    }
    uint next(){
        const ulong a = 698769069UL;
        ulong t;
        kiss_x = 69069*kiss_x+12345;
        kiss_y ^= (kiss_y<<13); kiss_y ^= (kiss_y>>17); kiss_y ^= (kiss_y<<5);
        t = a*kiss_z+kiss_c; kiss_c = (t>>32);
        kiss_z=cast(uint)t;
        return kiss_x+kiss_y+kiss_z;
    }
    ulong nextL(){
        return ((cast(ulong)next)<<32)+cast(ulong)next;
    }
    
    void seed(uint delegate() r){
        kiss_x = r();
        for (int i=0;i<100;++i){
            kiss_y=r();
            if (kiss_y!=0) break;
        }
        if (kiss_y==0) kiss_y=362436000;
        kiss_z=r();
        /* Don’t really need to seed c as well (is reset after a next),
           but doing it allows to completely restore a given internal state */
        kiss_c = r() % 698769069; /* Should be less than 698769069 */
        nBytes = 0;
        restB=0;
    }
    ///  IWritable implementation
    void write (IWriter input){
        input(kiss_x)(kiss_y)(kiss_z)(kiss_c)(nBytes)(restB);
    }
    /// IReadable implementation
    void read (IReader input){
        input(kiss_x)(kiss_y)(kiss_z)(kiss_c)(nBytes)(restB);
    }
    /// writes the current status in a string
    char[] toString(){
        char[] res=new char[6+6*9];
        int i=0;
        res[i..i+6]="KISS99";
        i+=6;
        foreach (val;[kiss_x,kiss_y,kiss_z,kiss_c,nBytes,restB]){
            res[i]='_';
            ++i;
            Integer.format(res[i..i+8],val,"x8");
            i+=8;
        }
        assert(i==res.length,"unexpected size");
        return res;
    }
    /// reads the current status from a string (that should have been trimmed)
    /// returns the number of chars read
    uint fromString(char[] s){
        uint i=0;
        assert(s[i..i+4]=="KISS","unexpected kind, expected KISS");
        assert(s[i+4..i+7]=="99_","unexpected version, expected 99");
        i+=6;
        foreach (val;[&kiss_x,&kiss_y,&kiss_z,&kiss_c,&nBytes,&restB]){
            assert(s[i]=='_',"no separator _ found");
            ++i;
            uint ate;
            *val=cast(uint)Integer.convert(s[i..i+8],16,&ate);
            assert(ate==8,"unexpected read size");
            i+=8;
        }
        return i;
    }
}

/+ like Kiss99, but synchronized, so multiple thread access is ok
+ (but if you need multiple thread access think about having a random number generator per thread)
+ This is the engine, *never* use it directly, always use it though a RandomG class
+/
struct Kiss99Sync{
    uint kiss_x = 123456789;
    uint kiss_y = 362436000;
    uint kiss_z = 521288629;
    uint kiss_c = 7654321;
    uint nBytes = 0;
    uint restB  = 0;
    Mutex lock;
    
    const int canCheckpoint=true;
    const int canSeed=true;
    
    void skip(uint n){
        for (int i=n;i!=n;--i){
            next;
        }
    }
    ubyte nextB(){
        if (nBytes>0) {
            ubyte res=cast(ubyte)(restB & 0xFF);
            restB >>= 8;
            --nBytes;
            return res;
        } else {
            restB=next;
            ubyte res=cast(ubyte)(restB & 0xFF);
            restB >>= 8;
            nBytes=3;
            return res;
        }
    }
    uint next(){
        uint res;
        const ulong a = 698769069UL;
        ulong t;
        synchronized(lock){
            kiss_x = 69069*kiss_x+12345;
            kiss_y ^= (kiss_y<<13); kiss_y ^= (kiss_y>>17); kiss_y ^= (kiss_y<<5);
            t = a*kiss_z+kiss_c; kiss_c = (t>>32);
            kiss_z=cast(uint)t;
            res=kiss_x+kiss_y+kiss_z;
        }
        return res;
    }
    ulong nextL(){
        return ((cast(ulong)next)<<32)+cast(ulong)next;
    }
    
    void seed(uint delegate() r){
        if (!lock) lock=new Mutex();
        synchronized(lock){
            kiss_x = r();
            for (int i=0;i<100;++i){
                kiss_y=r();
                if (kiss_y!=0) break;
            }
            if (kiss_y==0) kiss_y=362436000;
            kiss_z=r();
            /* Don’t really need to seed c as well (is reset after a next),
               but doing it allows to completely restore a given internal state */
            kiss_c = r() % 698769069; /* Should be less than 698769069 */
            nBytes=0;
            restB=0;
        }
    }
    ///  IWritable implementation
    void write (IWriter input){
        synchronized(lock){
            input(kiss_x)(kiss_y)(kiss_z)(kiss_c)(nBytes)(restB);
        }
    }
    /// IReadable implementation
    void read (IReader input){
        synchronized(lock){
            input(kiss_x)(kiss_y)(kiss_z)(kiss_c)(nBytes)(restB);
        }
    }
    /// writes the current status in a string
    char[] toString(){
        char[] res=new char[6+6*9];
        int i=0;
        res[i..i+6]="KISS99";
        i+=6;
        synchronized(lock){
            foreach (val;[kiss_x,kiss_y,kiss_z,kiss_c,nBytes,restB]){
                res[i]='_';
                ++i;
                Integer.format(res[i..i+8],val,"x8");
                i+=8;
            }
        }
        assert(i==res.length,"unexpected size");
        return res;
    }
    /// reads the current status from a string (that should have been trimmed)
    /// returns the number of chars read
    uint fromString(char[] s){
        uint i=0;
        assert(s[i..i+4]=="KISS","unexpected kind, expected KISS");
        assert(s[i+4..i+7]=="99_","unexpected version, expected 99");
        i+=6;
        synchronized(lock){
            foreach (val;[&kiss_x,&kiss_y,&kiss_z,&kiss_c,&nBytes,&restB]){
                assert(s[i]=='_',"no separator _ found");
                ++i;
                uint ate;
                *val=cast(uint)Integer.convert(s[i..i+8],16,&ate);
                assert(ate==8,"unexpected read size");
                i+=8;
            }
        }
        return i;
    }
}
