/*******************************************************************************
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: Sep 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.random.engines.Sync;
import tango.io.protocol.model.IWriter:IWritable,IWriter;
import tango.io.protocol.model.IReader:IReadable,IReader;
private import Integer = tango.text.convert.Integer;
import tango.core.sync.Mutex: Mutex;

/+ Makes a synchronized engine out of the engine E, so multiple thread access is ok
+ (but if you need multiple thread access think about having a random number generator per thread)
+ This is the engine, *never* use it directly, always use it though a RandomG class
+/
struct Sync(E){
    E engine;
    Mutex lock;
    
    const int canCheckpoint=E.canCheckpoint;
    const int canSeed=E.canSeed;
    
    void skip(uint n){
        for (int i=n;i!=n;--i){
            engine.next;
        }
    }
    ubyte nextB(){
        synchronized(lock){
            return engine.nextB();
        }
    }
    uint next(){
        synchronized(lock){
            return engine.next();
        }
    }
    ulong nextL(){
        synchronized(lock){
            return engine.nextL();
        }
    }
    
    void seed(uint delegate() r){
        if (!lock) lock=new Mutex();
        synchronized(lock){
            engine.seed(r);
        }
    }
    ///  IWritable implementation
    void write (IWriter input){
        synchronized(lock){
            engine.write(input);
        }
    }
    /// IReadable implementation
    void read (IReader input){
        synchronized(lock){
            engine.read(input);
        }
    }
    /// writes the current status in a string
    char[] toString(){
        synchronized(lock){
            return "Sync"~engine.toString();
        }
    }
    /// reads the current status from a string (that should have been trimmed)
    /// returns the number of chars read
    uint fromString(char[] s){
        int i;
        assert(s[0..4]=="Sync","unexpected kind, expected Sync");
        synchronized(lock){
            i=engine.fromString(s[i+4..$]);
        }
        return i+4;
    }
}
