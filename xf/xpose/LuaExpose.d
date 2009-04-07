module xf.xpose.LuaExpose;

private {
	import dlua.all;
	version (Tango) {
		import tango.stdc.string : strlen;
		
		public char* toStringz(char[] s) { return (s ~ \0).ptr; }
		char[] toString(char* s) { return s is null ? null : s[0..strlen(s)]; }
		
		import tango.core.Memory : gc = GC;
		public void gc_addRoot(void* p) { gc.addRoot(p); }
		public void gc_removeRoot(void* p) { gc.removeRoot(p); }		
	} else {
		import std.string : toStringz, toString;
		public import std.gc : gc_addRoot = addRoot, gc_removeRoot = removeRoot;
	}
}

public import xf.xpose.Utils;



int registerDClassesWithLua(lua_State* L) {
	foreach (fn, dummy_; registeredDClassesForLua) {
		fn(L);
	}
	return registeredDClassesForLua.keys.length;
}


void registerDClassForLua_(T)() {
	registeredDClassesForLua[&T.initLuaReflection] = true;
}


private {
	bool[void function(lua_State*)] registeredDClassesForLua;
}



public import dlua.all;

struct LuaDUserData {
	Object	obj;
}


T luaToDObject(T)(lua_State* L, int index) {
	auto userdata = cast(LuaDUserData*)lua_touserdata(L, index);
	if (userdata is null) luaL_typerror(L, index, toStringz(shortNameOf!(T)));
	return cast(T)userdata.obj;
}


T checkDObject(T)(lua_State* L, int index) {
	luaL_checktype(L, index, LUA_TUSERDATA);

	char* className = toStringz(shortNameOf!(T));
	auto userdata = cast(LuaDUserData*)luaL_checkudata(L, index, className);
	if (userdata is null) luaL_typerror(L, index, className);
	
	T res = cast(T)userdata.obj;
	if (res is null) luaL_error(L, toStringz("null " ~ shortNameOf!(T)));
	return res;
}


T pushDObject(T)(lua_State* L, T t) {
	assert (t !is null);
	auto userdata = cast(LuaDUserData*)lua_newuserdata(L, LuaDUserData.sizeof);
	gc_addRoot(userdata);	// TODO: not sure if it should go here
	userdata.obj = t;
	luaL_getmetatable(L, toStringz(shortNameOf!(T)));
	lua_setmetatable(L, -2);
	return t;
}


T evalLuaArg(T)(lua_State* L, int index) {
	static if (is(T == float) || is(T == double) || is (T == real)) {
		return cast(T)luaL_checknumber(L, index);
	}
	else static if (is(T == int) || is(T == uint) || is(T == short) || is(T == ushort) || is(T == byte) || is(T == ubyte) || is(T == long) || is(T == ulong)) {
		return cast(T)luaL_checkinteger(L, index);
	}
	else static if (is(T == char[])) {
		return .toString(luaL_checkstring(L, index));
	}
	else static if (is(T == char*)) {
		return luaL_checkstring(L, index);
	}
	else static assert (false, "other types not supported atm: " ~ T.mangleof);
}


void pushLuaArg(T)(lua_State* L, T t) {
	static if (is(T == float) || is(T == double) || is (T == real)) {
		lua_pushnumber(L, cast(lua_Number)t);
	}
	else static if (is(T == int) || is(T == uint) || is(T == short) || is(T == ushort) || is(T == byte) || is(T == ubyte) || is(T == long) || is(T == ulong)) {
		lua_pushinteger(L, cast(lua_Integer)t);
	}
	else static if (is(T == char[])) {
		lua_pushlstring(L, t.ptr, t.length);
	}
	else static if (is(T == char*)) {
		lua_pushstring(L, t.ptr);
	}
	else static if (is(T : Object)) {
		pushDObject!(T)(L, t);
	}
	else static assert (false, "other types not supported atm: " ~ T.mangleof);
}


template canLuaHandleDType(T) {
	const bool canLuaHandleDType = 
					is(T == float) || is(T == double) || is (T == real)
				||	is(T == int) || is(T == uint) || is(T == short) || is(T == ushort) || is(T == byte) || is(T == ubyte) || is(T == long) || is(T == ulong)
				||	is(T == char[])
				||	is(T == char*);
}



template LuaExposeLowLevel_mix() {
	static char[] begin() {
		return ``;
	}
	static char[] end() {
		return ``;
	}
	static char[] method(char[] name, char[] rename, char[] overload, char[] attribs) {
		return
		`extern(C) static int LuaMeth_`~rename~`(lua_State* L) {
			typeof(this) self = checkDObject!(typeof(this))(L, 1);
			assert (self !is null, "dlua obj is null");
			
			ParameterTypeTuple!(`~overload~`) params;
			foreach (i, dummy_; params) params[i] = evalLuaArg!(typeof(dummy_))(L, i+2);

			static if(is(ReturnType!(`~overload~`) == void)) {
				self.`~name~`(params);
				return 0;
			} else {
				pushLuaArg(L, self.`~name~`(params));
				return 1;
			}
		}`;
	}
	static char[] field(char[] name, char[] rename, bool readOnly, char[] attribs) {
		return
		`static if (canLuaHandleDType!(typeof(typeof(this).init.`~name~`))) {
			extern(C) static int LuaMeth_get`~capitalize(rename)~`(lua_State* L) {
				typeof(this) self = checkDObject!(typeof(this))(L, 1);
				assert (self !is null, "dlua obj is null");
				pushLuaArg(L, self.`~name~`);
				return 1;
			}
		`
		~ (readOnly ? `}` :
		`	extern(C) static int LuaMeth_set`~capitalize(rename)~`(lua_State* L) {
				typeof(this) self = checkDObject!(typeof(this))(L, 1);
				assert (self !is null, "dlua obj is null");
				self.`~name~` = evalLuaArg!(typeof(self.`~name~`))(L, 2);
				return 0;
			}
		}`);
	}
}


template LuaExposeHighLevel_mix() {
	static char[] begin() {
		return `
			static if (is(typeof(this) == class)) {
				private template DLuaInitializerMix() {
					static this() {
						xf.xpose.LuaExpose.registerDClassForLua_!(typeof(this));
					}
				}
				mixin DLuaInitializerMix;

				extern (C) static int LuaDObject_new(lua_State* L) {
					pushDObject(L, new typeof(this));
					return 1;
				}

				extern (C) static int luaDObject_destroy(lua_State* L) {
					auto ptr = lua_touserdata(L, 1);
					gc_removeRoot(ptr);		// TODO: not sure if this is ok
					return 0;
				}

				private static luaL_reg[] luaMetaMethods_ = [
					{"__gc", &luaDObject_destroy },
					{null, null}
				];
				
				private static luaL_reg[] luaClassMethods_ = [
					{"new", &LuaDObject_new}
				];
			} else {
				private static luaL_reg[] luaMetaMethods_ = [
					{null, null}
				];
				
				private static luaL_reg[] luaClassMethods_ = [
				];
			}
			

			static void initLuaReflection(lua_State *L) {
				static bool luaReflInitDone_ = false;
				if (luaReflInitDone_) return;
				luaReflInitDone_ = true;
				
		`;
	}
	static char[] end() {
		return `
				luaClassMethods_ ~= luaL_reg(null, null);
			
				char* className = toStringz(shortNameOf!(typeof(this)));
				luaL_register(L, className, luaClassMethods_.ptr);
				int methods = lua_gettop(L);
				
				luaL_newmetatable(L, className);
				luaL_register(L, null, luaMetaMethods_.ptr);
				int metatable = lua_gettop(L);

				lua_pushliteral(L, "__metatable");
				lua_pushvalue(L, metatable);
				lua_rawset(L, methods);
				lua_pushliteral(L, "__index");
				lua_pushvalue(L, methods);
				lua_rawset(L, metatable);
				lua_pop(L, 1);	// remove meta table
				lua_pop(L, 1);	// remove methods
			}`;
	}
	static char[] method(char[] name, char[] rename, char[] overload, char[] attribs) {
		return `{ luaClassMethods_ ~= luaL_reg("`~rename~`", &LuaMeth_`~rename~`); }`;
	}
	static char[] field(char[] name, char[] rename, bool readOnly, char[] attribs) {
		return
		`static if (is(typeof(this.LuaMeth_get`~capitalize(rename)~`))) {
			luaClassMethods_ ~= luaL_reg("get`~capitalize(rename)~`", &LuaMeth_get`~capitalize(rename)~`);`
			~ (readOnly ? `}` :
			`luaClassMethods_ ~= luaL_reg("set`~capitalize(rename)~`", &LuaMeth_set`~capitalize(rename)~`);
		}`);
	}
}



struct LuaExpose {
	template handler(int i : 0) {
		mixin LuaExposeHighLevel_mix;
	}

	template handler(int i : 1) {
		mixin LuaExposeLowLevel_mix;
	}
	
	mixin HandlerStructMix;
}
