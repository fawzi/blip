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
    /+ auto topo=uniformTopology([2,2,1]);
    sout("topo:\n");
    Sout(topo);
    sout("----\n");+/
    auto topo=defaultTopology;
    auto rootN=NumaNode(topo.maxLevel,0);
    sout(rootN);
    sout("subnodes of ")(rootN)("\n");
    foreach(subN;topo.subNodes(rootN)){
        sout(subN);
    }
    sout("\n==========\n");
    foreach(subN;subnodesWithLevel(1,cast(Topology!(NumaNode))topo,rootN)){
        sout(subN);
    }
    sout("\nend\n");
    auto t=cast(HwlocTopology)defaultTopology;
    if (t!is null){
	sout("hwloc:\n");
	numaLooper(rootN,topo,delegate void(NumaNode n){
	    sout("{\n")(n)(",");
	    auto obj=t.hwlocObjForNumaNode(rootN);
	    if (obj !is null) {
		char[128] string;
		auto len=hwloc_obj_type_snprintf(string.ptr,string.length, obj, 0);
		if (len>0){
		    sout(string[0..len])(" ");
		}
		sout("root.arity")(obj.arity)(" root.children")(cast(void*)obj.children)(" depth:")(obj.depth)
		    (" pos:")(obj.logical_index)("\n");
		obj=obj.first_child;
		sout("root.arity")(obj.arity)(" root.children")(cast(void*)obj.children)(" depth:")(obj.depth)
		    (" pos:")(obj.logical_index)("\n");
	    }
	    sout("\n}\n");
	});
    }
    return 0;
}
