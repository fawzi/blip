/// fixed point numbers (integer based), unlike the floating points they have a uniform spacing
/// on all the range that thay cover, which can be an advantage with additions/subtractions..
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
module blip.omg.core.LinearAlgebra;
private {
    import blip.omg.core.Algebra;
    import blip.omg.core.Fixed;
    import blip.omg.util.Meta;
    import blip.omg.core.Misc : unitSqNormEpsilon, deg2rad, rad2deg, pi, invSqrt;
    import blip.util.TangoConvert : convTo = to;
    import blip.math.Math : sqrt, abs, sin, cos, tan, acos, atan2, asin,floor;
    import blip.core.Traits : isFloatingPointType,ctfe_i2a;
    import blip.serialization.Serialization;
    import blip.serialization.SerializationMixins;
    import blip.util.Convert;
    import blip.Comp;
}

private struct Column(flt, int rows) {
    union {
        flt[rows]               row;
        .Vector!(flt, rows) vec;
    }
}

/// mixin to loop on vectors and matrixes
string vectMLoopMixin(string [] names,string op){
    string res=`
    {`;
    foreach(n;names){
        res~=`
        auto `~n~`Ptr=&(`~n~`.cell[0]);`;
    }
    res~=`
        static if (is(typeof(*`~names[0]~`))){
            alias typeof(*`~names[0]~`) MyVectType;
        } else {
            alias typeof(`~names[0]~`) MyVectType;
        }
        foreach (i; Range!(MyVectType.dim)) {
            `~op;
    foreach(n;names){
        res~=`
            ++`~n~`Ptr;`;
    }
    res~=`
        }
    }`;
    return res;
}

// ------------------------------------------------------------------------------------------------------------------------------------------------------------
// Vector
// ------------------------------------------------------------------------------------------------------------------------------------------------------------

struct Vector(flt_, int dim_) {
    alias flt_ flt;
    const static int dim = dim_;

    static assert (dim >= 2 && dim <= 4);
    static assert (isRingType!(flt));
    private const bool fieldOps = isFieldType!(flt);

    union {
        flt[dim] cell;
        Repeat!(flt, dim) tuple;
        
        struct {
            static if (dim >= 1)    union { flt x; flt r; }
            static if (dim >= 2)    union { flt y; flt g; }
            static if (dim >= 3)    union { flt z; flt b; }
            static if (dim >= 4)    union { flt w; flt a; }
        }
    }
    
    alias vectMLoopMixin simpleLoopMixin;
    
    flt opIndex(int i){
        return cell[i];
    }
    void opIndexAssign(flt v,int i){
        cell[i]=v;
    }
    int opApply(int delegate(ref flt) loopBody){
        if (auto res=loopBody(cell[0])) return res;
        if (auto res=loopBody(cell[1])) return res;
        static if (dim>2) if (auto res=loopBody(cell[2])) return res;
        static if (dim>3) {
            if (auto res=loopBody(cell[3])) return res;
            static assert(dim==4,"dim should be at most 4");
        }
        return 0;
    }
    int opApply(int delegate(ref size_t,ref flt) loopBody){
        static assert(dim>1,"dim should be at least 2");
        size_t i=0;
        if (auto res=loopBody(i,cell[0])) return res;
        ++i;
        if (auto res=loopBody(i,cell[1])) return res;
        static if (dim>2) {
            ++i;
            if (auto res=loopBody(i,cell[2])) return res;
        }
        static if (dim>3) {
            i=3;
            if (auto res=loopBody(i,cell[3])) return res;
            static assert(dim==4,"dim should be at most 4");
        }
        return 0;
    }
    static if (2 == dim) const static Vector zero = { x : cscalar!(flt, 0), y : cscalar!(flt, 0) };
    static if (3 == dim) const static Vector zero = { x : cscalar!(flt, 0), y : cscalar!(flt, 0), z : cscalar!(flt, 0) };
    static if (4 == dim) const static Vector zero = { x : cscalar!(flt, 0), y : cscalar!(flt, 0), z : cscalar!(flt, 0), w : cscalar!(flt, 0) };

    static if (2 == dim) const static Vector one = { x : cscalar!(flt, 1), y : cscalar!(flt, 1) };
    static if (3 == dim) const static Vector one = { x : cscalar!(flt, 1), y : cscalar!(flt, 1), z : cscalar!(flt, 1) };
    static if (4 == dim) const static Vector one = { x : cscalar!(flt, 1), y : cscalar!(flt, 1), z : cscalar!(flt, 1), w : cscalar!(flt, 1) };

    static if (2 == dim) const static Vector unitX = { x : cscalar!(flt, 1), y : cscalar!(flt, 0) };
    static if (3 == dim) const static Vector unitX = { x : cscalar!(flt, 1), y : cscalar!(flt, 0), z : cscalar!(flt, 0) };
    static if (4 == dim) const static Vector unitX = { x : cscalar!(flt, 1), y : cscalar!(flt, 0), z : cscalar!(flt, 0), w : cscalar!(flt, 0) };

    static if (2 == dim) const static Vector unitY = { x : cscalar!(flt, 0), y : cscalar!(flt, 1) };
    static if (3 == dim) const static Vector unitY = { x : cscalar!(flt, 0), y : cscalar!(flt, 1), z : cscalar!(flt, 0) };
    static if (4 == dim) const static Vector unitY = { x : cscalar!(flt, 0), y : cscalar!(flt, 1), z : cscalar!(flt, 0), w : cscalar!(flt, 0) };

    static if (3 == dim) const static Vector unitZ = { x : cscalar!(flt, 0), y : cscalar!(flt, 0), z : cscalar!(flt, 1) };
    static if (4 == dim) const static Vector unitZ = { x : cscalar!(flt, 0), y : cscalar!(flt, 0), z : cscalar!(flt, 1), w : cscalar!(flt, 0) };

    static if (4 == dim) const static Vector unitW = { x : cscalar!(flt, 0), y : cscalar!(flt, 0), z : cscalar!(flt, 0), w : cscalar!(flt, 1) };
    
    void opBypax(V)(V x,flt a=cscalar!(flt,1),flt b=cscalar!(flt,1)){
        static assert(is(V==Vector!(V.flt,dim)),"opBypax only between vectors with the same size, not "~V.stringof);
        if (b==cscalar!(flt,1)){
            mixin(vectMLoopMixin(["this","x"],"*thisPtr += a*(*xPtr);"));
        } else {
            mixin(vectMLoopMixin(["this","x"],"*thisPtr = (*thisPtr)*b+a*(*xPtr);"));
        }
    }
    
    
    bool ok() {
        static if (dim >= 1) if (isNaN(x)) return false;
        static if (dim >= 2) if (isNaN(y)) return false;
        static if (dim >= 3) if (isNaN(z)) return false;
        static if (dim >= 4) if (isNaN(w)) return false;
        return true;
    }
    
    // :P
    alias ok isOK;
    alias ok isCorrect;

    static Vector from(T)(T v) {
        Vector res = void;
        static if (dim >= 1) res.x = scalar!(flt)(v.x);
        static if (dim >= 2) res.y = scalar!(flt)(v.y);
        static if (dim >= 3) res.z = scalar!(flt)(v.z);
        static if (dim >= 4) res.w = scalar!(flt)(v.w);
        assert (res.ok);
        return res;
    }
    

    void set(T)(T v) {
        static if (is(T:flt)){
            static if (dim >= 1) x = v;
            static if (dim >= 2) y = v;
            static if (dim >= 3) z = v;
            static if (dim >= 4) w = v;
        } else {
            assert (v.ok);
            static if (dim >= 1) x = scalar!(flt)(v.x);
            static if (dim >= 2) y = scalar!(flt)(v.y);
            static if (dim >= 3) z = scalar!(flt)(v.z);
            static if (dim >= 4) w = scalar!(flt)(v.w);
        }
    }

    alias set opSliceAssign;
    
    static if (dim == 2) {
        static Vector opCall(flt x = cscalar!(flt, 0), flt y = cscalar!(flt, 0)) {
            assert (!isNaN(x) && !isNaN(y));
            Vector res = void;
            res.x = x;
            res.y = y;
            return res;
        }
    }
    
    
    static if (dim == 3) {
        static Vector opCall(flt x = cscalar!(flt, 0), flt y = cscalar!(flt, 0), flt z = cscalar!(flt, 0)) {
            assert (!isNaN(x) && !isNaN(y) && !isNaN(z));
            Vector res = void;
            res.x = x;
            res.y = y;
            res.z = z;
            return res;
        }
    }
    
    
    static if (dim == 4) {
        static Vector opCall(flt x = cscalar!(flt, 0), flt y = cscalar!(flt, 0), flt z = cscalar!(flt, 0), flt w = cscalar!(flt, 0)) {
            assert (!isNaN(x) && !isNaN(y) && !isNaN(z) && !isNaN(w));
            Vector res = void;
            res.x = x;
            res.y = y;
            res.z = z;
            res.w = w;
            return res;
        }
    }
    

    static if (dim == 2) {
        static Vector opIndex(real x, real y) {
            assert (x <>= 0 && y <>= 0);
            Vector res = void;
            res.x = scalar!(flt)(x);
            res.y = scalar!(flt)(y);
            return res;
        }
    }
    
    
    static if (dim == 3) {
        static Vector opIndex(real x, real y, real z) {
            assert (x <>= 0 && y <>= 0 && z <>= 0);
            Vector res = void;
            res.x = scalar!(flt)(x);
            res.y = scalar!(flt)(y);
            res.z = scalar!(flt)(z);
            return res;
        }
    }
    
    
    static if (dim == 4) {
        static Vector opIndex(real x, real y, real z, real w) {
            assert (x <>= 0 && y <>= 0 && z <>= 0 && w <>= 0);
            Vector res = void;
            res.x = scalar!(flt)(x);
            res.y = scalar!(flt)(y);
            res.z = scalar!(flt)(z);
            res.w = scalar!(flt)(w);
            return res;
        }
    }

    
    string toString() {
        string res = "[";
            res ~= convTo!(string )(x);
            static if (dim >= 2) res ~= ", " ~ convTo!(string )(y);
            static if (dim >= 3) res ~= ", " ~ convTo!(string )(z);
            static if (dim >= 4) res ~= ", " ~ convTo!(string )(w);
        return res ~ "]";
    }
    
    flt opDot(Vector b) {
        assert (ok && b.ok);
        static if (2 == dim) return x * b.x + y * b.y;
        else static if (3 == dim) return x * b.x + y * b.y + z * b.z;
        else static if (4 == dim) return x * b.x + y * b.y + z * b.z + w * b.w;
        else static assert (false);
    }
    
    mixin(serializeSome("","a small vector","cell"));
    
    static if(dim==3) {
        
        static if (isFloatingPointType!(flt)) {
            /// assumes that the current vector is normalized
            void formBasis(Vector* v1, Vector* v2) {
                assert (ok);
                
                real anx = abs(x);
                real any = abs(y);
                real anz = abs(z);
                
                int k;
                if (anx > any) {
                    if (anx > anz) k = 1; else k = 0;
                } else {
                    if (any > anz) k = 2; else k = 0;
                }
                
                *v1 = zero;
                v1.cell[k] = 1;
                
                *v2 = .cross(*this, *v1);
                *v1 = .cross(*v2, *this);
            }
        }
    }
    
    
    static if (dim==2) {
        Vector rotatedHalfPi() {
            assert (ok);
            
            Vector res = void;
            res.x = -this.y;
            res.y = this.x;
            return res;
        }
    }
    

    flt norm22() {
        assert (ok);
                static if (2 == dim) return x * x + y * y;
        else    static if (3 == dim) return x * x + y * y + z * z;
        else    static if (4 == dim) return x * x + y * y + z * z + w * w;
        else    static assert (false);
    }

    Vector dup(){
        return *this;
    }
    
    flt norm2() {
        assert (ok);
        flt sq = norm22();
        if (sq > cscalar!(flt, 0)) {
            return scalar!(flt)(sqrt(scalar!(real)(sq)));
        }
        return sq;
    }
    

    static if (fieldOps) {
        void normalize() {
            flt l = norm2();
            if (l != cscalar!(flt, 0)) {
                static if (isFloatingPointType!(flt)) {
                    flt inv = cscalar!(flt, 1) / l;
                    *this *= inv;
                } else {
                    *this /= l;
                }
            }
        }
        
        Vector normalized() {
            Vector res = *this;
            res.normalize();
            return res;
        }
    }


    static if (is(flt == float)) {
        void quickNormalize() {
            flt inv = invSqrt(norm22);
            *this *= inv;
        }


        Vector quickNormalized() {
            Vector res = *this;
            res.quickNormalize();
            return res;
        }
    }
    
    
    private template opXVAssign(string op) {
        void opXVAssign(T)(T rhs) {
            assert (ok);
            static if (is(typeof(rhs.opVecMul_r(*this)) : Vector)) {
                *this = rhs.opVecMul_r(*this);
            } else static if (isVectorType!(T, dim)) {
                assert (rhs.ok);
                static if (dim >= 1) mixin("x"~op~"=rhs.x;");
                static if (dim >= 2) mixin("y"~op~"=rhs.y;");
                static if (dim >= 3) mixin("z"~op~"=rhs.z;");
                static if (dim >= 4) mixin("w"~op~"=rhs.w;");
            } else {
                assert (!isNaN(rhs));
                static if (dim >= 1) mixin("x"~op~"=rhs;");
                static if (dim >= 2) mixin("y"~op~"=rhs;");
                static if (dim >= 3) mixin("z"~op~"=rhs;");
                static if (dim >= 4) mixin("w"~op~"=rhs;");
            }
        }
    }


    public {
        alias opXVAssign!("+")  opAddAssign;
        alias opXVAssign!("-")  opSubAssign;
        alias opXVAssign!("*")  opMulAssign;

        static if (fieldOps) {
            alias opXVAssign!("/")  opDivAssign;
        }
    }
    
    
    Vector opAdd(T)(T rhs) {
        auto res = *this;
        res += rhs;
        return res;
    }
    
    
    Vector opSub(T)(T rhs) {
        auto res = *this;
        res -= rhs;
        return res;
    }
    
    
    Vector opMul(T)(T rhs) {
        auto res = *this;
        res *= rhs;
        return res;
    }
    
    
    static if (fieldOps) {
        Vector opDiv_r(flt lhs) {
            assert (!isNaN(lhs));
            
            Vector res = void;
            
            static if (dim >= 1) {
                assert(x != cscalar!(flt, 0));
                res.x = scalar!(flt)(lhs / x);
            }
            
            static if (dim >= 2) {
                assert(y != cscalar!(flt, 0));
                res.y = scalar!(flt)(lhs / y);
            }
            
            static if (dim >= 3) {
                assert(z != cscalar!(flt, 0));
                res.z = scalar!(flt)(lhs / z);
            }
            
            static if (dim >= 4) {
                assert(w != cscalar!(flt, 0));
                res.w = scalar!(flt)(lhs / w);
            }
            
            return res;
        }

        Vector opDiv(T)(T rhs) {
            auto res = *this;
            res /= rhs;
            return res;
        }
    }
    
    
    Vector opNeg() {
        assert (ok);
        static if (2 == dim) return opCall(-x, -y);
        static if (3 == dim) return opCall(-x, -y, -z);
        static if (4 == dim) return opCall(-x, -y, -z, -w);
    }
    
    
    int leastAxis() {
        assert (ok);
        
        real m = real.max;
        int mi = -1;
        foreach (i, c; cell) {
            real ca = abs(scalar!(real)(c));
            if (ca < m) {
                m = ca;
                mi = i;
            }
        }
        assert (mi != -1);
        return mi;
    }


    int dominatingAxis() {
        assert (ok);
        
        real m = -real.max;
        int mi = -1;
        foreach (i, c; cell) {
            real ca = abs(scalar!(real)(c));
            if (ca > m) {
                m = ca;
                mi = i;
            }
        }
        assert (mi != -1);
        return mi;
    }
    
    
    flt* ptr() {
        assert (ok);
        return &x;
    }
    
    
    private static string genSwizzleCode(string str) {
        string res = "";
        foreach (i, c; str) {
            assert (i <= 9);
            if (c == '0' || c == '1') {
                res ~= "res.cell["~cast(char)('0'+i)~"] = cscalar!(flt, "~c~");";
            } else {
                res ~= "res.cell["~cast(char)('0'+i)~"] = this." ~ c ~ ";";
            }
        }
        return res;
    }
    
    
    Vector!(flt, str.length) swizzle(string str)() {
        assert (ok);
        Vector!(flt, str.length) res = void;
        mixin(genSwizzleCode(str));
        return res;
    }
    
    
    flt distance(Vector other) {
        assert (ok);
        assert (other.ok);
        other -= *this;
        return other.norm2;
    }
    
    
    bool opEquals(Vector v) {
        assert (ok);
        assert (v.ok);
        
        static if (dim >= 1) if (x != v.x) return false;
        static if (dim >= 2) if (y != v.y) return false;
        static if (dim >= 3) if (z != v.z) return false;
        static if (dim >= 4) if (w != v.w) return false;
        return true;
    }
    
    
    bool isUnit() {
        real sql = cast(real)norm22();
        return abs(sql - 1.0) < unitSqNormEpsilon;
    }
}


alias Vector!(float, 2) vec2;
alias Vector!(float, 3) vec3;
alias Vector!(float, 4) vec4;

alias Vector!(double, 2)    vec2d;
alias Vector!(double, 3)    vec3d;
alias Vector!(double, 4)    vec4d;

alias Vector!(int, 2)   vec2i;
alias Vector!(int, 3)   vec3i;
alias Vector!(int, 4)   vec4i;

alias Vector!(ubyte, 2) vec2ub;
alias Vector!(ubyte, 3) vec3ub;
alias Vector!(ubyte, 4) vec4ub;

alias Vector!(fixed, 2) vec2fi;
alias Vector!(fixed, 3) vec3fi;
alias Vector!(fixed, 4) vec4fi;



// ------------------------------------------------------------------------------------------------------------------------------------------------------------
// Matrix
// ------------------------------------------------------------------------------------------------------------------------------------------------------------

struct Matrix(flt_, int rows_, int cols_) {
    static assert ((rows == cols || rows + 1 == cols) && rows >= 2 && cols <= 4);
    const bool isExtended = rows + 1 == cols;
    
    alias flt_ flt;
    const int rows = rows_;
    const int cols = cols_;
    const int dim = rows_*cols_;

    static assert (isRingType!(flt));
    private const bool fieldOps = isFieldType!(flt);

    
    // Column-major memory layout
    union {
        Column!(flt, rows)[cols]    col;
        Repeat!(flt, rows*cols) tuple;
        flt[rows*cols]                  cell;
    }
    
    bool ok() {
        debug {
            foreach (c; Range!(cols)) {
                foreach (r; Range!(rows)) {
                    if (isNaN(col[c].row[r])) return false;
                }
            }
            return true;
        } else {
            return !isNaN(col[0].row[0]);
        }
    }
    alias ok isOK;
    alias ok isCorrect;
    
    alias vectMLoopMixin simpleLoopMixin;
    
    void opBypax(U)(U x,flt a=cscalar!(flt,1),flt b=cscalar!(flt,1)){
        static assert(is(U==Matrix!(U.flt,rows,cols)),"opBypax only between matrix with the same struct, not "~U.stringof);
        if (b==cscalar!(flt,1)){
            mixin(vectMLoopMixin(["this","x"],"*thisPtr += scalar!(flt)(a*(*xPtr));"));
        } else {
            mixin(vectMLoopMixin(["this","x"],"*thisPtr = scalar!(flt)((*thisPtr)*b+a*(*xPtr));"));
        }
    }
    
    int opApply(int delegate(ref flt)loopBody){
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                mixin("if (auto res=loopBody(col[c].row[r])) return res;");
            }
        }
        return 0;
    }
    int opApply(int delegate(ref size_t,ref flt)loopBody){
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                mixin("{ size_t i=c*r; if (auto res=loopBody(i,col[c].row[r])) return res; }");
            }
        }
        return 0;
    }
    
    static Matrix opCall(flt[] raw) {
        Matrix res = void;
        (&res.col[0].row[0])[0..rows*cols] = raw[0..rows*cols];
        return res;
    }
    
    mixin(serializeSome("","a small matrix","cell"));
    
    flt cgetRC(int r, int c)() {
        assert (ok);
        static if (r == rows && isExtended) {
            return cscalar!(flt, r == c ? 1 : 0);
        } else {
            return col[c].row[r];
        }
    }

    Vector!(flt,cols) opIndex(int r){
        static if (cols==1) return Vector!(flt,cols)(res.col[0].row[r]);
        else static if (cols==2) return Vector!(flt,cols)(col[0].row[r],col[1].row[r]);
        else static if (cols==3) return Vector!(flt,cols)(col[0].row[r],col[1].row[r],col[2].row[r]);
        else static if (cols==4) return Vector!(flt,cols)(col[0].row[r],col[1].row[r],col[2].row[r],col[3].row[r]);
        else static assert(0);
    }
    
    
    static string _rc(int r, int c)(string src) {
        static if (r == rows && isExtended) {
            static if (r == c) {
                return "cscalar!(flt, 1)";
            } else {
                return "cscalar!(flt, 0)";
            }
        } else {
            return src ~ ".col["~c.stringof~"].row["~r.stringof~"]";
        }
    }
    

    flt getRC(int r, int c) {
        assert (ok);
        if (r == rows && isExtended) {
            return scalar!(flt)(r == c ? 1 : 0);
        } else {
            return col[c].row[r];
        }
    }
    
    
    alias getRC opIndex;

    
    void csetRC(int r, int c)(flt v) {
        col[c].row[r] = v;
    }

    
    void setRC(int r, int c, flt v) {
        col[c].row[r] = v;
    }
    
    
    void opIndexAssign(flt v, int r, int c) {
        col[c].row[r] = v;
    }
    
    
    private template oneAtPos(int i) {
        static if (i >= rows) {
            const static flt oneAtPos[rows] =
                    ([cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0)][0..rows]);
        } else {
            const static flt oneAtPos[rows] =
                    (([cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0)][0..i])
                ~   cscalar!(flt,1)
                ~   ([cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0),cscalar!(flt,0)][0 .. rows - i - 1]));
        }
    }
    
    static if (2 == cols) {
        const static Matrix identity = {
            col: [
                { row: oneAtPos!(0) },
                { row: oneAtPos!(1) }
            ]
        };
        const static Matrix zero = {
            col: [
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) }
            ]
        };
    } else
    static if (3 == cols) {
        const static Matrix identity = {
            col: [
                { row: oneAtPos!(0) },
                { row: oneAtPos!(1) },
                { row: oneAtPos!(2) }
            ]
        };
        const static Matrix zero = {
            col: [
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) }
            ]
        };
    } else
    static if (4 == cols) {
        const static Matrix identity = {
            col: [
                { row: oneAtPos!(0) },
                { row: oneAtPos!(1) },
                { row: oneAtPos!(2) },
                { row: oneAtPos!(3) }
            ]
        };
        const static Matrix zero = {
            col: [
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) },
                { row: oneAtPos!(rows) }
            ]
        };
    } else
    static assert (false);
    
    
    static Matrix from(T)(T mat) {
        static if (is(T.flt) && is(T == Quaternion!(T.flt))) {
            return mat.toMatrix!(rows, cols)();
        } else {
            static assert(T.rows == rows);
            static assert(T.cols == cols);
            
            Matrix res = void;
            foreach (r; Range!(rows)) {
                foreach (c; Range!(cols)) {
                    res.csetRC!(r, c)(mat.cgetRC!(r, c));
                }
            }
            
            return res;
        }
    }
    
    
    static if (3 == rows && 3 == cols) {
        static Matrix fromVectors(T)(T v0, T v1, T v2) {
            Matrix res = void;
            res.col[0].vec = v0;
            res.col[1].vec = v1;
            res.col[2].vec = v2;
            return res;
        }
    }
    
    
    void makeIdentity() {
        *this = identity;
    }
    
    
    void transpose() {
        *this = this.transposed();
    }
    
    
    Matrix transposed() {
        assert (ok);
        Matrix res = void;
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                res.csetRC!(r, c)(cgetRC!(c, r));
            }
        }
        return res;
    }
    
    
    flt determinant() {
        assert (ok);

        static if (2 == cols) {
            return cgetRC!(0, 0) * cgetRC!(1, 1)  - cgetRC!(0, 1) * cgetRC!(1, 0);
        } else
        static if (3 == cols) {
            return
                cgetRC!(0, 0) * (       cgetRC!(1, 1) * cgetRC!(2, 2)
                                        -   cgetRC!(1, 2) * cgetRC!(2, 1))
            -   cgetRC!(0, 1) * (       cgetRC!(1, 0) * cgetRC!(2, 2)
                                        -   cgetRC!(1, 2) * cgetRC!(2, 0))
            +   cgetRC!(0, 2) * (       cgetRC!(1, 0) * cgetRC!(2, 1)
                                        -   cgetRC!(1, 1) * cgetRC!(2, 0));
        } else
        static if (4 == cols) {
            return
                    (cgetRC!(0,0) * cgetRC!(1,1) - cgetRC!(0,1) * cgetRC!(1,0)) * (cgetRC!(2,2) * cgetRC!(3,3) - cgetRC!(2,3) * cgetRC!(3,2))
                -   (cgetRC!(0,0) * cgetRC!(1,2) - cgetRC!(0,2) * cgetRC!(1,0)) * (cgetRC!(2,1) * cgetRC!(3,3) - cgetRC!(2,3) * cgetRC!(3,1))
                +   (cgetRC!(0,0) * cgetRC!(1,3) - cgetRC!(0,3) * cgetRC!(1,0)) * (cgetRC!(2,1) * cgetRC!(3,2) - cgetRC!(2,2) * cgetRC!(3,1))
                +   (cgetRC!(0,1) * cgetRC!(1,2) - cgetRC!(0,2) * cgetRC!(1,1)) * (cgetRC!(2,0) * cgetRC!(3,3) - cgetRC!(2,3) * cgetRC!(3,0))
                -   (cgetRC!(0,1) * cgetRC!(1,3) - cgetRC!(0,3) * cgetRC!(1,1)) * (cgetRC!(2,0) * cgetRC!(3,2) - cgetRC!(2,2) * cgetRC!(3,0))
                +   (cgetRC!(0,2) * cgetRC!(1,3) - cgetRC!(0,3) * cgetRC!(1,2)) * (cgetRC!(2,0) * cgetRC!(3,1) - cgetRC!(2,1) * cgetRC!(3,0));
        } else
        static assert (false);
    }
    
    
    static if (fieldOps) {
        Matrix inverse() {
            assert (ok);

            Matrix res = void;
            static if (2 == cols) {
                res.csetRC!(0, 0)(cgetRC!(1, 1));
                res.csetRC!(0, 1)(-cgetRC!(1, 0));
                res.csetRC!(1, 0)(-cgetRC!(1, 0));
                res.csetRC!(1, 1)(cgetRC!(0, 0));
                flt det_ = this.determinant();
            } else
            static if (3 == cols) {
                res.csetRC!(0, 0)(cgetRC!(1, 1) * cgetRC!(2, 2) - cgetRC!(1, 2) * cgetRC!(2, 1));
                res.csetRC!(0, 1)(cgetRC!(0, 2) * cgetRC!(2, 1) - cgetRC!(0, 1) * cgetRC!(2, 2));
                res.csetRC!(0, 2)(cgetRC!(0, 2) * cgetRC!(2, 1) - cgetRC!(0, 1) * cgetRC!(2, 2));

                res.csetRC!(0, 0)(cgetRC!(1, 1) * cgetRC!(2, 2) - cgetRC!(1, 2) * cgetRC!(2, 1));
                res.csetRC!(0, 1)(cgetRC!(0, 2) * cgetRC!(2, 1) - cgetRC!(0, 1) * cgetRC!(2, 2));
                res.csetRC!(0, 2)(cgetRC!(0, 1) * cgetRC!(1, 2) - cgetRC!(0, 2) * cgetRC!(1, 1));
                res.csetRC!(1, 0)(cgetRC!(1, 2) * cgetRC!(2, 0) - cgetRC!(1, 0) * cgetRC!(2, 2));
                res.csetRC!(1, 1)(cgetRC!(0, 0) * cgetRC!(2, 2) - cgetRC!(0, 2) * cgetRC!(2, 0));
                res.csetRC!(1, 2)(cgetRC!(0, 2) * cgetRC!(1, 0) - cgetRC!(0, 0) * cgetRC!(1, 2));
                
                flt det_ = cgetRC!(0, 0) * res.cgetRC!(0, 0) + cgetRC!(0, 1) * res.cgetRC!(1, 0);
                
                static if (3 == rows) {
                    res.csetRC!(2, 0)(cgetRC!(1, 0) * cgetRC!(2, 1) - cgetRC!(1, 1) * cgetRC!(2, 0));
                    res.csetRC!(2, 1)(cgetRC!(0, 1) * cgetRC!(2, 0) - cgetRC!(0, 0) * cgetRC!(2, 1));
                    res.csetRC!(2, 2)(cgetRC!(0, 0) * cgetRC!(1, 1) - cgetRC!(0, 1) * cgetRC!(1, 0));
                    det_ += cgetRC!(0, 2) * res.cgetRC!(2, 0);
                }
            } else
            static if (4 == cols) {
                res.csetRC!(0, 0) = cgetRC!(1, 1) * (cgetRC!(2, 2) * cgetRC!(3, 3) - cgetRC!(2, 3) * cgetRC!(3, 2)) + cgetRC!(1, 2) * (cgetRC!(2, 3) * cgetRC!(3, 1) - cgetRC!(2, 1) * cgetRC!(3, 3)) + cgetRC!(1, 3) * (cgetRC!(2, 1) * cgetRC!(3, 2) - cgetRC!(2, 2) * cgetRC!(3, 1));
                res.csetRC!(0, 1) = cgetRC!(2, 1) * (cgetRC!(0, 2) * cgetRC!(3, 3) - cgetRC!(0, 3) * cgetRC!(3, 2)) + cgetRC!(2, 2) * (cgetRC!(0, 3) * cgetRC!(3, 1) - cgetRC!(0, 1) * cgetRC!(3, 3)) + cgetRC!(2, 3) * (cgetRC!(0, 1) * cgetRC!(3, 2) - cgetRC!(0, 2) * cgetRC!(3, 1));
                res.csetRC!(0, 2) = cgetRC!(3, 1) * (cgetRC!(0, 2) * cgetRC!(1, 3) - cgetRC!(0, 3) * cgetRC!(1, 2)) + cgetRC!(3, 2) * (cgetRC!(0, 3) * cgetRC!(1, 1) - cgetRC!(0, 1) * cgetRC!(1, 3)) + cgetRC!(3, 3) * (cgetRC!(0, 1) * cgetRC!(1, 2) - cgetRC!(0, 2) * cgetRC!(1, 1));
                res.csetRC!(0, 3) = cgetRC!(0, 1) * (cgetRC!(1, 3) * cgetRC!(2, 2) - cgetRC!(1, 2) * cgetRC!(2, 3)) + cgetRC!(0, 2) * (cgetRC!(1, 1) * cgetRC!(2, 3) - cgetRC!(1, 3) * cgetRC!(2, 1)) + cgetRC!(0, 3) * (cgetRC!(1, 2) * cgetRC!(2, 1) - cgetRC!(1, 1) * cgetRC!(2, 2));
                res.csetRC!(1, 0) = cgetRC!(1, 2) * (cgetRC!(2, 0) * cgetRC!(3, 3) - cgetRC!(2, 3) * cgetRC!(3, 0)) + cgetRC!(1, 3) * (cgetRC!(2, 2) * cgetRC!(3, 0) - cgetRC!(2, 0) * cgetRC!(3, 2)) + cgetRC!(1, 0) * (cgetRC!(2, 3) * cgetRC!(3, 2) - cgetRC!(2, 2) * cgetRC!(3, 3));
                res.csetRC!(1, 1) = cgetRC!(2, 2) * (cgetRC!(0, 0) * cgetRC!(3, 3) - cgetRC!(0, 3) * cgetRC!(3, 0)) + cgetRC!(2, 3) * (cgetRC!(0, 2) * cgetRC!(3, 0) - cgetRC!(0, 0) * cgetRC!(3, 2)) + cgetRC!(2, 0) * (cgetRC!(0, 3) * cgetRC!(3, 2) - cgetRC!(0, 2) * cgetRC!(3, 3));
                res.csetRC!(1, 2) = cgetRC!(3, 2) * (cgetRC!(0, 0) * cgetRC!(1, 3) - cgetRC!(0, 3) * cgetRC!(1, 0)) + cgetRC!(3, 3) * (cgetRC!(0, 2) * cgetRC!(1, 0) - cgetRC!(0, 0) * cgetRC!(1, 2)) + cgetRC!(3, 0) * (cgetRC!(0, 3) * cgetRC!(1, 2) - cgetRC!(0, 2) * cgetRC!(1, 3));
                res.csetRC!(1, 3) = cgetRC!(0, 2) * (cgetRC!(1, 3) * cgetRC!(2, 0) - cgetRC!(1, 0) * cgetRC!(2, 3)) + cgetRC!(0, 3) * (cgetRC!(1, 0) * cgetRC!(2, 2) - cgetRC!(1, 2) * cgetRC!(2, 0)) + cgetRC!(0, 0) * (cgetRC!(1, 2) * cgetRC!(2, 3) - cgetRC!(1, 3) * cgetRC!(2, 2));
                res.csetRC!(2, 0) = cgetRC!(1, 3) * (cgetRC!(2, 0) * cgetRC!(3, 1) - cgetRC!(2, 1) * cgetRC!(3, 0)) + cgetRC!(1, 0) * (cgetRC!(2, 1) * cgetRC!(3, 3) - cgetRC!(2, 3) * cgetRC!(3, 1)) + cgetRC!(1, 1) * (cgetRC!(2, 3) * cgetRC!(3, 0) - cgetRC!(2, 0) * cgetRC!(3, 3));
                res.csetRC!(2, 1) = cgetRC!(2, 3) * (cgetRC!(0, 0) * cgetRC!(3, 1) - cgetRC!(0, 1) * cgetRC!(3, 0)) + cgetRC!(2, 0) * (cgetRC!(0, 1) * cgetRC!(3, 3) - cgetRC!(0, 3) * cgetRC!(3, 1)) + cgetRC!(2, 1) * (cgetRC!(0, 3) * cgetRC!(3, 0) - cgetRC!(0, 0) * cgetRC!(3, 3));
                res.csetRC!(2, 2) = cgetRC!(3, 3) * (cgetRC!(0, 0) * cgetRC!(1, 1) - cgetRC!(0, 1) * cgetRC!(1, 0)) + cgetRC!(3, 0) * (cgetRC!(0, 1) * cgetRC!(1, 3) - cgetRC!(0, 3) * cgetRC!(1, 1)) + cgetRC!(3, 1) * (cgetRC!(0, 3) * cgetRC!(1, 0) - cgetRC!(0, 0) * cgetRC!(1, 3));
                res.csetRC!(2, 3) = cgetRC!(0, 3) * (cgetRC!(1, 1) * cgetRC!(2, 0) - cgetRC!(1, 0) * cgetRC!(2, 1)) + cgetRC!(0, 0) * (cgetRC!(1, 3) * cgetRC!(2, 1) - cgetRC!(1, 1) * cgetRC!(2, 3)) + cgetRC!(0, 1) * (cgetRC!(1, 0) * cgetRC!(2, 3) - cgetRC!(1, 3) * cgetRC!(2, 0));
                
                static if (4 == rows) {
                    res.csetRC!(3, 0) = cgetRC!(1, 0) * (cgetRC!(2, 2) * cgetRC!(3, 1) - cgetRC!(2, 1) * cgetRC!(3, 2)) + cgetRC!(1, 1) * (cgetRC!(2, 0) * cgetRC!(3, 2) - cgetRC!(2, 2) * cgetRC!(3, 0)) + cgetRC!(1, 2) * (cgetRC!(2, 1) * cgetRC!(3, 0) - cgetRC!(2, 0) * cgetRC!(3, 1));
                    res.csetRC!(3, 1) = cgetRC!(2, 0) * (cgetRC!(0, 2) * cgetRC!(3, 1) - cgetRC!(0, 1) * cgetRC!(3, 2)) + cgetRC!(2, 1) * (cgetRC!(0, 0) * cgetRC!(3, 2) - cgetRC!(0, 2) * cgetRC!(3, 0)) + cgetRC!(2, 2) * (cgetRC!(0, 1) * cgetRC!(3, 0) - cgetRC!(0, 0) * cgetRC!(3, 1));
                    res.csetRC!(3, 2) = cgetRC!(3, 0) * (cgetRC!(0, 2) * cgetRC!(1, 1) - cgetRC!(0, 1) * cgetRC!(1, 2)) + cgetRC!(3, 1) * (cgetRC!(0, 0) * cgetRC!(1, 2) - cgetRC!(0, 2) * cgetRC!(1, 0)) + cgetRC!(3, 2) * (cgetRC!(0, 1) * cgetRC!(1, 0) - cgetRC!(0, 0) * cgetRC!(1, 1));
                    res.csetRC!(3, 3) = cgetRC!(0, 0) * (cgetRC!(1, 1) * cgetRC!(2, 2) - cgetRC!(1, 2) * cgetRC!(2, 1)) + cgetRC!(0, 1) * (cgetRC!(1, 2) * cgetRC!(2, 0) - cgetRC!(1, 0) * cgetRC!(2, 2)) + cgetRC!(0, 2) * (cgetRC!(1, 0) * cgetRC!(2, 1) - cgetRC!(1, 1) * cgetRC!(2, 0));
                }
                
                flt det_ = this.determinant();
            } else
            static assert (false);
            
            static if (optimizeDivWithReciprocalMul!(flt)) {
                flt rdet = cscalar!(flt, 1) / det_;
                res *= rdet;
            } else {
                res /= det_;
            }
            return res;
        }
        
        
        void invert() {
            *this = inverse();
        }
    }
    
    
    private void opXAssign_(string x)(flt rhs) {
        assert (ok);
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                mixin("col[c].row[r]"~x~"=rhs;");
                //.opXAssign!(x)(col[c].row[r], rhs);
            }
        }
    }
    public alias opXAssign_!("+")   opAddAssign;
    public alias opXAssign_!("-")   opSubAssign;
    public alias opXAssign_!("*")   opMulAssign;
    
    static if (fieldOps) {
        public alias opXAssign_!("/")   opDivAssign;
    }

    private Matrix opX_(string x)(flt rhs) {
        Matrix res = *this;
        res.opXAssign_!(x)(rhs);
        return res;
    }

    public alias opX_!("+") opAdd;
    public alias opX_!("-")     opSub;
    public alias opX_!("*") opMul;

    static if (fieldOps) {
        public alias opX_!("/")     opDiv;
    }

    void set(V,int rows, int cols)(ref Matrix!(V,rows,cols) o){
        assert (o.ok);
        
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                col[c].row[r] = scalar!(flt)(o.col[c].row[r]);
            }
        }
    }
    void set()(flt o){
        assert (ok);
        
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                col[c].row[r] = o;
            }
        }
    }
    alias set opSliceAssign;

    private void opMXAssign_(string x)(ref Matrix rhs) {
        assert (ok);
        assert (rhs.ok);
        
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                //.opXAssign!(x)(col[c].row[r], rhs.col[c].row[r]);
                mixin("col[c].row[r] " ~ x ~ "= rhs.col[c].row[r];");
            }
        }
    }
    
    public alias opMXAssign_!("+")  opAddAssign;
    public alias opMXAssign_!("-")      opSubAssign;
    
    Matrix opMul(ref Matrix rhs) {
        assert (ok);
        assert (rhs.ok);
        
        Matrix res = void;
        foreach (c; Range!(cols)) {
            foreach (r; Range!(rows)) {
                res.col[c].row[r] = cscalar!(flt, 0);
                foreach (i; Range!(cols)) {
                    mixin(_rc!(r, c)(`res`) ~ `+= ` ~ _rc!(r, i)(`this`) ~ `*` ~ _rc!(i, c)(`rhs`) ~ `;`);
                    /+static if (rows == cols) {
                        res.col[c].row[r] += this.col[i].row[r] * rhs.col[c].row[i];
                    } else {
                        .opXAssign!("+")(res.col[c].row[r], this.cgetRC!(r, i) * rhs.cgetRC!(i, c));
                    }+/
                }
            }
        }
        return res;
    }
    
    
    void opMulAssign(ref Matrix rhs) {
        *this = opMul(rhs);
    }
    
    
    // matrix * vector
    Vector!(flt, i) opVecMul(int i)(Vector!(flt, i) rhs) {
        assert (ok);
        assert (rhs.ok);

        auto res = Vector!(flt, i).zero;
        foreach (r; Range!(i)) {
            foreach (c; Range!(cols)) {
                static if (r >= rows) {
                    static if (r == c) {
                        const flt prod1 = cscalar!(flt, 1);
                    } else {
                        const flt prod1 = cscalar!(flt, 0);
                    }
                } else {
                    mixin("flt prod1 = " ~ _rc!(r, c)("this") ~ ";");
                    //flt prod1 = cgetRC!(r, c)();
                }
                
                static if (c >= i) {
                    const flt prod2 = cscalar!(flt, 1);
                } else {
                    flt prod2 = rhs.cell[c];
                }
                
                //.opXAssign!("+")(res.cell[r], prod1 * prod2);
                res.cell[r] += prod1 * prod2;
            }
        }
        return res;
    }


    // vector * matrix
    Vector!(flt, i) opVecMul_r(int i)(Vector!(flt, i) rhs) {
        assert (ok);
        assert (rhs.ok);

        auto res = Vector!(flt, i).zero;
        foreach (c; Range!(cols)) {
            foreach (r; Range!(i)) {
                static if (r >= rows) {
                    static if (r == c) {
                        const flt prod1 = cscalar!(flt, 1);
                    } else {
                        const flt prod1 = cscalar!(flt, 0);
                    }
                } else {
                    mixin("flt prod1 = " ~ _rc!(r, c)("this") ~ ";");
                    //flt prod1 = cgetRC!(r, c)();
                }
                
                static if (r >= i) {
                    const flt prod2 = cscalar!(flt, 1);
                } else {
                    flt prod2 = rhs.cell[r];
                }
                
                //.opXAssign!("+")(res.cell[r], prod1 * prod2);
                res.cell[c] += prod1 * prod2;
            }
        }
        return res;
    }

    
    alias opVecMul!(2)  xform;
    alias opVecMul!(3)  xform;
    alias opVecMul!(4)  xform;
    alias xform opMul;
    

    Matrix opNeg() {
        Matrix res = void;
        foreach (r; Range!(rows)) {
            foreach (c; Range!(cols)) {
                res.col[c].row[r] = this.col[c].row[r];
            }
        }
        return res;
    }

    
    static if (rows >= 3) {
        /// angle in degrees
        static Matrix xRotation(real angle) {
            assert (!isNaN(angle));
            Matrix res = Matrix.identity;

            flt Sin = scalar!(flt)(sin(angle * deg2rad));
            flt Cos = scalar!(flt)(cos(angle * deg2rad));
            
            res.csetRC!(1, 1) = Cos;
            res.csetRC!(2, 1) = Sin;
            res.csetRC!(2, 2) = Cos;
            res.csetRC!(1, 2) = -Sin;
            
            return res;
        }


        /// angle in degrees
        static Matrix yRotation(real angle) {
            assert (!isNaN(angle));
            Matrix res = Matrix.identity;

            flt Sin = scalar!(flt)(sin(angle * deg2rad));
            flt Cos = scalar!(flt)(cos(angle * deg2rad));
            
            res.csetRC!(0, 0) = Cos;
            res.csetRC!(2, 0) = -Sin;
            res.csetRC!(2, 2) = Cos;
            res.csetRC!(0, 2) = Sin;
            
            return res;
        }

        static Matrix scaling(Vector!(flt, 3) v) {
            assert (v.ok);
            Matrix res = Matrix.identity;
            res.csetRC!(0, 0) = v.x;
            res.csetRC!(1, 1) = v.y;
            res.csetRC!(2, 2) = v.z;
            return res;
        }
    } else static if (2 == rows && 2 == cols) {
        static Matrix scaling(Vector!(flt, 2) v) {
            assert (v.ok);
            Matrix res = Matrix.identity;
            res.csetRC!(0, 0) = v.x;
            res.csetRC!(1, 1) = v.y;
            return res;
        }
    }

    static if (rows >= 2) {
        /// angle in degrees
        static Matrix zRotation(real angle) {
            assert (!isNaN(angle));
            Matrix res = Matrix.identity;

            flt Sin = scalar!(flt)(sin(angle * deg2rad));
            flt Cos = scalar!(flt)(cos(angle * deg2rad));
            
            res.csetRC!(0, 0) = Cos;
            res.csetRC!(0, 1) = -Sin;
            res.csetRC!(1, 1) = Cos;
            res.csetRC!(1, 0) = Sin;
            
            return res;
        }
    }
    
    
    static if (4 == cols) {
        Matrix!(flt, 3, 3) getRotation() {
            assert (ok);
            Matrix!(flt, 3, 3) res = void;
            foreach (i; Range!(3)) {
                foreach (j; Range!(3)) {
                    res.csetRC!(i, j) = cgetRC!(i, j);
                }
            }
            return res;
        }
        

        void setRotation(Matrix!(flt, 3, 3) rot) {
            assert (ok);
            foreach (i; Range!(3)) {
                foreach (j; Range!(3)) {
                    csetRC!(i, j) = rot.cgetRC!(i, j);
                }
            }
        }

        
        Vector!(flt, 3) getTranslation() {
            assert (ok);
            mixin("return Vector!(flt, 3)("~_rc!(0, 3)("this")~", "~_rc!(1, 3)("this")~", "~_rc!(2, 3)("this")~");");
        }
        

        static if (cols >= 4) {
            void setTranslation(Vector!(flt, 3) v) {
                assert (v.ok);
                mixin(_rc!(0, 3)("this")~" = v.x;");
                mixin(_rc!(1, 3)("this")~" = v.y;");
                mixin(_rc!(2, 3)("this")~" = v.z;");
            }
        }

        
        static Matrix translation(Vector!(flt, 3) v) {
            assert (v.ok);
            Matrix res = Matrix.identity;
            mixin(_rc!(0, 3)("res")~" = v.x;");
            mixin(_rc!(1, 3)("res")~" = v.y;");
            mixin(_rc!(2, 3)("res")~" = v.z;");
            return res;
        }
        
        
        static if (4 == rows) {
            static Matrix perspective(real fov, real aspect, real near, real far) {
                assert (fov <>= 0 && aspect <>= 0 && near <>= 0 && far <>= 0);
                assert (fov > 0 && fov < 180);
                
                real fd = 1.0 / tan(fov * 0.5 * deg2rad);

                Matrix res = Matrix.identity;
                res.csetRC!(0, 0)(scalar!(flt)(fd / aspect));
                res.csetRC!(1, 1)(scalar!(flt)(fd));
                res.csetRC!(2, 2)(scalar!(flt)((far + near) / (near - far)));
                res.csetRC!(2, 3)(scalar!(flt)((2 * far * near) / (near - far)));
                res.csetRC!(3, 2)(cscalar!(flt, -1));
                res.csetRC!(3, 3)(cscalar!(flt, 0));
                
                return res;
            }


            static Matrix ortho(real left, real right, real bottom, real top, real near, real far) {
                assert (left <>= 0 && right <>= 0 && bottom <>= 0 && top <>= 0 && near <>= 0 && far <>= 0);
                Matrix res = Matrix.identity;
                res.csetRC!(0, 0)(scalar!(flt)(2.0 / (right - left)));
                res.csetRC!(1, 1)(scalar!(flt)(2.0 / (top - bottom)));
                res.csetRC!(2, 2)(scalar!(flt)(-2.0 / (far - near)));
                res.csetRC!(0, 3)(scalar!(flt)(-(right + left) / (right - left)));
                res.csetRC!(1, 3)(scalar!(flt)(-(top + bottom) / (top - bottom)));
                res.csetRC!(2, 3)(scalar!(flt)(-(far + near) / (far - near)));
                return res;
            }
        }
    }
    
    
    string toString() {
        string row(int r) {
            string res = "(" ~ convTo!(string )(getRC(r, 0));
            for (int i = 1; i < cols; ++i) {
                res ~= "," ~ convTo!(string )(getRC(r, i));
            }
            return res ~ ")";
        }
        string res = "[" ~ row(0);
        for (int i = 1; i < rows; ++i) {
            res ~= "; " ~ row(i);
        }
        return res ~ "]";
    }
    
    
    flt* ptr() {
        return &col[0].row[0];
    }
    
    
    bool opEquals(ref Matrix rhs) {
        foreach (r; Range!(rows)) {
            foreach (c; Range!(cols)) {
                if (col[c].row[r] != rhs.col[c].row[r]) {
                    return false;
                }
            }
        }
        return true;
    }

    /// outer op, implement for non square???
    static Matrix outerOp(Vector!(flt,rows) v1,Vector!(flt,cols) v2,Matrix m=zero,
                 flt scaleAB=1, flt scaleTarget=1){
        m.csetRC!(0,0)(m.cgetRC!(0,0)*scaleTarget+scaleAB*v1.x*v2.x);
        static if (cols>1) m.csetRC!(0,1)(m.cgetRC!(0,1)*scaleTarget+scaleAB*v1.x*v2.y);
        static if (cols>2) m.csetRC!(0,2)(m.cgetRC!(0,2)*scaleTarget+scaleAB*v1.x*v2.z);
        static if (cols>3) m.csetRC!(0,3)(m.cgetRC!(0,3)*scaleTarget+scaleAB*v1.x*v2.w);
        static if (rows>1){
            m.csetRC!(1,0)(m.cgetRC!(1,0)*scaleTarget+scaleAB*v1.y*v2.x);
            static if (cols>1) m.csetRC!(1,1)(m.cgetRC!(1,1)*scaleTarget+scaleAB*v1.y*v2.y);
            static if (cols>2) m.csetRC!(1,2)(m.cgetRC!(1,2)*scaleTarget+scaleAB*v1.y*v2.z);
            static if (cols>3) m.csetRC!(1,3)(m.cgetRC!(1,3)*scaleTarget+scaleAB*v1.y*v2.w);
        }
        static if (rows>2){
            m.csetRC!(2,0)(m.cgetRC!(2,0)*scaleTarget+scaleAB*v1.z*v2.x);
            static if (cols>1) m.csetRC!(2,1)(m.cgetRC!(2,1)*scaleTarget+scaleAB*v1.z*v2.y);
            static if (cols>2) m.csetRC!(2,2)(m.cgetRC!(2,2)*scaleTarget+scaleAB*v1.z*v2.z);
            static if (cols>3) m.csetRC!(2,3)(m.cgetRC!(2,3)*scaleTarget+scaleAB*v1.z*v2.w);
        }
        static if (rows>3){
            m.csetRC!(3,0)(m.cgetRC!(3,0)*scaleTarget+scaleAB*v1.w*v2.x);
            static if (cols>1) m.csetRC!(3,1)(m.cgetRC!(3,1)*scaleTarget+scaleAB*v1.w*v2.y);
            static if (cols>2) m.csetRC!(3,2)(m.cgetRC!(3,2)*scaleTarget+scaleAB*v1.w*v2.z);
            static if (cols>3) m.csetRC!(3,3)(m.cgetRC!(3,3)*scaleTarget+scaleAB*v1.w*v2.w);
        }
        static assert(rows<=4&&cols<=4);
        return m;
    }
}

string Matrix_rc(int rows,int cols,int r, int c,string src) {
    bool isExtended = rows + 1 == cols;
    if (r == rows && isExtended) {
            if (r == c) {
            return "cscalar!(flt, 1)";
        } else {
            return "cscalar!(flt, 0)";
        }
    } else {
        return src ~ ".col["~ctfe_i2a(c)~"].row["~ctfe_i2a(r)~"]";
    }
}


alias Matrix!(float, 2, 2)  mat2;
alias Matrix!(float, 3, 3)  mat3;
alias Matrix!(float, 3, 4)  mat34;
alias Matrix!(float, 4, 4)  mat4;



// ------------------------------------------------------------------------------------------------------------------------------------------------------------
// Quaternion
// ------------------------------------------------------------------------------------------------------------------------------------------------------------


/// Meant to be used for rotations in 3D, the norm is assumed to be 1, unless floating point errors jump in
struct Quaternion(flt_) {
    alias flt_ flt;
    static assert (isFieldType!(flt));
    
    union {
        struct {
            flt x, y, z, w;
        }
        .Vector!(flt, 4) xyzw;
    }
    
    mixin(serializeSome("Quaternion!("~flt_.stringof~")","a quaternion","x|y|z|w"));
    
    const static Quaternion identity = { x: cscalar!(flt, 0), y: cscalar!(flt, 0), z: cscalar!(flt, 0), w: cscalar!(flt, 1) };
    
    static Quaternion from(T)(Quaternion!(T) q){
        Quaternion res;
        res.x=convertTo!(flt_)(q.x);
        res.y=convertTo!(flt_)(q.y);
        res.z=convertTo!(flt_)(q.z);
        res.w=convertTo!(flt_)(q.w);
        return res;
    }

    bool ok() {
        if (isNaN(x)) return false;
        if (isNaN(y)) return false;
        if (isNaN(z)) return false;
        if (isNaN(w)) return false;
        return true;
    }
    
    string toString(){
        return xyzw.toString; // TODO better
    }
    
    // :P
    alias ok isOK;
    alias ok isCorrect;

    
    static Quaternion opCall(ref typeof(xyzw) vec) {
        Quaternion res = void;
        res.xyzw = vec;
        assert (res.ok);
        return res;
    }
    
    
    static Quaternion opCall(flt x, flt y, flt z, flt w) {
        Quaternion res = void;
        res.x = x;
        res.y = y;
        res.z = z;
        res.w = w;
        assert (res.ok);
        return res;
    }
    
    
    static Quaternion opCall(Matrix!(flt, 3, 3) m) {
        real trace = cast(real)(m.cgetRC!(0, 0) + m.cgetRC!(1, 1) + m.cgetRC!(2, 2)) + 1;
        if (trace > 0.00000001) {
            real S = sqrt(trace) * 2;
            return Quaternion(
                scalar!(flt)(cast(real)(m.cgetRC!(2, 1) - m.cgetRC!(1, 2)) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(0, 2) - m.cgetRC!(2, 0)) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(1, 0) - m.cgetRC!(0, 1)) / S),
                scalar!(flt)(0.25 * S)
            );
        } else if ( m.cgetRC!(0, 0) > m.cgetRC!(1, 1) && m.cgetRC!(0, 0) > m.cgetRC!(2, 2) ) {
            real S = sqrt( 1.0 + cast(real)(m.cgetRC!(0, 0) - m.cgetRC!(1, 1) - m.cgetRC!(2, 2)) ) * 2;
            return Quaternion(
                scalar!(flt)(0.25 * S),
                scalar!(flt)(cast(real)(m.cgetRC!(0, 1) + m.cgetRC!(1, 0) ) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(2, 0) + m.cgetRC!(0, 2) ) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(2, 1) - m.cgetRC!(1, 2) ) / S)
            );
        } else if ( m.cgetRC!(1, 1) > m.cgetRC!(2, 2) ) {
            real S = sqrt( 1.0 + cast(real)(m.cgetRC!(1, 1) - m.cgetRC!(0, 0) - m.cgetRC!(2, 2)) ) * 2;
            return Quaternion(
                scalar!(flt)(cast(real)(m.cgetRC!(0, 1) + m.cgetRC!(1, 0) ) / S),
                scalar!(flt)(0.25 * S),
                scalar!(flt)(cast(real)(m.cgetRC!(1, 2) + m.cgetRC!(2, 1) ) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(0, 2) - m.cgetRC!(2, 0) ) / S)
            );
        } else {
            real S = sqrt( 1.0 + cast(real)(m.cgetRC!(2, 2) - m.cgetRC!(0, 0) - m.cgetRC!(1, 1)) ) * 2;
            return Quaternion(
                scalar!(flt)(cast(real)(m.cgetRC!(2, 0) + m.cgetRC!(0, 2) ) / S),
                scalar!(flt)(cast(real)(m.cgetRC!(1, 2) + m.cgetRC!(2, 1) ) / S),
                scalar!(flt)(0.25 * S),
                scalar!(flt)(cast(real)(m.cgetRC!(1, 0) - m.cgetRC!(0, 1) ) / S)
            );
        }
    }
    
    
    flt magnitude() {
        assert (ok);
        return scalar!(flt)(sqrt(cast(real)(x * x + y * y + z * z + w * w)));
    }


    void normalize() {
        assert (ok);
        flt det = magnitude();
        static if (optimizeDivWithReciprocalMul!(flt)) {
            det = cscalar!(flt, 1) / det;
            x *= det;
            y *= det;
            z *= det;
            w *= det;
        } else {
            x /= det;
            y /= det;
            z /= det;
            w /= det;
        }
    }
    
    
    Quaternion normalized() {
        Quaternion res = *this;
        res.normalize();
        return res;
    }


    void invert() {
        assert (ok);
        x = -x;
        y = -y;
        z = -z;
    }
    
    
    Quaternion inverse() {
        assert (ok);
        return Quaternion(-x, -y, -z, w);
    }
    

    // Right-handed rotation around vector [1.0; 0.0; 0.0]
    static Quaternion xRotation(real angle) {
        assert (angle <>= 0);
        Quaternion res = void;
        
        angle *= deg2rad * 0.5;
        res.w = scalar!(flt)(cos(angle));
        res.x = scalar!(flt)(sin(angle));
        res.y = cscalar!(flt, 0);
        res.z = cscalar!(flt, 0);
        
        assert (res.ok);
        return res;
    }
    
    
    // Right-handed rotation around vector [0.0; 1.0; 0.0]
    static Quaternion yRotation(real angle) {
        assert (angle <>= 0);
        Quaternion res = void;
        
        angle *= deg2rad * 0.5;
        res.w = scalar!(flt)(cos(angle));
        res.x = cscalar!(flt, 0);
        res.y = scalar!(flt)(sin(angle));
        res.z = cscalar!(flt, 0);
        
        assert (res.ok);        
        return res;
    }
    
    // Right-handed rotation around vector [0.0; 0.0; 1.0]
    static Quaternion zRotation(real angle) {
        assert (angle <>= 0);
        Quaternion res = void;
        
        angle *= deg2rad * 0.5;
        res.w = scalar!(flt)(cos(angle));
        res.x = cscalar!(flt, 0);
        res.y = cscalar!(flt, 0);
        res.z = scalar!(flt)(sin(angle));
        
        assert (res.ok);        
        return res;
    }


    // the axis must be normalized
    static Quaternion axisRotation(.Vector!(flt, 3) axis, real angle) {
        if (0 == angle) {
            return Quaternion.identity;
        }
        assert (axis.isUnit);
        assert (angle <>= 0);
        flt sinA    = scalar!(flt)(sin(angle * 0.5 ));
        flt cosA    = scalar!(flt)(cos(angle * 0.5 ));
        return Quaternion(axis.x * sinA, axis.y * sinA, axis.z * sinA, cosA);
    }

    Quaternion opAdd(ref Quaternion b){
        Quaternion res=*this;
        res+=b;
        return res;
    }
    void opAddAssign(ref Quaternion b){
        x+=b.x;
        y+=b.y;
        z+=b.z;
        auto norm=sqrt(x*x+y*y+z*z);
        flt fr=norm-2*floor(norm/2);
        if (fr>1) fr=2-fr;
        auto det=fr/norm;
        x*=det;
        y*=det;
        z*=det;
        w=1-fr*fr;
    }

    Matrix!(flt, rows, cols) toMatrix(int rows = 3, int cols = 3)() {
        static assert (rows >= 3);
        static assert (cols >= 3);
        
        assert (ok);
        static if (3 == rows && 3 == cols) {
            Matrix!(flt, rows, cols) res = void;
        } else {
            Matrix!(flt, rows, cols) res = Matrix!(flt, rows, cols).identity;
        }
        
        flt x2 = x + x;
        flt y2 = y + y; 
        flt z2 = z + z;
        
        flt xx = x * x2;    flt xy = x * y2;    flt xz = x * z2;
        flt yy = y * y2;    flt yz = y * z2;    flt zz = z * z2;
        flt wx = w * x2;    flt wy = w * y2;    flt wz = w * z2;
        
        mixin(Matrix_rc(rows,cols,0, 0,"res")~" = cscalar!(flt, 1) - yy - zz;");
        mixin(Matrix_rc(rows,cols,1, 0,"res")~" = xy + wz;");
        mixin(Matrix_rc(rows,cols,2, 0,"res")~" = xz - wy;");
        
        mixin(Matrix_rc(rows,cols,0, 1,"res")~" = xy - wz;");
        mixin(Matrix_rc(rows,cols,1, 1,"res")~" = cscalar!(flt, 1) - xx - zz;");
        mixin(Matrix_rc(rows,cols,2, 1,"res")~" = yz + wx;");
        
        mixin(Matrix_rc(rows,cols,0, 2,"res")~" = xz + wy;");
        mixin(Matrix_rc(rows,cols,1, 2,"res")~" = yz - wx;");
        mixin(Matrix_rc(rows,cols,2, 2,"res")~" = cscalar!(flt, 1) - xx - yy;");
        
        return res;
    }


    void getAxisAngle(out Vector!(flt, 3) axis, out real angle) {
        normalize();
        
        real cos_a = cast(real)w;
        angle = acos(cos_a) * 2.0;
        
        real sin_a_ = sqrt(1.0 - cos_a * cos_a);
        
        if (sin_a_ < 0.0005 && sin_a_ > -0.0005) {
            axis.x = x;
            axis.y = y;
            axis.z = z;
        } else {
            flt sin_a = scalar!(flt)(sin_a_);

            static if (optimizeDivWithReciprocalMul!(flt)) {
                sin_a = cscalar!(flt, 1) / sin_a;
                axis.x = x * sin_a;
                axis.y = y * sin_a;
                axis.z = z * sin_a;
            } else {
                axis.x = x / sin_a;
                axis.y = y / sin_a;
                axis.z = z / sin_a;
            }
        }
    }


    void opMulAssign(ref Quaternion rhs) {
        *this = this.opMul(rhs);
    }


    Quaternion opMul(ref Quaternion rhs) {
        assert (ok);
        assert (rhs.ok);
        Quaternion res = void;
        res.x = w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y;
        res.y = w * rhs.y + y * rhs.w + z * rhs.x - x * rhs.z;
        res.z = w * rhs.z + z * rhs.w + x * rhs.y - y * rhs.x;
        res.w = w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z;
        return res;
    }
    

    Quaternion inverseMult(Quaternion rhs) {
        return rhs.opMul(*this);
    }


    Quaternion opMul(real t) {
        Quaternion res = slerp(Quaternion.identity, *this, t);
        return res;
    }
    
    void opBypax(V)(V v,flt a=cscalar!(flt,1),flt b=cscalar!(flt,1)){
        static assert(is(U==Quaternion!(U.flt)),"opBypax only between quaternions, not "~V.stringof);
        if (b==cscalar!(flt,1)){
            x+=a*v.x;
            y+=a*v.y;
            z+=a*v.z;
        } else {
            x=b*x+a*v.x;
            y=b*y+a*v.y;
            z=b*z+a*v.z;
        }
        auto norm=sqrt(x*x+y*y+z*z);
        flt fr=norm-2*floor(norm/2);
        if (fr>1) fr=2-fr;
        auto det=fr/norm;
        x*=det;
        y*=det;
        z*=det;
        w=1-fr*fr;
    }
    
    static Quaternion slerp(Quaternion A, Quaternion B, real time) {
        assert (A.ok);
        assert (B.ok);
        assert (time <>= 0);

        Quaternion res = void;
        
        real scale1 = void;
        real scale2 = void;
        
        // compute dot product, aka cos(theta):
        real cosTheta = cast(real)(A.x*B.x + A.y*B.y + A.z*B.z + A.w*B.w);
        
        if (cosTheta < 0) {
            // flip the 'start' quat
            A.x = -A.x;
            A.y = -A.y;
            A.z = -A.z;
            A.w = -A.w;
            cosTheta = -cosTheta;
        }
        
        if ((cosTheta + 1) > 0.05) {
            // If the quats are close, use linear interploation
            if ((1.0 - cosTheta) < 0.05) {
                scale1 = 1.0 - time;
                scale2 = time;
            }
            else { 
                // Otherwise, do spherical interpolation
                real theta      = acos(cosTheta);
                real sinTheta   = sin(theta);
                scale1 = sin(theta * (1.0 - time)) / sinTheta;
                scale2 = sin(theta * time) / sinTheta;
            }
        } else {
            B.x = -A.y;
            B.y =  A.x;
            B.z = -A.w;
            B.w =  A.z;
            scale1 = sin(pi * (0.5 - time));
            scale2 = sin(pi * time);
        }
        
        flt s1 = scalar!(flt)(scale1);
        flt s2 = scalar!(flt)(scale2);
        
        res.x = s1 * A.x + s2 * B.x;
        res.y = s1 * A.y + s2 * B.y;
        res.z = s1 * A.z + s2 * B.z;
        res.w = s1 * A.w + s2 * B.w;
        
        return res;
    }
    
    
    Quaternion deltaFrom(Quaternion other) {
        assert (ok);
        assert (other.ok);
        other.invert();
        return other * *this;
    }


    T xform(T)(T rhs) {
        assert (ok);
        assert (rhs.ok);

        real rx = cast(real)x;
        real ry = cast(real)y;
        real rz = cast(real)z;
        real rw = cast(real)w;
        
        real rrx = cast(real)rhs.x;
        real rry = cast(real)rhs.y;
        real rrz = cast(real)rhs.z;
        
        real a = rw * rw - (rx * rx + ry * ry + rz * rz);
        real b = 2.0 * (rx * rrx + ry * rry + rz * rrz);
        real c = 2.0 * rw;
        
        real cross[3];
        cross[0] = ry * rrz - rz * rry;
        cross[1] = rz * rrx - rx * rrz;
        cross[2] = rx * rry - ry * rrx;
        
        return T[
            a * rrx + b * rx + c * cross[0],
            a * rry + b * ry + c * cross[1],
            a * rrz + b * rz + c * cross[2]
        ];
    }


    real yaw() {
        assert (ok);
        return atan2(cast(real)(cscalar!(flt, 2) * (w*y + x*z)), cast(real)(w*w - x*x - y*y + z*z));
    }


    real pitch() {
        assert (ok);
        return asin(cast(real)(cscalar!(flt, 2) * (w*x - y*z)));
    }


    real roll() {
        assert (ok);
        return atan2(cast(real)(cscalar!(flt, 2) * (w*z + x*y)), cast(real)(w*w - x*x + y*y - z*z));
    }
    
    
    flt* ptr() {
        assert (ok);
        return &x;
    }
    
    
    bool opEquals(ref Quaternion rhs) {
        return xyzw.opEquals(rhs.xyzw);
    }
}


alias Quaternion!(float)        quat;


static T cross(T)(T a, T b) {
    assert (a.ok && b.ok);
    return T(
        a.y * b.z - b.y * a.z,
        a.z * b.x - b.z * a.x,
        a.x * b.y - b.x * a.y
    );
}
