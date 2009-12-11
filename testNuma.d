module testNuma;
import blip.io.Console;
import blip.serialization.Sout;
import blip.parallel.smp.Numa;
import blip.serialization.Serialization;
import tango.core.stacktrace.TraceExceptions;

int main(){
    auto topo=uniformTopology([2,2,1]);
    
    sout("topo:\n");
    Sout(topo);
    sout("----\n");
    return 0;
}