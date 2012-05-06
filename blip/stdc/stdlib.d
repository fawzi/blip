/// stdlib c header
///
/// wrapping of a tango module
module blip.stdc.stdlib;
version(Tango){
    public import tango.stdc.stdlib;
} else {
    public import core.stdc.stdlib;
}