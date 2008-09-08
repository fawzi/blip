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

/// identity function
T Id(T)(T a) { return a; }

/// is T is a real floating point number
template isReal(T){
    const isReal=is(T==float)||is(T==double)||is(T==real);
}
/// if T is a complex number
template isComplex(T){
    const isComplex=is(T==cfloat)||is(T==creal)||is(T==cdouble);
}

/// if T is a purely imaginary number
template isImaginary(T){
    const isImaginary=is(T==ifloat)|| is(T==idouble)|| is(T==ireal);
}

/// complex type for the given type
template complexType(T){
    static if(is(T==float)||is(T==ifloat)||is(T==cfloat)){
        alias cfloat complexType;
    } else static if(is(T==double)|| is(T==idouble)|| is(T==cdouble)){
        alias cdouble complexType;
    } else static if(is(T==real)|| is(T==ireal)|| is(T==creal)){
        alias creal complexType;
    } else static assert(0,"unsupported type in complexType "~T.stringof);
}

/// real type for the given type
template realType(T){
    static if(is(T==float)|| is(T==ifloat)|| is(T==cfloat)){
        alias float realType;
    } else static if(is(T==double)|| is(T==idouble)|| is(T==cdouble)){
        alias double realType;
    } else static if(is(T==real)|| is(T==ireal)|| is(T==creal)){
        alias real realType;
    } else static assert(0,"unsupported type in realType "~T.stringof);
}

/// if the type is a normal number
template isNumber(T){
    const isNumber=is(T==int)||is(T==uint)||is(T==long)||is(T==ulong)
        ||is(T==float)||is(T==ifloat)||is(T==cfloat)
        ||is(T==double)||is(T==idouble)||is(T==cdouble)
        ||is(T==real)||is(T==ireal)||is(T==creal);
}

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
    const bool isArray=is( T U : U[] );
}

template staticArraySize(T)
{
    static assert(isStaticArray!(T),"staticArraySize needs a static array as type");
    static assert(arrayRank!(T)==1,"implemented only for 1d arrays...");
    const size_t staticArraySize=(T).sizeof / typeof(T.init).sizeof;
}

template isStaticArray(T)
{
    const bool isStaticArray=is( typeof(T.init)[(T).sizeof / typeof(T.init).sizeof] == T );
}

/// returns a dynamic array
template dynArray(T)
{
    static if( isStaticArray!(T) )
        alias typeof(T.dup) dynArray;
    else static if (isArray!(T))
        alias T dynArray;
    else
        alias T[] dynArray;
}

/// transform eventual static arrays to dynamic ones
template noStaticArray(T)
{
    static if( isStaticArray!(T) )
        alias typeof(T.dup) noStaticArray;
    else
        alias T noStaticArray;
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

// ------- CTFE -------

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

/// checks is c is a valid token char (also at compiletime), assumes a-z A-Z 1-9 sequences in collation
bool ctfe_isTokenChar(char c){
    return (c=='_' || c>='a'&&c<='z' || c>='A'&&c<='Z' || c=='0'|| c>='1' && c<='9');
}

/// checks if code contains the given token
bool ctfe_hasToken(char[] token,char[] code){
    bool outOfTokens=true;
    int i=0;
    while(i<code.length){
        if (outOfTokens){
            int j=0;
            for (;((j<token.length)&&(i<code.length));++j,++i){
                if (code[i]!=token[j]) break;
            }
            if (j==token.length){
                if (i==code.length || !ctfe_isTokenChar(code[i])){
                    return true;
                }
            }
        }
        do {
            outOfTokens=(!ctfe_isTokenChar(code[i]));
            ++i;
        } while((!outOfTokens) && i<code.length)
    }
    return false;
}

/// replaces all occurrences of token in code with repl
char[] ctfe_replaceToken(char[] token,char[] repl,char[] code){
    char[] res="".dup;
    bool outOfTokens=true;
    int i=0,i0;
    while(i<code.length){
        i0=i;
        if (outOfTokens){
            int j=0;
            for (;((j<token.length)&&(i<code.length));++j,++i){
                if (code[i]!=token[j]) break;
            }
            if (j==token.length){
                if (i==code.length || !ctfe_isTokenChar(code[i])){
                    res~=repl;
                    i0=i;
                }
            }
        }
        do {
            outOfTokens=(!ctfe_isTokenChar(code[i]));
            ++i;
        } while((!outOfTokens) && i<code.length)
        res~=code[i0..i];
    }
    return res;
}

/// compile time integer power
T ctfe_powI(T)(T x,int p){
    T xx=cast(T)1;
    if (p<0){
        p=-p;
        x=1/x;
    }
    for (int i=0;i<p;++i)
        xx*=x;
    return xx;
}
