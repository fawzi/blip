module xf.xpose.ReflectionExpose;

private {
	import xf.xpose.Expose : expose, attribsContain, firstWord;
	version (Tango) {
		import tango.io.Stdout;
		import tango.text.Util : split, trim;
	} else {
		static assert (false);		// TODO :P
	}
}

public import xf.xpose.Utils;



template PrintoutExpose_mix() {
	static char[] begin() { return `void initReflection() {`\n; };
	static char[] end() { return `}`\n; }
	static char[] method(char[] name, char[] rename, char[] overload, char[] attribs) {
		return `funcExpose!(ReturnType!(`~overload~`),"`
			~rename~`",ParameterTypeTuple!(`~overload~`)`
			~`)(this,`~`cast(`~overload~`)`~`&`~name~`,"`~attribs~`");`\n;
	}
	static char[] field(char[] name, char[] rename, bool readOnly, char[] attribs) {
		return `fieldExpose!("`~rename~`", `~ToString!(readOnly)~`)(this, `~name~`,"`~attribs~`");`\n;
	}
}




template fieldExpose(char[] name, bool readOnly) {
	void fieldExpose(ThisType, T)(ThisType thisptr, inout T t, char[] attribs) {
		static if (readOnly) Stdout.format(`ReadOnly: `);
		dynFieldExpose(cast(void*)thisptr, t, name, attribs);
	}
}


void dynFieldExpose(T)(void* thisptr, inout T t, char[] name, char[] attribs) {
	Stdout.formatln("field {}\t: {} ", name, typeid(T)/+, attribs.join(`  ;  `)+/);
	attribIter: foreach (attr; attribs.split(`;`)) {
		attr = trim(attr);
		switch (attr) {
			case `no-serial`: Stdout.formatln(`the field will not be serialized`); continue attribIter;
			case `no-net`: Stdout.formatln(`the field will not be synched thru the network`); continue attribIter;
			default: break;
		}
		
		/+static if (is(T == vec3)) switch (attr) {
			case `normal`: writefln(`the vector is normalized`); continue attribIter;
		}

		else +/static if (is(T == int)) switch (firstWord(attr)) {
			case `range`: Stdout.formatln(`the int has a range specifier: {}`, attr[5..$]); continue attribIter;
		}

		else static if (is(T == float)) switch (firstWord(attr)) {
			case `range`: Stdout.formatln(`the int float a range specifier: {}`, attr[5..$]); continue attribIter;
		}

		else static if (is(T == char[])) switch (firstWord(attr)) {
			case `ascii`: Stdout.formatln(`the string is an ASCII (7bit) string`); continue attribIter;
			case `length`: Stdout.formatln(`the string has a length specifier: {}`, attr[6..$]);
		}
	}
	Stdout.newline;
}


template funcExpose(RetVal, char[] name, Params ...) {
	void funcExpose(ThisType, T)(ThisType thisptr, T t, char[] attribs ...) {
		dynFuncExpose!(RetVal, Params)(cast(void*)thisptr, t, name, attribs);
	}
}


template dynFuncExpose(RetVal, Params ...) {
	void dynFuncExpose(T)(void* thisptr, T t, char[] name, char[] attribs) {
		Stdout.formatln("func  {}\t: {}\tparams:{} ", name, typeid(T), typeid(Params), attribs);
		
		static if (!is(T == delegate)) {
			Stdout.formatln(`static function`);
		}

		Stdout.newline;
	}
}



struct PrintoutExpose {
	template handler(int i : 0) {
		mixin PrintoutExpose_mix;
	}
	
	mixin HandlerStructMix;
}
