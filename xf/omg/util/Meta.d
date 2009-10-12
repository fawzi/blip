module xf.omg.util.Meta;

import tango.core.Tuple;

private template RangeImpl(int i, T ...) {
	static if (i > 0) {
		alias .RangeImpl!(i-1, i-1, T) RangeImpl;
	} else {
		alias T RangeImpl;
	}
}


template Range(int i) {
	alias RangeImpl!(i) Range;
}


template Repeat(T, int count) {
	static if (!count) {
		alias Tuple!() Repeat;
	} else {
		alias Tuple!(T, Repeat!(T, count-1)) Repeat;
	}
}
