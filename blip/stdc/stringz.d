/// utilities for c syle 0 terminated strings
///
/// wrapping of a tango module
module blip.stdc.stringz;
version(Tango) {
    public import tango.stdc.stringz: toStringz;
} else {
    public import std.string: toStringz;
}