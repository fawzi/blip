module xf.xpose.Utils;



version (Tango) {
	/**
		Templates from std.traits, by Walter Bright.
		Reformatted to fit here better.
	*/
	template ReturnType(alias dg) {
		alias ReturnType!(typeof(dg)) ReturnType;
	}
 
	template ReturnType(dg) {
		static if (is(dg R == return)) {
			alias R ReturnType;
		} else {
			static assert(0, "argument has no return type");
		}
	}
 
	template ParameterTypeTuple(alias dg) {
		alias ParameterTypeTuple!(typeof(dg)) ParameterTypeTuple;
	}
 
	template ParameterTypeTuple(dg) {
		static if (is(dg P == function)) {
			alias P ParameterTypeTuple;
		} else static if (is(dg P == delegate)) {
			alias ParameterTypeTuple!(P) ParameterTypeTuple;
		} else static if (is(dg P == P*)) {
			alias ParameterTypeTuple!(P) ParameterTypeTuple;
		} else {
			static assert(0, "argument has no parameters");
		}
	}


	// stuff stolen from Phobos
	enum
	{
		_SPC =	8,
		_CTL =	0x20,
		_BLK =	0x40,
		_HEX =	0x80,
		_UC  =	1,
		_LC  =	2,
		_PNC =	0x10,
		_DIG =	4,
		_ALP =	_UC|_LC,
	}

	ubyte _ctype[128] =
	[
		_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,
		_CTL,_CTL|_SPC,_CTL|_SPC,_CTL|_SPC,_CTL|_SPC,_CTL|_SPC,_CTL,_CTL,
		_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,
		_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,_CTL,
		_SPC|_BLK,_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,
		_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,
		_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,
		_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,_DIG|_HEX,
		_PNC,_PNC,_PNC,_PNC,_PNC,_PNC,
		_PNC,_UC|_HEX,_UC|_HEX,_UC|_HEX,_UC|_HEX,_UC|_HEX,_UC|_HEX,_UC,
		_UC,_UC,_UC,_UC,_UC,_UC,_UC,_UC,
		_UC,_UC,_UC,_UC,_UC,_UC,_UC,_UC,
		_UC,_UC,_UC,_PNC,_PNC,_PNC,_PNC,_PNC,
		_PNC,_LC|_HEX,_LC|_HEX,_LC|_HEX,_LC|_HEX,_LC|_HEX,_LC|_HEX,_LC,
		_LC,_LC,_LC,_LC,_LC,_LC,_LC,_LC,
		_LC,_LC,_LC,_LC,_LC,_LC,_LC,_LC,
		_LC,_LC,_LC,_PNC,_PNC,_PNC,_PNC,_CTL
	];

	int isalpha(dchar c)  { return (c <= 0x7F) ? _ctype[c] & (_ALP)      : 0; }
	int isdigit(dchar c)  { return (c <= 0x7F) ? _ctype[c] & (_DIG)      : 0; }

	int rfind(char[] str, char[] foo) {
		assert (foo.length == 1);
		foreach_reverse(i, c; str) {
			if (c == foo[0]) return i;
		}
		return -1;
	}

	template ToString(int i) {
		static if (i < 10) const char[] ToString = "" ~ cast(char)(i + '0');
		else const char[] ToString = ToString!(i / 10) ~ ToString!(i % 10);
	}

	template ToString(bool B) {
		const char[] ToString = B ? "true" : "false";
	}
} else {
	public import std.traits : ReturnType, ParameterTypeTuple;
	public import std.ctype : isalpha, isdigit;
	public import std.string : rfind;
	public import std.metastrings : ToString;
}



char[] shortName(char[] classname) {
	int dot = rfind(classname, `.`);
	return -1 == dot ? classname : classname[dot+1..$];
}


char[] shortNameOf(T)() {
	return shortName(typeid(T).toString);
}


char[] capitalize(char[] name) {
	assert (name.length > 0);
	
	if (name[0] >= 'a' && name[0] <= 'z') {
		return cast(char)(name[0] + 'A' - 'a') ~ name[1..$];
	}
	else return name;
}


// ---- this stuff was inside HandlerStructMix before
template firstUnusedHandlerIndex(A, int i = 0) {
	static if (is(typeof(A.handler!(i)))) {
		const int firstUnusedHandlerIndex = firstUnusedHandlerIndex!(A, i+1);
	} else {
		const int firstUnusedHandlerIndex = i;
	}
}


static private char[] intToString__(uint i) {
	if (i < 10) return ""~"0123456789"[i];
	return intToString__(i/10) ~ ("0123456789"[i%10]);
}
static private char[] generateExposeHandlers(int n, int offset, char[] context) {
	char[] res;
	for (int i = 0; i < n; ++i) {
		res ~= `template handler(int i : `~intToString__(i+offset)~`) { alias `~context~`.handler!(`~intToString__(i)~`) handler; }`;
	}
	return res;
}


struct CombinedHandlerType(A, B) {
	const int firstUnusedInA = firstUnusedHandlerIndex!(A);
	const int firstUnusedInB = firstUnusedHandlerIndex!(B);
	mixin(generateExposeHandlers(firstUnusedInA, 0, `A`));
	mixin(generateExposeHandlers(firstUnusedInB, firstUnusedInA, `B`));
}
// ----


template HandlerStructMix() {
	static CombinedHandlerType!(typeof(*this), RHS) opAnd(RHS)(RHS rhs) {
		return CombinedHandlerType!(typeof(*this), RHS)();
	}
}


template Combine(T ...) {
	static if (T.length > 1) {
		alias typeof(T[0]() & Combine!(T[1..$])()) Combine;
	} else {
		alias T[0] Combine;
	}
}
