/// helper to use wisper style calling
/// author: fawzi
module blip.util.Wisper;

/// helper to use wisper style calling
struct Wisper(T){
    T call;
    Wisper opCall(U)(U u){
        static if(is(U==void delegate(T))){
            u(call);
        } else static if (is(typeof(call(u)))){
            call(u);
        } else {
            static assert(0,"Wisper!("~T.stingof~") cannot handle "~U.stringof);
        }
        return *this;
    }
}
/// ditto
Wisper!(T) wisper(T)(T c){
    Wisper!(T) res;
    res.call=c;
    return res;
}
