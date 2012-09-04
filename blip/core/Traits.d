/// utilities for varius compiletime/type related informations/manipulations
///
/// mainly wrapping of a tango module
module blip.core.Traits;
public import tango.core.Traits;
import blip.Comp;
import tango.core.Tuple;

int cmp(T,U)(T t,U u){
    static if (is(T:Object)&&is(U:Object)){
        return t.opCmp(u);
    } else static if(is(typeof(t.opCmp(u)))){
        return t.opCmp(u);
    } else static if(is(typeof(u.opCmp(t)))){
        return u.opCmp(t);
    } else static if (is(T==U)){
        return typeid(T).compare(&t,&u);
    } else {
        static assert(0,"cannot compare "~T.stringof~" with "~U.stringof);
    }
}

/// combines two hashes
extern(C) hash_t rt_hash_combine( hash_t val1, hash_t val2 );
/// hashes length bytes
extern(C) hash_t rt_hash_str(const(void) *bStart,size_t length, hash_t seed=0);
/// hashes the size_t aligned block bStart[0..length]
extern(C) hash_t rt_hash_block(const(size_t) *bStart,size_t length, hash_t seed=0);

/// returns a valid hash for the given value, this might be different than the default D hash!
hash_t getHash(U)(U t){
    alias UnqualAll!(U) T;
    static if (is(typeof(t.toHash())==hash_t)){
        return t.toHash();
    } else static if (is(T==char[])||is(T==byte[])||is(T==ubyte[])||is(T==void[])){
        return rt_hash_str(t.ptr,t.length);
    } else static if (is(T==wchar[])||is(T==short[])||is(T==ushort[])){
        return rt_hash_str(t.ptr,t.length*2);
    } else static if (is(T==dchar[])||is(T==int[])||is(T==uint[])){
        return rt_hash_str(t.ptr,t.length*4);
    } else static if (is(T==long[])||is(T==ulong[])){
        return rt_hash_str(t.ptr,t.length*8);
    } else {
        return typeid(U).getHash(&t);
    }
}
/// returns a valid hash for the given value, and combines it with a previous hash
/// this might be different than the default D hash!
hash_t getHash(T,U)(T t,U hash){
    static assert(is(U==hash_t));
    static if (is(typeof(t.toHash(hash))==hash_t)){
        return t.toHash(hash);
    } else static if (is(T==char[])||is(T==byte[])||is(T==ubyte[])||is(T==void[])){
        return rt_hash_str(t.ptr,t.length,hash);
    } else static if (is(T==wchar[])||is(T==short[])||is(T==ushort[])){
        return rt_hash_str(t.ptr,t.length*2,hash);
    } else static if (is(T==dchar[])||is(T==int[])||is(T==uint[])){
        return rt_hash_str(t.ptr,t.length*4,hash);
    } else static if (is(T==long[])||is(T==ulong[])){
        return rt_hash_str(t.ptr,t.length*8);
    } else static if (is(typeof(t.toHash())==hash_t)){
        return rt_hash_combine(t.toHash(),hash);
    } else static if (is(T==hash_t)){
        return rt_hash_combine(t,hash);
    } else static if (is(T==int)||is(T==uint)){
        return rt_hash_combine(cast(hash_t)t,hash);
    } else {
        return rt_hash_combine(typeid(T).getHash(&t),hash);
    }
}

/// representation of a string so that evaluating ctfe_rep(s) generates the string s
string ctfe_rep(string s){
    bool needsDquoteEscape=false;
    bool needsSQuoteEscape=false;
    foreach(c;s){
        switch(c){
        case '"','\\','\n','\r' :
            needsDquoteEscape=true;
            break;
        case '`':
            needsSQuoteEscape=true;
            break;
        default:
        }
    }
    if (!needsDquoteEscape){
        return "\""~s~"\"";
    } if (needsSQuoteEscape){
        string res="\"";
        size_t i0=0;
        foreach(i,c;s){
            switch(c){
            case '"','\\':
                res~=s[i0..i];
                res~='\\';
                res~=c;
                break;
            case '\n':
                res~=s[i0..i];
                res~="\\n";
                break;
            case '\r':
                res~=s[i0..i];
                res~="\\r";
                break;
            default:
            }
        }
        res~=s[i0..s.length];
        res~="\"";
        return res;
    } else {
        return "`"~s~"`";
    }
}

bool typeHasPointers(T)(){
    return (typeid(T).flags & 1)!=0;
}

/// type of a property
template PropType(T){
    static if((is(T==function)||is(T==delegate))&&is(T U==return)){
        alias U PropType;
    } else {
        alias T PropType;
    }
}

/// splits the string at the given splitChars
string[] ctfeSplit(string splitChars,string str,bool skipEmpty){
    string[]res;
    size_t i=0;
    foreach(j,c;str){
        foreach (c2;splitChars){
            if (c==c2){
                if ((!skipEmpty)||j>i){
                    res~=str[i..j];
                }
                i=j+1;
            }
        }
    }
    if (i<str.length) res~=str[i..$];
    return res;
}

void tryDeleteT(T)(ref T obj){
    static if (is(typeof(obj.deallocData()))){
        obj.deallocData();
    } else static if (is(typeof(obj.clear()))){
        obj.clear();
    }
    static if (is(typeof(delegate void(){ delete obj; }))){
        delete obj;
    }
}

bool isNullT(T)(ref T obj){
    static if (is(typeof(obj is null))){
        return obj is null;
    } else static if (is(typeof(obj.isNull()))){
        return obj.isNull();
    } else static if (is(typeof(obj.isDummy()))){
        return obj.isDummy();
    } else {
        return false;
    }
}

/// the non array core types
template isBasicCoreType(T){
    immutable bool isBasicCoreType=is(T==bool)||is(T==byte)||is(T==ubyte)||is(T==short)
     ||is(T==ushort)||is(T==int)||is(T==uint)||is(T==float)
     ||is(T==long)||is(T==ulong)||is(T==double)||is(T==real)
     ||is(T==ifloat)||is(T==idouble)||is(T==ireal)||is(T==cfloat)
     ||is(T==cdouble)||is(T==creal)||is(T==char[])||is(T==wchar[])||is(T==dchar[]);
}
/// the basic types, out of these more complex types are built
template isCoreType(T){
    immutable bool isCoreType=is(T==bool)||is(T==byte)||is(T==ubyte)||is(T==short)
     ||is(T==ushort)||is(T==int)||is(T==uint)||is(T==float)
     ||is(T==long)||is(T==ulong)||is(T==double)||is(T==real)
     ||is(T==ifloat)||is(T==idouble)||is(T==ireal)||is(T==cfloat)
     ||is(T==cdouble)||is(T==creal)||is(T==char[])||is(T==wchar[])
     ||is(T==dchar[])||is(T==ubyte[])||is(T==void[]);
}

alias Tuple!(bool,byte,ubyte,short,ushort,int,uint,long,ulong,
    float,double,real,ifloat,idouble,ireal,cfloat,cdouble,creal,ubyte[],
    char[],wchar[],dchar[],void[]) CoreTypes;
alias Tuple!(char[],wchar[],dchar[]) CoreStringTypes;

/// string suitable to build names for the core type T
template strForCoreType(T){
    static if (is(T S:S[])){
        static if (is(T==ubyte[])){
            istring strForCoreType="binaryBlob";
        } else static if (is(T==void[])){
            istring strForCoreType="binaryBlob2";
        } else {
            istring strForCoreType=S.stringof~"Str";
        }
    } else{
        istring strForCoreType=T.stringof;
    }
}


/// compile time integer to string
string ctfe_i2s(int i){
    string digit="0123456789";
    string res="";
    if (i==0){
        return "0";
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
/// ditto
string ctfe_i2s(long i){
    string digit="0123456789";
    string res="";
    if (i==0){
        return "0";
    }
    bool neg=false;
    if (i<0){
        neg=true;
        i=-i;
    }
    while (i>0) {
        res=digit[cast(size_t)(i%10)]~res;
        i/=10;
    }
    if (neg)
        return '-'~res;
    else
        return res;
}
/// ditto
string ctfe_i2s(uint i){
    string digit="0123456789";
    string res;
    if (i==0){
        return "0";
    }
    bool neg=false;
    while (i>0) {
        res=digit[i%10]~res;
        i/=10;
    }
    return res;
}
/// ditto
string ctfe_i2s(ulong i){
    string digit="0123456789";
    string res;
    if (i==0){
        return "0";
    }
    bool neg=false;
    while (i>0) {
        res=digit[cast(size_t)(i%10)]~res;
        i/=10;
    }
    return res;
}
