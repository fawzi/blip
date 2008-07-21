/*******************************************************************************
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.random.engines.URandom;
version(darwin) { version=has_urandom; }
version(linux)  { version=has_urandom; }

version(has_urandom) {
    import tango.io.protocol.model.IWriter:IWritable,IWriter;
    import tango.io.protocol.model.IReader:IReadable,IReader;
    import Integer = tango.text.convert.Integer;
    import tango.core.sync.Mutex: Mutex;
    import tango.io.FileConduit; // use stdc read/write?

    /// basic source that takes data from system random device
    /// This is an engine, do not use directly, use RandomG!(Urandom)
    /// should use stdc rad/write?
    struct URandom{
        static FileConduit.Style readStyle;
        static Mutex lock;
        static this(){
            readStyle.access=FileConduit.Access.Read;
            readStyle.open  =FileConduit.Open.Exists;
            readStyle.share =FileConduit.Share.Read;
            readStyle.cache =FileConduit.Cache.None;

            lock=new Mutex();
        }
        const int canCheckpoint=false;
        const int canSeed=false;
    
        void skip(uint n){ }
        ubyte nextB(){
            union ToVoidA{
                ubyte i;
                void[1] a;
            }
            ToVoidA el;
            synchronized(lock){
                auto fn = new FileConduit("/dev/urandom", readStyle); 
                if(fn.read(el.a)!=el.a.length){
                    throw new Exception("could not write the requested bytes from urandom");
                }
                fn.close();
            }
            return el.i;
        }
        uint next(){
            union ToVoidA{
                uint i;
                void[4] a;
            }
            ToVoidA el;
            synchronized(lock){
                auto fn = new FileConduit("/dev/urandom", readStyle); 
                if(fn.read(el.a)!=el.a.length){
                    throw new Exception("could not write the requested bytes from urandom");
                }
                fn.close();
            }
            return el.i;
        }
        ulong nextL(){
            union ToVoidA{
                ulong l;
                void[8] a;
            }
            ToVoidA el;
            synchronized(lock){
                auto fn = new FileConduit("/dev/urandom", readStyle); 
                if(fn.read(el.a)!=el.a.length){
                    throw new Exception("could not write the requested bytes from urandom");
                }
                fn.close();
            }
            return el.l;
        }

        void seed(uint delegate() r) { }
        ///  IWritable implementation
        void write (IWriter input){
            char[] r="URandom";
            input(r);
        }
        /// IReadable implementation
        void read (IReader input){
            char[] r;
            input(r);
            assert(r=="URandom","unexpected read");
        }
        /// writes the current status in a string
        char[] toString(){
            return "URandom";
        }
        /// reads the current status from a string (that should have been trimmed)
        /// returns the number of chars read
        uint fromString(char[] s){
            char[] r="URandom";
            assert(s[0.. r.length]==r,"unxepected string instad of URandom:"~s);
            return r.length;
        }
    }
}
