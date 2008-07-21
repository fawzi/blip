/*******************************************************************************
    TemplateFu contains various template stuff that I found useful to put
    in a single module
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module frm.TemplateFu;
/// returns the number of arguments in the tuple (its length)
template nArgs(){
    const int nArgs=0;
}
/// returns the number of arguments in the tuple (its length)
template nArgs(T,S...){
    const int nArgs=1+nArgs!(S);
}

/// compile time integer to string
char [] ctfe_i2a(int i){
    char[] digit="0123456789";
    char[] res="".dup;
    if (i==0){
        return "0".dup;
    }
    bool neg=false;
    if (i<0){
        neg=true;
        i=-i;
    }
    while (i>0) {
        res=digit[i%10]~res;
        i/=10;
    }
    if (neg)
        return '-'~res;
    else
        return res;
}

/// identity function
T Id(T)(T a) { return a; }

template isAtomicType(T)
{
    static if( is( T == bool )
            || is( T == char )
            || is( T == wchar )
            || is( T == dchar )
            || is( T == byte )
            || is( T == short )
            || is( T == int )
            || is( T == long )
            || is( T == ubyte )
            || is( T == ushort )
            || is( T == uint )
            || is( T == ulong )
            || is( T == float )
            || is( T == double )
            || is( T == real )
            || is( T == ifloat )
            || is( T == idouble )
            || is( T == ireal ) )
        const isAtomicType = true;
    else
        const isAtomicType = false;
}

template isArray(T)
{
    static if( is( T U : U[] ) )
        const isArray = true;
    else
        const isArray = false;
}

template staticArraySize(T)
{
    static assert(isStaticArray!(T),"staticArraySize needs a static array as type");
    static assert(arrayRank!(T)==1,"implemented only for 1d arrays...");
    const size_t staticArraySize=(T).sizeof / typeof(T.init).sizeof;
}

template isStaticArray(T)
{
    static if( is( typeof(T.init)[(T).sizeof / typeof(T.init).sizeof] == T ) )
        const isStaticArray = true;
    else
        const isStaticArray = false;
}

template dynArray(T)
{
    static if( isStaticArray!(T) )
        alias typeof(T.dup) dynArray;
    else static if (isArray!(T))
        alias T dynArray;
    else
        alias T[] dynArray;
}

/// Strips the []'s off of a type.
template arrayBaseT(T)
{
    static if( is( T S : S[]) ) {
        alias arrayBaseT!(S)  arrayBaseT;
    }
    else {
        alias T arrayBaseT;
    }
}

/// strips one [] off a type
template arrayElT(T:T[])
{
    static if( is( T S : S[]) ) {
        alias arrayBaseT!(S)  arrayBaseT;
    }
}

/// Count the []'s on an array type
template arrayRank(T) {
    static if(is(T S : S[])) {
        const uint arrayRank = 1 + arrayRank!(S);
    } else {
        const uint arrayRank = 0;
    }
}

