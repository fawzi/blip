/// conversion of arbitrary types to string
///
/// author:fawzi
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
module blip.text.StringConversions;
import blip.container.GrowableArray;
import blip.io.BasicIO;

template toStringT(T){
    immutable(T)[] toStringT(V)(V v){
        static if (is(V==T)){
            return v;
        } else { // piggyback on writeOut
            T[256] buf;
            auto b=lGrowableArray(buf,0,GASharing.Local);
            writeOut(&b.appendArr,v);
            return b.takeIData(true);
        }
    }
}

alias toStringT!(char) toString8;
alias toStringT!(wchar) toString16;
alias toStringT!(dchar) toString32;

// add also a generic from string???
// probably building on the top of json serialization would be the obvious choice...
