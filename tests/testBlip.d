/// module that creates an executable that executes all automatic tests of blip
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
module testBlip;
import blip.test.BlipTests;
import blip.io.Console;
import blip.io.BasicIO;
import tango.math.random.Random;
import blip.rtest.RTest;
version(NoTrace){} else { import blip.core.stacktrace.TraceExceptions; import blip.util.TraceAll; }
import blip.Comp;

void main(string [] args){
    sout(rand.toString()); sout("\n");
    mainTestFun(args,blipTests!()());
}
