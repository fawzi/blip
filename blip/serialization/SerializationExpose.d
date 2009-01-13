/// adds serialization support using xpose magic
module blip.serialization.SerializationExpose;
import blip.serialization.SerializationBase;
import xf.xpose.Expose;
public alias xf.xpose.Expose.expose expose;
public alias xf.xpose.Expose.attribsContain attribsContain;
public alias xf.xpose.Expose.attribsGet attribsGet;
public import xf.xpose.Utils;

template NewSerializationExpose_mix0() {
    static char[] begin(char[] target) {
        return `
        static ClassMetaInfo serializationMetaInfo;
        
        ClassMetaInfo getSerializationMetaInfo() {
            return serializationMetaInfo;
        }

        /* private template SerializationInitializerMix() { */
            static this() {
                alias `~("" == target ? `UnrefType!(typeof(this))` : target)~` TargetType;
                serializationMetaInfo=ClassMetaInfo.createForType!(TargetType)();
                static if(!is(TargetType==UnrefType!(typeof(this)))){
                    serializationMetaInfo.externalHandlers=new ExternalSerializationHandlers;
                    serializationMetaInfo.externalHandlers.serialize=&serializeFunction;
                }
                
                serializationGatherFieldInfo(serializationMetaInfo);
            }
        /*}*/

        protected static void serializationGatherFieldInfo(ClassMetaInfo serializationMetaInfo) {`;
    }
    
    
    static char[] end(char[] target) {
        return `}  /* mixin SerializationInitializerMix;*/ `;
    }
    
    
    static char[] method(char[] target, char[] name, char[] rename, char[] overload, char[] attribs) {
        return "pragma(msg,`method(target: '"~target~"' name: '"~name~"' rename: '"~rename~"' overload: '"~overload~"' attribs: '"~attribs~"')8`);\n";
    }
    
    static char[] field(char[] target, char[] name, char[] rename, bool readOnly, char[] attribs) {
        char[] res="".dup;
        if (rename.length==0) rename=name;
        char[] fieldN="field_"~rename;
        char[] type=attribsGet(attribs,"type");
        char[] indent="    ";
        res~=indent~"{\n";
        res~=indent~"    alias "~(target.length>0?target:"UnrefType!(typeof(this))")~" TType;\n";
        char[] fType=attribsGet(attribs,"type");
        if (fType.length>0){
            res~=indent~"    alias "~fType~" FType;\n";
        } else {
            res~=indent~"    TType tt;alias typeof(tt."~name~") FType;\n";
        }
        if (attribsContain(`~"`"~attribs~"`"~`, "no-serial"))
            res~=indent~"    auto sLevel=SerializationLevel.never;\n";
        else {
            res~=indent~"    static if (is(typeof(*FType))&& (! isArrayType!(FType)) && !(is(typeof(*FType)==class)||is(typeof(*FType)==struct)||is(typeof(*FType) U== U[]))){\n";
            res~=indent~"        auto sLevel=SerializationLevel.debugLevel;\n";
            res~=indent~"    } else {\n";
            res~=indent~"        auto sLevel=SerializationLevel.normalLevel;\n";
            res~=indent~"    }\n";
        }
        char[] doc=attribsGet(attribs,"doc");
        char[] citeList=attribsGet(attribs,"cites");
        res~=indent~"    serializationMetaInfo.addFieldOfType!(FType)(`"~rename~"`,`"
            ~doc~"`,`"~citeList~"`,sLevel);\n";
        res~=indent~"}\n";
        return res;
    }
}


template NewSerializationExpose_mix1() {
    static char[] begin(char[] target) {
        if (target.length==0) target=`UnrefType!(typeof(this))`;
        return
        `
        static if (is(`~target~` == class)) {
            alias typeof(super) SuperType;
            static if (!is(typeof(SuperType.init.preSerialize(Serializer.init)))) {
                void preSerialize(Serializer s){ }
            }
            static if (!is(typeof(SuperType.init.postSerialize(Serializer.init)))) {
                void postSerialize(Serializer s){ }
            }
            void serialize(Serializer s){
                static if (is(`~target~` T==super)){
                    static if (is(typeof(T.init.serialize(s)))){
                        static assert(`~target~`==UnrefType!(typeof(this)),"serialization in subclasses of types that implement methods to serialize have to be impemented inside the subclasses, not outside");
                        super.serialize(s);
                    }
                }
                serializeFunction(s,serializationMetaInfo,cast(void*)this);
            }
        } else static if (is(`~target~` == struct)) {
            void serialize(Serializer s){
                serializeFunction(s,serializationMetaInfo,cast(void*)this);
            }
        }
        
        static void serializeFunction(Serializer serializer, ClassMetaInfo metaInfo, void* _this) {
            assert(metaInfo is serializationMetaInfo);
            static if (is(`~target~` T==super)){
                static if (!is(typeof(T.init.serialize(s)))){
                    if (metaInfo.superMeta !is null &&
                        metaInfo.superMeta.externalHandlers !is null){
                        assert(metaInfo.superMeta.externalHandlers.serialize !is null,
                            "null externalHandlers.serialize for class "~metaInfo.superMeta.className~"("~T.stringof~")");
                        metaInfo.superMeta.externalHandlers.serialize(serializer,metaInfo.superMeta,_this);
                    }
                }
            }
            int fieldIndex=0;
`;
    }
    
    
    static char[] end(char[] target) {
        return ` }`;
    }
    
    
    static char[] method(char[] target, char[] name, char[] rename, char[] overload, char[] attribs) {
        return ``;
    }
    
    static char[] field(char[] target, char[] name, char[] rename, bool readOnly, char[] attribs) {
        if (rename.length==0) rename=name;
        char[] fieldN="field_"~rename;
        char[] prefix = "" == target ? "(cast(typeof(this))_this)." : `(cast(RefType!(`~target~`))_this).`;
        char[] res=`
        {
            FieldMetaInfo *fieldMeta=serializationMetaInfo[fieldIndex];
            serializer.field(fieldMeta,`~prefix~name~`);
            ++fieldIndex;
        }
        `;
        return res;
    }

}

struct NewSerializationExpose {
	template handler(int i : 0) {
		mixin NewSerializationExpose_mix0;
	}

	template handler(int i : 1) {
		mixin NewSerializationExpose_mix1;
	}
	
	mixin HandlerStructMix;
}
