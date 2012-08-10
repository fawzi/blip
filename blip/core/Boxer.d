/// type that can wrap any other type at runtime
///
/// wrapping of a tango module
module blip.core.Boxer;
version(Tango) {
    import tango.core.Variant;
    alias Variant.opCall box;
    alias Variant Box;
    T unbox(T)(Variant v){
	return v.get!(T)();
    }
    bool unboxable(T)(Variant v){
	return v.isImplicitly!(T)();
    }
} else {
    public import std.boxer: Box, box, unbox, uboxable;
}
