/// tests the text parser, and utf utilities
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
module testTextParsing;
import blip.text.TextParser;
import blip.io.IOArray;
import tango.io.stream.Lines;
import tango.math.Math;
import blip.rtest.BasicGenerators;
import blip.text.UtfUtils;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; }
import blip.io.Console;
import blip.io.StreamConverters;

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
    
    auto p=new TextParser!(char)(toReaderChar(new IOArray("12tz,rk tt 23.4 +7.2i \t6.4+3.2i \"a string with space\" \"escapedString\\\"\"\n")));
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