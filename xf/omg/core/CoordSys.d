/// coordinate sytems/transformations
///
/// These files are a sligthly modified version of xf.omg available from http://team0xf.com:1024/omg/
///
/// author: Tomasz Stachowiak (h3r3tic)
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
module xf.omg.core.CoordSys;
private {
    import xf.omg.core.LinearAlgebra;
}



/**
    The usage of vec3fi (fixed - based) instead of vec3 (float - based) yields two advantages:
    1. uniform resolution across the whole space
    2. higher precission even than using doubles because CoordSys only uses 'fixed-safe' operations which don't overflow under normal circumstances
*/
struct CoordSys {
    vec3fi  origin;
    quat        rotation;
    
    static const CoordSys identity = { origin: vec3fi.zero, rotation: quat.identity };
    
    
    static CoordSys opCall(vec3fi origin, quat rotation) {
        CoordSys res;
        res.origin = origin;
        res.rotation = rotation;
        return res;
    }
    
    
    CoordSys opIn(CoordSys reference) {
        CoordSys res;
        res.origin = reference.origin;
        res.origin += reference.rotation.xform(this.origin);
        res.rotation = reference.rotation * this.rotation;
        res.rotation.normalize();
        return res;
    }


    CoordSys quickIn(CoordSys reference) {
        CoordSys res;
        res.origin = reference.origin;
        res.origin += reference.rotation.xform(this.origin);
        res.rotation = reference.rotation * this.rotation;
        return res;
    }
    
    
    CoordSys deltaFrom(CoordSys from) {
        return *this in from.inverse;
    }


    vec3 opIn_r(vec3 v) {
        return rotation.xform(v) + vec3.from(origin);
    }


    vec3fi opIn_r(vec3fi v) {
        return rotation.xform(v) + origin;
    }
    
    
    quat opIn_r(quat q) {
        return rotation * q;
    }
    
    
    CoordSys worldToLocal(CoordSys global) {
        CoordSys inv = *this;
        inv.invert();
        return global in inv;
    }


    void invert() {
        rotation.invert();
        origin = rotation.xform(-origin);
    }
    
    
    CoordSys inverse() {
        CoordSys res = *this;
        res.invert();
        return res;
    }


    mat4 toMatrix() {
        mat4 res = rotation.toMatrix!(4, 4)();
        res.setTranslation(vec3.from(this.origin));
        return res;
    }
    
    char[] toString(){
        return "{" ~ origin.toString ~ ";" ~ rotation.toString ~ "}";
    }
}
