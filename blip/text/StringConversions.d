module blip.text.StringConversions;
import blip.container.GrowableArray;
import blip.io.BasicIO;

template toStringT(T){
    T[] toStringT(V)(V v){
        static if (is(V==T)){
            return v;
        } else { // piggyback on writeOut
            T[256] buf;
            auto b=lGrowableArray(buf,0,GASharing.Local);
            writeOut(&b.appendArr,v);
            return b.takeData(true);
        }
    }
}

alias toStringT!(char) toString8;
alias toStringT!(char) toString16;
alias toStringT!(char) toString32;

// add also a generic from string???
// probably building on the top of json serialization would be the obvious choice...
