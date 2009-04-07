module xf.xpose.IoExpose;

public import dio.dio;
public import xf.xpose.Utils;



int registerDClassesWithIo(Dio dio) {
	foreach (fn, dummy_; registeredDClassesForIo) {
		dioInit(dio, fn);
	}
	return registeredDClassesForIo.keys.length;
}


void registerDClassForIo_(T)() {
	registeredDClassesForIo[&T.initIoReflection] = true;
}


private {
	bool[void function(IoState)] registeredDClassesForIo;
}



template IoExposeLowLevel_mix() {
	static char[] begin() {
		return ``;
	};
	static char[] end() {
		return ``;
	}
	static char[] method(char[] name, char[] rename, char[] overload, char[] attribs) {
		return
		`extern(C) static IoObject IoMeth_`~rename~`(IoObject self, IoObject l, IoMessage m) {
			Dio dio = Dio.dio(self);
			auto dobj = dio.dObject(self);
			if (dobj is null) throw new Exception("io prop setter: null obj");
			typeof(this) o = cast(typeof(this))(dobj);
			if (o is null) throw new Exception("io meth caller: invalid obj");
			ParameterTypeTuple!(`~overload~`) params;
			foreach (i, dummy_; params) params[i] = dio.dtype!(typeof(dummy_))(dio.evalArg(m, l, i));

			static if(is(ReturnType!(`~overload~`) == void)) {
				o.`~name~`(params);
				return self;
			} else {
				return dio.iotype(o.`~name~`(params));
			}
		}`;
	}
	static char[] field(char[] name, char[] rename, bool readOnly, char[] attribs) {
		return
		`static if (is(typeof(Dio.init.iotype(typeof(this).init.`~name~`)))) {
			extern(C) static IoObject IoMeth_get`~capitalize(rename)~`(IoObject self, IoObject l, IoMessage m) {
				Dio dio = Dio.dio(self);
				auto dobj = dio.dObject(self);
				if (dobj is null) throw new Exception("io prop setter: null obj");
				typeof(this) o = cast(typeof(this))(dobj);
				if (o is null) throw new Exception("io prop getter: invalid obj");
				return dio.iotype(o.`~name~`);
			}`
			~ (readOnly ? `}` :
			`extern(C) static IoObject IoMeth_set`~capitalize(rename)~`(IoObject self, IoObject l, IoMessage m) {
				Dio dio = Dio.dio(self);
				auto dobj = dio.dObject(self);
				if (dobj is null) throw new Exception("io prop setter: null obj");
				typeof(this) o = cast(typeof(this))(dobj);
				if (o is null) throw new Exception("io prop setter: invalid obj");
				o.`~name~` = dio.dtype!(typeof(o.`~name~`))(dio.evalArg(m, l, 0));
				return self;
			}
		}`);
	}
}


template IoExposeHighLevel_mix() {
	static char[] begin() {
		return
		`static if (is(typeof(this) == class)) {
			private template DIoInitializerMix() {
				static this() {
					xf.xpose.IoExpose.registerDClassForIo_!(typeof(this));
				}
			}
			mixin DIoInitializerMix;

			static void initIoReflection(IoState s) {
				//printf("Initializing Io reflection for class %.*s"\n, shortNameOf!(typeof(this)));
				Dio dio = Dio.dio(s);
				dio.proto("Dio", shortNameOf!(typeof(this)), &initIoProto);
			}

			extern(C) static IoObject IoCloneFunc(IoObject self) {
				Dio dio = Dio.dio(self);
				IoObject c = Dioc_rawClone(self);
				dio.dObject(c, new typeof(this));
				return c;
			}
			
			extern(C) static IoObject initIoProto(IoState s) {
				Dio dio = Dio.dio(s);
				IoObject self = dio.object();
				dio.tag(self, shortNameOf!(typeof(this)));
				//dio.dObject(self, new typeof(this));
				dio.tagCloneFunc(self, &IoCloneFunc);
		`;
	};
	static char[] end() {
		return `return self; }}`\n;
	}
	static char[] method(char[] name, char[] rename, char[] overload, char[] attribs) {
		return `dio.method(self, "`~rename~`", &IoMeth_`~rename~`);`;
	}
	static char[] field(char[] name, char[] rename, bool readOnly, char[] attribs) {
		return
		`static if (is(typeof(this.IoMeth_get`~capitalize(rename)~`))) {
			dio.method(self, "get`~capitalize(rename)~`", &IoMeth_get`~capitalize(rename)~`);`
			~ (readOnly ? `}` :
			`dio.method(self, "set`~capitalize(rename)~`", &IoMeth_set`~capitalize(rename)~`);
		}`);
	}
}



struct IoExpose {
	template handler(int i : 0) {
		mixin IoExposeHighLevel_mix;
	}


	template handler(int i : 1) {
		mixin IoExposeLowLevel_mix;
	}
	
	mixin HandlerStructMix;
}
