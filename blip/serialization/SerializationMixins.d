/// simple serialization mixins (that cover the most common serialization cases)
/// these are less powerful than the Xpose version, but cover the most common case
/// and can be compiled with all compilers
///
/// author: Fawzi
module blip.serialization.SerializationMixins;
public import blip.t.core.Traits: ctfe_i2a,isStaticArrayType,DynamicArrayType;

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
char[] serializeSome(char[] typeName1,char[]fieldsDoc,bool classAddPost=true){
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
        res~=`
        {
            static if (is(typeof(this.`~field~`()))){
                alias typeof(this.`~field~`()) FieldType;
                    FieldType thisField=this.`~field~`;
                    s.field(metaI[`~ctfe_i2a(ifield)~`],thisField);
                    this.`~field~`=thisField;
            } else {
                alias typeof(this.`~field~`) FieldType;
                static if(isStaticArrayType!(FieldType)){
                    auto thisField=this.`~field~`[];
                    s.field(metaI[`~ctfe_i2a(ifield)~`],thisField);
                    assert(this.`~field~`.length==thisField.length);
                    if (this.`~field~`.ptr !is thisField.ptr)
                        this.`~field~`[]=thisField;
                } else {
                    s.field(metaI[`~ctfe_i2a(ifield)~`],this.`~field~`);
                }
            }
        }`;
    }
    res~="    }\n";
    res~=`
    static if (is(typeof(this)==class)) {
        alias typeof(super) SuperType;
        static if (!is(typeof(SuperType.init.preSerialize(Serializer.init)))) {
            void preSerialize(Serializer s){ }
        }
        static if (!is(typeof(SuperType.init.preUnserialize(Unserializer.init)))) {
            typeof(this) preUnserialize(Unserializer s){ return this; }
        }`;
    if (classAddPost){
        res~=`
        static if (!is(typeof(SuperType.init.postSerialize(Serializer.init)))) {
            void postSerialize(Serializer s){ }
        }
        static if (!is(typeof(SuperType.init.postUnserialize(Unserializer.init)))) {
            typeof(this) postUnserialize(Unserializer s){ return this; }
        }`;
    }
    res~=`
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

/// serializes some fields
/// basic version, does not work for subclasses serialized with external structs
/// (should take the logic from the Xpose version)
char[] createView(char[] viewName,char[]fieldsDoc,char[] baseType=""){
    char[] res="";
    bool inContext=false;
    if (viewName[0]<'A' && viewName[0]>'Z') {
        assert(0,"first letter of viewName should be an uppercase letter");
    }
    if (baseType.length==0){
        inContext=true;
        res~=`
        alias typeof(this) `~viewName~`InnerType;`;
        baseType=viewName~`InnerType`;
    }
    res~=`
    struct `~viewName~`{
        `~baseType~` el;`;
    
    res~=`
        static ClassMetaInfo metaI;
        static this(){
            metaI=ClassMetaInfo.createForType!(typeof(*this))(typeof(*this).mangleof);`;
    auto fieldsDocArray=extractFieldsAndDocs(fieldsDoc);
    for (int ifield=0;ifield<fieldsDocArray.length/2;++ifield){
        auto field=fieldsDocArray[2*ifield];
        auto doc=fieldsDocArray[2*ifield+1];
        res~=`
            {
                static if (is(typeof(this.`~field~`()))){
                    alias typeof(this.`~field~`()) FieldType;
                } else {
                    alias typeof(this.`~field~`) FieldType;
                }
                metaI.addFieldOfType!(FieldType)("`~field~"\",`"~doc~"`"~`);
            }`;
    }
    res~=`
        }
        static `~viewName~` opCall(`~baseType~` a){
            `~viewName~` res;
            res.el=a;
            return res;
        }
        ClassMetaInfo getSerializationMetaInfo(){
            return metaI;
        }
        void serial(Ser)(Ser s){`;
    for (int ifield=0;ifield<fieldsDocArray.length/2;++ifield){
        auto field=fieldsDocArray[2*ifield];
        res~=`
            {
                static if (is(typeof(el.`~field~`()))){
                    alias typeof(el.`~field~`()) FieldType;
                        FieldType thisField=el.`~field~`;
                        s.field(metaI[`~ctfe_i2a(ifield)~`],thisField);
                        el.`~field~`=thisField;
                } else {
                    alias typeof(el.`~field~`) FieldType;
                    static if(isStaticArrayType!(FieldType)){
                        auto thisField=el.`~field~`[];
                        s.field(metaI[`~ctfe_i2a(ifield)~`],thisField);
                        assert(el.`~field~`.length==thisField.length);
                        if (el.`~field~`.ptr !is thisField.ptr)
                            el.`~field~`[]=thisField;
                    } else {
                        s.field(metaI[`~ctfe_i2a(ifield)~`],el.`~field~`);
                    }
                }
            }`;
    }
    res~=`
        }
        void serialize(Serializer s){
            serial(s);
        }
        void unserialize(Unserializer s){
            serial(s);
        }
        void preSerialize(Serializer s){
            static if (is(typeof(el is null))){
                if (el is null){
                    if (is(typeof(*el))){
                        el=new typeof(*el);
                    } else {
                        el=new typeof(el);
                    }
                }
            }
        }
    }
    `;
    if (inContext){
        char viewLow=cast(char)(viewName[0]-'A'+'a');
        res~=`
    `~viewName~` `~[viewLow]~viewName[1..$]~`(){
        `~viewName~` res;
        res.el=this;
        return res;
    }
    `;
    }
    return res;
}
    

