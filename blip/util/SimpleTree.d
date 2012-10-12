/// a tree structure on the number 0..n rooted at x
/// to implement gaher/scatter like operations
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
module SimpleTree;

/// parents and childs of an element, T is supposed to be an integer type
struct ParentChilds(T){
    T parent;
    T left;
    T right;
}

/// returns the parent and childs of el for a tree on 0..n with the root at
/// root, n is used to mark invalid/non existing elements
/// T is supposed to be an integer type able to represent at least 2*n (and n+1)
ParentChilds!(T) parentChilds(T)(T root,T n,T el){
    T myN=((el+n-root)%n)+1;
    ParentChilds!(T) res;
    if (myN!=1){
        res.parent=((myN>>1)+root-1)%n;
    } else {
        res.parent=n;
    }
    T lN=(myN<<1);
    if (lN<n){
        res.left=(lN+root-1)%n;
        T rN=lN+1;
        if (rN<n){
            res.right=(rN+root-1)%n;
        } else {
            res.right=n;
        }
    } else {
        res.left=n;
        res.right=n;
    }
    return res;
}
