module xf.omg.core.Fixed;
version(NoFix){} else {
private {
	import tango.util.Convert : convTo = to;
	import tango.math.Math : rndint;
	import tango.math.IEEE : RoundingMode, getIeeeRounding;
	import blip.serialization.Serialization;
	import blip.serialization.SerializationMixins;
	import tango.core.Traits;
}



struct fixed32T(int fracBits_) {
	const	int fracBits = fracBits_;
	public	int store = 0;
	
	const	fixed32T max = { store: int.max };
	const	fixed32T min = { store: int.min };
	
	const 	int maxInt = (1 << (31 - fracBits)) - 1;
	const 	int minInt = -(1 << (31 - fracBits));
	
	static assert (((maxInt << fracBits) >> fracBits) == maxInt);
	static assert ((((maxInt+1) << fracBits) >> fracBits) != maxInt+1);
	static assert (((minInt << fracBits) >> fracBits) == minInt);
	static assert ((((minInt-1) << fracBits) >> fracBits) != minInt-1);
	
    static ClassMetaInfo metaI;
    static this(){
        metaI=ClassMetaInfo.createForType!(typeof(this))("fixed32T!("~ctfe_i2a(fracBits)~")");
        metaI.addFieldOfType!(int)("int","integer part");
        metaI.addFieldOfType!(int)("frac","fractional part");
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        int i=store>>fracBits_;
        int f=store & ((1<<fracBits_)-1);
        s.field(metaI[0],i);
        s.field(metaI[1],f);
    }
    void unserialize(Unserializer s){
        int i,f;
        s.field(metaI[0],i);
        s.field(metaI[1],f);
        store=i<<fracBits_;
        store |= f & ((1<<fracBits_)-1);
    }
	
	static fixed32T fromReal(real val) {
		assert (val >= cast(real)minInt && val <= cast(real)maxInt);
		fixed32T res = void;
		// HACK: getIeeeRounding doesn't work if there's no D_InlineAsm_X86, as of Tango rev. 4873
		//assert (getIeeeRounding() == RoundingMode.ROUNDTONEAREST);
		res.store = rndint(val * (1 << fracBits));
		return res;
	}


	template ctFromReal(real val) {
		static assert (val >= cast(real)minInt && val <= cast(real)maxInt);
		const fixed32T ctFromReal = { store : cast(int)(val * (1 << fracBits)) };
	}


	static fixed32T fromInt(int val) {
		assert (val >= minInt && val <= maxInt);
		val <<= fracBits;
		fixed32T res = void;
		res.store = val;
		return res;
	}
	

	alias fromReal opCall;
	alias fromInt opCall;
	
	
	void opAddAssign(fixed32T rhs) {
		store += rhs.store;
	}
	
	
	void opSubAssign(fixed32T rhs) {
		store -= rhs.store;
	}
	
	
	void opMulAssign(fixed32T rhs) {
		store = cast(int)((cast(long)rhs.store * store) >> fracBits);
	}


	// we'll allow scaling by real as scaling is often used in various interpolation functions
	void opMulAssign(real rhs) {
		store = cast(int)(cast(real)store * rhs);
	}
	
	
	void opDivAssign(fixed32T rhs) {
		long st = store;
		st <<= fracBits;
		st /= rhs.store;
		store = cast(int)st;
	}
	
	
	fixed32T opAdd(fixed32T rhs) {
		fixed32T res = *this;
		res += rhs;
		return res;
	}


	fixed32T opSub(fixed32T rhs) {
		fixed32T res = *this;
		res -= rhs;
		return res;
	}


	fixed32T opMul(fixed32T rhs) {
		fixed32T res = *this;
		res *= rhs;
		return res;
	}


	fixed32T opMul(real rhs) {
		fixed32T res = *this;
		res *= rhs;
		return res;
	}


	fixed32T opDiv(fixed32T rhs) {
		fixed32T res = *this;
		res /= rhs;
		return res;
	}
	

	fixed32T opNeg() {
		fixed32T res;
		res.store = -store;
		return res;
	}

	
	int opCmp(fixed32T rhs) {
		return store - rhs.store;
	}


	bool opEquals(fixed32T rhs) {
		return store == rhs.store;
	}


	char[] toString() {
		return convTo!(char[])(cast(real)*this);
	}
	
	
	real opCast() {
		return (1.0 / (1 << fracBits)) * store;
	}

	
	bool isNaN() {
		return false;
	}
}

template fixedT(int intBits, int fracBits) {
	static if (32 == intBits + fracBits) {
		alias fixed32T!(fracBits) fixedT;
	} else {
		static assert ("Only 32 bit fixed point supported at the moment");
	}
}

alias fixedT!(16, 16)	fixed;
}