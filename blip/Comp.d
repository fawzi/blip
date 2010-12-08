/// compatibility module to help the D1-D2 transition
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
module blip.Comp;

version(D_Version2){
mixin(`
  template Const(T){
      alias const(T) Const;
  }
  template Immutable(T){
      alias immutable(T) Immutable;
  }
  immutable(T) Idup(T)(T val){
      return val.idup;
  }
  alias immutable(char)[] string;
  alias const(char)[] cstring;
`);
} else {
  template Const(T){
      alias T Const;
  }
  template Immutable(T){
      alias T Immutable;
  }
  T Idup(T)(T val){
      return val.dup;
  }
  alias char[] string;
  alias char[] cstring;
}
