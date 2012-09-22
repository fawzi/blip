/// definition of the encoding independent string
///
/// author:fawzi
//
// Copyright 2010 the blip developer group
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
module blip.text.String;
import blip.text.StringConversions;
import blip.io.BasicIO;
import blip.Comp;

struct String{
    immutable(void)* ptr;
    size_t _l;
    enum Encoding:size_t{
	// currently this is also the bitshift for the type...
        Utf8=0,
        Utf16=1,
        Utf32=2,
    }
    template encodingOfT(T){
        static if(is(T==char)){
            alias Encoding.Utf8 encodingOfT;
        } else static if(is(T==wchar)){
            alias Encoding.Utf16 encodingOfT;
        } else static if(is(T==dchar)){
            alias Encoding.Utf32 encodingOfT;
        } else {
            static assert(0,"unknown encoding for type "~T.stringof);
        }
    }
    template TypeOfEncoding(size_t e){
        static if(e==Encoding.Utf8){
            alias char TypeOfEncoding;
        } else static if(e==Encoding.Utf16){
            alias wchar TypeOfEncoding;
        } else static if(Encoding.Utf32){
            alias dchar TypeOfEncoding;
        } else {
            static assert(0,"unknown encoding for type "~T.stringof);
        }
    }
    template BitshiftForT(T){
        static if(is(T==char)){
            enum :int{ BitshiftForT=0 }
        } else static if(is(T==wchar)){
            enum :int{ BitshiftForT=1 }
        } else static if(is(T==dchar)){
            enum :int{ BitshiftForT=2 }
        } else {
            static assert(0,"unknown encoding for type "~T.stringof);
        }
        
    }
    enum :size_t {
        MaskLen=((~cast(size_t)0)>>2)
    }
    enum :int {
        BitsLen=8*size_t.sizeof-2
    }
    /// encoding of this string
    @property int encodingId(){
        return cast(int)(_l>>BitsLen);
    }
    /// bit shift for the stored encoding (use the fact that bishift=encoding id)
    @property int encodingBitShift(){
	return cast(int)(_l>>BitsLen);
    }			    
    /// length of the string in bytes
    @property size_t byteLength(){
        return (_l & MaskLen);
    }
    /// length in charcter units (*not* utf codepoints)
    @property size_t cLength(){
	return (_l & MaskLen)>>encodingBitShift;
    }
    /// builds a string from encoded data
    this(immutable(char)[] s){
        assert((s.length&~MaskLen)==0);
        this.ptr=s.ptr;
        this._l=(Encoding.Utf8<<BitsLen)|s.length;
    }
    /// ditto
    this(immutable(wchar)[] s){
        assert((s.length&~(MaskLen>>1))==0);
        this.ptr=s.ptr;
        this._l=(Encoding.Utf16<<BitsLen)|(s.length>>1);
    }
    /// ditto
    this(immutable(dchar)[] s){
        assert((s.length&~(MaskLen>>2))==0);
        this.ptr=s.ptr;
        this._l=(Encoding.Utf32<<BitsLen)|(s.length>>2);
    }
    /// this string within a given encoding
    immutable(T)[] asStringT(T)(T[] buf=null){ // buf not used at the moment...
        auto e=encodingId();
        if (e==encodingOfT!(T)) {
            return (cast(immutable(T)*)ptr)[0..(cLength)];
        }
        switch (e){
        case Encoding.Utf8:
            return toStringT!(T)((cast(immutable(char)*)ptr)[0..cLength]);
        case Encoding.Utf16:
            return toStringT!(T)((cast(immutable(wchar)*)ptr)[0..cLength]);
        case Encoding.Utf32:
            return toStringT!(T)((cast(immutable(dchar)*)ptr)[0..cLength]);
        default:
            assert(0,"unknown encoding for type "~T.stringof);
        }
        
    }
    /// utility internal casting (use only if you know the encoding to be T)
    immutable(T)[] asT(T)(){
        assert(encodingOfT!(T)==encodingOfT);
        return (cast(T*)ptr)[0..(byteLength>>BitshiftForT!(T))];
    }
    /// sinks the string in the requested encoding
    void sinkTo(T)(T sink){
        switch(encodingId){
        case Encoding.Utf8:
            writeOut(sink,asT!(char)());
            break;
        case Encoding.Utf16:
            writeOut(sink,asT!(wchar)());
            break;
        case Encoding.Utf32:
            writeOut(sink,asT!(dchar)());
            break;
        default:
            throw new Exception("unexpected encoding",__FILE__,__LINE__);
        }
    }
    /// description (used when passing this to a dumper)
    void desc(scope void delegate(in cstring) sink){
        sink(asStringT!(char));
    }
    /// ditto
    void desc(scope void delegate(in cstringw) sink){
        sink(asStringT!(wchar));
    }
    /// ditto
    void desc(scope void delegate(in cstringd) sink){
        sink(asStringT!(dchar));
    }
    // implement common python/java/obj-c string ops
    // indexing: define two indexing types? codepoint,native?
    
}
