/// stdint c header
///
/// wrapping of a tango module
module blip.stdc.stdint;
version(Tango){
    public import tango.stdc.stdint;
} else {
    public import core.stdc.stdint;
}
