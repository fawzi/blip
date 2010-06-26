/// tests the PriQueue structure
/// (not so useful, remove???)
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
module testPriQueue;
import blip.parallel.smp.BasicTasks;
import blip.parallel.smp.PriQueue;
import blip.io.Console;

void main(){
    PriQueue!(Task) queue=new PriQueue!(Task)();
    queue.insert(10,new Task("bla1", delegate(){ sout("task1\n");}));
    writeOut(sout("xx1").call,queue); sout("\n");
    auto t=queue.popNext();
    writeOut(sout("xx2").call,queue); sout("\n");
    queue.insert(12,new Task("bla2", delegate(){ sout("task2\n");}));
    writeOut(sout("xx3").call,queue); sout("\n");
    queue.insert(10,t);
    writeOut(sout("xx4").call,queue); sout("\n");
    queue.insert(12,t);
    writeOut(sout("xx5").call,queue); sout("\n");
    auto t2=queue.popNext();
    writeOut(sout("xx5.1").call,queue); sout("\n");
    queue.insert(20,t);    
    writeOut(sout("xx6").call,queue); sout("\n");
    queue.insert(0,t);    
    writeOut(sout("xx7").call,queue); sout("\n");
    sout("done\n");
}
