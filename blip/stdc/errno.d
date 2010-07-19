/// errno functions
/// mainly wrapping of a tango module
module blip.stdc.errno;
public import tango.stdc.errno: errno;
import tango.core.Version;
static if (Tango.Major==1){
    public import tango.sys.consts.errno;
} else {
    public import tango.stdc.constants.errno;
}
public import tango.stdc.string: strlen;

version (Windows){
    private extern extern(C) char * strerror(int errnum);
    
    char[] strerror_d(int errnum,char[] buf){
        auto res=strerror(errnum);
        for (size_t i=0;i<buf.length;++i){
            if (res[i]==0){
                return buf[0..i];
            }
            buf[i]=res[i];
        }
        return buf;
    }
    
} else version(linux) {
    extern extern(C) int __xpg_strerror_r(int errnum, char *strerrbuf, size_t buflen);
    
    char[] strerror_d(int errnum,char[] buf){
        __xpg_strerror_r(errnum,buf.ptr,buf.length);
        buf[$-1]=0;
        return buf[0..strlen(buf.ptr)];
    }
    
} else version(darwin) {
    extern extern(C) int strerror_r(int errnum, char *strerrbuf, size_t buflen);

    char[] strerror_d(int errnum,char[] buf){
        strerror_r(errnum,buf.ptr,buf.length);
        buf[$-1]=0;
        return buf[0..strlen(buf.ptr)];
    }
} else {
    static assert(0,"strerror_r not available on this platform");
}
