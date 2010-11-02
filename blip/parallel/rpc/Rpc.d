/// utility import of the rpc machinery
///
/// localProxies are kind of hacked in... should probably be improved:
/// - subtask handling (in mixins) slightly different from normal call
/// - targetObj has to be available, and a single lookup is done at creation time
///   (does not update if the vended object is changed)
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
module blip.parallel.rpc.Rpc;
public import blip.parallel.rpc.RpcBase;
public import blip.parallel.rpc.RpcMixins;
public import blip.parallel.rpc.RpcMpi;
public import blip.parallel.rpc.RpcStcp;
