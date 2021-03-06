/// serialization to/from Json format
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
module blip.serialization.JsonSerialization;
import blip.serialization.SerializationBase;
import blip.serialization.Handlers;
import blip.io.Console;
import tango.io.model.IConduit:IOStream;
import blip.core.Boxer;
import blip.BasicModels;
import blip.text.TextParser;
import blip.text.UtfUtils;
import blip.container.GrowableArray;
import blip.io.BasicIO;
import blip.io.StreamConverters;
import blip.Comp;

class JsonSerializer(T=char) : Serializer {
    int depth;
    long writeCount,lineCount;
    bool atStart;
    bool compact; // skips class, id when possible
    const T[1] nline=[cast(T)'\n'];
    Dumper!(void delegate(cstring)) s; // quick dump of strings
    /// writes a newline
    void newline(){
        handlers.rawWriteStr(nline);
    }

    /// constructor using a wispered sink delegate
    this(string dsc,Dumper!(void delegate(T[])) sink){
        this(dsc,sink.call);
    }
    /// constructor using a sink delegate
    this(string dsc,void delegate(T[])sink){
        this(new FormattedWriteHandlers!(T)(dsc,sink));
    }
    /// constructor using a sink delegate
    this(OutWriter dsc,void delegate(T[])sink){
        this(new FormattedWriteHandlers!(T)(dsc,sink));
    }
    /// constructor using an OutStreamI (or a WriteHandlers)
    this(OutStreamI s){
        WriteHandlers w=cast(WriteHandlers)cast(Object)s;
        if (w is null){
            w=new FormattedWriteHandlers!(T)(s);
        }
        super(w);
        this.s=dumper(handlers.charSink());
        writeCount=0;
        atStart=true;
        compact=true;
    }
    /// indents the output
    void indent(int amount){
        T[20] str;
        str[]=' ';
        amount=2*amount;
        while(amount>0){
            auto toAdd=((amount>20)?20:amount);
            handlers.rawWriteStr(str[0..toAdd]);
            amount-=toAdd;
        }
    }
    void writeField(FieldMetaInfo *field){
        ++writeCount;
        if (field !is null && (!field.pseudo)){
            if (!atStart) {
                handlers.rawWriteStr([cast(T)',']);
                atStart=false;
            }
            newline;
            ++lineCount;
            indent(depth);
            s(field.name);
            handlers.rawWriteStr([cast(T)':']);
        }
    }
    /// writes something that has a custom write operation
    override void writeCustomField(FieldMetaInfo *field, void delegate()writeOp){
        writeField(field);
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
        s("null");
    }
    /// writes the start of an array of the given size
    override PosCounter writeArrayStart(FieldMetaInfo *field,ulong size){
        atStart=true;
        writeField(field);
        handlers.rawWriteStr([cast(T)'[']);
        ++depth;
        if (size>6){
            newline;
            indent(depth);
        }
        return PosCounter(size);
    }
    /// writes a separator of the array
    override void writeArrayEl(ref PosCounter ac, void delegate() writeEl) {
        if (ac.pos==0){
            ac.data=box(writeCount+10*lineCount);
        } else if (ac.pos==1){
            auto diff=writeCount+10*lineCount-unbox!(long)(ac.data);
            auto newlineEach=20L/(++diff);
            if (newlineEach>8) newlineEach=8;
            else if (newlineEach<1) newlineEach=1;
            ac.data=box(cast(int)newlineEach);
        }
        if (ac.pos>0){
            handlers.rawWriteStr([cast(T)',',' ']);
            if (ac.pos % unbox!(int)(ac.data) ==0) {  /// wrap lines
                newline;
                indent(depth);
            }
        }
        ac.next();
        writeEl();
        ++writeCount;
        atStart=false;
    }
    /// writes the end of the array
    override void writeArrayEnd(ref PosCounter ac) {
        ac.end();
        handlers.rawWriteStr([cast(T)']']);
        --depth;
    }
    /// start of a dictionary
    override PosCounter writeDictStart(FieldMetaInfo *field,ulong l, bool stringKeys=false) {
        writeField(field);
        if (compact){
            handlers.rawWriteStr([cast(T)'{']);
            atStart=true;
        } else {
            if (stringKeys)
                s(`{ class:"dict"`);
            else
                s(`{ class:"associativeArray"`);
            atStart=false;
        }
        auto res=PosCounter(l);
        res.data=box(stringKeys);
        ++depth;
        return res;
    }
    /// writes an entry of the dictionary
    override void writeEntry(ref PosCounter ac, void delegate() writeKey,void delegate() writeVal) {
        if (!atStart) handlers.rawWriteStr([cast(T)',']);
        newline;
        ac.next();
        indent(depth);
        ++depth;
        if (unbox!(bool)(ac.data)){
            writeKey();
            handlers.rawWriteStr([cast(T)':']);
            writeVal();
        } else {
            s(`{ key:`);
            writeKey();
            s(",\n");
            indent(depth-1);
            s(`  val:`);
            writeVal();
            handlers.rawWriteStr([cast(T)'}']);
        }
        --depth;
        ++writeCount;
        atStart=false;
    }
    /// end of dictionary
    override void writeDictEnd(ref PosCounter ac) {
        ac.end();
        --depth;
        if (ac.pos>0) {
            newline;
            indent(depth);
        }
        handlers.rawWriteStr([cast(T)'}']);
    }
    /// writes an Object
    override void writeObject(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        bool isSubclass,void delegate() realWrite, Object o)
    {
        writeField(field);
        assert(metaInfo!is null);
        if (compact && !isSubclass){
            handlers.rawWriteStr([cast(T)'{']);
            if (objId!=cast(objectId)0){
                s(" id:")(cast(long)objId);
                atStart=false;
            } else {
                atStart=true;
            }
        } else {
            s(`{ class:"`)(metaInfo.className)("\"");
            s(`, id:`)(cast(long)objId);
            atStart=false;
        }
        ++depth;
        realWrite();
        --depth;
        newline;
        indent(depth);
        s("}");
    }
    /// write ObjectProxy
    override void writeProxy(FieldMetaInfo *field, objectId objId){
        writeField(field);
        s(`{ class:"proxy"`);
        s(`, id:`)(cast(long)objId)("}");
    }
    /// write Struct
    override void writeStruct(FieldMetaInfo *field, ClassMetaInfo metaInfo, objectId objId,
        void delegate() realWrite,void *t){
        writeField(field);
        assert(metaInfo!is null);
        if (compact) {
            handlers.rawWriteStr(cast(T[])`{`);
            if (objId!=cast(objectId)0) {
                s(` "id":`)(cast(long)objId);
                atStart=false;
            } else {
                atStart=true;
            }
        } else {
            s(`{ class:"`)(metaInfo.className)(`"`);
            if (objId!=cast(objectId)0) s(`, "id":`)(cast(long)objId);
            atStart=false;
        }
        ++depth;
        realWrite();
        --depth;
        newline;
        indent(depth);
        s("}");
    }
    /// writes a core type
    override void writeCoreType(FieldMetaInfo *field, void delegate() realWrite,void *t){
        writeField(field);
        realWrite();
    }

    override void writeEndRoot() {
        newline;
    }
    override void writeTupleSpacer() {
        s(" ");
    }
    
    override void writeProtocolVersion(){
        s("BLIP_JSON_1.0\n");
    }
}


class JsonUnserializer(T=char) : Unserializer {
    TextParser!(T) reader;
    alias T[] S;
    bool fieldRead;
    bool sloppyCommas;
    const Eof=TextParser!(T).Eof;
    
    this(FormattedReadHandlers!(T)h){
        super(h);
        this.reader=h.reader;
        this.sloppyCommas=false;
    }
    this(TextParser!(T)r){
        this(new FormattedReadHandlers!(T)(r));
    }
    this(Reader!(T) s){
        this(new TextParser!(T)(s));
    }
    static class FieldMismatchException:Exception{
        FieldMetaInfo *mismatchedField;
        string actualField;
        this(FieldMetaInfo *mismatchedField,string actualField,string desc,string filename,long line){
            super(desc,filename,line);
            this.actualField=actualField;
            this.mismatchedField=mismatchedField;
        }
    }
    
    /// reads a field
    void readField(FieldMetaInfo *field){
        if(this.fieldRead){
            this.fieldRead=false;
        } else {
            if (field !is null && (!field.pseudo)){
                this.reader.skipString(cast(S)",",false);
                if (!this.reader.skipString2(cast(S)field.name,false)){
                    string fieldReadName;
                    this.reader(fieldReadName);
                    if (fieldReadName.length>0)
                        this.reader.skipString(cast(S)":");
                    throw new FieldMismatchException(field,fieldReadName,
                        collectAppender(delegate void(CharSink s){
                            dumper(s)("unexpected field '")(fieldReadName)("' at "); this.reader.parserPos(s);
                        }),__FILE__,__LINE__);
                }
                this.reader.skipString(cast(S)":");
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
        return PosCounter(ulong.max);
    }
    /// reads an element of the array (or its end)
    /// returns true if an element was read
    override bool readArrayEl(ref PosCounter ac, void delegate() readEl) {
        if (ac.length==ac.pos) return false;
        if (sloppyCommas){
            reader.skipString(cast(S)",",false);
            if (reader.skipString(cast(S)"]",false)){
                ac.end;
                return false;
            }
        } else if (ac.pos!=0 && (!reader.skipString(cast(S)",",false))){
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
        auto res=PosCounter(ulong.max);
        res.data=box(stringKeys);
        reader.skipString(cast(S)"{");
        if (reader.skipString2(cast(S)`class`,false)){
            reader.skipString(cast(S)":");
            if (stringKeys){
                reader.skipString2(cast(S)`dict`);
            } else {
                reader.skipString2(cast(S)`associativeArray`);
            }
        }
        if (reader.check(&scanId)){ // discarded, present for consistency
            reader.next(&scanId);
            long oidL;
            reader(oidL);
        }
        return res;
    }
    /// reads an entry of the dictionary
    override bool readEntry(ref PosCounter ac, void delegate() readKey,void delegate() readVal) {
        if (ac.length==ac.pos) {
            ac.end;
            return false;
        }
        if (((!reader.skipString(cast(S)",",false))||sloppyCommas)){
            if (reader.skipString(cast(S)"}",false)){
                ac.end;
                return false;
            }
        }
        ac.next;
        if (unbox!(bool)(ac.data)){
            readKey();
            reader.skipString(cast(S)":");
            readVal();
        } else {
            reader.skipString(cast(S)"{");
            reader.skipString2(cast(S)`key`);
            reader.skipString(cast(S)":");
            readKey();
            reader.skipString(cast(S)",",false);
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
        if (data[i]==',') ++i;
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
        } else return 0;
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
        readField(field);
        if (!reader.skipString(cast(S)"{",false)){
            if(!reader.skipString(cast(S)"null",false)) serializationError("maybeReadProxy failed",__FILE__,__LINE__);
            oid=cast(objectId)0;
            t=null;
            return true;
        }
        if (reader.skipString2(cast(S)"class",false)){
            reader.skipString(cast(S)":");
            string className;
            reader(className);
            if (className=="proxy"||reader.check(&scanId)){
                reader.next(&scanId);
                long oidL;
                reader(oidL);
                oid=cast(objectId)oidL;
            }
            if (className=="proxy") {
                setPtrFromId(oid,t);
                reader.skipString(cast(S)"}");
                return true;
            } else if (metaI is null || metaI.className!=className){
                metaI=SerializationRegistry().getMetaInfo(className);
                assert(metaI!is null,"could not find meta info for '"~className~"'");
            }
        } else if (reader.skipString2("id",false)){
            reader.skipString(":");
            long oidL;
            reader(oidL);
            oid=cast(objectId)oidL;
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
            version(UnserializationTrace) {
                sout("field mismatch, trying recovery by reading field "~
                    e.actualField~"\n");
                scope(exit){
                    sout("field mismatch, finished recovery\n");
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
            while(1){
                if(!stackTop.missingLabels.remove(stackTop.labelToRead)){
                    serializationError(collectAppender(delegate void(CharSink sink){ auto s=dumper(sink);
                        s("unexpected extra object field '")(stackTop.labelToRead)("'");
                        if (field !is null){
                            if (field.name.length!=0)
                                s(" in '")(field.name)("'");
                            if (field.metaInfo !is null && field.metaInfo.className.length!=0){
                                if (field.name.length==0)
                                    s(" in element ");
                                s(" of type ")(field.metaInfo.className);
                            }
                        }
                        s(", known fields of ")(metaInfo.className)(":");
                        bool first=true;
                        foreach (f;metaInfo){
                            if (!f.pseudo){
                                if (!first) s(",");
                                first=false;
                                s("'")(f.name)("'");
                            }
                        }
                    }),__FILE__,__LINE__);
                    // should try to skip it?
                }
                fieldRead=true;
                unserializeF();
                auto sep=reader.getSeparator();
                stackTop=top; // might have been reallocated
                switch (sep){
                    case ",":
                        if (sloppyCommas) reader.getSeparator();
                    case "":
                        if ((!sloppyCommas) &&  sep!=",")
                            serializationError("expected ',' or '}'",__FILE__,__LINE__);
                        reader(stackTop.labelToRead);
                        if (stackTop.labelToRead.length==0) serializationError("empty label name",
                            __FILE__,__LINE__);
                        reader.skipString(cast(S)":");
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
    /// utility method that throws an exception
    /// override this to give more info on parser position,...
    /// this method *has* to throw
    override void serializationError(string msg,string filename,long line,Exception next=null){
        reader.parseError(msg,filename,line,next);
    }
    
    override bool readProtocolVersion(){
        return reader.skipString("BLIP_JSON_1.0",false);
    }
    
}
