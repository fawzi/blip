/// module that tests the serialization handlers
/// not so useful, remove???
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
module testHandlers;
import blip.serialization.Handlers;
import blip.container.GrowableArray;
import blip.io.Console;
import blip.io.BasicIO;
import blip.Comp;

void main(){
    char[14] buf;
    auto arr=new GrowableArray!(char)(buf,0);
    auto f=new FormattedWriteHandlers!()(&arr.appendArr);
    int i=10;
    string s="bla";
    f(i);
    f(s);
    f(cast(void[])"bla2");
    sout(cast(string )arr.takeData)("\n");
    soutStream.flush;
    ssout(outWriter("sep\n"));
    auto arr2=new GrowableArray!(ubyte)();
    auto f2=new BinaryWriteHandlers!()(&arr2.appendVoid);
    f2(i);
    f2(s);
    f2(cast(void[])"bla2");
    writeOut(sout,arr2.takeData,"x");
    soutStream.flush;
}