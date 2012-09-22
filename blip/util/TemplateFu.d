/// TemplateFu contains various template/ctfe stuff that I found useful to put
/// in a single module (but most of it migrated to tango.core.Traits)
/// author: fawzi
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.util.TemplateFu;
import blip.core.Traits;
import blip.Comp;

/// returns the number of arguments in the tuple (its length)
template nArgs(){
    enum int nArgs=0;
}
/// returns the number of arguments in the tuple (its length)
template nArgs(T,S...){
    enum int nArgs=1+nArgs!(S);
}

/// identity function
T Id(T)(T a) { return a; }

// ------- CTFE -------

/// checks is c is a valid token char (also at compiletime), assumes a-z A-Z 1-9 sequences in collation
bool ctfe_isTokenChar(char c){
    return (c=='_' || c>='a'&&c<='z' || c>='A'&&c<='Z' || c=='0'|| c>='1' && c<='9');
}

/// checks if code contains the given token
bool ctfe_hasToken(string token,string code){
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
        } while((!outOfTokens) && i<code.length);
    }
    return false;
}

/// replaces all occurrences of token in code with repl
string ctfe_replaceToken(string token,string repl,string code){
    string res="";
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
        } while((!outOfTokens) && i<code.length);
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

struct Fun2Dlg(T,S...){
    T function(S) fun;
    T dlg(S args){
        static if(is(T==void)){
            fun(args);
        } else {
            return fun(args);
        }
    }
}

T delegate(S) fun2Dlg(T,S...)(T function(S) fun){
    auto res=new Fun2Dlg!(T,S);
    res.fun=fun;
    return &res.dlg;
}
