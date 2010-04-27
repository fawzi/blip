/// conversion to/from types, this most notably does not support conversion to/from strings
/// to do that see blip.text.StringConversions
module blip.util.Convert;

/// conversion to/from types, this most notably does not support conversion to/from strings
/// to do that see blip.text.StringConversions
template convertTo(T){
    T convertTo(V)(V x){
        static if (is(typeof(T.from(x))==T)){
            return T.from(x);
        } else static if (is(typeof(x.to!(T)())==T)){
            return x.to!(T)();
        } else static if (is(V:T)){
            return cast(T)x;
        } else {
            assert(0,"cannot convert "~V.stringof~" to "~T.stringof);
        }
    }
}
