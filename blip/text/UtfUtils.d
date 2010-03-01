/*******************************************************************************
    Utf utilities (code points counting, scanning)
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.text.UtfUtils;
import Utf=tango.text.convert.Utf;
import tango.io.model.IConduit;
public import tango.text.convert.Utf: cropRight, cropLeft;
public import tango.text.Util:trim;

/// returns the number of code points in the string str, raise if str contains invalid or 
/// partial characters (but does not explicitly validate)
size_t nCodePoints(T)(T[] str){
    static if (is(T==char)){ // optimized for mostly ascii content
        T* p=str.ptr;
        size_t l=str.length;
        size_t n=0;
        bool charLoop(T* pEnd){
            while (p<pEnd){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T* pEnd){
            while (p<pEnd){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0 || ++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xE0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                    case 0xC0,0xD0:
                        if (++p==pEnd || (*p & 0xC0)!=0x80) return true; 
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)==0) break;
            }
            return false;
        }
        if (l<8){
            if (charLoop(p+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        } else {
            T* pEnd=cast(T*)((cast(size_t)(str.ptr+l))&(~cast(size_t)7));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
            while (p<pEnd){
                if ((*(cast(int*)p))&0x80808080 ==0){
                    p+=4;
                    n+=4;
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-8",__FILE__,__LINE__);
        }
        return n;
    } else static if (is(T==wchar)){
        T* p=str.ptr;
        size_t n=0;
        bool charLoop(T*pEnd){
            while(p<pEnd){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T*pEnd){
            while(p<pEnd){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) return true;
                    if (++p==pEnd || ((*p)&0xFC00)!=0xDC00) return true;
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)==0) break;
            }
            return false;
        }
        size_t l=str.length;
        if (l<4){
            if (charLoop(p+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        } else {
            T*pEnd=cast(T*)((cast(size_t)(p+l))&(~(cast(size_t)7)));
            if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
            while (p<pEnd){
                int i= *(cast(int*)p);
                if ((i&0xF800_0000) != 0xD800_0000 && (i&0xF800) != 0xD800){
                    p+=2;
                    n+=2;
                } else {
                    if (charLoop2(pEnd)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
                }
            }
            if (charLoop(str.ptr+l)) throw new Exception("invalid UTF-16",__FILE__,__LINE__);
        }
        return n;
    } else static if (is(T==dchar)) {
        return str.length;
    } else {
        static assert(0,"unexpected char type "~T.stringof);
    }
}

template convertToString(T=char){
    T[]convertToString(S)(S[]src,T[]dest=null){
        static if(is(T==S)){
            return src;
        } else static if(is(T==char)){
            return Utf.toString(src,dest);
        } else static if(is(T==wchar)){
            return Utf.toString16(src,dest);
        } else static if(is(T==dchar)){
            return Utf.toString32(src,dest);
        } else {
            static assert(0,"unexpected char type "~T.stringof);
        }
    }
}

debug(UnitTest){
    unittest{
        assert("abcè"w==cast(wchar[])"abcè","cast char->wchar are expected to work");
        assert(("abcè"d==cast(dchar[])"abcè"),"cast char->dchar are expected to work");
        assert("abcè"w=="abcè","comparison wchar,char are expected to work");
        assert(("abcè"d=="abcè"),"comparison dchar,char are expected to work");
        
        assert(nCodePoints("abc")==3);
        assert(nCodePoints("åbôd")==4);
        assert(nCodePoints("abc"w)==3);
        assert(nCodePoints("åbôd"w)==4);
        assert(nCodePoints("abc"d)==3);
        assert(nCodePoints("åbôd"d)==4);

        assert(nCodePoints("abcabcabcabc")==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc")==23);
        assert(nCodePoints("abcabcabcabc"w)==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc"w)==23);
        assert(nCodePoints("abcabcabcabc"d)==12);
        assert(nCodePoints("åbôdåbôdabbdabddåbôdabc"d)==23);
    }
}

/// scans until it has the requested number of code points in the string str
/// raises if str contains invalid or contains partial characters (but does not explicitly validate)
size_t scanCodePoints(T)(T[] str,size_t nn){
    static if (is(T==char)){ // optimized for mostly ascii content
        T* p=str.ptr;
        size_t l=str.length;
        size_t n=0;
        void invalidUtfError(long line){
            throw new Exception("invalid UTF-8",__FILE__,line);
        }
        bool charLoop(T* pEnd,long line){
            assert(p<=pEnd,"ppp");
            while (p<pEnd && n<nn){
                if ((*p)&0x80){ // use the stride table instead?
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0) invalidUtfError(line);
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                    case 0xE0:
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                    case 0xC0,0xD0:
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                        break;
                    default:
                        invalidUtfError(line);
                    }
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T* pEnd,long line){
            assert(p<=pEnd,"ppp");
            while (p<pEnd && n<nn){
                if ((*p)&0x80){
                    switch ((*p)&0xF0){
                    case 0xF0:
                        if ((*p)&0x08!=0) invalidUtfError(line);
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                    case 0xE0:
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                    case 0xC0,0xD0:
                        if (++p==pEnd) return true;
                        if ((*p & 0xC0)!=0x80) invalidUtfError(line);
                        break;
                    default:
                        return true;
                    }
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)==0) break;
            }
            return false;
        }
        if (l<8 || nn<4){
            if (charLoop(p+l,__LINE__)) return IOStream.Eof;
        } else {
            T* pEnd=cast(T*)((cast(size_t)(str.ptr+l))&(~cast(size_t)7));
            nn-=3;
            if (charLoop2(pEnd,__LINE__)) return IOStream.Eof;
            while (p<pEnd && n<nn){
                if ((*(cast(int*)p))&0x80808080 ==0){
                    p+=4;
                    n+=4;
                } else {
                    if (charLoop2(pEnd,__LINE__)) return IOStream.Eof;
                }
            }
            nn+=3;
            if (charLoop(str.ptr+l,__LINE__)) return IOStream.Eof;
            
        }
        if (n<nn) return IOStream.Eof;
        return cast(size_t)(p-str.ptr);
    } else static if (is(T==wchar)){
        T* p=str.ptr;
        size_t n=0;
        void invalidUtfError(long line){
            throw new Exception("invalid UTF-16",__FILE__,line);
        }
        bool charLoop(T*pEnd,long line){
            while(p<pEnd && n<nn){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) invalidUtfError(line);
                    if (++p==pEnd) return true;
                    if (((*p)&0xFC00)!=0xDC00) invalidUtfError(line);
                }
                ++p;
                ++n;
            }
            return false;
        }
        bool charLoop2(T*pEnd,long line){
            while(p<pEnd && n<nn){
                if ((*p)&0xF800==0xD800){
                    if ((*p)&0x0400) invalidUtfError(line);
                    if (++p==pEnd) return true;
                    if (((*p)&0xFC00)!=0xDC00) invalidUtfError(line);
                }
                ++p;
                ++n;
                if (((cast(size_t)p)&7)==0) break;
            }
            return false;
        }
        size_t l=str.length;
        if (l<4 || n<1){
            if (charLoop(p+l,__LINE__)) return Eof;
        } else {
            T*pEnd=cast(T*)((cast(size_t)(p+l))&(~(cast(size_t)7)));
            if (charLoop2(pEnd,__LINE__)) return Eof;
            --nn;
            while (p!=pEnd && nn<nn){
                int i= *(cast(int*)p);
                if ((i&0xF800_0000) != 0xD800_0000 && (i&0xF800) != 0xD800){
                    p+=2;
                    n+=2;
                } else {
                    if (charLoop2(pEnd,__LINE__)) return Eof;
                }
            }
            ++n;
            if (charLoop(str.ptr+l,__LINE__)) return Eof;
        }
        if (n<nn) return IOStream.Eof;
        return p-str.ptr;
    } else static if (is(T==dchar)) {
        if (str.length<nn) return IOStream.Eof;
        return nn;
    } else {
        static assert(0,"unexpected char type "~T.stringof);
    }
}
