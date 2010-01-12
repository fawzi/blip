module testNuma;
import blip.io.Console;
import blip.serialization.Sout;
import blip.parallel.smp.Numa;
import blip.serialization.Serialization;
import tango.core.stacktrace.TraceExceptions;

int main(){
    /+auto topo=uniformTopology([2,2,1]);
    sout("topo:\n");
    Sout(topo);
    sout("----\n");+/
    //auto t=cast(HwlocTopology)defaultTopology;
    auto rootN=NumaNode(2,0);
    sout(rootN);
/+    sout("subnodes of ")(rootN)("\n");
    foreach(subN;t.subNodes(rootN)){
        sout(subN);
    }
    sout("\n==========\n");
    foreach(subN;subnodesWithLevel(1,cast(Topology!(NumaNode))t,rootN)){
        sout(subN);
    }
    sout("\nend\n");+/
/+    auto obj=t.hwlocObjForNumaNode(rootN);
    sout("root.arity")(obj.arity)(" root.children")(cast(void*)obj.children)(" depth:")(obj.depth)
    (" pos:")(obj.logical_index)("\n");
    obj=obj.first_child;
    sout("root.arity")(obj.arity)(" root.children")(cast(void*)obj.children)(" depth:")(obj.depth)
(" pos:")(obj.logical_index)("\n");
    obj=obj.first_child;
    if (obj){
        sout("root.arity")(obj.arity)(" root.children")(cast(void*)obj.children)(" depth:")(obj.depth)
(" pos:")(obj.logical_index)("\n");
    }+/
    return 0;
}