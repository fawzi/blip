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

struct String{
    void* ptr;
    size_t _l;
    enum Encoding:size_t{
        Utf8,
        Utf16,
        Utf32,
    }
    template encodingOfT(T){
        static if(is(T==char)){
            alias Encoding.Utf8 encodingOfT;
        } else static if(is(T==wchar)){
            alias Encoding.Utf16 encodingOfT;
        } else static if(is(T==wchar)){
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
        } else static if(is(T==wchar)){
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
    /// length of the string in bytes
    size_t len(){
        return (_l & MaskLen);
    }
    size_t encodingId(){
        return cast(int)(_l>>BitsLen);
    }
    
    static String opCall(char[] s){
        assert((s.length&~MaskLen)==0);
        String res;
        res.ptr=s.ptr;
        res._l=(Encoding.Utf8<<BitsLen)|s.length;
        return res;
    }
    static String opCall(wchar[] s){
        assert((s.length&~(MaskLen>>1))==0);
        String res;
        res.ptr=s.ptr;
        res._l=(Encoding.Utf16<<BitsLen)|(s.length>>1);
        return res;
    }
    static String opCall(char[] s){
        assert((s.length&~(MaskLen>>2))==0);
        String res;
        res.ptr=s.ptr;
        res._l=(Encoding.Utf32<<BitsLen)|(s.length>>2);
        return res;
    }
    T[] asStringT(T)(T[] buf=null){ // buf not used at the moment...
        auto e=encodingId();
        if (e==encodingOfT!(T)) {
            return (cast(T*)ptr)[0..(len>>BitshiftForT!(T))];
        }
        return toStringT!(T)((cast(T*)ptr)[0..(len>>BitshiftForT!(T))]);
    }

    // implement common python/java/obj-c string ops
    // indexing: deifine two indexing types? codepoint,native?
    
}