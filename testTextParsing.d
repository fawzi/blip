module testTextParsing;
import blip.text.TextParser;
import tango.io.device.Array;
import tango.io.stream.Lines;
import tango.math.Math;
import blip.rtest.BasicGenerators;
import blip.text.UtfUtils;
import tango.core.stacktrace.TraceExceptions;
import blip.io.Console;

void main(){
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
    
    auto p=new TextParser!(char)(new Array("12tz,rk tt 23.4 +7.2i \t6.4+3.2i \"a string with space\" \"escapedString\\\"\"\n"));
    int i;
    real r;
    ireal ir;
    creal cr;
    char[] s;
    wchar[] ws;
    dchar[] ds;
    p(i);
    assert(i==12);
    p(s);
    assert(s=="tz");
    s=p.getSeparator();
    assert(s==",");
    p(s)(ws);
    assert(s=="rk");
    assert(ws=="tt"w);
    p(r)(ir)(cr);
    assert(abs(r-23.4)<1.e-10);
    assert(abs(ir-7.2i)<1.e-10);
    assert(abs(cr-(6.4+3.2i))<1.e-10);
    p(s)(ds);
    assert(s=="a string with space");
    assert(ds==`escapedString"`d);
    sout("did tests!\n");
}