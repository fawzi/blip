/// serialization to/from Json format
module blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import blip.serialization.Handlers;
import tango.io.Stdout : Stdout;
import tango.io.stream.Format;
import tango.core.Variant;
import blip.BasicModels;
import blip.text.TextParser;

class JsonSerializer(T=char) : Serializer {
    int depth;
    FormatOutput!(T) writer;
    this(FormatOutput!(T)w){
        super(new FormattedWriteHandlers(w));
        writer=w;
    }
    /// indents the output
    void indent(int amount){
        for (int i=0;i<amount;++i)
            writer.stream.write(cast(T[])"  ");
    }
    void writeField(FieldMetaInfo *field){
        if (field !is null){
            writer(cast(T[])",").newline;
            indent(depth);
            writer(cast(T[])field.name);
            writer(cast(T[])":");
        }
    }
    /// writes something that has a custom write operation
    override void writeCustomField(FieldMetaInfo *field, void delegate()writeOp){
        writeOp();
    }
    /// write a pointer (for debug purposes)
    override void writeDebugPtr(FieldMetaInfo *field,void* o){
        size_t u=cast(size_t)o;
        handlers.handle(u);
    }
    /// null object
    override void writeNull(FieldMetaInfo *field) {
        writeField(field);
        writer(cast(T[])"null");
    }
    /// writes the start of an array of the given size
    override PosCounter writeArrayStart(FieldMetaInfo *field,size_t size){
        writeField(field);
        writer(cast(T[])`[`);
        ++depth;
        if (size>6){
            writer.newline;
            indent(depth);
        }
        return PosCounter(size);
    }
    /// writes a separator of the array
    override void writeArrayEl(ref PosCounter ac, void delegate() writeEl) {
        if (ac.pos>0){
            writer(cast(T[])", ");
            if (ac.pos % 6 ==0) {  /// wrap lines
                writer.newline;
                indent(depth);
            }
        }
        ac.next();
        writeEl();
        
    }
    /// writes the end of the array
    override void writeArrayEnd(ref PosCounter ac) {
        ac.end();
        writer(cast(T[])"]");
        --depth;
    }
    /// start of a dictionary
    override PosCounter writeDictStart(FieldMetaInfo *field,size_t length, bool stringKeys=false) {
        writeField(field);
        if (stringKeys)
            writer(cast(T[])`{ "class":"dict"`);
        else
            writer(cast(T[])`{ "class":"associativeArray"`);
        auto res=PosCounter(length);
        res.data=Variant(stringKeys);
        ++depth;
        return res;
    }
    /// writes an entry of the dictionary
    override void writeEntry(ref PosCounter ac, void delegate() writeKey,void delegate() writeVal) {
        writer(cast(T[])",\n");
        ac.next();
        indent(depth);
        ++depth;
        if (ac.data.get!(bool)){
            writeKey();
            writer(cast(T[])":");
            writeVal();
        } else {
            writer(cast(T[])`{"key":`);
            writeKey();
            writer(cast(T[])",\n");
            indent(depth-1);
            writer(cast(T[])` "val":`);
            writeVal();
            writer(cast(T[])`}`);
        }
        --depth;
    }
    /// end of dictionary
    override void writeDictEnd(ref PosCounter ac) {
        ac.end();
        writer(cast(T[])`}`);
        --depth;
    }
    /// writes an Object
    override void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite, Object o){
        writeField(field);
        assert(metaInfo!is null);
        writer(cast(T[])`{ "class":"`)(metaInfo.className)(`"`);
        writer(cast(T[])`, "id":`)(objId);
        ++depth;
        realWrite();
        --depth;
        writer(cast(T[])`}`);
    }
    /// write ObjectProxy
    override void writeProxy(FieldMetaInfo *field, objectId objId){
        writeField(field);
        writer(cast(T[])`{ "class":"proxy"`);
        writer(cast(T[])`, "id":`)(objId)(" }");
    }
    /// write Struct
    override void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite,void *t){
        writeField(field);
        assert(metaInfo!is null);
        writer(cast(T[])`{ "class":"`)(metaInfo.className)(`"`);
        if (objId!=cast(objectId)0) writer(cast(T[])`, "id":`)(objId);
        ++depth;
        realWrite();
        --depth;
        writer(cast(T[])" }");
    }
    /// writes a core type
    override void writeCoreType(FieldMetaInfo *field, void delegate() realWrite,void *t){
        writeField(field);
        realWrite();
    }

    override void writeEndRoot() {
        writer.newline;
    }
}

class JsonUnserializer(T=char) : Unserializer {
    TextParser!(T) reader;
    alias T[] S;
    bool fieldRead;
    const Eof=TextParser!(T).Eof;
    
    this(FormattedReadHandlers!(T)h){
        super(h);
        this.reader=h.reader;
    }
    this(TextParser!(T)r){
        this(new FormattedReadHandlers!(T)(r));
    }
    this(InputStream s){
        this(new TextParser!(T)(s));
    }
    class FieldMismatchException:Exception{
        FieldMetaInfo *mismatchedField;
        char[] actualField;
        this(FieldMetaInfo *field,char[] actualField,char[]desc,char[]filename,long line){
            super(desc~" at "~convertToString!()(reader.parserPos()),filename,line);
            this.actualField=actualField;
            this.mismatchedField=mismatchedField;
        }
    }
    
    /// reads a field
    void readField(FieldMetaInfo *field){
        if(fieldRead){
            fieldRead=false;
        } else {
            if (field !is null){
                reader.skipString(cast(S)",",false);
                if (!reader.skipString2(cast(S)field.name,false)){
                    char[] fieldRead;
                    reader(fieldRead);
                    throw new FieldMismatchException(field,fieldRead,
                        "unexpected field",__FILE__,__LINE__);
                }
                reader.skipString(cast(S)":");
            }
        }
    }
    
    /// reads something that has a custom write operation
    override void readCustomField(FieldMetaInfo *field, void delegate()readOp){
        readField(field);
        readOp();
    }
    /// write a pointer (for debug purposes)
    override void readDebugPtr(FieldMetaInfo *field,void** o){
        readField(field);
        long l;
        reader(l);
    }
    /// reads the start of an array
    override PosCounter readArrayStart(FieldMetaInfo *field){
        readField(field);
        reader.skipString(cast(S)"[");
        return PosCounter(size_t.max);
    }
    /// reads an element of the array (or its end)
    /// returns true if an element was read
    override bool readArrayEl(ref PosCounter ac, void delegate() readEl) {
        if (ac.length==ac.pos) return false;
        if (ac.pos!=0 && !reader.skipString(cast(S)",",false)){
            if (reader.skipString(cast(S)"]",false)){
                ac.end;
                return false;
            } else {
                serializationError("error unserializing array",__FILE__,__LINE__);
            }
        } else if (ac.pos==0){
            if (reader.skipString(cast(S)"]",false)){
                ac.end;
                return false;
            }
        }
        ac.next();
        readEl();
        return true;
    }
    /// start of a dictionary
    override PosCounter readDictStart(FieldMetaInfo *field, bool stringKeys=false) {
        readField(field);
        auto res=PosCounter(size_t.max);
        res.data=Variant(stringKeys);
        reader.skipString(cast(S)"{");
        if (!reader.skipString2(cast(S)`class`,false)){
            reader.skipString(cast(S)":");
            if (stringKeys){
                reader.skipString2(cast(S)`dict`);
            } else {
                reader.skipString2(cast(S)`associativeArray`);
            }
        }
        return res;
    }
    /// reads an entry of the dictionary
    override bool readEntry(ref PosCounter ac, void delegate() readKey,void delegate() readVal) {
        if (ac.length==ac.pos) return false;
        if (ac.pos!=0 && !reader.skipString(cast(S)",",false)){
            if (reader.skipString(cast(S)"}",false)){
                ac.length=ac.pos;
                return false;
            } else {
                serializationError("error unserializing array",__FILE__,__LINE__);
            }
        } else if (ac.pos==0){
            if (reader.skipString(cast(S)"}",false)){
                ac.length=ac.pos;
                return false;
            }
        }
        if (ac.data.get!(bool)){
            readKey();
            reader.skipString(cast(S)":");
            readVal();
        } else {
            reader.skipString(cast(S)"{");
            reader.skipString2(cast(S)`key`);
            reader.skipString(cast(S)":");
            readKey();
            reader.skipString(cast(S)",");
            reader.skipString2(cast(S)`val`);
            reader.skipString(cast(S)":");
            readVal();
            reader.skipString(cast(S)"}");
        }
        return true;
    }
    /// scans for the id string
    size_t scanId(T[]data,SliceExtent se){
        size_t i=0;
        size_t l=data.length;
        for(;i!=l;++i){
            T c=data[i];
            if (!(c==' '||c=='\t'||c=='\r'||c=='\n')){
                break;
            }
        }
        if (i==l) return Eof;
        if (data[i]!=',') return 0;
        ++i;
        for(;i!=l;++i){
            T c=data[i];
            if (!(c==' '||c=='\t'||c=='\r'||c=='\n')){
                break;
            }
        }
        if (i==l) return Eof;
        T c=data[i];
        if (c=='"'){
            if (++i==l) return Eof;
            if (data[i]!='i') return 0;
            if (++i==l) return Eof;
            if (data[i]!='d') return 0;
            if (++i==l) return Eof;
            if (data[i]!='"') return 0;
        } else if (c=='i'){
            if (++i==l) return Eof;
            if (data[i]!='d') return 0;
        }
        ++i;
        for(;i!=l;++i){
            c=data[i];
            if (!(c==' '||c=='\t'||c=='\r'||c=='\n')){
                break;
            }
        }
        if (i==l) return Eof;
        if (data[i]!=':') return 0;
        return i+1;
    }
    /// reads a Proxy or null
    /// returns true if it did read a proxy (and did set t)
    override bool maybeReadProxy(FieldMetaInfo *field,ref ClassMetaInfo metaI, ref objectId oid, ref void *t){
        if (!reader.skipString(cast(S)"{",false)){
            if(!reader.skipString(cast(S)"null"),false) serializationError("maybeReadProxy failed",__FILE__,__LINE__);
            oid=cast(objectId)0;
            t=null;
            Stdout("pallino").newline;
            return true;
        }
        reader.skipString2(cast(S)"class");
        reader.skipString(cast(S)":");
        char[] className;
        reader(className);
        if (className=="proxy"||reader.check(&scanId)){
            reader.next(&scanId);
            long oidL;
            reader(oidL);
            oid=cast(objectId)oidL;
        }
        if (className=="proxy") {
            setPtrFromId(oid,t);
            return true;
        } else if (metaI is null || metaI.className!=className){
            metaI=SerializationRegistry().getMetaInfo(className);
            assert(metaI!is null,"could not find meta info for "~className);
        }
        return false;
    }
    /// reads the class of a serialized object and instantiate it
    /// called immediately after maybeReadProxy
    override Object readAndInstantiateClass(FieldMetaInfo *field, ref ClassMetaInfo metaI,
        ref objectId oid,Object o){
        return instantiateClass(metaI);
    }
    /// reads an object (called after readAndInstantiateClass)
    override void readObject(FieldMetaInfo *field, ClassMetaInfo metaInfo,void delegate() unserializeF,Object o){
        readStruct(field,metaInfo,unserializeF,cast(void*)o);
    }
    override void readStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo,void delegate() unserializeF,void *t){
        try{
            unserializeF();
            reader.skipString(cast(S)"}");
        } catch (FieldMismatchException e) {
            version(SerializationTrace) {
                Stdout("field mismatch, trying recovery by reading field "~
                    e.actualField).newline;
                scope(exit){
                    Stdout("field mismatch, finished recovery").newline;
                }
            }
            auto stackTop=top;
            stackTop.labelToRead=e.actualField;
            stackTop.setMissingLabels(e.mismatchedField);
            if (e.actualField==""){
                auto sep=reader.getSeparator();
                if (sep!="}"){
                    serializationError("no field and object not ended",__FILE__,__LINE__);
                }
                return;
            }
            fieldRead=true;
            while(1){
                if(!stackTop.missingLabels.remove(stackTop.labelToRead)){
                    serializationError("unexpected extra object field "~stackTop.labelToRead,
                        __FILE__,__LINE__);
                    // should try to skip it?
                }
                unserializeF();
                auto sep=reader.getSeparator();
                switch (sep){
                    case ",":
                        reader(stackTop.labelToRead);
                        fieldRead=true;
                        break;
                    case "}":
                        return;
                    default:
                        serializationError("unexpected separator in object unserialization '"~sep~"'",
                            __FILE__,__LINE__);
                }
            }
        }
    }
    /// reads a core type
    void readCoreType(FieldMetaInfo *field,void delegate() realRead){
        readField(field);
        realRead();
    }
}
