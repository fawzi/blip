module xf.xpose.Expose;

private {
	import xf.xpose.Utils;
}

public {
	alias xf.xpose.Utils.CombinedHandlerType CombinedHandlerType;
	alias xf.xpose.Utils.HandlerStructMix HandlerStructMix;
	alias xf.xpose.Utils.Combine Combine;
}


// utility stuff -------------------------------------------------------------------------------------------------------------------------------------------------------


char[][] splitLines(char[] str) {
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


void splitNameAttribs(char[] line, out char[] name, out char[] attribs) {
	int i = 0;
	for (; i < line.length; ++i) {
		if (' ' == line[i] || '\t' == line[i]) break;
	}
	name = line[0..i];
	attribs = line[i..$];
}


char[] quoteAttribs(char[] attribs) {
	char[] res;
	
	while (attribs.length > 0) {
		if (' ' == attribs[0] || '\t' == attribs[0] || ';' == attribs[0]) {
			attribs = attribs[1..$];
			continue;
		}
		
		res ~= `,"`;
		while (attribs.length > 0 && attribs[0] != ';') {
			res ~= attribs[0];
			attribs = attribs[1..$];
		}
		res ~= '"';		// add one quot
	}
	
	return res;
}


char[] firstWord(char[] str) {
	int last = -1;
	foreach(i, ch; str) if (isalpha(ch) || isdigit(ch) || '-' == ch || '_' == ch) last = i; else break;
	if (last != -1) return str[0..last+1];
	return null;
}


bool beginsWith(char[] str, char[] beg) {
	return str.length >= beg.length && str[0..beg.length] == beg;
}


char[] rStrip(char[] s) {
	while (s.length > 0 && (s[$-1] == ' ' || s[$-1] == '\t')) s = s[0..$-1];
	return s;
}


char[] lStrip(char[] s) {
	while (s.length > 0 && (s[0] == ' ' || s[0] == '\t')) s = s[1..$];
	return s;
}


void extractInfo(char[] attribs, inout char[] filtered, inout char[] name, inout bool readOnly, inout char[] overload) {
	while (attribs.length > 0) {
		if (' ' == attribs[0] || '\t' == attribs[0]) {
			attribs = attribs[1..$];
			continue;
		}
		
		int end = 0;
		for (int i = 0; i < attribs.length; end=++i) {
			char c = attribs[i];
			if (c == ';') break;
		}
		
		char[] part = attribs[0..end];
		attribs = attribs[end..$];
		if (attribs.length > 0) attribs = attribs[1..$];
		part = rStrip(part);
		
		if (beginsWith(part, `overload`)) {
			part = lStrip(part[`overload`.length+1..$]);
			int openparen = 0;
			foreach (i, c; part) if (c == '(') { openparen = i; break; }
			overload = part[0..openparen] ~ ` delegate` ~ part[openparen..$];
		} else if (beginsWith(part, `name`)) {
			name = lStrip(part[`name`.length+1..$]);
		} else if (beginsWith(part, `readOnly`)) {
			readOnly = true;
		} else {
			if (part.length > 0) {
				filtered ~= part ~ `;`;
			}
		}
	}
}


bool attribsContain(char[] attribs, char[] item) {
	while (attribs.length > 0) {
		if (' ' == attribs[0] || '\t' == attribs[0] || ';' == attribs[0]) {
			attribs = attribs[1..$];
			continue;
		}
		
		int end = 0;
		for (int i = 0; i < attribs.length; end=++i) {
			char c = attribs[i];
			if (c == ';') break;
		}
		
		char[] part = attribs[0..end];
		attribs = attribs[end..$];
		part = lStrip(rStrip(part));
		
		if (part == item) return true;
	}
	
	return false;
}


char[] attribsGet(char[] attribs, char[] item) {
	while (attribs.length > 0) {
		if (' ' == attribs[0] || '\t' == attribs[0] || ';' == attribs[0]) {
			attribs = attribs[1..$];
			continue;
		}
		
		int end = 0;
		for (int i = 0; i < attribs.length && attribs[i] != ';'; end=++i) {}
		
		char[] part = attribs[0..end];
		attribs = attribs[end..$];
		part = lStrip(rStrip(part));
		
		if (part == item) return "";
		
		if (part.length > item.length && part[0..item.length] == item) {
			int end2 = item.length;
			for (int i = end2; i < part.length; ++i) {
				char c = part[i];
				if (' ' == c || '\t' == c) {
					continue;
				} else if ('=' == c) {
					end2 = i;
					break;
				} else {
					return "";
				}
			}
			if ('=' == part[end2]) {
				return lStrip(part[end2+1..$]);
			} else {
				return "";
			}
		}
	}
	
	return "";
}


template expose_worker(namespace, int expNr = 0) {
	char[] expose(char[] expStr) {
		return _expose!(namespace, expNr)("``", expStr);
	}

	char[] expose(char[] targetTypeName, char[] expStr) {
		return _expose!(namespace, expNr)("`"~targetTypeName~"`", expStr);
	}
}

template expose(namespace, int expNr = 0) {
	alias expose_worker!(namespace, expNr).expose expose;
}


// Thanks, downs!
private char[] ctReplace(char[] source, char[][] pairs) {
	assert((pairs.length%2) == 0, "Parameters to ctReplace must come in pairs. ");
	if (!pairs.length) return source;
	else {
		char[] what = pairs[0], wth = pairs[1];
		int i = 0;
		while (i <= source.length - what.length) {
			if (source[i .. i+what.length] == what) {
				source = source[0 .. i] ~ wth ~ source[i+what.length .. $];
				i += wth.length;
			} else {
				i++;
			}
		}
		return ctReplace(source, pairs[2 .. $]);;
	}
}


private char[] _expose(namespace, int expNr = 0)(char[] targetTypeName, char[] expStr) {
	static if (0 == expNr) {
		char[] result = "mixin(\"static char[] mixf__\"~$fid$~\"() { char[] result = ``;";
	} else {
		char[] result = null;
	}
	
	static if (0 == expNr || is(typeof(mixin(`&namespace.handler!(` ~ expNr.stringof ~ `).begin`)))) {
		result ~= "result ~= $namesp$.handler!($expNr$).begin($targetTypeName$);";
		
		foreach (line; expStr.splitLines()) {
			char[] name, tmpAttribs, attribs;
			splitNameAttribs(line, name, tmpAttribs);
			
			char[] rename = name;
			bool readOnly = false;
			char[] overload = "typeof(&" ~ name ~ ")";
			
			extractInfo(tmpAttribs, attribs, rename, readOnly, overload);
			
			static if (is(typeof(namespace.xposeFieldsOnly))) {
				char[] resPart =
				"result ~= $namesp$.handler!($expNr$).field($targetTypeName$, `$name$`, `$rename$`, $readOnly$, `$attribs$`);";
			} else {
				char[] resPart =
				"static if (is(typeof($name$) == function)) {"
				"	result ~= $namesp$.handler!($expNr$).method($targetTypeName$, `$name$`, `$rename$`, `$overload$`, `$attribs$`);"
				"} else {"
				"	result ~= $namesp$.handler!($expNr$).field($targetTypeName$, `$name$`, `$rename$`, $readOnly$, `$attribs$`);"
				"}";
			}
			result ~= ctReplace(resPart, [
				`$rename$`, rename,
				`$name$`, name,
				`$readOnly$`, (readOnly ? "true" : "false"),
				`$overload$`, overload,
				`$attribs$`, attribs
			]);
		}
		
		result ~= "result ~= $namesp$.handler!($expNr$).end($targetTypeName$);";
		result = ctReplace(result, [
			`$namesp$`, namespace.stringof,
			`$expNr$`, expNr.stringof
		]);
		result ~= _expose!(namespace, expNr+1)(targetTypeName, expStr);
	} else {
		result ~= "return result; } /+pragma(msg, mixf__\"~$fid$~\"());+/ mixin(mixf__\"~$fid$~\"());\");";
	}
	
	return ctReplace(result, [
		`$targetTypeName$`, targetTypeName,
		`$fid$`, `__LINE__.stringof`
	]);
}
