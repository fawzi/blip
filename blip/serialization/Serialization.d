/// serialization support
/// built borrowing from xpose binary serialization by h3r3tic, but adding protocol
/// like support (inspired by Kris tango Reader/Writer), and support for json and xml like
/// serializations.
/// The serialization can remove cycles. Support for serialization can be added either by hand
/// or via mixins (serializeSome)
///
/// == Blip Overview: Serialization (from blip.serialization.Serialization)==
/// 
/// Serialization is somewhat connected to output, but has another goal, it tries to save 
/// some in memory objects to a stream, or to generate in memory objects reading a stream.
/// 
/// There are various ways and formats to encode the information in a stream.
/// Blip tries to separate the concerns as much as possible, thus the serialization functions
/// in an object are independent on the actual format used to output them to a stream.
/// The format is chosen by the serializer. There is a serializer that writes out json
/// format, and another that writes a binary format. Other formats can be added.
/// To allow efficient binary serialization an object has to give a description of its content
/// separately from the function actually doing the serialization.
/// 
/// This can be done by hand (see testSerial), but it is easier just using the serializeSome mixin:
/// {{{
/// import blip.serialization.Serialization;
/// 
/// class A{
///  int x;
///  int _y;
///  int y(){ return _y; }
///  void y(int v){ _y=v; }
///  
///  mixin(serializeSome("A","a doc",`
///  x: coordinates x in pixels
///  y: coordinate y in pixels`));
///  
///  mixin printOut!();
/// }
/// 
/// struct B{
///  int z;
///  A a;
///  
///  mixin(serializeSome("","",`z|a`));
///  mixin printOut!();
/// }
/// }}}
/// the printOut mixin adds a description method desc that writes out the object using the
/// json format, and a toString method, so that by defining serialization one has also easily
/// a description.
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
module blip.serialization.Serialization;
public import blip.serialization.SerializationBase;
//public import blip.serialization.SerializationExpose;
public import blip.serialization.SerializationMixins;
public import blip.serialization.JsonSerialization;
public import blip.serialization.SBinSerialization;
public import blip.serialization.SimpleWrappers;
public import blip.serialization.StringSerialize;
public import blip.serialization.Handlers: isCoreType;