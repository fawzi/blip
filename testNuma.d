module testNuma;
import tango.io.Stdout;
import blip.parallel.smp.Numa;
import blip.serialization.Serialization;
import tango.core.stacktrace.TraceExceptions;

int main(){
    auto topo=uniformTopology([2,2,1]);
    
    auto s=new JsonSerializer!()(Stdout);
    Stdout("topo:").newline;
    s(topo);
    Stdout("----").newline;
    return 0;
}