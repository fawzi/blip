module blip.container.HashMap;
import HMap=tango.util.container.HashMap;

final class HashMap (K, V) :HMap.HashMap!(K,V){
    this(){
        super();
    }
    size_t length(){
        return size();
    }
}