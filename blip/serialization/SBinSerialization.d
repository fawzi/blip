/// serialization to/from Json format
module blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import blip.serialization.Handlers;
import tango.io.Stdout : Stdout;
import tango.io.stream.Format;
import tango.io.model.IConduit:IOStream;
import tango.core.Variant;
import blip.BasicModels;
import blip.text.TextParser;

class SBinSerializer : Serializer {
    long[MetaInfo] writtenMetaInfo;
    int depth;
    uint lastMetaId;
    bool compact; // skips meta info
    BinaryWriteHandlers writer;
    void writeCompressed(T)(T l){
        while (1){
            ubyte u=cast(ubyte)(l & 0x7FFF);
            l=>>7;
            if (l!=0){
                writer.handle(u|0x8000);
            } else {
                writer.handle(u);
                break;
            }
        }
    }
    void writeMetaInfo(ClassMetaInfo metaInfo){
        writer.handle(metaInfo.className);
        writeCompressed(metaInfo.nTotFields);
        if (compact){
            writeCompressed(0);
        } else {
            writeCompressed(1);
            foreach(f;metaInfo){
                writer.handle(f.name);
                writeCompressed((f.metaInfo)?cast(uint)f.metaInfo.kind:0u);
            }
        }
    }
    this(BinaryWriteHandlers w){
        super(w);
        writer=w;
        lastMetaId=3; // 0: null, 1: default type, 2: proxy, 3: metaInfo
        compact=true;
    }
    void writeField(FieldMetaInfo *field){ }
    /// writes something that has a custom write operation
    override void writeCustomField(FieldMetaInfo *field, void delegate()writeOp){
        writeField(field);
        writeOp();
    }
    /// write a pointer (for debug purposes)
    override void writeDebugPtr(FieldMetaInfo *field,void* o){
        ulong u=cast(ulong)cast(size_t)o;
        handlers.handle(u);
    }
    /// null object
    override void writeNull(FieldMetaInfo *field) {
        writeField(field);
        writeCompressed(0u);
    }
    /// writes the start of an array of the given size
    override PosCounter writeArrayStart(FieldMetaInfo *field,size_t size){
        writeField(field);
        if (size==size_t.max){
            ulong lSize=ulong.max;
            writeCompressed(lSize);
        } else {
            ulong lSize;
            writeCompressed(lSize);
        }
        return PosCounter(size);
    }
    /// writes a separator of the array
    override void writeArrayEl(ref PosCounter ac, void delegate() writeEl) {
        if (ac.length==size_t.max){
            writeCompressed(1u);
        }
        ac.next();
        writeEl();
    }
    /// writes the end of the array
    override void writeArrayEnd(ref PosCounter ac) {
        if (ac.length==size_t.max){
            writeCompressed(0u);
        }
        ac.end();
    }
    /// start of a dictionary
    override PosCounter writeDictStart(FieldMetaInfo *field,size_t length, bool stringKeys=false) {
        writeField(field);
        if (size==size_t.max){
            long lSize=long.max;
            writeCompressed(lSize);
        } else {
            long lSize;
            writeCompressed(lSize);
        }
        return PosCounter(size);
    }
    /// writes an entry of the dictionary
    override void writeEntry(ref PosCounter ac, void delegate() writeKey,void delegate() writeVal) {
        if (ac.length==size_t.max){
            writeCompressed(1);
        }
        ac.next();
        writeKey();
        writeVal();
    }
    /// end of dictionary
    override void writeDictEnd(ref PosCounter ac) {
        if (ac.length==size_t.max){
            writeCompressed(0);
        }
        ac.end();
    }
    /// writes an Object
    override void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        bool isSubclass,void delegate() realWrite, Object o){
        writeField(field);
        assert(metaInfo!is null);
        uint metaId=1;
        if (compact && !isSubclass){
            writeCompressed(metaId);
        } else {
            auto metaIdPtr= metaInfo in writtenMetaInfo;
            if (metaIdPtr is null){
                metaId=++lastMetaId;
                writtenMetaInfo[metaInfo]=metaId;
                writeCompressed(3);
                writeCompressed(metaId);
                writeMI(metaInfo);
            } else {
                writeCompressed(*metaIdPtr);
            }
        }
        ulong oid=cast(ulong)objId
        writeCompressed(oid)
        realWrite();
    }
    /// write ObjectProxy
    override void writeProxy(FieldMetaInfo *field, objectId objId){
        writeField(field);
        writeCompressed(2u);
        writeCompressed(cast(ulong)objId);
    }
    /// write Struct
    override void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite,void *t){
        uint metaId=1;
        if (compact){
            writeCompressed(metaId);
        } else {
            auto metaIdPtr= metaInfo in writtenMetaInfo;
            if (metaIdPtr is null){
                metaId=++lastMetaId;
                writtenMetaInfo[metaInfo]=metaId;
                writeCompressed(3u);
                writeCompressed(metaId);
                writeMI(metaInfo);
            } else {
                writeCompressed(*metaIdPtr);
            }
        }
        ulong oid=cast(ulong)objId
        writeCompressed(oid)
        realWrite();
    }
    /// writes a core type
    override void writeCoreType(FieldMetaInfo *field, void delegate() realWrite,void *t){
        writeField(field);
        realWrite();
    }

    override void writeEndRoot() {
        writer.handle(0xdeadbeef);
    }
    
    override void writeProtocolVersion(){
        writer.handle("BLIP_SBIN_1.0");
    }
}

class SBinUnserializer(T=char) : Unserializer {
    BinaryReadHandlers reader;
    MetaInfo[uint] _readMetaInfo;
    alias T[] S;
    bool fieldRead;
    const Eof=TextParser!(T).Eof;
    
    void readCompressed(T)(T l){
        l=cast(T)0;
        int cont=1;
        while (1){
            ubyte u;
            reader.handle(u)
            u=cast(ubyte);
            l=(l<<7)|(u & 0x7FFF);
            if (!(u&0x8000)) break;
        }
    }
    ClassMetaInfo readMetaInfo(){
        char[] className;
        reader.handle(className);
        ClassMetaInfo metaInfo=SerializationRegistry().getMetaInfo(className);
        if (metaInfo is null)
            serializationError("meta info for class named "~className~" not found",__FILE__,__LINE__);
        uint nTotFields;
        readCompressed(nTotFields);
        if (nTotFields!=metaInfo.nTotFields()){
            serializationError("meta info different from expected, recovery not implemented",&
                __FILE__,__LINE__);
        }
        uint cont;
        readCompressed(cont);
        if (cont){
            foreach(f;metaInfo){
                char[]fName;
                reader.handle(fName);
                uint kind;
                readCompressed(kind);
                if (f.name!=fName || ((f.metaInfo)?cast(uint)f.metaInfo.kind:0u)!=kind){
                    throw new FieldMismatchException(f,fName," mismatched field in binary unserializing",
                        __FILE__,__LINE__);
                }
            }
        }
    }
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
        this(FieldMetaInfo *mismatchedField,char[] actualField,char[]desc,char[]filename,long line){
            super(desc~" at "~convertToString!()(reader.parserPos()),filename,line);
            this.actualField=actualField;
            this.mismatchedField=mismatchedField;
        }
    }
    
    /// reads a field
    void readField(FieldMetaInfo *field){ }
    
    /// reads something that has a custom write operation
    override void readCustomField(FieldMetaInfo *field, void delegate()readOp){
        readField(field);
        readOp();
    }
    /// write a pointer (for debug purposes)
    override void readDebugPtr(FieldMetaInfo *field,void** o){
        readField(field);
        ulong l;
        reader(l);
    }
    /// reads the start of an array
    override PosCounter readArrayStart(FieldMetaInfo *field){
        readField(field);
        ulong lSize;
        readCompressed(lSize);
        size_t size;
        if (lSize==ulong.max){
            size=size_t.max;
        } else if (lSize>=size_t.max){
            serializationError("trying to decode an array too large for 32 bit representation",__FILE__,__LINE__);
        else {
            size=cast(size_t)lSize;
        }
        return PosCounter(size);
    }
    /// reads an element of the array (or its end)
    /// returns true if an element was read
    override bool readArrayEl(ref PosCounter ac, void delegate() readEl) {
        if (ac.length==ac.pos) {
            ac.end;
            return false;
        }
        if (ac.length==size_t.max){
            ulong cont;
            readCompressed(cont);
            if (cont==0){
                ac.end;
                return false;
            } else {
                assert(cont==1,"error unserializing array");
            }
        }
        ac.next();
        readEl();
        return true;
    }
    /// start of a dictionary
    override PosCounter readDictStart(FieldMetaInfo *field, bool stringKeys=false) {
        readField(field);
        ulong lSize;
        size_t size;
        readCompressed(lSize);
        if (lSize==ulong.max){
            size=size_t.max;
        } else if (lSize>=size_t.max){
            serializationError("trying to decode an array too large for 32 bit representation",__FILE__,__LINE__);
        } else {
            size=cast(size_t)lSize;
        }
        auto res=PosCounter(size);
        return res;
    }
    /// reads an entry of the dictionary
    override bool readEntry(ref PosCounter ac, void delegate() readKey,void delegate() readVal) {
        if (ac.length==ac.pos) {
            ac.end;
            return false;
        }
        if (ac.length==size_t.max){
            uint cont;
            readCompressed(cont);
            if (cont==0) {
                ac.end;
                return false;
            }
            assert(cont==1,"error in dictionary continuation");
        }
        ac.next();
        readKey();
        readVal();
        return true;
    }
    /// reads a Proxy or null
    /// returns true if it did read a proxy (and did set t)
    override bool maybeReadProxy(FieldMetaInfo *field,ref ClassMetaInfo metaI, ref objectId oid, ref void *t){
        readField(field);
        uint classId;
        readCompressed(classId);
        switch (classId){
        case 0:
            t=null;
            oid=cast(objectId)0;
            return true;
        case 2:
            ulong oidL;
            readCompressed(oidL);
            oid=cast(objectId)oidL;
            setPtrFromId(oid,t);
            return true;
        case 1:
            assert(metaI!is null,"metaI is null and default type");
            break;
        case 3:
            metaI=readMetaInfo();
            break;
        default:
            metaI=_readMetaInfo[classId];
            if (metaI is null){
                serializationError("could not find previously read metaInfo",
                    __FILE__,__LINE__);
            }
        }
        ulong oidL;
        readCompressed(oidL);
        oid=cast(objectId)oidL;
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
        unserializeF();
    }
    /// reads a core type
    void readCoreType(FieldMetaInfo *field,void delegate() realRead){
        readField(field);
        realRead();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    override void serializationError(char[]msg,char[]filename,long line){
        reader.parseError(msg,filename,line);
    }
    
    override bool readProtocolVersion(){
        return reader.skipString("BLIP_JSON_1.0",false);
    }
    
}
