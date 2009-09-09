/// simple serialization mixins (that cover the most common serialization cases)
/// these are less powerful than the Xpose version, but cover the most common case
/// and can be compiled with all compilers
///
/// author: Fawzi
module blip.serialization.SerializationMixins;
import tango.core.Traits: ctfe_i2a;

char[][] extractFieldsAndDocs(char[] fieldsDoc){
    int i=0;
    char[][] res=[];
    while (i<fieldsDoc.length){
        char[] field="",doc="";
        while (i<fieldsDoc.length && fieldsDoc[i]==' ') ++i;
        auto fieldStart=i;
        while (i<fieldsDoc.length){
            if (fieldsDoc[i]==' ' || fieldsDoc[i]==':' || fieldsDoc[i]=='|' || fieldsDoc[i]=='\n') break;
            i++;
        }
        field=fieldsDoc[fieldStart..i]; // check that it is actually a valid identifier???
        while (i<fieldsDoc.length && fieldsDoc[i]==' ') ++i;
        if (i<fieldsDoc.length && fieldsDoc[i]==':'){
            while (i<fieldsDoc.length && fieldsDoc[i]==' ') ++i;
            auto docStart=i;
            while (i<fieldsDoc.length){
                if (fieldsDoc[i]=='|'|| fieldsDoc[i]=='\n') break; // allow multiline doc??
                i++;
            }
            doc=fieldsDoc[docStart..i];
        }
        if (field.length>0){
            res~=field;
            res~=doc;
        }
        ++i;
    }
    return res;
}

/// serializes some fields
/// basic version, does not work for subclasses serialized with external structs
/// (should take the logic from the Xpose version)
char[] serializeSome(char[] typeName1,char[]fieldsDoc){
    char[] typeName=typeName1;
    char[] res="";
    res~="static ClassMetaInfo metaI;\n";
    res~="static this(){\n";
    res~="    static if (is(typeof(this) == class)){\n";
    res~="        metaI=ClassMetaInfo.createForType!(typeof(this))(";
    if (typeName.length==0) {
        res~="typeof(this).mangleof";
    } else {
        res~="`"~typeName~"`";
    }
    res~=");\n";
    res~="    }else{\n";
    res~="        metaI=ClassMetaInfo.createForType!(typeof(*this))(";
    if (typeName.length==0) {
        res~="typeof(*this).mangleof";
    } else {
        res~="`"~typeName~"`";
    }
    res~=");\n";
    res~="    }\n";
    auto fieldsDocArray=extractFieldsAndDocs(fieldsDoc);
    for (int ifield=0;ifield<fieldsDocArray.length/2;++ifield){
        auto field=fieldsDocArray[2*ifield];
        auto doc=fieldsDocArray[2*ifield+1];
        res~="    metaI.addFieldOfType!(typeof(this."~field~"))(`"~field~"`,`"~doc~"`);\n";
    }
    res~="}\n";
    res~="ClassMetaInfo getSerializationMetaInfo(){\n";
    res~="    return metaI;\n";
    res~="}\n";
    res~="void serial(Ser)(Ser s){\n";
    for (int ifield=0;ifield<fieldsDocArray.length/2;++ifield){
        auto field=fieldsDocArray[2*ifield];
        res~="    static if(isStaticArrayType!(typeof(this."~field~"))){\n";
        res~="        auto this_"~field~"=this."~field~"[];\n";
        res~="        s.field(metaI["~ctfe_i2a(ifield)~"],this_"~field~");\n";
        res~="        assert(this."~field~".length==this_"~field~".length);\n";
        res~="        if (this."~field~".ptr !is this_"~field~".ptr)\n";
        res~="            this."~field~"[]=this_"~field~";\n";
        res~="    } else {\n";
        res~="        s.field(metaI["~ctfe_i2a(ifield)~"],this."~field~");\n";
        res~="    }\n";
    }
    res~="    }\n";
    res~=`
    static if (is(typeof(this)==class)) {
        alias typeof(super) SuperType;
        static if (!is(typeof(SuperType.init.preSerialize(Serializer.init)))) {
            void preSerialize(Serializer s){ }
        }
        static if (!is(typeof(SuperType.init.postSerialize(Serializer.init)))) {
            void postSerialize(Serializer s){ }
        }
        static if (!is(typeof(SuperType.init.preUnserialize(Unserializer.init)))) {
            typeof(this) preUnserialize(Unserializer s){ return this; }
        }
        static if (!is(typeof(SuperType.init.postUnserialize(Unserializer.init)))) {
            typeof(this) postUnserialize(Unserializer s){ return this; }
        }
        void serialize(Serializer s){
            static if (is(typeof(SuperType.init.serialize(s)))){
                super.serialize(s);
            }
            serial(s);
        }
        void unserialize(Unserializer s){
            static if (is(typeof(SuperType.init.unserialize(s)))){
                super.unserialize(s);
            }
            serial(s);
        }
    } else static if (is(typeof(*this) == struct)) {
        void serialize(Serializer s){
            serial(s);
        }
        void unserialize(Unserializer s){
            serial(s);
        }
    } else {
        static assert(0,"serialization supported only within classes or structs");
    }
`;
    return res;
}
