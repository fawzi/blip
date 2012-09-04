/// compatibility module to help the D1-D2 transition
///
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
module blip.Comp;

version(D_Version2){
mixin(`
  import std.traits: Unqual;
  template Const(T){
      alias const(T) Const;
  }
  template Immutable(T){
      alias immutable(T) Immutable;
  }
  immutable(T) Idup(T)(T val){
      return val.idup;
  }
  //alias immutable(char)[] string;
  alias const(char)[] cstring;
  alias const(wchar)[] cstringw;
  alias const(dchar)[] cstringd;
  alias immutable(char[]) istring;
`);

/**
 * Evaluates to true if T is a static array type.
 */
template isStaticArrayTypeLocal( T : T[U], size_t U )
{
    immutable bool isStaticArrayTypeLocal = true;
}

template isStaticArrayTypeLocal( T )
{
    immutable bool isStaticArrayTypeLocal = false;
}

template UnqualAll0(T)
{
    static if (is(T U == shared(const U))) alias Unqual!(U) UnqualAll0;
    else static if (is(T U ==        const U )) alias Unqual!(U) UnqualAll0;
    else static if (is(T U ==    immutable U )) alias Unqual!(U) UnqualAll0;
    else static if (is(T U ==        inout U )) alias Unqual!(U) UnqualAll0;
    else static if (is(T U ==       shared U )) alias Unqual!(U) UnqualAll0;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/U.sizeof] == T)) {
		alias Unqual!(U)[T.sizeof/U.sizeof] UnqualAll0;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias Unqual!(U)[] UnqualAll1;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
        alias Unqual!(typeof(T.init.values[0]))[Unqual!(typeof(T.init.keys[0]))] UnqualAll0;
    } else static if (is(T U : U*)) {
	alias Unqual!(U)* UnqualAll0;
    } else                                        alias T UnqualAll0;
}

template UnqualAll1(T)
{
    static if (is(T U == shared(const U))) alias UnqualAll0!(U) UnqualAll1;
    else static if (is(T U ==        const U )) alias UnqualAll0!(U) UnqualAll1;
    else static if (is(T U ==    immutable U )) alias UnqualAll0!(U) UnqualAll1;
    else static if (is(T U ==        inout U )) alias UnqualAll0!(U) UnqualAll1;
    else static if (is(T U ==       shared U )) alias UnqualAll0!(U) UnqualAll1;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/U.sizeof] == T)) {
		alias UnqualAll0!(U)[T.sizeof/U.sizeof] UnqualAll1;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAll0!(U)[] UnqualAll1;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	    alias UnqualAll0!(typeof(T.init.values[0]))[UnqualAll0!(typeof(T.init.keys[0]))] UnqualAll1;
    } else static if (is(T U : U*)) {
	alias UnqualAll0!(U)* UnqualAll1;
    } else                                        alias T UnqualAll1;
}

template UnqualAll2(T)
{
    static if (is(T U == shared(const U))) alias UnqualAll1!(U) UnqualAll2;
    else static if (is(T U ==        const U )) alias UnqualAll1!(U) UnqualAll2;
    else static if (is(T U ==    immutable U )) alias UnqualAll1!(U) UnqualAll2;
    else static if (is(T U ==        inout U )) alias UnqualAll1!(U) UnqualAll2;
    else static if (is(T U ==       shared U )) alias UnqualAll1!(U) UnqualAll2;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/U.sizeof] == T)) {
		alias UnqualAll1!(U)[T.sizeof/T.init.ptr.sizeof] UnqualAll2;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAll1!(U)[] UnqualAll2;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	    alias UnqualAll1!(typeof(T.init.values[0]))[UnqualAll1!(typeof(T.init.keys[0]))] UnqualAll2;
    } else static if (is(T U:U*)) {
	alias UnqualAll1!(U)* UnqualAll2;
    }
    else                                        alias T UnqualAll2;
}

template UnqualAll3(T)
{
    static if (is(T U == shared(const U))) alias UnqualAll2!(U) UnqualAll3;
    else static if (is(T U ==        const U )) alias UnqualAll2!(U) UnqualAll3;
    else static if (is(T U ==    immutable U )) alias UnqualAll2!(U) UnqualAll3;
    else static if (is(T U ==        inout U )) alias UnqualAll2!(U) UnqualAll3;
    else static if (is(T U ==       shared U )) alias UnqualAll2!(U) UnqualAll3;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/U.sizeof] == T)) {
		alias UnqualAll2!(U)[T.sizeof/T.init.ptr.sizeof] UnqualAll3;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAll2!(U)[] UnqualAll3;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	    alias UnqualAll2!(typeof(T.init.values[0]))[UnqualAll2!(typeof(T.init.keys[0]))] UnqualAll3;
    } else static if (is(T U:U*)) {
	alias UnqualAll2!(U)* UnqualAll3;
    } else                                        alias T UnqualAll3;
}

template UnqualAll4(T)
{
    static if (is(T U == shared(const U))) alias UnqualAll3!(U) UnqualAll4;
    else static if (is(T U ==        const U )) alias UnqualAll3!(U) UnqualAll4;
    else static if (is(T U ==    immutable U )) alias UnqualAll3!(U) UnqualAll4;
    else static if (is(T U ==        inout U )) alias UnqualAll3!(U) UnqualAll4;
    else static if (is(T U ==       shared U )) alias UnqualAll3!(U) UnqualAll4;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/T.init.ptr.sizeof] == T)) {
		alias UnqualAll3!(U)[T.sizeof/U.sizeof] UnqualAll4;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAll3!(U)[] UnqualAll4;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	    alias UnqualAll3!(typeof(T.init.values[0]))[UnqualAll3!(typeof(T.init.keys[0]))] UnqualAll4;
    } else static if (is(T U:U*)) {
	alias UnqualAll3!(U)* UnqualAll4;
    } else                                        alias T UnqualAll4;
}

template UnqualAllRec(T){
    alias UnqualAll4!(T) UnqualAllRec;
}

template UnqualAll(T)
{
    version(none) {
    static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/T.init.ptr.sizeof] == T)) {
		alias UnqualAll!(U)[T.sizeof/T.init.ptr.sizeof] UnqualAll;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAll!(U)[] UnqualAll;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	    alias UnqualAll!(typeof(T.init.values[0]))[UnqualAll!(typeof(T.init.keys[0]))] UnqualAll;
    /+} else static if (is(T U == delegate)) {
        newArgs0=Tuple!();
        foreach (i,V; U) {
	    mixin("alias Tuple!(newArgs"~ctfe_i2s(i)~",UnqualAll!(V)) newArgs"~ctfe_i2s(i+1)~";");
        }
        static if (is(T V == return)) {
	    mixin("alias UnqualAll!(V)delegate(newArgs"~ctfe_i2s(U.sizeof)~") UnqualAll;");
        } else static assert(0);
    } else static if (is(T U == function)) {
        newArgs0=Tuple!();
        foreach (i,V; U) {
	    mixin("alias Tuple!(newArgs"~ctfe_i2s(i).idup~",UnqualAll!(V)) newArgs"~ctfe_i2s(i+1)~";");
        }
        static if (is(T V == return)) {
	    mixin("alias UnqualAll!(V)function(newArgs"~ctfe_i2s(U.sizeof)~") UnqualAll;");
        } else static assert(0); +/
    } else static if (is(T U:U*)) {
	alias UnqualAll!(U)* UnqualAll;
    } else static if (is(T U == shared(const U))) alias UnqualAll!(U) UnqualAll;
    else static if (is(T U ==        const U )) alias UnqualAll!(U) UnqualAll;
    else static if (is(T U ==    immutable U )) alias UnqualAll!(U) UnqualAll;
    else static if (is(T U ==        inout U )) alias UnqualAll!(U) UnqualAll;
    else static if (is(T U ==       shared U )) alias UnqualAll!(U) UnqualAll;
    else                                        alias T UnqualAll;
    } else {
    static if (is(T U == shared(const U))) alias UnqualAllRec!(U) UnqualAll;
    else static if (is(T U ==        const U )) alias UnqualAllRec!(U) UnqualAll;
    else static if (is(T U ==    immutable U )) alias UnqualAllRec!(U) UnqualAll;
    else static if (is(T U ==        inout U )) alias UnqualAllRec!(U) UnqualAll;
    else static if (is(T U ==       shared U )) alias UnqualAllRec!(U) UnqualAll;
    else static if (is(T U : U[])) {
	static if (isStaticArrayTypeLocal!(T)){
	    static if (is(U[T.sizeof/U.sizeof] == T)) {
		alias UnqualAllRec!(U)[T.sizeof/T.init.ptr.sizeof] UnqualAll;
	    } else { 
		static assert(0,"multidimensional static arrays are unsupported");
	    }
        } else {
	    alias UnqualAllRec!(U)[] UnqualAll;
	}
    } else static if (is( typeof(T.init.values[0])[typeof(T.init.keys[0])] == T )) {
	alias UnqualAllRec!(typeof(T.init.keys[0])) K;
	alias UnqualAllRec!(typeof(T.init.values[0])) V;
	alias V[K] UnqualAll;
    } else static if (is(T U:U*)) {
	alias UnqualAllRec!(U)* UnqualAll;
    } else                                        alias T UnqualAll;
    }
}
/+    static assert(is(UnqualAll!(const(char)[]) == char[]));
    static assert(is(UnqualAll!(string) == char[]));
    static assert(is(UnqualAll!(immutable(Object)) == Object));
    static assert(is(UnqualAll!(int[string]) == int[char[]]));
    static assert(is(UnqualAll!(int[const(char)[]]) == int[char[]]));
    static assert(is(UnqualAll!(shared Object) == Object));+/

} else {
  template Const(T){
      alias T Const;
  }
  template Immutable(T){
      alias T Immutable;
  }
  T Idup(T)(T val){
      return val.dup;
  }
  alias char[] string;
  alias char[] cstring;
  alias wchar[] cstringw;
  alias dchar[] cstringd;
  alias char[] istring;
  template Unqual(T){
      alias T Unqual;
  }
}
