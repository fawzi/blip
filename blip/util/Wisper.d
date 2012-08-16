/// helper to use wisper style calling
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
module blip.util.Wisper;

/// helper to use wisper style calling
struct Wisper(T){
    T call;
    Wisper opCall(U)(U u){
        static if(is(U==void delegate(T))){
            u(call);
        } else static if (is(typeof(call(u)))){
            call(u);
        } else {
            static assert(0,"Wisper!("~T.stingof~") cannot handle "~U.stringof);
        }
        return this;
    }
}
/// ditto
Wisper!(T) wisper(T)(T c){
    Wisper!(T) res;
    res.call=c;
    return res;
}
