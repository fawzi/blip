/*******************************************************************************
    TemplateFu contains various template stuff that I found useful to put
    in a single module
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.TemplateFu;
import blip.t.core.Traits;

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

// ------- CTFE -------

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
