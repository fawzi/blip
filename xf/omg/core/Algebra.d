module xf.omg.core.Algebra;

private {
	import tango.core.Traits;
}



template cscalar(T, real value) {
	static if (is(typeof(T.ctFromReal!(value)) == T)) {		// compile-time version
		const T cscalar = T.ctFromReal!(value);
	} else static if (is(typeof(T.fromReal(value)) == T)) {
		const T cscalar = T.fromReal(value);
	} else {
		const T cscalar = cast(T)value;
	}
}


template scalar(T) {
	T scalar(S)(S value) {
		static if (is(T == S)) {
			return value;
		} else static if (is(typeof(T.fromReal(value)) == T)) {
			return T.fromReal(value);
		} else {
			return cast(T)value;
		}
	}
}


template negativeMax(T) {
	static if (isFloatingPointType!(T)) {
		const T negativeMax = -T.max;
	} else {
		const T negativeMax = T.min;
	}
}


template _TypeInstance(T) {
	T _TypeInstance;
}


/**
	Checks whether the type supports multiplication, addition and subtraction.
	This slightly differs from the theory, where a field must only support multiplication
	and addition. In maths, they must also support opposite elements, so
	this is more or less the same
*/
template isRingType(T) {
	static if (
		is(typeof(T.init * T.init) : T) &&
		is(typeof(T.init + T.init) : T) &&
		is(typeof(T.init - T.init) : T) &&
		is(typeof(_TypeInstance!(T) *= T.init)) &&
		is(typeof(_TypeInstance!(T) += T.init)) &&
		is(typeof(_TypeInstance!(T) -= T.init))
	) {
		const bool isRingType = true;
	} else {
		const bool isRingType = false;
	}
}


/**
	Checks whether the type supports multiplication, division, addition and subtraction.
	This slightly differs from the theory, where a field must only support multiplication
	and addition. In maths, they must also support inverse and opposite elements, so
	this is more or less the same
*/
template isFieldType(T) {
	static if (
		isRingType!(T) &&
		is(typeof(T.init / T.init) : T) &&
		is(typeof(_TypeInstance!(T) /= T.init))
	) {
		const bool isFieldType = true;
	} else {
		const bool isFieldType = false;
	}
}


template isVectorType(T, int dim) {
	static if (
		is(typeof(T.dim)) &&
		is(typeof(T.dim == dim)) &&
		T.dim == dim
	) {
		const bool isVectorType = true;
	} else {
		const bool isVectorType = false;
	}
}



static assert (isFieldType!(float));
static assert (isFieldType!(double));
static assert (isFieldType!(real));
static assert (isRingType!(int));
static assert (isRingType!(long));
static assert (isRingType!(ubyte));
static assert (!isRingType!(Object));



template opXAssign(char[] op) {
	void opXAssign(T1, T2)(ref T1 lhs, T2 rhs) {
		static if (mixin("is(typeof(lhs "~op~"= rhs))")) {
			mixin("lhs "~op~"= rhs;");
		} else {
			mixin("lhs = lhs "~op~" rhs;");
		}
	}
}


/+T oppositeElement(T)(T a) {
	static if (is(typeof(-a) : T)) {
		return -a;
	} else {
		return cscalar!(T, 0) - a;
	}
}+/



bool isNaN(T)(T a) {
	static if (is(typeof(T.init.isNaN()) : bool)) {
		return a.isNaN();
	} else static if (isFloatingPointType!(T)) {
		return a !<>= 0;
	} else static if(isIntegerType!(T)) {
		return false;
	} else {
		return true;
	}
}



template optimizeDivWithReciprocalMul(T) {
	const bool optimizeDivWithReciprocalMul = isFloatingPointType!(T);
}
