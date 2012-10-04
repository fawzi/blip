module blip.util.IgnoreSigpipe;
import tango.stdc.posix.signal;
import tango.stdc.signal;

shared static this(){
    sigaction_t act;
    act.sa_handler=SIG_IGN;
    auto res=sigaction(SIGPIPE, &act ,cast(sigaction_t*)null);
    if (res){
        throw new Exception("could not ignore SIGPIPE",__FILE__,__LINE__);
    }
}
