module xf.xpose2.Serialization;

private {
	import xf.xpose2.Expose;
	
	version (Tango) import tango.io.Stdout : Stdout;
	import tango.core.Traits;
	//import std.string : format;
}

public alias xf.xpose2.Expose.xpose2 xpose2;

public alias tango.core.Traits.isStaticArrayType isStaticArrayType;



// serializeFunc and unserializeFunc get called after all fields of the object have been (un)serialized
// they should be static functions having the signature void f(T* obj, Serializer/Unserializer s)
template xposeSerialization(char[] target_ = "", char[] serializeFunc = "", char[] unserializeFunc = "") {
	private import xf.xpose2.Serialization; // workaround for dmdfe bug

	static if (target_ == "") {
		static if (is(typeof(*this) == struct)) {
			const char[] target = typeof(*this).stringof;
		} else {
			const char[] target = typeof(this).stringof;
		}
	} else {
		const char[] target = target_;
	}
	
	static ClassMetaInfo serializationMetaInfo;
	
	ClassMetaInfo getSerializationMetaInfo() {
		return serializationMetaInfo;
	}
	
	static int function(Serializer, void*, int) getSerializationFunction() {
		return &serializerDescribe!(Serializer);
	}
	
	static int function(Unserializer, void*, int) getUnserializationFunction() {
		return &serializerDescribe!(Unserializer);
	}
	
	static if (is(typeof(this) == class)) {
		alias typeof(super) TypeOfSuper;
	}

	protected static void serializationGatherFieldInfo(inout ClassMetaInfo serializationMetaInfo) {
		static if (is(TypeOfSuper)) {
			static if (is(typeof(TypeOfSuper.serializationGatherFieldInfo(serializationMetaInfo)))) {
				if (&serializationGatherFieldInfo !is &TypeOfSuper.serializationGatherFieldInfo) {
					TypeOfSuper.serializationGatherFieldInfo(serializationMetaInfo);
				}
			}
		}
		
		mixin(`alias `~("" == target ? `UnrefType!(typeof(this))` : target)~` TargetType;`);

		// workaround for dmdfe bug
		static if (is(typeof(*this) == struct)) {
			alias typeof(*this) ThisT;
		} else {
			alias typeof(this) ThisT;
		}
		
		with (serializationMetaInfo) {
			static if (is(ThisT.xposeFields)) foreach (field; ThisT.xposeFields) {{
				static if (field.isData) {
					static if (is(typeof(field.attribs.serial))) {
						const attribs = field.attribs.serial;
					} else {
						alias void attribs;
					}
					
					static if (!is(attribs.skip)) {
						const char[] writeFunc = mixin(is(attribs.write) ? `attribs.write.value` : `""`);
						const char[] readFunc = mixin(is(attribs.read) ? `attribs.read.value` : `""`);
						const char[] rename = mixin(is(attribs.rename) ? `attribs.rename.value` : `field.name`);
						
						//pragma (msg, rename);

						static assert (
							!((writeFunc.length == 0) ^ (readFunc.length == 0)),
							"must have both custom read and write funcs for '"~name~"'"
						);
								
						mixin(ctReplace(`
						static if (writeFunc.length > 0) {
							static if (is(typeof($name$))) {
								fields ~= FieldMetaInfo(rename, typeid(typeof($name$)).toString, 0, FieldMetaInfo.TypeId_Other);
							} else {
								fields ~= FieldMetaInfo(rename, "", 0, FieldMetaInfo.TypeId_Other);
							}
						} else static if (isBasicType!(typeof($name$))) {
							fields ~= FieldMetaInfo(rename, typeid(typeof($name$)).toString, $name$.sizeof, FieldMetaInfo.TypeId_Primitive);
						} else {
							static if (is(typeof($name$) == class)) {
								fields ~= FieldMetaInfo(rename, typeid(typeof($name$)).toString, 0, FieldMetaInfo.TypeId_Class);
							} else static if (is(typeof($name$) == struct)) {
								fields ~= FieldMetaInfo(rename, typeid(typeof($name$)).toString, 0, FieldMetaInfo.TypeId_Struct);
							} else {
								fields ~= FieldMetaInfo(rename, typeid(typeof($name$)).toString, 0, FieldMetaInfo.TypeId_Other);
							}
						}`, [`$name$`, "TargetType.init." ~ field.name]));
					} /+else {
						pragma (msg, "serializer: skipping field " ~ field.name);
					}+/
				}
			}}
		}
	}


	static this() {
		mixin(`alias `~("" == target ? `UnrefType!(typeof(this))` : target)~` TargetType;`);
		serializationMetaInfo.className = TargetType.mangleof;
		serializationGatherFieldInfo(serializationMetaInfo);
		SerializationRegistry().register!(TargetType, UnrefType!(typeof(this)))(serializationMetaInfo.className);
	}


	static int serializerDescribe(Serializer)(Serializer serializer_, void* _this, int fieldOffset = 0) {
		static if (is(typeof(this) == class)) {
			static if (is(typeof(TypeOfSuper.serializerDescribe(serializer_, _this)))) {
				//pragma (msg, typeof(this).stringof ~ " : " ~ TypeOfSuper.stringof);
				int fieldsInSuper = TypeOfSuper.serializerDescribe(serializer_, _this);
				//Stdout.formatln("{} : {} :: fields in super: {}", typeof(this).stringof, TypeOfSuper.stringof, fieldsInSuper);
				fieldOffset += fieldsInSuper;
			}
		}
		
		int serializationFieldCounter = fieldOffset;
		
		// workaround for dmdfe bug
		static if (is(typeof(*this) == struct)) {
			alias typeof(*this) ThisT;
		} else {
			alias typeof(this) ThisT;
		}
		
		static if (is(ThisT.xposeFields)) foreach (field; ThisT.xposeFields) {{
			static if (field.isData) {
				static if (is(typeof(field.attribs.serial))) {
					const attribs = field.attribs.serial;
				} else {
					alias void attribs;
				}
				
				static if (!is(attribs.skip)) {
					const char[] prefix = "" == target ? "(cast(typeof(this))_this)." : `(cast(RefType!(`~target~`))_this).`;
					const char[] customPrefix1 = "" == target ? "(cast(typeof(this))_this)." : ``;
					const char[] customPrefix2 = "" == target ? "" : `(cast(RefType!(`~target~`))_this), `;
					const char[] writeFunc = mixin(is(attribs.write) ? `attribs.write.value` : `""`);
					const char[] readFunc = mixin(is(attribs.read) ? `attribs.read.value` : `""`);
					const char[] rename = mixin(is(attribs.rename) ? `attribs.rename.value` : `field.name`);

					static assert (
						!((writeFunc.length == 0) ^ (readFunc.length == 0)),
						"must have both custom read and write funcs for '"~name~"'"
					);

					
					static if (is(Serializer : xf.xpose2.Serialization.Serializer)) {
						static if (writeFunc.length > 0) {
							serializer_.lengthWrappedWrite({
								mixin(customPrefix1 ~ writeFunc ~ "(" ~ customPrefix2 ~"serializer_);");
								//pragma(msg, "manual write func override");
							});
							const bool _auto_ = false;
						} else static if (isStaticArrayType!(typeof(mixin(prefix~field.name)))) {
							auto t = mixin(prefix~field.name ~ "[]");
							serializer_.field(serializationFieldCounter, serializationMetaInfo.fields[serializationFieldCounter], t);
						} else serializer_.field(serializationFieldCounter, serializationMetaInfo.fields[serializationFieldCounter], mixin(prefix~field.name));
					} else static if (is(Serializer : xf.xpose2.Serialization.Unserializer)) {
						static if (readFunc.length > 0) {
							serializer_.lengthWrappedRead({
								mixin(customPrefix1 ~ readFunc ~ "(" ~ customPrefix2 ~ "serializer_);");
								//pragma(msg, "manual read func override");
							});
							const bool _auto_ = false;
						} else static if (isStaticArrayType!(typeof(mixin(prefix~field.name)))) {
							auto t = mixin(prefix~field.name ~ "[]");
							serializer_.field(serializationFieldCounter, serializationMetaInfo.fields[serializationFieldCounter], t);
						} else serializer_.field(serializationFieldCounter, serializationMetaInfo.fields[serializationFieldCounter], mixin(prefix~field.name));
					}
					
					++serializationFieldCounter;
				}
			}
		}}
		
		static if (is(Serializer : xf.xpose2.Serialization.Serializer) && serializeFunc.length) {
			serializer_.lengthWrappedWrite({
				mixin(serializeFunc ~ "((cast(RefType!(" ~ target ~ "))_this), serializer_);");
			});
		} else static if (is(Serializer : xf.xpose2.Serialization.Unserializer) && unserializeFunc.length) {
			serializer_.lengthWrappedRead({
				mixin(unserializeFunc ~ "((cast(RefType!(" ~ target ~ "))_this), serializer_);");
			});
		}
		
		return serializationFieldCounter;
	}
}



const onUnserializedFuncName = "onUnserialized";


template RefType(T) {
	static if (is(T == class)) {
		alias T RefType;
	} else {
		alias T* RefType;
	}
}


template UnrefType(T) {
	static if (is(T == class)) {
		alias T UnrefType;
	} else {
		alias typeof(*T) UnrefType;
	}
}



class SerializationRegistry {
	Object keyOf(T)() {
		static if (is(T == class)) {
			return T.classinfo;
		} else {
			return typeid(T);
		}
	}
	
	
	void register(T, Worker)(char[] name) {
		version(SerializationTrace) Stdout.formatln("Registering {} in the serialization factory", name);
		Object key = keyOf!(T);
		
		static if (is(T == class) && is(typeof(new T))) {
			factories[name] = function Object() { return new T; };
		}
		
		static if (mixin("is(typeof(&Worker.init."~onUnserializedFuncName~"))")) {
			static if (is(T == Worker)) {
				static assert (mixin("is(typeof(&Worker.init."~onUnserializedFuncName~") == void delegate())"),
				"onUnserialized for " ~ T.stringof ~ " must have the signature: void onUnserialized()");
				onUnserialFuncs[key] = function void(void* this_) {
					mixin("(cast(RefType!(T))this_)." ~ onUnserializedFuncName ~ "();");
				};
			} else {
				static assert (mixin("is(typeof(&Worker.init."~onUnserializedFuncName~") == void delegate(RefType!(T)))"),
				"onUnserialized for " ~ T.stringof ~ " must have the signature: void onUnserialized("~RefType!(T).stringof~")");
				onUnserialFuncs[key] = cast(void function(void*))mixin("&Worker.init."~onUnserializedFuncName);
			}
		}

		serialFuncs[key] = Worker.getSerializationFunction();
		unserialFuncs[key] = Worker.getUnserializationFunction();
		metaInfos[key] = &Worker.serializationMetaInfo;
	}
	
	
	Object create(char[] name) {
		assert(factories[name]);
		return factories[name]();
	}
	
	
	int function(Serializer, void*, int) getSerializeFunc(Object ci) {
		auto ptr = ci in serialFuncs;
		if (ptr is null) return null;
		return *ptr;
	}
	

	int function(Unserializer, void*, int) getUnserializeFunc(Object ci) {
		auto ptr = ci in unserialFuncs;
		if (ptr is null) return null;
		return *ptr;
	}
	
	
	void function(void*) getOnUnserializedFunc(Object ci) {
		if (auto res = ci in onUnserialFuncs) return *res;
		return null;
	}
	
	
	ClassMetaInfo* getMetaInfo(Object ci) {
		auto ptr = ci in metaInfos;
		if (ptr is null) return null;
		return *ptr;
	}

	
	private Object function()[char[]]								factories;
	private int function(Serializer, void*, int)[Object]		serialFuncs;
	private int function(Unserializer, void*, int)[Object]	unserialFuncs;
	private void function(void*)[Object]							onUnserialFuncs;
	ClassMetaInfo*[Object]											metaInfos;
	
	
	static typeof(this) opCall() {
		static typeof(this) instance;
		if (instance is null) instance = new typeof(this);
		return instance;
	}
}


struct FieldMetaInfo {
	char[]	name;
	char[]	typeName;
	uint		typeSize = 0;		// 0 means 'variable'
	byte		typeId;
	
	const static byte TypeId_Primitive = 1;
	const static byte TypeId_Class = 2;
	const static byte TypeId_Struct = 3;
	const static byte TypeId_Other = 4;
	
	static FieldMetaInfo opCall(char[] n, char[] tn, uint ts, byte typeId) {
		FieldMetaInfo res;
		res.name = n;
		res.typeName = tn;
		res.typeSize = ts;
		res.typeId = typeId;
		//if (TypeId_Primitive == typeId) assert (ts != 0);
		return res;
	}
}


struct ClassMetaInfo {
	char[]				className;
	FieldMetaInfo[]	fields;
}



template isBasicType(T) {
	const bool isBasicType =
		is(T : long) ||
		is(T : ulong) ||
		is(T : int) ||
		is(T : uint) ||
		is(T : short) ||
		is(T : ushort) ||
		is(T : byte) ||
		is(T : ubyte) ||
		is(T : bool) ||
		is(T : float) ||
		is(T : double) ||
		is(T : real) ||
		is(T : ifloat) ||
		is(T : idouble) ||
		is(T : ireal) ||
		is(T : cfloat) ||
		is(T : cdouble) ||
		is(T : creal) ||
		is(T : dchar) ||
		is(T : wchar) ||
		is(T : char);
}


template isArrayType(T) {
	const bool isArrayType = false;
}


template isArrayType(T : T[]) {
	const bool isArrayType = true;
}


template isAssocArrayType(T) {
	static if (is(typeof(T.keys)) && is(typeof(T.values))) {
		static if (is(T == typeof(T.values[0])[typeof(T.keys[0])])) {
			const bool isAssocArrayType = true;
		} else const bool isAssocArrayType = false;
	} else const bool isAssocArrayType = false;
}

static assert (isAssocArrayType!(char[char[]]));


template isPointerType(T) {
	static if (is(typeof(*T))) const isPointerType = true;
	else const isPointerType = false;
}



version (Tango) {
	template SerializerBackend() {
		private {
			import tango.io.protocol.Writer;
			import tango.io.device.File : FileConduit = File;
			import tango.io.device.Device : DeviceConduit = Device;
			
			const FileConduit.Style WriteCreate = {FileConduit.Access.Write, FileConduit.Open.Create}; 
		}

		protected FileConduit	fileCond;
		protected Writer			writer;
		
		
		struct StreamContext {
			uint	streamPos = uint.max;
		}
		
		
		StreamContext pushStreamContext() {
			StreamContext res;
			res.streamPos = streamTell();
			uint tmp = 0;
			this.raw(tmp);
			return res;
		}
		
		
		void popStreamContext(StreamContext context, uint blockLength) {
			uint endPos = streamTell();
			fileCond.seek(context.streamPos);
			raw(blockLength);
			flush();
			fileCond.seek(endPos);
		}
		
		
		uint streamTell() {
			flush();
			return fileCond.position();
		}
		
		
		this(FileConduit fc) {
			assert (fc !is null);
			this.fileCond = fc;
			this.writer = new Writer(this.fileCond);
		}
		
		
		this(char[] filename) {
			assert (filename !is null);
			this(new FileConduit(filename, WriteCreate));
		}


		typeof(this) flush() {
			writer.flush();
			return this;
		}
		
		
		typeof(this) close() {
			flush();
			delete writer;
			fileCond.close();
			delete fileCond;
			return this;
		}
		
		
		final void writeByte(ubyte* b) {
			writer(*b);
		}
	}
} else {
	template SerializerBackend() {
		private {
			import std.stream;
		}

		protected Stream stream;
		
		struct StreamContext {
			uint	streamPos = uint.max;
		}
		
		
		StreamContext pushStreamContext() {
			StreamContext res;
			res.streamPos = stream.position();
			uint tmp = 0;
			this.raw(tmp);
			return res;
		}
		
		
		void popStreamContext(StreamContext context, uint blockLength) {
			uint endPos = stream.position();
			stream.seekSet(context.streamPos);
			raw(blockLength);
			stream.seekSet(endPos);
		}
		
		
		uint streamTell() {
			return stream.position();
		}
		
		
		this(Stream s) {
			assert (s !is null);
			this.stream = s;
		}
		
		
		this(char[] filename) {
			assert (filename !is null);
			this.stream = new BufferedFile(filename, FileMode.OutNew);
		}


		typeof(this) flush() {
			stream.flush();
			return this;
		}
		
		
		typeof(this) close() {
			stream.close();
			delete stream;
			return this;
		}
		
		
		final void writeByte(ubyte* b) {
			stream.write(*b);
		}
	}
}


// for extra initialization
private class SerializerBase {
	typedef uint classId;
	typedef uint objectId;
	
	ClassMetaInfo*[classId]	knownClasses;
	classId[ClassMetaInfo*]	classMetaToId;
	classId							lastClassId;
	uint[ClassMetaInfo*]		classDefPositions;
	
	void*[objectId]				objectIdToPtr;
	objectId[void*]				ptrToObjectId;
	objectId						lastObjectId;
	uint[void*]					objectDefPositions;


	this() {
		objectIdToPtr[0] = null;
		ptrToObjectId[null] = 0;
	}
}


class Serializer : SerializerBase {
	mixin SerializerBackend;
	
	
	private void lazyWriteMetaInfo(ClassMetaInfo* metaInfo) {
		assert (metaInfo !is null);
		
		void writeClassMeta(ClassMetaInfo* metaInfo) {
			raw(metaInfo.className);
			packedNum(metaInfo.fields.length);
			foreach (inout field; metaInfo.fields) {
				raw(field.name);
				raw(field.typeName);
				raw(field.typeId);
				packedNum(field.typeSize);
			}
		}

		if (!(metaInfo in classMetaToId)) {
			classMetaToId[metaInfo] = ++lastClassId;
			knownClasses[lastClassId] = metaInfo;
			packedNum(cast(uint)lastClassId * 2 + 1);
			classDefPositions[metaInfo] = streamTell();
			writeClassMeta(metaInfo);
		} else {
			classId id = classMetaToId[metaInfo];
			packedNum(cast(uint)id * 2);
			packedNum(streamTell() - classDefPositions[metaInfo]);
		}
	}
	
	
	typeof(this) opCall(T)(T o) {
		static if (is(T == class)) {
			writeObjectIdOr(cast(void*)o, {
				// write the class meta info
				{
					auto metaInfo = SerializationRegistry().getMetaInfo(o.classinfo);
					assert (metaInfo !is null, 
						"No class metaInfo registered for type '"
						~o.classinfo.name~"'("
						~T.stringof~")");
					lazyWriteMetaInfo(metaInfo);
				}

				lengthWrappedWrite({
					auto funcPtr = SerializationRegistry().getSerializeFunc(o.classinfo);
					assert (funcPtr !is null);
					funcPtr(this, cast(void*)o, 0);
				});
			});
		}
		else static if (is(T == struct)) {
			auto metaInfo = SerializationRegistry().getMetaInfo(typeid(T));
			assert (metaInfo !is null, T.stringof ~ ": no meta info");
			lazyWriteMetaInfo(metaInfo);

			lengthWrappedWrite({
				auto funcPtr = SerializationRegistry().getSerializeFunc(typeid(T));
				assert (funcPtr !is null);
				funcPtr(this, cast(void*)&o, 0);
			});
		} else static if (is(T == interface)) {
			return opCall(cast(Object)o);
		} else {
			raw(o);
		}
		//else static assert (false);
		
		return this;
	}
	
	
	private void packedNum(ulong num) {
		do {
			ubyte part = num & 127;
			if (num > 0b01111111) part |= 0b10000000;
			num >>= 7;
			writeByte(&part);
		} while (num != 0);
	}
	
	
	private void raw(T)(inout T t) {
		static if (isArrayType!(T)) {
			packedNum(t.length);
			foreach (inout x; t) raw(x);
		} else {
			static assert (isBasicType!(T), T.stringof);
			for (int i = 0; i < T.sizeof; ++i) {
				writeByte(cast(ubyte*)&t + i);
			}
		}
	}
	
	
	void writeObjectIdOr(void* ptr, void delegate() otherwise) {
		auto objIdPtr = ptr in ptrToObjectId;
		
		if (objIdPtr !is null) {
			packedNum(*objIdPtr);
			if (ptr !is null) {
				packedNum(streamTell() - objectDefPositions[ptr]);
			}
		} else {
			++lastObjectId;
			objectIdToPtr[cast(objectId)(lastObjectId*2)] = ptr;
			ptrToObjectId[ptr] = cast(objectId)(lastObjectId*2);
			packedNum(lastObjectId*2+1);
			objectDefPositions[ptr] = streamTell();
			otherwise();
		}
	}
	
	
	void lengthWrappedWrite(void delegate() dg) {
		uint						firstStreamPos = uint.max;
		StreamContext		context = pushStreamContext();
		
		firstStreamPos = this.streamTell();
		
		dg();
		
		uint lastStreamPos = this.streamTell();
		uint blockLength = lastStreamPos - firstStreamPos;
		
		popStreamContext(context, blockLength);
	}
	
	
	void field(T)(int classFieldIndex, FieldMetaInfo fieldMeta, inout T t, bool writeLength = true) {
		static if (is(T == class)) {
			version(SerializationTrace) Stdout.formatln("serializing object field : {} {}", fieldMeta.name, typeid(T));
			this.opCall(t);
		}
		else static if (is(T == struct)) {
			this.opCall(t);
		}
		else {
			auto realWrite = delegate void() {
				static if (isBasicType!(T)) {
					version(SerializationTrace) Stdout.formatln("serializing basic field : {} {}", fieldMeta.name, typeid(T));
					raw(t);
				}
				else static if (isArrayType!(T)) {
					version(SerializationTrace) Stdout.formatln("serializing array field : {} {}", fieldMeta.name, typeid(T));
					uint length = t.length;
					packedNum(length);
					version(SerializationTrace) Stdout.formatln("length: {}", t.length);
					writeObjectIdOr(t.ptr, {
						foreach (inout x; t) {
							this.field(int.max, FieldMetaInfo.init, x, false);
						}
					});
				}
				else static if (isAssocArrayType!(T)) {
					uint length = t.keys.length;
					packedNum(length);
					foreach (key, inout value; t) {
						this.field(int.max, FieldMetaInfo.init, key, false);
						this.field(int.max, FieldMetaInfo.init, value, false);
					}
				}
				else static if (isPointerType!(T)) {
					writeObjectIdOr(t, {
						this.field(int.max, FieldMetaInfo.init, *t, false);
					});
				}
				else static if (is(T == interface)) {
					this.opCall(cast(Object)t);
				}
				else {
					pragma(msg, "Error: Unable to write field of type "~T.stringof);
					static assert (false, T.somerandompropertywhichwilltriggeranerror);
				}
			};


			if (writeLength && 0 == fieldMeta.typeSize) {
				lengthWrappedWrite(realWrite);
			} else {
				uint firstStreamPos = this.streamTell();
				realWrite(); 
				uint lastStreamPos = this.streamTell();
				uint blockLength = lastStreamPos - firstStreamPos;
				if (writeLength && blockLength != fieldMeta.typeSize) {
					assert (false);
					//throw new Exception(format(`Serialized field size (%s) doesn't match the size in field's meta info (%s)`, blockLength, fieldMeta.typeSize));
				}
			}
		}
	}
}


version (Tango) {
	template UnserializerBackend() {
		private {
			import tango.io.protocol.Reader;
			import tango.io.device.File : FileConduit = File;
			import tango.io.device.Conduit : Conduit;
			import tango.io.stream.Buffered;
			import tango.io.device.Array : Array;
			import tango.io.device.FileMap : FileMap;
		}

		protected InputStream	fileCond;
		protected Reader			reader;
		
		
		uint streamTell() {
			auto buf = reader.buffer();
			return fileCond.seek(0, Conduit.Anchor.Current) - buf.limit + buf.position;
		}
		

		void streamSeek(uint pos) {
			fileCond.seek(pos);
			reader.buffer.clear();
		}
		
		
		this(InputStream fc) {
			assert (fc !is null);
			this.fileCond = fc;
			this.reader = new Reader(this.fileCond);
		}
		
		
		this(char[] filename) {
			assert (filename !is null);
			this(new FileMap(filename, FileConduit.ReadExisting));
		}


		typeof(this) close() {
			delete reader;
			fileCond.close();
			delete fileCond;
			return this;
		}
		
		
		final void readByte(ubyte* b) {
			reader(*b);
		}
	}
} else {
	template UnserializerBackend() {
		private {
			import std.stream;
		}

		protected Stream stream;
		

		this(Stream s) {
			assert (s !is null);
			this.stream = s;
		}


		this(char[] filename) {
			assert (filename !is null);
			this.stream = new BufferedFile(filename, FileMode.In);
		}


		uint streamTell() {
			return stream.position();
		}


		void streamSeek(uint pos) {
			version (SerializationDebug) Stdout.formatln("seeking to {}", pos);
			stream.seekSet(pos);
		}


		final void readByte(ubyte* b) {
			stream.read(*b);
		}
	}
}


struct CurUnserialObject {
	uint					streamBegin;
	ClassMetaInfo	metaInfo;
	uint					curFieldIndex;
}


class Unserializer {
	mixin UnserializerBackend;
	import tango.text.convert.Format : Format;

	public {
		bool recoverFromErrors = false;
	}	
	
	
	CurUnserialObject pushUnserialObject(uint streamBegin, ClassMetaInfo metaInfo) {
		CurUnserialObject backup = curUnserialObject;
		curUnserialObject.streamBegin = streamBegin;
		curUnserialObject.metaInfo = metaInfo;
		curUnserialObject.curFieldIndex = 0;
		return backup;
	}
	
	
	void popUnserialObject(CurUnserialObject prev) {
		curUnserialObject = prev;
	}


	T get(T)() {
		static if (is(T == class) || is(T == interface)) {
			return getObject!(T);
		}
		else static if (is(T == struct)) {
			return getStruct!(T);
		}
		else static assert (false, "Cannot get() type '"~T.stringof~"'");
	}
	
	
	ulong packedNum() {
		ulong res = 0;
		bool cont = true;
		for (int i = 0; cont; ++i) {
			ubyte part;
			readByte(&part);
			//Stdout.formatln(`part: {}`, part);
			cont = (part & 0b10000000) != 0;
			res |= (part & 0b01111111) << (i * 7);
		}
		//Stdout.formatln(`packedNum returning {}`, res);
		return res;
	}
	

	private void raw(T)(ref T t) {
		static if (isArrayType!(T)) {
			t.length = packedNum();
			foreach (inout x; t) raw(x);
		} else {
			static assert (isBasicType!(T));
			for (int i = 0; i < T.sizeof; ++i) {
				readByte(cast(ubyte*)&t + i);
			}
		}
	}

	
	ClassMetaInfo getClassMeta(classId id, bool skip = false) {
		assert (id != 0, `should never happen :S class meta should always be intialized to something in the serializer`);		
		bool infoNow = (id & 1) != 0;
		id /= 2;
		
		version (SerializationDebug) Stdout.formatln("class id = {}");
		
		uint firstPos;
		uint nextPos;
		uint infoOffset;
		if (!infoNow) {
			firstPos = streamTell();
			infoOffset = packedNum();
			nextPos = streamTell();
		}
		
		if (!infoNow && skip) return ClassMetaInfo.init;
		
		if (!infoNow && id in knownClasses) {
			return knownClasses[id];
		} else {
			if (!infoNow) {
				version (SerializationDebug) Stdout.formatln("skipping back by {} to read class info", infoOffset);
				streamSeek(firstPos - infoOffset);
			}
			
			ClassMetaInfo metaInfo;
			
			raw(metaInfo.className);
			metaInfo.fields.length = packedNum();
			
			foreach (inout field; metaInfo.fields) {
				raw(field.name);
				raw(field.typeName);
				raw(field.typeId);
				field.typeSize = packedNum();
			}
			
			if (!skip) {
				knownClasses[id] = metaInfo;
			}

			if (!infoNow) {
				streamSeek(nextPos);
			}
			
			return metaInfo;
		}
	}
	
	
	T createObject(T)(ClassMetaInfo clsMeta) {
		return cast(T)SerializationRegistry().create(clsMeta.className);
	}
	
	
	void lengthWrappedRead(void delegate() dg) {
		uint blockLen;
		raw(blockLen);
		version (SerializationDebug) Stdout.formatln("block length: {}", blockLen);
		uint curPos = streamTell();
		
		if (recoverFromErrors) {
			try {
				dg();
			} catch (Object err) {
				version(Tango) Stdout(`exception caught while unserializing: {} ({})`\n, err.toString, err.classinfo.name);
				else printf(`exception caught while unserializing: %.*s (%.*s)`\n, err, err.classinfo.name);
				
				// set it to an invalid value so it wont be used in any way
				curUnserialObject.curFieldIndex = -1;
			}
		} else {
			dg();
		}

		version (SerializationDebug) Stdout.format("lengthWrappedRead: ");
		if (streamTell() != curPos+blockLen) {
			streamSeek(curPos+blockLen);
		}
	}
	
	
	void* getObjectOr(void* delegate(objectId) dg) {
		objectId objId = cast(objectId)packedNum();
		if (0 == objId) return null;
		
		bool infoNow = (objId & 1) != 0;
		objId /= 2;

		if (!infoNow && objId in objectIdToPtr) {
			packedNum();
			return objectIdToPtr[objId];
		} else {
			uint firstPos;
			uint nextPos;
			uint infoOffset;

			if (!infoNow) {
				firstPos = streamTell();
				infoOffset = packedNum();
				nextPos = streamTell();
				streamSeek(firstPos - infoOffset);
			}
			
			void* res = dg(objId);

			if (!infoNow) {
				streamSeek(nextPos);
			}
			
			return res;
		}
	}
	
	
	T getObject(T)() {
		static if (is(T == interface)) {
			return cast(T)getObject!(Object)();
		} else {
			version (SerializationDebug) Stdout.formatln("getObject");
			void* ptr = getObjectOr((objectId objId){
				version(SerializationTrace) Stdout.formatln(`unserializing class id: {}`, cast(uint)objId);
				auto metaInfo = getClassMeta(cast(classId)packedNum());
				
				version(SerializationTrace) Stdout.formatln(`instantiating the object`);
				T obj = createObject!(T)(metaInfo);
				assert (obj !is null, "Object is null");
				
				objectIdToPtr[objId] = cast(void*)obj;

				version(SerializationTrace) Stdout.formatln(`unserializing an object`);
				lengthWrappedRead({
					auto funcPtr = SerializationRegistry().getUnserializeFunc(obj.classinfo);
					assert (funcPtr !is null, "unserialize func pointer was null for " ~ obj.classinfo.name);
					
					auto metaBackup = pushUnserialObject(streamTell(), metaInfo);
					{
						funcPtr(this, cast(void*)obj, 0);
					}
					popUnserialObject(metaBackup);
				});
				version(SerializationTrace) Stdout.formatln(`done unserializing an object`);
				
				return cast(void*)obj;
			});

			// just a null pointer/reference
			if (ptr is null) {
				version (SerializationDebug) Stdout.formatln("* returning a null reference");
				return null;
			}
			
			T res = cast(T)cast(Object)ptr;
			assert (res !is null, `classes dont match`);
			
			auto onUnserial = SerializationRegistry().getOnUnserializedFunc(res.classinfo);
			if (onUnserial !is null) {
				onUnserial(cast(void*)res);
			}
			
			return res;
		}
	}
	

	T readObject(T)(T obj) {
		assert (obj !is null);
	
		static if (is(T == interface)) {
			return cast(T)readObject!(Object)(obj);
		} else {
			version (SerializationDebug) Stdout.formatln("readObject");
			
			void* ptr = getObjectOr((objectId objId) {
				version(SerializationTrace) Stdout.formatln(`unserializing class id: {}`, cast(uint)objId);
				auto metaInfo = getClassMeta(cast(classId)packedNum());
				
				objectIdToPtr[objId] = cast(void*)obj;

				version(SerializationTrace) Stdout.formatln(`unserializing an object`);
				lengthWrappedRead({
					auto funcPtr = SerializationRegistry().getUnserializeFunc(obj.classinfo);
					assert (funcPtr !is null, "unserialize func pointer was null for " ~ obj.classinfo.name);
					
					auto metaBackup = pushUnserialObject(streamTell(), metaInfo);
					{
						funcPtr(this, cast(void*)obj, 0);
					}
					popUnserialObject(metaBackup);
				});
				version(SerializationTrace) Stdout.formatln(`done unserializing an object`);
				
				return cast(void*)obj;
			});
			
			assert (ptr is cast(void*)obj);
			
			T res = cast(T)cast(Object)ptr;
			assert (res !is null, `classes dont match`);
			
			auto onUnserial = SerializationRegistry().getOnUnserializedFunc(res.classinfo);
			if (onUnserial !is null) {
				onUnserial(cast(void*)res);
			}
			
			return res;
		}
	}
	
	
	T getStruct(T)() {
		version (SerializationDebug) Stdout.formatln("getStruct");
		auto metaInfo = getClassMeta(cast(classId)packedNum());
		
		T res;

		lengthWrappedRead({
			auto funcPtr = SerializationRegistry().getUnserializeFunc(typeid(T));
			assert (funcPtr !is null);

			auto metaBackup = pushUnserialObject(streamTell(), metaInfo);
			{
				//res.serializerDescribe(this, &res);
				funcPtr(this, cast(void*)&res, 0);
			}
			popUnserialObject(metaBackup);
		});

		auto onUnserial = SerializationRegistry().getOnUnserializedFunc(typeid(T));
		if (onUnserial !is null) {
			onUnserial(cast(void*)&res);
		} else {
			static if (is(typeof(mixin("&res."~onUnserializedFuncName)))) {
				mixin("res.onUnserializedFuncName();");
			}
		}
		
		return res;
	}
	
	
	typeof(this) opCall(T)(ref T o) {
		static if (is(T == class) || is(T == interface)) {
			o = getObject!(T)();
		} else static if (is(T == struct)) {
			o = getStruct!(T)();
		} else {
			raw(o);
		}
		
		return this;
	}
	
	
	int findFieldIndex(in FieldMetaInfo fieldMeta) {
		foreach (i, field; curUnserialObject.metaInfo.fields) {
			if (	field.name == fieldMeta.name &&
					field.typeName == fieldMeta.typeName &&
					field.typeSize == fieldMeta.typeSize)
				{
					return i;
				}
		}
		
		return -1;
	}


	void seekToNextField(in FieldMetaInfo curFieldMeta) {
		++curUnserialObject.curFieldIndex;
		
		switch (curFieldMeta.typeId) {
			case FieldMetaInfo.TypeId_Primitive: {
				version (SerializationDebug) Stdout.formatln("skipping a prim field");
				if (curFieldMeta.typeSize != 0) {
					version(SerializationDebug) Stdout.format("seekToNextField: ");
					streamSeek(streamTell() + curFieldMeta.typeSize);
				} else {
					goto otherSkip;
				}
			} break;

			case FieldMetaInfo.TypeId_Class:
				version (SerializationDebug) Stdout.formatln("skipping an object field");
				objectId objId = cast(objectId)packedNum();
				if (0 == objId) return;	// null reference
				
				version (SerializationDebug) Stdout.formatln("object id = {}", objId/2);
				
				if (0 == (objId & 1)) {
					uint defOffset = packedNum();
					version (SerializationDebug) Stdout.formatln("definition offset: {}", defOffset);		// skip the definition offset
					return;
				}
				// falls through
			case FieldMetaInfo.TypeId_Struct:
				version (SerializationDebug) Stdout.formatln("skipping a struct field");
				getClassMeta(cast(classId)packedNum(), true);
				// falls through
			otherSkip: case FieldMetaInfo.TypeId_Other:
				version (SerializationDebug) Stdout.formatln("skipping an other field");
				assert (curFieldMeta.typeSize == 0);
				uint len;
				raw(len);
				version (SerializationDebug) Stdout.format("2seekToNextField: ");
				streamSeek(streamTell() + len);
				break;
		}
	}
	
	
	void seekToField(int index) {
		version (SerializationDebug) Stdout.formatln("seeking to object start at {}", curUnserialObject.streamBegin);
		streamSeek(curUnserialObject.streamBegin);
		curUnserialObject.curFieldIndex = 0;
		foreach (i, field; curUnserialObject.metaInfo.fields[0..index]) {
			version (SerializationDebug) Stdout.formatln("skipping {} : {} ({}) : {}", i, field.name, field.typeName, field.typeSize);
			seekToNextField(field);
		}
	}

	
	void field(T)(int classFieldIndex, in FieldMetaInfo fieldMeta, inout T t, bool readLength = true) {
		version (SerializationDebug) if (int.max != classFieldIndex) {
			version(SerializationTrace) Stdout.formatln("field!({})", typeid(T).toString);
		}
		
		if (classFieldIndex != int.max) {
			version (SerializationDebug) Stdout.formatln("{} : {}", fieldMeta.name, fieldMeta.typeName);
			int streamFieldIndex = findFieldIndex(fieldMeta);
			version (SerializationDebug) Stdout.formatln("field {} index in stream: {}", classFieldIndex, streamFieldIndex);
			if (streamFieldIndex != -1) {
				uint before = streamTell();
				if (streamFieldIndex != curUnserialObject.curFieldIndex) {
					version (SerializationDebug) Stdout.formatln("pos before field seeking: {}", before);
					seekToField(streamFieldIndex);
				} else {
					version (SerializationDebug) Stdout.formatln("* not seeking");
				}
				version (SerializationDebug) Stdout.formatln("stream offset: {}", streamTell() - before);
			} else {
				return;
			}
		}
		
		if (classFieldIndex != int.max) {
			scope (exit) {
				++curUnserialObject.curFieldIndex;
			}
		}
		
		static if (is(T == class)) {
			version(SerializationTrace) Stdout.formatln("unserializing object field : {} {}", fieldMeta.name, typeid(T));
			t = getObject!(T);
		}
		else static if (is(T == struct)) {
			version(SerializationTrace) Stdout.formatln("unserializing object field : {} {}", fieldMeta.name, typeid(T));
			t = getStruct!(T);
		}
		else {
			auto realRead = delegate void() {
				static if (isBasicType!(T)) {
					version(SerializationTrace) Stdout.formatln("unserializing basic field : {} {} : ", fieldMeta.name, typeid(T));
					raw(t);
					version(SerializationTrace) Stdout.formatln("{}", t);
				}
				else static if (isArrayType!(T)) {
					version(SerializationTrace) Stdout.formatln("unserializing array field : {} {}", fieldMeta.name, typeid(T).toString);
					uint len = packedNum();
					version(SerializationTrace) Stdout.formatln("length: {}", len);

					void* ptr = getObjectOr((objectId objId){
						t.length = len;
						objectIdToPtr[objId] = t.ptr;
						foreach (inout x; t) {
							this.field(int.max, FieldMetaInfo.init, x, false);
						}
						
						return cast(void*)t.ptr;
					});
					
					if (ptr !is null) {
						t = (cast(typeof(T.ptr))ptr)[0..len];
					} else {
						t = null;
					}
				}
				else static if (isAssocArrayType!(T)) {
					uint len = packedNum();
					while (len--) {
						typeof(T.keys[0])		key;
						typeof(T.values[0])	val;
						
						this.field(int.max, FieldMetaInfo.init, key, false);
						this.field(int.max, FieldMetaInfo.init, val, false);
						
						t[key] = val;
					}
				}
				else static if (isPointerType!(T)) {
					t = cast(T)getObjectOr((objectId objId){
						t = new typeof(*t);
						objectIdToPtr[objId] = t;
						this.field(int.max, FieldMetaInfo.init, *t, false);
						return cast(void*)t;
					});
				}
				else static if (is(T == interface)) {
					t = cast(T)getObject!(Object);
				}
				else static assert (false);
			};

			if (readLength && 0 == fieldMeta.typeSize) {
				lengthWrappedRead(realRead);
			} else {
				uint firstStreamPos = this.streamTell();
				realRead(); 
				uint lastStreamPos = this.streamTell();
				uint blockLength = lastStreamPos - firstStreamPos;
				if (readLength && blockLength != fieldMeta.typeSize) {
					throw new Exception(Format(`Unserialized field size ({}) doesn't match the size in field's meta info ({})`, blockLength, fieldMeta.typeSize));
				}
			}
		}
	}


	private {
		typedef uint classId;
		typedef uint objectId;
			
		ClassMetaInfo[classId]	knownClasses;
		void*[objectId]				objectIdToPtr;
		
		CurUnserialObject			curUnserialObject;
	}
}
