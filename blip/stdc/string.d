/// string c header
///
/// wrapping of a tango module
module blip.stdc.string;
version(Tango){
    public import tango.stdc.string;
} else {
    public import core.stdc.string;
}
