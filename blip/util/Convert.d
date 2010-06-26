/// conversion to/from types, this most notably does not support conversion to/from strings
/// to do that see blip.text.StringConversions (change and add that??)
///
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
module blip.util.Convert;

/// conversion to/from types, this most notably does not support conversion to/from strings
/// to do that see blip.text.StringConversions
template convertTo(T){
    T convertTo(V)(V x){
        static if (is(typeof(T.from(x))==T)){
            return T.from(x);
        } else static if (is(typeof(x.to!(T)())==T)){
            return x.to!(T)();
        } else static if (is(V:T)){
            return cast(T)x;
        } else {
            assert(0,"cannot convert "~V.stringof~" to "~T.stringof);
        }
    }
}
