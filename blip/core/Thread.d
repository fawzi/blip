/// threading and fiber primitives
///
/// wrapping of a tango module
module blip.core.Thread;
public import tango.core.Thread;
version(D_Version2){
    template ThreadLocal(T){
	alias T ThreadLocal;
    }
}
