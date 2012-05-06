// useful info on what is portable
// http://www.opengroup.org/onlinepubs/000095399/basedefs/
// http://daniel.haxx.se/projects/portability/
/// c_long c_ulong definitions
///
/// wrapping of a tango module
module blip.stdc.config;
version(Tango){
    public import tango.stdc.config;
} else {
    public import core.stdc.config;
}
