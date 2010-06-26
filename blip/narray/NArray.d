/// Main module that exports multidimensional arrays.
///
/// == Blip Overview: N-dimensional arrays (from blip.narray.NArray) ==
/// 
/// Blip has n-dimensional dense arrays that work very well with large amount of data.
/// Most operations that you expect from an N dimensional array are there.
/// {{{
/// import blip.narray.NArray;
/// 
/// auto a=zeros!(real)([3,4,12]); // a 3x4x12 array of reals filled with zeros
/// auto b=a[2]; // the last 4x12 slice of a
/// b[3,4]=1.5; // changes both a and b
/// c=dot(a,b.T); // 3x4x4 obtained multiplying a b transposed
/// auto a2=ones!(real)([3,3]); // a 3x3 array of reals filled with ones
/// c[Range(0,-1),Range(1,4),4]=a2; // using python notation this means c[:,1:,4]=a2
/// auto a3=empty!(real)(4); // an unitialized 4-vector of reals
/// foreach(i,v;b){
///     index_type start=i%2;
///     scope d=a3[Range(start,start-2)];
///     d+=v;
/// }
/// a3[]=1.4;
/// a3[2]=a3[2]+1.1; // unfortunately due to limitations of D1 += and indexing does not work
/// sout(a3.dataPrinter(":6")); // prints data using 6 digits of precision
/// }}}
/// If you have some data in an array you can have a NArray that uses that memory with
/// {{{
/// int[] myData=...;
/// auto nArr=a2NA(myData);
/// }}}
/// There many other features, some highlight are:
/// inv (Inverse of a square matrix),
/// solve (Solve a linear system of equations),
/// det (Determinant of a square matrix),
/// eig (Eigenvalues and vectors of a square matrix),
/// eigh (Eigenvalues and eigenvectors of a Hermitian matrix),
/// svd (Singular value decomposition of a matrix),
/// filtering operations, folding, convolution,...
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
module blip.narray.NArray;
public import blip.narray.NArrayType;
public import blip.narray.NArrayBasicOps;
public import blip.narray.NArrayLinAlg;
