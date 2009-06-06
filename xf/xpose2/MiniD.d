module xf.xpose2.MiniD;

public {
	import minid.api;
	import minid.ex;
	import minid.bind;
	import tango.core.Traits;
	
	import tango.io.Stdout;
}



void checkInitialized(MDThread* t)
{
	getRegistry(t);
	pushString(t, "minid.bind.initialized");

	if(!opin(t, -1, -2))
	{
		newTable(t);       fielda(t, -3, "minid.bind.WrappedClasses");
		newTable(t);       fielda(t, -3, "minid.bind.WrappedInstances");
		pushBool(t, true); fielda(t, -3);
		pop(t);
	}
	else
		pop(t, 2);
}



void function(MDThread* t)[] xposeMiniD_classInit;

void xposeMiniD_initAll(MDThread* t) {
	foreach (func; xposeMiniD_classInit) {
		func(t);
	}
}


template MiniDWrapperCommon(bool allowSubclassing) {
	mixin(wrapperCodegen!(allowSubclassing)());
	
	static if (is(_Target == struct)) {
		alias checkStructSelf checkStructClassSelf;
	} else {
		alias checkClassSelf checkStructClassSelf;
	}

	
	private static char[] opFieldCodegen(char[] exclusionStr)(char[] action) {
		char[] res = "";
		
		static if (is(xposeFields)) foreach (field; xposeFields) {{
			static if (is(typeof(field.attribs.md))) {
				const attribs = field.attribs.md;
			} else {
				alias void attribs;
			}
			
			static if (!is(attribs.skip)) {
				static if (field.isData) {
					mixin(`const bool exclude = is(attribs.`~exclusionStr~`);`);
					static if (!exclude) {
						const char[] name = field.name;
						const char[] targetName = target~'.'~name;
						res ~= `case "`~field.name~`":`~ctReplace(action, [`$name$`, name])~";break;";
					}
				}
			}
		}}
		
		return res;
	}


	private static uword _minid_constructor(MDThread* t, uword numParams) {
		checkInstParam(t, 0, target);
		
		static if (is(xposeFields)) foreach (fieldI, field; xposeFields) {{
			static if (is(typeof(field.attribs.md))) {
				const attribs = field.attribs.md;
			} else {
				alias void attribs;
			}
			
			const char[] name = field.name;
			const char[] targetName = target~'.'~name;

			static if (!is(attribs.skip) && (field.isCtor || is(attribs.ctor))) {
				if (numParams == field.paramTypes.length) {
					field.paramTypes ctorArgs;
					foreach (i, arg; ctorArgs) {
						if (canCastTo!(typeof(arg))(t, i + 1)) {
							ctorArgs[i] = superGet!(typeof(arg))(t, i + 1);
						} else {
							mixin("goto failCtorFromField" ~ fieldI.stringof ~ ";");
						}
					}

					static if (allowSubclassing) {
						auto obj = new typeof(this)(getVM(t), ctorArgs);
					} else {
						static if (!field.isCtor) {		// static func marked as a ctor
							static assert (field.isFunction && field.isStatic);
							static if (is(_Target == struct)) {
								mixin(`auto obj = new StructWrapper!(_Target)(`~target~'.'~name~`(ctorArgs));`);
							} else {
								mixin(`auto obj = `~target~'.'~name~`(ctorArgs);`);
							}
						} else {
							static if (is(_Target == struct)) {
								auto obj = new StructWrapper!(_Target)(_Target(ctorArgs));
							} else {
								auto obj = new _Target(ctorArgs);
							}
						}
					}
					
					pushNativeObj(t, obj);
					setExtraVal(t, 0, 0);
					static if (!is(_Target == struct)) {
						setWrappedInstance(t, obj, 0);
					}
					return 0;
				}
				
				mixin("failCtorFromField" ~ fieldI.stringof ~ ":{}");
			}
		}}
		
		static if (is(typeof(new typeof(this)(getVM(t))))) {
			if (0 == numParams) {
				static if (allowSubclassing) {
					auto obj = new typeof(this)(getVM(t));
				} else {
					static if (is(_Target == struct)) {
						auto obj = new StructWrapper!(_Target)(_Target());
					} else {
						auto obj = new _Target();
					}
				}
				
				pushNativeObj(t, obj);
				setExtraVal(t, 0, 0);
				static if (!is(_Target == struct)) {
					setWrappedInstance(t, obj, 0);
				}
				return 0;
			}
		}		
		
		auto buf = StrBuffer(t);
		buf.addChar('(');
		if (numParams > 0) {
			pushTypeString(t, 1);
			buf.addTop();

			for (uword i = 2; i <= numParams; i++) {
				buf.addString(", ");
				pushTypeString(t, i);
				buf.addTop();
			}
		}

		buf.addChar(')');
		buf.finish();
		throwException(t, "Parameter list {} passed to constructor does not match any wrapped constructors", getString(t, -1));
		return 0;
	}
	
	
	static if (allowSubclassing) {
		private static char[] ctorShimCodegen() {
			char[] res = "";
			static if (is(xposeFields)) foreach (field; xposeFields) {{
				static if (is(typeof(field.attribs.md))) {
					const attribs = field.attribs.md;
				} else {
					alias void attribs;
				}
				
				const char[] name = field.name;
				const char[] targetName = target~'.'~name;

				static if (!is(attribs.skip) && field.isCtor) {
					static if (0 == field.paramTypes.length) {
						res ~=
						`this(MDVM* vm) {
							_mdvm_ = vm;
							static if(is(typeof(&`~target~`._ctor))) {
								super();
							}
						}`;
					} else {
						static if (is(field.attribs.overload)) {
							const char[] overloadTypeName = field.attribs.overload.typeName;
							res ~=
							`this(MDVM* vm, ParameterTupleOf!(`~overloadTypeName~`) args) {
								_mdvm_ = vm;
								static if(is(typeof(&`~target~`._ctor))) {
									super(args);
								}
							}`;
						} else {
							res ~=
							`this(MDVM* vm, ParameterTupleOf!(`~target~`._ctor) args) {
								_mdvm_ = vm;
								static if(is(typeof(&`~target~`._ctor))) {
									super(args);
								}
							}`;
						}
					}
				}
			}}
			
			return res;
		}
		mixin(ctorShimCodegen());


		private static char[] funcOverridesCodegen() {
			char[] res = "";
			
			static if (is(xposeFields)) foreach (field; xposeFields) {{
				static if (is(typeof(field.attribs.md))) {
					const attribs = field.attribs.md;
				} else {
					alias void attribs;
				}
				
				const char[] name = field.name;
				const char[] targetName = target~'.'~name;

				static if (!is(attribs.skip) && field.isFunction) {
					static if (is(field.attribs.overload)) {
						const char[] overloadTypeName = field.attribs.overload.typeName;
					} else {
						const char[] overloadTypeName = targetName;
						/+res ~=
						`private ReturnTypeOf!(`~targetName~`) `~name~`__super(ParameterTupleOf!(`~targetName~`) args) {
							return super.`~name~`(args);
						}
						override ReturnTypeOf!(`~targetName~`) `~name~`(ParameterTupleOf!(`~targetName~`) args) {`;+/
					}

					res ~=
					`private ReturnTypeOf!(`~overloadTypeName~`) `~name~`__super(ParameterTupleOf!(`~overloadTypeName~`) args) {
						return super.`~name~`(args);
					}
					override ReturnTypeOf!(`~overloadTypeName~`) `~name~`(ParameterTupleOf!(`~overloadTypeName~`) args) {`;

					static if (is(attribs.rename)) {
						const char[] mdname = attribs.rename.value;
					} else {
						const char[] mdname = name;
					}
					
					res ~=
					`if (auto t = _haveMDOverload_("`~mdname~`")) {
						// instance is on top
						auto reg = stackSize(t) - 1;
						pushNull(t);
						foreach (arg; args) {
							superPush(t, arg);
						}
						
						alias ReturnTypeOf!(`~overloadTypeName~`) ReturnType;
						static if (is(ReturnType == void)) {
							methodCall(t, reg, "`~mdname~`", 0);
						} else {
							methodCall(t, reg, "`~mdname~`", 1);
							auto ret = superGet!(ReturnType)(t, -1);
							pop(t);
							return ret;
						}
					} else {
						return super.`~name~`(args);
					}
				}`;
				}
			}}
			
			return res;
		}
	
		private MDVM* _mdvm_;
		
		mixin(funcOverridesCodegen());
	}


	static uword _minid_opField(MDThread* t, uword numParams) {
		auto _this = checkStructClassSelf!(_Target, target)(t);
		auto fieldName = checkStringParam(t, 1);
		mixin(`
		switch (fieldName) {
			` ~
			opFieldCodegen!("writeOnly")("superPush(t, _this.$name$)") ~ `
			default:
				static if (is(typeof(SuperWrapClassType._minid_opField(t, numParams)))) {
					return SuperWrapClassType._minid_opField(t, numParams);
				}
				throwException(t, "No field " ~ fieldName ~ " in " ~ target);
		}`);
		return 1;
	}


	static uword _minid_opFieldAssign(MDThread* t, uword numParams) {
		auto _this = checkStructClassSelf!(_Target, target)(t);
		auto fieldName = checkStringParam(t, 1);
		mixin(`
		switch (fieldName) {
			` ~
			opFieldCodegen!("readOnly")("_this.$name$ = superGet!(typeof(_this.$name$))(t, 2)") ~ `
			default:
				static if (is(typeof(SuperWrapClassType._minid_opFieldAssign(t, numParams)))) {
					return SuperWrapClassType._minid_opFieldAssign(t, numParams);
				}
				throwException(t, "No field " ~ fieldName ~ " in " ~ target);
		}`);
		return 0;
	}
	
	
	static void _minid_classInitFuncs(MDThread* t) {
		static if (is(xposeFields)) foreach (field; xposeFields) {{
			static if (is(typeof(field.attribs.md))) {
				const attribs = field.attribs.md;
			} else {
				alias void attribs;
			}
			
			static if (!is(attribs.skip)) {
				static if (is(attribs.rename)) {
					const char[] name = attribs.rename.value;
				} else {
					const char[] name = field.name;
				}

				static if (field.isData) {
					static if (mixin(`!is(typeof( `~target~`.init.`~name~`.offsetof))`)) {		// is it static?
						static if (!is(attribs.writeOnly)) {
							mixin(`newFunction(t, &_minid_`~name~`, "`~name~`");`);
							fielda(t, -2, name);
						}
						
						static if (!is(attribs.readOnly)) {
							const char[] frename = renameStaticFieldSetter(name);
							mixin(`newFunction(t, &_minid_`~frename~`, "`~frename~`");`);
							fielda(t, -2, frename);
						}
					}
				} else static if (field.isFunction) {
					mixin(`newFunction(t, &_minid_`~name~`, "`~name~`");`);
					fielda(t, -2, name);
				}
			}
		}}
		
		static if (is(typeof(SuperWrapClassType._minid_classInitFuncs(t)))) {
			SuperWrapClassType._minid_classInitFuncs(t);
		}
	}


	static bool _minid_classInit_done = false;
	static void _minid_classInit(MDThread* t) {
		if (_minid_classInit_done) {
			return;
		} else {
			_minid_classInit_done = true;
		}
		
		int initialStackSize = stackSize(t);
		
		Stdout.formatln("_minid_classInit for {}", target);
		
		checkInitialized(t);

		// Check if this type has already been wrapped
		getWrappedClass(t, typeid(_Target));

		if (!isNull(t, -1)) {
			throwException(t, "Native type " ~ target ~ " cannot be wrapped more than once");
		}

		pop(t);

		static if (is(_Target == class) || (is(_Target == interface) && BaseTypeTupleOf!(_Target).length > 0)) {
			alias BaseTypeTupleOf!(_Target) BaseTypeTuple;
			static if (is(BaseTypeTuple[0] == Object)) {
				static if (BaseTypeTuple.length > 1) {
					alias BaseTypeTuple[1] BaseClass;
				} else {
					alias void BaseClass;
				}
			} else {
				alias BaseTypeTuple[0] BaseClass;
			}
		} else {
			alias void BaseClass;
		}

		static if (!is(BaseClass == void)) {
			static if (is(typeof(BaseClass._minid_classInit(t)))) {
				BaseClass._minid_classInit(t);
			}

			static if (is(BaseClass == class)) {
				auto base = getWrappedClass(t, BaseClass.classinfo);
			} else static if (is(BaseClass == interface)) {
				auto base = getWrappedClass(t, typeid(BaseClass));
			} else static assert (false, "wtf: " ~ BaseClass.stringof);
		} else {
			auto base = pushNull(t);
		}

		char[] _classname_ = target;
		newClass(t, base, _classname_);
		
		_minid_classInitFuncs(t);

		// Set the allocator
		newFunction(t, &_minid_classAllocator, target ~ ".allocator");
		setAllocator(t, -2);

		newFunction(t, &_minid_opField, target ~ ".opField");
		fielda(t, -2, "opField");

		newFunction(t, &_minid_opFieldAssign, target ~ ".opField");
		fielda(t, -2, "opFieldAssign");

		newFunction(t, &_minid_constructor, target ~ ".constructor");
		fielda(t, -2, "constructor");

		// Set the class
		setWrappedClass(t, typeid(_Target));
		static if (!is(_Target == struct)) {
			setWrappedClass(t, _Target.classinfo);
		}
		newGlobal(t, _classname_);
		
		int toCleanup = stackSize(t) - initialStackSize;
		pop(t, toCleanup);
	}


	static this() {
		xposeMiniD_classInit ~= &_minid_classInit;
	}


	private static uword _minid_classAllocator(MDThread* t, uword numParams) {
		newInstance(t, 0, 1);

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}
}


template xposeMiniD(char[] target_ = "") {
	mixin xposeMiniD_worker!(target_, true);
}


template xposeMiniDNoSubclass(char[] target_ = "") {
	mixin xposeMiniD_worker!(target_, false);
}


private char[] capitalizeFirst(char[] str) {
	assert (str.length > 0);
	if (str[0] >= 'a' && str[0] <= 'z') {
		return cast(char)(str[0] + 'A' - 'a') ~ str[1..$];
	} else {
		return str;
	}
}


private char[] renameStaticFieldSetter(char[] name) {
	return "set" ~ capitalizeFirst(name);
}


template xposeMiniD_worker(char[] target_, bool allowSubclassing) {
	static if (target_ == "") {
		static if (is(typeof(*this) == struct)) {
			private const char[] target = typeof(*this).stringof;
		} else {
			private const char[] target = typeof(this).stringof;
		}
	} else {
		private const char[] target = target_;
	}
	mixin("private alias " ~ target ~ " _Target;");
	
	static if ((is(_Target == class) || is(_Target == interface)) && (is(typeof(this) == class) || is(typeof(this) == interface))) {
		alias BaseTypeTupleOf!(typeof(this))[0] SuperWrapClassType;
	}


	private static char[] wrapperCodegen(bool allowSubclassing)() {
		char[] res = "";
		static if (is(xposeFields)) foreach (field; xposeFields) {{
			static if (is(typeof(field.attribs.md))) {
				const attribs = field.attribs.md;
			} else {
				alias void attribs;
			}
			
			const char[] name = field.name;
			const char[] targetName = target~'.'~name;

			static if (!is(attribs.skip)) {
				static if (is(attribs.rename)) {
					const char[] rename = attribs.rename.value;
				} else {
					const char[] rename = name;
				}
				
				static if (field.isData) {
					static if (mixin(`!is(typeof( `~target~`.init.`~name~`.offsetof))`)) {		// is it static?
						static if (!is(attribs.writeOnly)) {
							res ~= `
							static uword _minid_`~rename~`(MDThread* t, uword numParams) {
								superPush(
									t,
									`~targetName~`
								);
								return 1;
							}`;
						}
						
						static if (!is(attribs.readOnly)) {
							res ~= `
							static uword _minid_`~renameStaticFieldSetter(rename)~`(MDThread* t, uword numParams) {
								`~targetName~` = superGet!(typeof(`~targetName~`))(t, 1);
								return 0;
							}`;
						}
					}
				} else static if (field.isFunction) {
					static if (field.isStatic) {
						static if (is(field.attribs.overload)) {
							const char[] ovt = field.attribs.overload.typeName;
							const char[] paramTypes = `ParameterTupleOf!(`~ovt~`)`;
							const char[] returnType = `ReturnTypeOf!(`~ovt~`)`;
						} else {
							const char[] paramTypes = `ParameterTupleOf!(`~targetName~`)`;
							const char[] returnType =  `ReturnTypeOf!(`~targetName~`)`;
						}

						const char[] theCall = target~'.'~name~`(args)`;
					} else {
						static if (allowSubclassing) {
							const char[] callTarget = name ~ "__super";
						} else {
							const char[] callTarget = name;
						}

						static if (is(field.attribs.overload)) {
							const char[] ovt = field.attribs.overload.typeName;
							const char[] paramTypes = `ParameterTupleOf!(`~ovt~`)`;
							const char[] theCall = `(cast(ReturnTypeOf!(`~ovt~`) delegate(`~paramTypes~`))&_this.`~callTarget~`)(args)`;
							const char[] returnType = `ReturnTypeOf!(`~ovt~`)`;
						} else {
							const char[] paramTypes = `ParameterTupleOf!(`~targetName~`)`;
							const char[] returnType =  `ReturnTypeOf!(`~targetName~`)`;
							const char[] theCall = "_this."~callTarget~`(args)`;
						}
					}
					
					res ~= `
						static uword _minid_`~rename~`(MDThread* t, uword numParams) {`;
							static if (!field.isStatic) {
								static if (allowSubclassing) {
									res ~=
									`static assert (is(typeof(this) == class));
									static assert (is(`~target~` == class));
									auto _this = cast(typeof(this))cast(void*)checkStructClassSelf!(`~target~`, "`~target~`")(t);`;
								} else {
									res ~= `auto _this = checkStructClassSelf!(`~target~`, "`~target~`")(t);`;
								}
							}
							
							res ~= paramTypes~` args;
							foreach (i, _dummy; args) {
								const int argNum = i + 1;
								if (i < numParams) {
									args[i] = superGet!(typeof(args[i]))(t, argNum);
								}
							}
							
							static if (is(`~returnType~` == void)) {
								`~theCall~`;
								return 0;
							}
							else {
								superPush(
									t,
									`~theCall~`
								);
								return 1;
							}
					`;
					res ~= `
						}`;
				} else {
				}
			}
		}}
		return res;
	}
	
	
	static if (target_ == "") {
		mixin MiniDWrapperCommon!(false);
	} else {
		static if (is(_Target == struct) || !allowSubclassing) {
			mixin MiniDWrapperCommon!(false);
		} else {
			//class MiniDWrapper : _Target {
				MDThread* _haveMDOverload_(char[] methodName) {
					if (_mdvm_ is null) {
						return null;
					}
					
					auto t = currentThread(_mdvm_);

					getRegistryVar(t, "minid.bind.WrappedInstances");
					pushNativeObj(t, this);
					idx(t, -2);
					deref(t, -1);

					if(isNull(t, -1)) {
						pop(t, 3);
						return null;
					} else {
						superOf(t, -1);
						field(t, -1, methodName);

						if (funcIsNative(t, -1)) {
							pop(t, 5);
							return null;
						} else {
							pop(t, 2);
							insertAndPop(t, -3);
							return t;
						}
					}
				}

				mixin MiniDWrapperCommon!(true);
			//}
		}
	}
}
