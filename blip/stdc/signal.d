/// signal header
///
/// wrapping of a tango module
module blip.stdc.signal;
version(Tango){
    public import tango.stdc.signal;
} else {
    public import core.stdc.signal;
}
