/// serialization to/from a simple sequential binary format
/// (useful to transmit to other processes/computers)
///
/// author: fawzi
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.serialization.SBinSerialization;
import blip.serialization.SerializationBase;
import blip.serialization.Handlers;
import blip.core.Variant;
import blip.BasicModels;
import blip.text.TextParser;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.Comp;

class SBinSerializer : Serializer {
    uint[void*] writtenMetaInfo;
    int depth;
    uint lastMetaId;
    bool compact; // skips meta info
    WriteHandlers writer;
    override void resetObjIdCounter(){
        lastMetaId=3;
        writtenMetaInfo=null; // avoid this?
        super.resetObjIdCounter();
    }
    
    void writeCompressed(T)(T l){
        while (1){
            ubyte u=cast(ubyte)(l & 0x7F);
            l=l>>7;
            if (l!=0){
                ubyte u2=u|0x80;
                writer.handle(u2);
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
    this(OutStreamI s){
        WriteHandlers w=cast(WriteHandlers)cast(Object)s;
        if (w is null){
            w=new BinaryWriteHandlers!()(s);
        }
        super(w);
        writer=w;
        lastMetaId=3; // 0: null, 1: default type, 2: proxy, 3: metaInfo
        compact=true;
    }
    this(string desc,void delegate(in void[]) s){
        this(new BinaryWriteHandlers!()(desc,s));
    }
    this(OutWriter desc,void delegate(in void[]) s){
        this(new BinaryWriteHandlers!()(desc,s));
    }
    void writeField(FieldMetaInfo *field){ }
    /// writes something that has a custom write operation
    override void writeCustomField(FieldMetaInfo *field, scope void delegate()writeOp){
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
    override PosCounter writeArrayStart(FieldMetaInfo *field,ulong l){
        writeField(field);
        writeCompressed(l);
        return PosCounter(l);
    }
    /// writes a separator of the array
    override void writeArrayEl(ref PosCounter ac, scope void delegate() writeEl) {
        if (ac.length==ulong.max){
            writeCompressed(1u);
        }
        ac.next();
        writeEl();
    }
    /// writes the end of the array
    override void writeArrayEnd(ref PosCounter ac) {
        if (ac.length==ulong.max){
            writeCompressed(0u);
        }
        ac.end();
    }
    /// start of a dictionary
    override PosCounter writeDictStart(FieldMetaInfo *field,ulong l, bool stringKeys=false) {
        writeField(field);
        writeCompressed(l);
        return PosCounter(l);
    }
    /// writes an entry of the dictionary
    override void writeEntry(ref PosCounter ac, scope void delegate() writeKey,scope void delegate() writeVal) {
        if (ac.length==ulong.max){
            writeCompressed(1u);
        }
        ac.next();
        writeKey();
        writeVal();
    }
    /// end of dictionary
    override void writeDictEnd(ref PosCounter ac) {
        if (ac.length==ulong.max){
            writeCompressed(0);
        }
        ac.end();
    }
    /// writes an Object
    override void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        bool isSubclass,scope void delegate() realWrite, Object o){
        writeField(field);
        assert(metaInfo!is null);
        uint metaId=1;
        if (compact && !isSubclass){
            writeCompressed(metaId);
        } else {
            auto metaIdPtr= (cast(void*)metaInfo) in writtenMetaInfo;
            if (metaIdPtr is null){
                metaId=++lastMetaId;
                writtenMetaInfo[cast(void*)metaInfo]=metaId;
                writeCompressed(3);
                writeCompressed(metaId);
                writeMetaInfo(metaInfo);
            } else {
                writeCompressed(*metaIdPtr);
            }
        }
        ulong oid=cast(ulong)objId;
        writeCompressed(oid);
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
	scope void delegate() realWrite,const(void) *t){
        uint metaId=1;
        if (compact){
            writeCompressed(metaId);
        } else {
            auto metaIdPtr= cast(void*)metaInfo in writtenMetaInfo;
            if (metaIdPtr is null){
                metaId=++lastMetaId;
                writtenMetaInfo[cast(void*)metaInfo]=metaId;
                writeCompressed(3u);
                writeCompressed(metaId);
                writeMetaInfo(metaInfo);
            } else {
                writeCompressed(*metaIdPtr);
            }
        }
        ulong oid=cast(ulong)objId;
        writeCompressed(oid);
        realWrite();
    }
    /// writes a core type
    override void writeCoreType(FieldMetaInfo *field, scope void delegate() realWrite,void *t){
        writeField(field);
        realWrite();
    }

    override void writeEndRoot() {
        uint l=0xdeadbeef;
        writer.handle(l);
    }
    
    override void writeProtocolVersion(){
        string s="BLIP_SBIN_1.0";
        writer.handle(s);
    }
}

class SBinUnserializer: Unserializer {
    ReadHandlers reader;
    ClassMetaInfo[uint] _readMetaInfo;
    uint lastMetaId;
    bool fieldRead;
    
    override void readEndRoot() {
        uint l;
        reader.handle(l);
        if (l!=0xdeadbeef){
            serializationError(collectIAppender(delegate void(scope CharSink s){
                    dumper(s)("readEndRoot found ")(l)(" instead of 0xdeadbeef, binary stream is likely to be garbled");
                }),__FILE__,__LINE__);
        }
    }
    override void resetObjIdCounter(){
        lastMetaId=3;
        _readMetaInfo=null; // avoid this?
        super.resetObjIdCounter();
    }
    void readCompressed(T)(ref T l){
        l=0;
        for (int i=0;i<T.sizeof*8;i+=7){
            ubyte u;
            reader.handle(u);
            l=l|((cast(T)(u & 0x7F))<<i);
            if ((u & 0x80) == 0) break;
        }
    }
    ClassMetaInfo readMetaInfo(){
        string className;
        reader.handle(className);
        ClassMetaInfo metaInfo=SerializationRegistry().getMetaInfo(className);
        if (metaInfo is null)
            serializationError("meta info for class named "~className~" not found",__FILE__,__LINE__);
        uint nTotFields;
        readCompressed(nTotFields);
        if (nTotFields!=metaInfo.nTotFields()){
            serializationError("meta info different from expected, recovery not implemented",
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
        return metaInfo;
    }
    this(ReadHandlers h){
        super(h);
        this.reader=h;
        lastMetaId=3;
    }
    this(Reader!(void) s){
        this(new BinaryReadHandlers!()(s));
    }
    this(void delegate(void[])readExact){
        this(new BinaryReadHandlers!()(readExact));
    }
    class FieldMismatchException:Exception{
        FieldMetaInfo *mismatchedField;
        string actualField;
        this(FieldMetaInfo *mismatchedField,string actualField,string desc,string filename,long line){
            super(collectIAppender(delegate void(scope CharSink s){ s(desc); s(" at "); reader.parserPos(s); }),filename,line);
            this.actualField=actualField;
            this.mismatchedField=mismatchedField;
        }
    }
    
    /// reads a field
    void readField(FieldMetaInfo *field){ }
    
    /// reads something that has a custom write operation
    override void readCustomField(FieldMetaInfo *field, scope void delegate()readOp){
        readField(field);
        readOp();
    }
    /// write a pointer (for debug purposes)
    override void readDebugPtr(FieldMetaInfo *field,void** o){
        readField(field);
        ulong l;
        reader.handle(l);
    }
    /// reads the start of an array
    override PosCounter readArrayStart(FieldMetaInfo *field){
        readField(field);
        ulong lSize;
        readCompressed(lSize);
        ulong size;
        if (lSize==ulong.max){
            size=ulong.max;
        } else if (lSize>=size_t.max){
            serializationError("trying to decode an array too large for 32 bit representation",__FILE__,__LINE__);
        } else {
            size=lSize;
        }
        return PosCounter(size);
    }
    /// reads an element of the array (or its end)
    /// returns true if an element was read
    override bool readArrayEl(ref PosCounter ac, scope void delegate() readEl) {
        if (ac.length==ac.pos) {
            ac.end;
            return false;
        }
        if (ac.length==ulong.max){
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
        ulong size;
        readCompressed(lSize);
        if (lSize==ulong.max){
            size=ulong.max;
        } else if (lSize>=size_t.max){
            serializationError("trying to decode an array too large for 32 bit representation",__FILE__,__LINE__);
        } else {
            size=cast(size_t)lSize;
        }
        auto res=PosCounter(size);
        return res;
    }
    /// reads an entry of the dictionary
    override bool readEntry(ref PosCounter ac, scope void delegate() readKey,scope void delegate() readVal) {
        if (ac.length==ac.pos) {
            ac.end;
            return false;
        }
        if (ac.length==ulong.max){
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
            break;
        case 3:
            uint newId;
            readCompressed(newId);
            ++lastMetaId;
            assert(lastMetaId==newId,"wrongly counted meta info ids");
            metaI=readMetaInfo();
            _readMetaInfo[newId]=metaI;
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
    override void readObject(FieldMetaInfo *field, ClassMetaInfo metaInfo,scope void delegate() unserializeF,Object o){
        readStruct(field,metaInfo,unserializeF,cast(void*)o);
    }
    override void readStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo,scope void delegate() unserializeF,void *t){
        unserializeF();
    }
    /// reads a core type
    void readCoreType(FieldMetaInfo *field,scope void delegate() realRead){
        readField(field);
        realRead();
    }
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    override void serializationError(string msg,string filename,long line,Exception e=null){
        throw new SerializationException(msg,collectIAppender(&reader.parserPos),filename,line,e);
    }
    /// returns true if this is the SBIN protocol, otherwise throws
    override bool readProtocolVersion(){
        return reader.skipString("BLIP_SBIN_1.0",false);
    }
    
}
