/// unistd header
///
/// wrapping of a tango module
module blip.stdc.unistd;
version(Tango){
    public import tango.stdc.posix.unistd: read, write, close, gethostname;
} else {
    public import core.sys.posix.unistd: read, write, close, gethostname;
}