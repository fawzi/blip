/// tester that writes out various information detected by the numa module
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
module testNuma;
import blip.io.Console;
import blip.serialization.Sout;
import blip.parallel.smp.Numa;
import blip.serialization.Serialization;
import blip.parallel.hwloc.hwloc;
version(NoTrace){} else { import tango.core.stacktrace.TraceExceptions; }

void numaLooper(NumaNode n,NumaTopology topo,void delegate(NumaNode) loopBody){
    loopBody(n);
    if (n.level>0){
	foreach(subN;topo.subNodes(n)){
	    numaLooper(subN,topo,loopBody);
	}
    }
}
    

int main(){
    auto topo=defaultTopology;
    auto rootN=NumaNode(topo.maxLevel,0);
    sout(rootN);
    sout("subnodes of ")(rootN)("\n");
    foreach(subN;topo.subNodes(rootN)){
        sout(subN);
    }
    sout("\n==========\n")("list cores:\n");
    foreach(subN;subnodesWithLevel(1,cast(Topology!(NumaNode))topo,rootN)){
        sout(subN);
    }
    sout("\nend\n");
    version(noHwloc){} else {
        auto t=cast(HwlocTopology)defaultTopology;
        if (t!is null){
            sout("hwloc:\n");
            numaLooper(rootN,topo,delegate void(NumaNode n){
                sout("{\n node:")(n)(",\n");
                auto obj=t.hwlocObjForNumaNode(n);
                if (obj !is null) {
                        char[128] string;
                        auto len=hwloc_obj_type_snprintf(string.ptr,string.length, obj, 0);
                        if (len>0){
                            sout("name:")(string[0..len])(",\n");
                        }
                        sout("arity:")(obj.arity)(", children:@")(cast(void*)obj.children)(", depth:")(obj.depth)
                            (" pos:")(obj.logical_index)("\n");
                }
                sout("\n}\n");
            });
            sout("random childrens:\n");
            numaLooper(rootN,topo,delegate void(NumaNode n){
                sout("{\n node:")(n)("has subnodes:");
                if (n.level>1){
                    NumaNode nSkip;
                    foreach(subN;randomSubnodesWithLevel(1,cast(Topology!(NumaNode))topo,n)){
                        sout(subN)(",");
                        nSkip=subN;
                    }
                    sout("skipping")(nSkip)(":");
                    foreach(subN;randomSubnodesWithLevel(1,cast(Topology!(NumaNode))topo,n,nSkip)){
                        sout(subN)(",");
                        nSkip=n;
                    }
                }
                sout("}\n");
            });
        }
    }
    sout("done\n");
    return 0;
}
