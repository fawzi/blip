module xf.xpose2.Expose;

private {
	import xf.xpose2.Utils;

	import tango.text.Util : split, trim;
	import tango.core.Traits : ReturnTypeOf, ParameterTupleOf;
	import xf.xpose2.Utils : ctReplace;
}

public {
	alias xf.xpose2.Utils.CombinedHandlerType CombinedHandlerType;
	alias xf.xpose2.Utils.HandlerStructMix HandlerStructMix;
	alias xf.xpose2.Utils.Combine Combine;
	import xf.utils.NameOf : isStaticMemberFunc;
}



public char[][] xposeAttribParser_overload(char[] foo) {
	return [
		"!type", foo,
		"typeName", '"' ~ foo ~ '"'
	];
}



private char[] intToStringCT(int i) {
	char[] res = "";
	do
	{
		res ~= "0123456789"[i%10];
		i /= 10;
	} while (i > 0);
	
	for (int j = 0; j < res.length/2; ++j) {
		char c = res[j];
		res[j] = res[res.length-j-1];
		res[res.length-j-1] = c;
	}
	return res;
}

private char[] rangeCodegen(int i) {
	char[] res = `alias RangeTuple!(`;
	if (i > 0) {
		res ~= "0";
		for (int j = 1; j < i; ++j) {
			res ~= "," ~ intToStringCT(j);
		}
	}
	return res ~ ") Range;";
}

private template RangeTuple(T ...) {
	alias T RangeTuple;
}

private template Range(int i) {
	mixin(rangeCodegen(i));
}

private char[][] allNamesInAlias(alias target)() {
	char[][] names;
	const int len = target.tupleof.length;
	int prefix = target.stringof.length + 3;		// "(Type)."
	foreach (i; Range!(len)) {
		names ~= target.tupleof[i].stringof[prefix..$];
	}
	return names;
}


private bool matchesClassCT(char c, char[] cls) {
	if (char.init == c) return false;
	assert (cls.length > 0);

	if ("." == cls) return true;
	if (1 == cls.length && c == cls[0]) return true;

	if ('[' == cls[0]) {
		assert (']' == cls[$-1]);
		cls = cls[1..$-1];
		bool res = true;
		int from = 0;
		if ('^' == cls[0]) {
			res = false;
			from = 1;
		}
		for (int i = from; i < cls.length; ++i) {
			if ('\\' == cls[i]) {
				if (cls[i+1] == c) return res;
				else ++i;
			} else if (i+1 < cls.length && '-' == cls[i+1]) {
				assert (i+2 < cls.length);
				if (c >= cls[i] && c <= cls[i+2]) return res;
				else i += 2;
			} else if (cls[i] == c) return res;
		}
		return !res;
	}
	assert (1 == cls.length);
	return cls[0] == c;
}

private int cutBRExprCT(char[] str, out char[] cls) {
	for (int i = 0; i < str.length; ++i) {
		if ('\\' == str[i]) ++i;
		else if (']' == str[i]) {
			cls = str[0..i+1];
			return i;
		}
	}
	assert (false);
	return int.max;
}


/**
	A very greedy pattern matching function.
	
	.				matches any character
	[abc]		matches a, b and c
	[a-z]			matches a through z
	[abcA-Z]	matches a, b, c, and A through Z, etc.
	[^stuff]		matches the inverse of [stuff]
	?				matches the preceding element zero or one time
	*				matches the preceding element zero or more times
	
	It's not a regex engine, it's much less powerful in order to be lightweight.
	The greediness means that "f.*r" will not match "foobar", but "f.*" will.
*/
private bool matchesPatternCT(char[] str, char[] pattern) {
	char[]	cls;
	bool		prevMatched = true;
	bool		fail = true;
	int		stri = -1;
	
	strIter: while (pattern.length > 0) {
		switch (pattern[0]) {
			case '*': {
				if (!prevMatched) --stri;
				while (prevMatched && matchesClassCT(stri+1 < str.length ? str[stri+1] : char.init, cls)) {
					++stri;
				}
				pattern = pattern[1..$];
				prevMatched = true;
			} break;
			
			case '?': {
				if (!prevMatched) --stri;
				pattern = pattern[1..$];
				prevMatched = true;
			} break;
			
			default: {
				// see if the previous class matched, return false if it didn't
				if (!prevMatched) {
					return false;
				} else {
					++stri;
				}
				
				// find the class
				if ('[' == pattern[0]) {
					pattern = pattern[cutBRExprCT(pattern, cls)+1..$];
				} else {
					cls = pattern[0..1];
					pattern = pattern[1..$];
				}
				prevMatched = matchesClassCT(stri < str.length ? str[stri] : char.init, cls);
			}
		}
	}
	
	return prevMatched && stri+1 >= str.length;
}


/**
	Matches the str to a pattern expression formed by patterns supported by matchesPatternCT
	and operators '+' and '-'
*/
private bool matchesComplexPatternCT(char[] str, char[] pattern) {
	bool res = false;
	char prevFunc = '+';
	int i = 0;
	for (; i < pattern.length; ++i) {
		if ('-' == pattern[i] || '+' == pattern[i]) {
			bool match = matchesPatternCT(str, pattern[0..i]);
			if ('+' == prevFunc) {
				res |= match;
			} else {
				res &= !match;
			}
			prevFunc = pattern[i];
			pattern = pattern[i+1..$];
			i = -1;
		}
	}

	if (i > 0) {
		bool match = matchesPatternCT(str, pattern[0..i]);
		if ('+' == prevFunc) {
			res |= match;
		} else {
			res &= !match;
		}
	}
	
	return res;
}


private bool isPatternCT(char[] str) {
	foreach (c; str) {
		switch (c) {
			case '.':
			case '?':
			case '*':
			case '-':
			case '+':
			case '[': return true;
			default: break;
		}
	}
	return false;
}

private char[][] matchedNamesCT(alias target)(char[] pattern) {
	char[][] res;
	foreach (name; allNamesInAlias!(target)) {
		if (matchesComplexPatternCT(name, pattern)) {
			res ~= name;
		}
	}
	return res;
}




private char[] escapeDoubleQuotes(char[] str) {
	char[] res;
	foreach (c; str) {
		switch (c) {
			case '\\': {
				res ~= `\\`;
			} break;
			
			case '"': {
				res ~= `\"`;
				break;
			}
			
			default: {
				res ~= c;
			}
		}
	}
	return res;
}


char[] attribCodegen(char[] name, char[][] parsed) {
	name = escapeDoubleQuotes(name);
	
	char[] res = 
		`interface `~name~` {
			enum : bool { isSimple = true }
			const name = "`~name~`";
		`;
	
	char[][] names;
	
	for (int i = 0; i < parsed.length; i += 2) {
		if ('!' == parsed[i][0]) {
			res ~= ctReplace(
				`alias $val$ $attr$;`\n,
				[
					`$attr$`, parsed[i][1..$],
					`$val$`, parsed[i+1]
				]
			);
			names ~= "(" ~ parsed[i][1..$] ~ ").init";
		} else {
			res ~= ctReplace(
				`const $attr$ = $val$;`\n,
				[
					`$attr$`, parsed[i],
					`$val$`, parsed[i+1]
				]
			);
			names ~= parsed[i];
		}
	}

	res ~= `alias Xpose2Tuple!(`;
	for (int i = 0; i < names.length; ++i) {
		if (i > 0) {
			res ~= ",";
		}
		res ~= names[i];
	}
	res ~= `) _tuple;`;

	res ~= `alias Xpose2Tuple!(`;
	for (int i = 0; i < names.length; ++i) {
		if (i > 0) {
			res ~= ",";
		}
		res ~= `"` ~ names[i] ~ `"`;
	}
	res ~= `) _nameTuple;`;
	res ~= `} const _Attrib_`~name~` = `~name~`.init;`\n;
	
	return res;
}


private char[] unescape(char[] str) {
	bool any = false;
	foreach (c; str) {
		if ('\\' == c) {
			any = true;
			break;
		}
	}
	if (any) {
		char[] res;
		bool escape = false;
		foreach (c; str) {
			if (escape) {
				res ~= c;
				escape = false;
			} else {
				if ('\\' == c) {
					escape = true;
				} else {
					res ~= c;
				}
			}
		}
		return res;
	} else {
		return str;
	}
}

private char[][] splitStrByChar(char[] str, char d) {
	char[][] res;
	int i = 0;
	int prev = 0;
	bool escape = false;
	
	for (; i < str.length; ++i) {
		if ('\\' == str[i]) {
			escape = true;
		} else {
			if (d == str[i] && !escape) {
				int from = prev;
				int to = i;
				if (to > from) {
					res ~= unescape(str[from .. to]);
				}
				prev = to+1;
			}
			escape = false;
		}
	}

	int from = prev;
	int to = str.length;
	if (to > from) {
		res ~= unescape(str[from .. to]);
	}
	
	return res;
}

private bool isSpaceCT(char c) {
	return ' ' == c || '\t' == c;
}

private char[] striplCT(char[] s) {
	uint i;
	for (i = 0; i < s.length; i++) {
		if (!isSpaceCT(s[i])) {
			break;
		}
	}
	return s[i .. s.length];
}

private char[] striprCT(char[] s) {
	uint i;
	for (i = s.length; i > 0; i--) {
		if (!isSpaceCT(s[i - 1])) {
			break;
		}
	}
	return s[0 .. i];
}


private char[] stripCT(char[] s) {
    return striprCT(striplCT(s));
}


private bool isLetterCT(char c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}


private bool isDigitCT(char c) {
	return c >= '0' && c <= '9';
}


private int locateCT(char[] str, char c) {
	foreach (i, c2; str) {
		if (c == c2) return i;
	}
	return str.length;
}


private char[] parseAttribsWorker(ref char[] str, int depth = 0, char[] prefix = "") {
	char[] code;
	
	char[][] names;
	while (str.length > 0) {
		int scolon = locateCT(str, ';');
		int obrace = locateCT(str, '{');
		int cbrace = locateCT(str, '}');
		
		bool singleField = void;
		bool lastField = false;
		
		int limit = void;
		int newStart = void;
		
		if (scolon < obrace && scolon < cbrace) {
			// semicolon is next
			singleField = true;
			limit = scolon;
			newStart = limit+1;
		} else if (cbrace < scolon && cbrace < obrace) {
			// closing brace is first
			singleField = true;
			lastField = true;
			limit = cbrace;
			newStart = limit+1;
		} else if (obrace < scolon && obrace < cbrace) {
			// opening brace is first
			singleField = false;
			limit = obrace;
			newStart = limit+1;
		} else {
			// last field
			singleField = true;
			lastField = true;
			limit = str.length;
			newStart = limit;
			assert (0 == depth);
		}
		
		char[] attrDef = striplCT(str[0..limit]);
		str = str[newStart..$];
		
		if (singleField) {
			if (attrDef.length > 0) {
				assert (isLetterCT(attrDef[0]) || '_' == attrDef[0]);
				int nameTo = 1;
				while (nameTo < attrDef.length && (
					isDigitCT(attrDef[nameTo]) ||
					isLetterCT(attrDef[nameTo]) ||
					'_' == attrDef[nameTo]
				)) {
					++nameTo;
				}
				
				char[] name = attrDef[0..nameTo];
				char[] value = stripCT(attrDef[nameTo..$]);
				names ~= name;
				
				char[] tmpCode =
					`;
					static if (is(typeof(attribCodegen("$name$", xposeAttribParser$prefix$_$name$(`~'`'~`$value$`~'`'~`))) == char[])) {
						res ~= attribCodegen("$name$", xposeAttribParser$prefix$_$name$(`~'`'~`$value$`~'`'~`));
					} else {
						`;
						if (value.length > 0) {
							tmpCode ~=
							`res ~= attribCodegen("$name$", ["value", `~'`'~`$value$`~'`'~`]);`;
						} else {
							tmpCode ~=
							`res ~= attribCodegen("$name$", null);`;
						}
						tmpCode ~= `
					} res ~= ""`;

				code ~= ctReplace(
					tmpCode,
					[
						`$name$`, name,
						`$value$`, value,
						`$prefix$`, prefix
					]
				);
			}
		} else {
			char[] scopeName = striprCT(attrDef);
			names ~= "_"~scopeName;
			assert (scopeName.length > 0);
			code ~= `~"interface _`~scopeName~`{ enum : bool { isSimple = false } const name = \"`~scopeName~`\"; "`;
			code ~= parseAttribsWorker(str, depth+1, prefix~'_'~scopeName);
			code ~= `~"} const `~scopeName~` = _`~scopeName~`.init;"`;
		}

		if (lastField) {
			break;
		}
	}

	code ~= `~"alias Xpose2Tuple!(`;
	for (int i = 0; i < names.length; ++i) {
		if (i > 0) {
			code ~= ",";
		}
		code ~= names[i];
	}
	code ~= `) _tuple;"`;
	
	return code;
}


private char[] parseAttribs(char[] str) {
	char[] code = `"interface _attribs {"`;
	code ~= parseAttribsWorker(str);
	code ~= `~"} const attribs = _attribs.init;"`;
	
	return code;
}


private void splitNameAttribs(char[] line, out char[] name, out char[] attribs) {
	int i = 0;
	for (; i < line.length; ++i) {
		if (' ' == line[i] || '\t' == line[i]) break;
	}
	name = line[0..i];
	attribs = line[i..$];
}

private char[][] splitLines(char[] str) {
	char[][] res;
	while (str.length) {
		int from = -1, to = -1;
		for (from = 0; from < str.length; ++from) {
			if (str[from] == '\n' || str[from] == '\r' || str[from] == '|') {
				str = str[from+1..$];
				from = -1;
				break;
			}
			if (str[from] == ' ' || str[from] == '\t') continue;
			break;
		}
		
		if (-1 == from) continue;

		for (to = from; to < str.length; ++to) {
			if (str[to] == '\n' || str[to] == '\r' || str[to] == '|') {
				break;
			}
		}
		
		char[] part = str[from..to];
		str = str[to..$];
		if (to == from) continue;
		while (part.length > 0 && (part[$-1] == ' ' || part[$-1] == '\t')) part = part[0..$-1];
		
		if (0 == part.length) continue;
		res ~= part;
	}
	
	return res;
}


template Xpose2Tuple(TList...) {
    alias TList Xpose2Tuple;
}


private void findFieldXposeRename(char[] str, out char[] dname, out char[] xname) {
	foreach (i, c; str) {
		if ('@' == c) {
			dname = str[0..i];
			xname = dname ~ `__` ~ str[i+1..$];
			return;
		}
	}
	
	dname = str;
	xname = str;
}


char[] xpose2MainCodegenWorker(char[] targetName, char[] dname, char[] dataPrefix, char[] xname, char[] reflName, char[] attribsCode) {
	if ("_ctor" == reflName) {
			return "
				res ~=
				`interface _Field_"~xname~" {
					enum : bool { isFunction = false }
					enum : bool { isCtor = true }
					enum : bool { isData = false }
					const name = \""~reflName~"\";
					alias "~targetName~" returnType;
					` ~ "~attribsCode~" ~ `
					static if (is(attribs.overload)) {
						alias ParameterTupleOf!(attribs.overload.type) paramTypes;
					} else {
						alias ParameterTupleOf!("~dataPrefix~dname~") paramTypes;
					}
				}`;
			";
	} else {
		return "
			static if (is(typeof("~dataPrefix~dname~") == function)) {
				res ~=
				`interface _Field_"~xname~" {
					enum : bool { isFunction = true }
					enum : bool { isCtor = false }
					enum : bool { isData = false }
					const bool isStatic = isStaticMemberFunc!("~dataPrefix~dname~")();
					const name = \""~reflName~"\";
					alias ReturnTypeOf!("~dataPrefix~dname~") returnType;
				` ~ "~attribsCode~" ~ `
					static if (is(attribs.overload)) {
						alias ParameterTupleOf!(attribs.overload.type) paramTypes;
					} else {
						alias ParameterTupleOf!("~dataPrefix~dname~") paramTypes;
					}`
					\\n`}`\\n;
			} else {
				res ~=
				`interface _Field_"~xname~" {
					enum : bool { isFunction = false }
					enum : bool { isCtor = false }
					enum : bool { isData = true }
					const name = \""~reflName~"\";
					alias typeof(("~dataPrefix[0..$-1]~").init."~dname~") type;
				` ~ "~attribsCode~" \\n`}`\\n;
			}";
	}
}


char[] xpose2MainCodegen(alias targetAlias)(char[] funcSuffix, char[] dataPrefix, char[] metaName, char[] expStr) {
	char[] res =
	"static char[] _xposeDataCodegenFunc"~funcSuffix~"() {
		char[] res;";
		
	expStr = stripCT(expStr);
	
	char[][] names;
	char[][] tmpNames;
	
	if (expStr.length > 0) foreach (line; splitLines(expStr)) {
		if (line.length > 0) {
			char[] tmpname;
			char[] attribs;
			splitNameAttribs(line, tmpname, attribs);
			char[] attribsCode = parseAttribs(attribs);
			
			if (isPatternCT(tmpname)) {
				foreach (dname; matchedNamesCT!(targetAlias)(tmpname)) {
					char[] xname = dname;
					char[] reflName = dname;
					//dname = dname;		BUG?
					names ~= xname;
					res ~= xpose2MainCodegenWorker(targetAlias.stringof, dname, dataPrefix, xname, reflName, attribsCode);
				}
			} else {
				for (int ni = 0; ni < tmpNames.length; ++ni) {
					if (tmpNames[ni] == tmpname) {
						if (tmpname.length > 2 && tmpname[$-2] == '@') {
							assert (tmpname[$-1] <= 'z', `onoz, too many overloads`);
							tmpname = tmpname[0..$-1] ~ "abcdefghijklmnopqrstuvwxyz"[tmpname[$-1]-'a'+1];
						} else {
							tmpname ~= "@a";
						}
					}
				}
				
				char[] dname;
				char[] xname;
				findFieldXposeRename(tmpname, dname, xname);
				
				char[] reflName = dname;
				//dname = dname;	BUG?
				
				names ~= xname;
				tmpNames ~= tmpname;
				res ~= xpose2MainCodegenWorker(targetAlias.stringof, dname, dataPrefix, xname, reflName, attribsCode);
			}
		}
	}
	
	res ~= "res ~= \"alias Xpose2Tuple!(";
	if (names.length > 0) foreach (i, name; names) {
		if (i > 0) {
			res ~= ",";
		}
		res ~= "_Field_" ~ name;
	}
	res ~= ") "~metaName~";\";\n";
	
	res ~= "return res; }";
	res ~= "mixin(_xposeDataCodegenFunc"~funcSuffix~"());";
	
	return res;
}


char[] xpose2(char[] expStr) {
	return ctReplace(
		`static if (is(typeof(*this) == struct)) {
			mixin(xpose2MainCodegen!(mixin(typeof(*this).stringof))(__LINE__.stringof, typeof(this).stringof[0..$-1] ~ ".", "xposeFields", "$expStr$"));
		} else {
			mixin(xpose2MainCodegen!(mixin(typeof(this).stringof))(__LINE__.stringof, typeof(this).stringof ~ ".", "xposeFields", "$expStr$"));
		}`,
		[ `$expStr$`, escapeDoubleQuotes(expStr) ]
	);
}


char[] xpose2(char[] target, char[] expStr) {
	return ctReplace(
		`mixin(xpose2MainCodegen!(`~target~`)(__LINE__.stringof, "$dataPrefix$", "xposeFields", "$expStr$"));`,
		[	`$expStr$`, escapeDoubleQuotes(expStr),
			`$dataPrefix$`, target ~ `.`
		]
	);
}


void dumpXposeSimpleAttrib(T)() {
	foreach (i, x; T._tuple) {
		pragma (msg, T._nameTuple[i] ~ " = " ~ x.stringof);
	}
}


void dumpXposeAttr(T)() {
	pragma (msg, "attrib " ~ T.name ~ "{");
	static if (T.isSimple) {
		dumpXposeSimpleAttrib!(T);
	} else {
		foreach (x; T._tuple) {
			dumpXposeAttr!(x);
		}
	}
	pragma (msg, "}");
}


void dumpXposeData(T)() {
	foreach (field; T.xposeFields) {
		pragma (msg, field.name ~ " {");
		static if (field.isFunction) {
			pragma (msg, "it's a function: " ~ field.returnType.stringof ~ " function " ~ field.paramTypes.stringof);
		} else {
			pragma (msg, "it's a simple field: " ~ field.type.stringof);
		}
		foreach (attr; field.attribs._tuple) {
			dumpXposeAttr!(attr)();
		}
		pragma (msg, "}");
	}
}
