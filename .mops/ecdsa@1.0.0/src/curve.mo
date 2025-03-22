import Field "field";
import Hex "hex";
import Binary "binary";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Iter "mo:base/Iter";

module {
  public type FpElt = { #fp : Nat };
  public type FrElt = { #fr : Nat };
  public type Affine = (FpElt, FpElt);
  public type Point = { #zero; #affine : Affine };

  type CurveParams = {
    a : FpElt;
    b : FpElt;
    g : (FpElt, FpElt);
    p : Nat;
    r : Nat;
    rHalf : Nat;
    pSqrRoot : Nat;
    kind : CurveKind;
  };

  // GLV endomorphism constants specifically for secp256k1
  private let GLV_CONSTANTS = {
    B00 : Int = 0x3086d221a7d46bcde86c90e49284eb15;
    B01 : Int = -0xe4437ed6010e88286f547fa90abfe4c3;
    B10 : Int = 0x114ca50f7a8e2f3f657c1108d9d44cfd8;
    rw = #fp(55594575648329892869085402983802832744385952214688224221778511981742606582254);
    SHIFT256 : Int = 0x10000000000000000000000000000000000000000000000000000000000000000;
    v0 : Int = 64502973549206556628585045361533709077;
    v1 : Int = 303414439467246543595250775667605759172;
  };

  public type Jacobi = (FpElt, FpElt, FpElt);

  public type CurveKind = {
    #secp256k1;
    #prime256v1;
  };

  public class Curve(kind : CurveKind) {
    public let params : CurveParams = getParams(kind);
    let p_ = params.p;
    let r_ = params.r;
    let a_ = params.a;
    let b_ = params.b;
    let pSqrRoot_ = params.pSqrRoot;

    // Check if the curve supports GLV endomorphism
    let hasGLV = switch (kind) {
      case (#secp256k1) true;
      case (#prime256v1) false;
    };

    public let Fp = {
      fromNat = func(n : Nat) : FpElt = #fp(n % p_);
      toNat = func(#fp(x) : FpElt) : Nat = x;
      add = func(#fp(x) : FpElt, #fp(y) : FpElt) : FpElt = #fp(Field.add_(x, y, p_));
      mul = func(#fp(x) : FpElt, #fp(y) : FpElt) : FpElt = #fp(Field.mul_(x, y, p_));
      sub = func(#fp(x) : FpElt, #fp(y) : FpElt) : FpElt = #fp(Field.sub_(x, y, p_));
      div = func(#fp(x) : FpElt, #fp(y) : FpElt) : FpElt = #fp(Field.div_(x, y, p_));
      pow = func(#fp(x) : FpElt, n : Nat) : FpElt = #fp(Field.pow_(x, n, p_));
      neg = func(#fp(x) : FpElt) : FpElt = #fp(Field.neg_(x, p_));
      inv = func(#fp(x) : FpElt) : FpElt = #fp(Field.inv_(x, p_));
      sqr = func(#fp(x) : FpElt) : FpElt = #fp(Field.sqr_(x, p_));
    };

    public let Fr = {
      fromNat = func(n : Nat) : FrElt = #fr(n % r_);
      toNat = func(#fr(x) : FrElt) : Nat = x;
      add = func(#fr(x) : FrElt, #fr(y) : FrElt) : FrElt = #fr(Field.add_(x, y, r_));
      mul = func(#fr(x) : FrElt, #fr(y) : FrElt) : FrElt = #fr(Field.mul_(x, y, r_));
      sub = func(#fr(x) : FrElt, #fr(y) : FrElt) : FrElt = #fr(Field.sub_(x, y, r_));
      div = func(#fr(x) : FrElt, #fr(y) : FrElt) : FrElt = #fr(Field.div_(x, y, r_));
      pow = func(#fr(x) : FrElt, n : Nat) : FrElt = #fr(Field.pow_(x, n, r_));
      neg = func(#fr(x) : FrElt) : FrElt = #fr(Field.neg_(x, r_));
      inv = func(#fr(x) : FrElt) : FrElt = #fr(Field.inv_(x, r_));
      sqr = func(#fr(x) : FrElt) : FrElt = #fr(Field.sqr_(x, r_));
    };

    public func fpSqrRoot(x : FpElt) : ?FpElt {
      let sq = Fp.pow(x, pSqrRoot_);
      if (Fp.sqr(sq) == x) ?sq else null;
    };

    // return x^3 + ax + b
    public func getYsqrFromX(x : FpElt) : FpElt = Fp.add(Fp.mul(Fp.add(Fp.sqr(x), a_), x), b_);

    /// Get y corresponding to x such that y^2 = x^ + ax + b.
    /// Return even y if `even` is true.
    public func getYfromX(x : FpElt, even : Bool) : ?FpElt {
      let y2 = getYsqrFromX(x);
      switch (fpSqrRoot(y2)) {
        case (null) null;
        case (?y) if (even == ((Fp.toNat(y) % 2) == 0)) ?y else ?Fp.neg(y);
      };
    };

    public func isValidAffine((x, y) : Affine) : Bool = Fp.sqr(y) == getYsqrFromX(x);

    public let G_ = (params.g.0, params.g.1, #fp(1));

    public let zeroJ = (#fp(0), #fp(0), #fp(0));

    public func isZero((_, _, z) : Jacobi) : Bool = z == #fp(0);

    public func toJacobi(a : Point) : Jacobi = switch (a) {
      case (#zero) zeroJ;
      case (#affine(x, y)) (x, y, #fp(1));
    };

    public func normalize((x, y, z) : Jacobi) : Jacobi {
      if (z == #fp(0)) return (x, y, z);
      let rz = Fp.inv(z);
      let rz2 = Fp.sqr(rz);
      (Fp.mul(x, rz2), Fp.mul(Fp.mul(y, rz2), rz), #fp(1));
    };

    public func fromJacobi(a : Jacobi) : Point {
      let (x, y, z) = normalize(a);
      if (z == #fp(0)) return #zero;
      #affine(x, y);
    };

    public func isValid((x, y, z) : Jacobi) : Bool {
      let x2 = Fp.sqr(x);
      let y2 = Fp.sqr(y);
      let z2 = Fp.sqr(z);
      var z4 = Fp.sqr(z2);
      var t = Fp.mul(z4, a_);
      t := Fp.add(t, x2);
      t := Fp.mul(t, x);
      z4 := Fp.mul(z4, z2);
      z4 := Fp.mul(z4, b_);
      t := Fp.add(t, z4);
      y2 == t;
    };

    public func isEqual(P1 : Jacobi, P2 : Jacobi) : Bool {
      let zero1 = isZero(P1);
      let zero2 = isZero(P2);
      if (zero1) return zero2;
      if (zero2) return false;
      let (x1, y1, z1) = P1;
      let (x2, y2, z2) = P2;
      let s1 = Fp.sqr(z1);
      let s2 = Fp.sqr(z2);
      var t1 = Fp.mul(x1, s2);
      var t2 = Fp.mul(x2, s1);
      if (t1 != t2) return false;
      t1 := Fp.mul(y1, s2);
      t2 := Fp.mul(y2, s1);
      t1 := Fp.mul(t1, z2);
      t2 := Fp.mul(t2, z1);
      t1 == t2;
    };

    public func neg((x, y, z) : Jacobi) : Jacobi = (x, Fp.neg(y), z);

    public func dbl((x, y, z) : Jacobi) : Jacobi {
      if (z == #fp(0)) return zeroJ;

      // Special optimized formula for curves with a=-3 (like prime256v1)
      // Uses complete formulas from https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html

      var x2 = Fp.sqr(x);
      var y2 = Fp.sqr(y);
      var z2 = Fp.sqr(z);

      // S = 4*x*y^2
      var S = Fp.mul(x, y2);
      S := Fp.add(S, S);
      S := Fp.add(S, S);

      // M = 3*x^2 + a*z^4
      var M = Fp.add(x2, x2);
      M := Fp.add(M, x2); // 3*x^2

      if (a_ != #fp(0)) {
        // For prime256v1, a = -3
        var z4 = Fp.sqr(z2);
        var az4 = Fp.mul(a_, z4);
        M := Fp.add(M, az4); // 3*x^2 + a*z^4
      };

      // x' = M^2 - 2*S
      var rx = Fp.sqr(M);
      rx := Fp.sub(rx, S);
      rx := Fp.sub(rx, S);

      // y' = M*(S - x') - 8*y^4
      var y4 = Fp.sqr(y2);
      y4 := Fp.add(y4, y4);
      y4 := Fp.add(y4, y4);
      y4 := Fp.add(y4, y4); // 8*y^4

      var ry = Fp.sub(S, rx); // S - x'
      ry := Fp.mul(M, ry); // M*(S - x')
      ry := Fp.sub(ry, y4); // M*(S - x') - 8*y^4

      // z' = 2*y*z
      var rz = Fp.mul(y, z);
      rz := Fp.add(rz, rz);

      return (rx, ry, rz);
    };

    public func add((px, py, pz) : Jacobi, (qx, qy, qz) : Jacobi) : Jacobi {
      if (pz == #fp(0)) return (qx, qy, qz);
      if (qz == #fp(0)) return (px, py, pz);
      let isPzOne = pz == #fp(1);
      let isQzOne = qz == #fp(1);
      var r = if (isPzOne) #fp(1) else Fp.sqr(pz);
      var U1 = #fp(0);
      var S1 = #fp(0);
      var H = #fp(0);
      if (isQzOne) {
        U1 := px;
        if (isPzOne) {
          H := qx;
        } else {
          H := Fp.mul(qx, r);
        };
        H := Fp.sub(H, U1);
        S1 := py;
      } else {
        S1 := Fp.sqr(qz);
        U1 := Fp.mul(px, S1);
        if (isPzOne) {
          H := qx;
        } else {
          H := Fp.mul(qx, r);
        };
        H := Fp.sub(H, U1);
        S1 := Fp.mul(S1, qz);
        S1 := Fp.mul(S1, py);
      };
      if (isPzOne) {
        r := qy;
      } else {
        r := Fp.mul(r, pz);
        r := Fp.mul(r, qy);
      };
      r := Fp.sub(r, S1);
      if (H == #fp(0)) {
        if (r == #fp(0)) {
          return dbl((px, py, pz));
        } else {
          return zeroJ;
        };
      };
      var rx = #fp(0);
      var ry = #fp(0);
      var rz = #fp(0);
      if (isPzOne) {
        if (isQzOne) {
          rz := H;
        } else {
          rz := Fp.mul(H, qz);
        };
      } else {
        if (isQzOne) {
          rz := Fp.mul(pz, H);
        } else {
          rz := Fp.mul(pz, qz);
          rz := Fp.mul(rz, H);
        };
      };
      var H3 = Fp.sqr(H);
      ry := Fp.sqr(r);
      U1 := Fp.mul(U1, H3);
      H3 := Fp.mul(H3, H);
      ry := Fp.sub(ry, U1);
      ry := Fp.sub(ry, U1);
      rx := Fp.sub(ry, H3);
      U1 := Fp.sub(U1, rx);
      U1 := Fp.mul(U1, r);
      H3 := Fp.mul(H3, S1);
      ry := Fp.sub(U1, H3);
      (rx, ry, rz);
    };

    public func sub((px, py, pz) : Jacobi, (qx, qy, qz) : Jacobi) : Jacobi = add((px, py, pz), (qx, Fp.neg(qy), qz));

    func mul_standard(a : Jacobi, #fr(k) : FrElt) : Jacobi {
      // Handle special cases
      if (k == 0 or isZero(a)) {
        return zeroJ;
      };

      // Simple double-and-add algorithm with window optimization for larger scalars
      var result = zeroJ;
      var doubling = a;
      var scalar = k;

      while (scalar > 0) {
        if (scalar % 2 == 1) {
          result := add(result, doubling);
        };
        doubling := dbl(doubling);
        scalar /= 2;
      };

      return result;
    };

    public func hexPoint(p : Jacobi) : (Text, Text, Text) {
      let (x, y, z) = normalize(p);
      (Hex.fromNat(Fp.toNat(x)), Hex.fromNat(Fp.toNat(y)), Hex.fromNat(Fp.toNat(z)));
    };

    public func debugPoint(p : Jacobi) : (Nat, Nat, Nat) {
      let (x, y, z) = normalize(p);
      (Fp.toNat(x), Fp.toNat(y), Fp.toNat(z));
    };

    // GLV endomorphism functions - only used for secp256k1
    func mulLambda((x, y, z) : Jacobi) : Jacobi {
      assert (hasGLV); // Only valid for secp256k1
      (Fp.mul(x, GLV_CONSTANTS.rw), y, z);
    };

    func split(x_ : Nat) : (Int, Int) {
      assert (hasGLV); // Only valid for secp256k1
      let x = x_ : Int;
      let t = (x * GLV_CONSTANTS.v0) / GLV_CONSTANTS.SHIFT256;
      var b = (x * GLV_CONSTANTS.v1) / GLV_CONSTANTS.SHIFT256;
      let a = x - (t * GLV_CONSTANTS.B00 + b * GLV_CONSTANTS.B10);
      b := -(t * GLV_CONSTANTS.B01 + b * GLV_CONSTANTS.B00);
      (a, b);
    };

    // Optimized multiplication using GLV endomorphism (only for secp256k1)
    func mul_glv(x : Jacobi, #fr(y) : FrElt) : Jacobi {
      assert (hasGLV);
      let w = 5;
      let tblSize : Nat = 2 ** (w - 2);
      let u = split(y);
      let naf0 = Binary.toNafWidth(u.0, w);
      let naf1 = Binary.toNafWidth(u.1, w);
      let maxBit = Nat.max(naf0.size(), naf1.size());
      var tbl0 = Buffer.Buffer<Jacobi>(tblSize);
      var tbl1 = Buffer.Buffer<Jacobi>(tblSize);
      tbl0.add(x);
      tbl1.add(mulLambda(x));
      do {
        let P2 = dbl(x);
        var j = 1;
        while (j < tblSize) {
          tbl0.add(add(tbl0.get(j - 1), P2));
          tbl1.add(mulLambda(tbl0.get(j)));
          j += 1;
        };
      };
      var z = zeroJ;
      let addTbl = func(tbl : Buffer.Buffer<Jacobi>, naf : [Int], i : Nat) {
        if (i >= naf.size()) return;
        let n = naf[i];
        if (n > 0) {
          let idx = Int.abs(n - 1) / 2;
          z := add(z, tbl.get(idx));
        } else if (n < 0) {
          let idx = Int.abs(-n - 1) / 2;
          z := add(z, neg(tbl.get(idx)));
        };
      };
      do {
        var i = 0;
        while (i < maxBit) {
          let bit = maxBit - 1 - i : Nat;
          z := dbl(z);
          addTbl(tbl0, naf0, bit);
          addTbl(tbl1, naf1, bit);
          i += 1;
        };
      };
      z;
    };

    // Main multiplication function that chooses the appropriate algorithm
    public func mul(x : Jacobi, scalar : FrElt) : Jacobi {
      let #fr(k) = scalar;

      // Handle special cases
      if (k == 0 or isZero(x)) {
        return zeroJ;
      };

      // Check if scalar represents a negative value (greater than r/2)
      let isNegative = k > params.rHalf;

      if (isNegative) {
        // Use the negated scalar value and negate the result
        let positiveK = #fr(r_ - k : Nat);

        // Use appropriate algorithm based on curve type
        let result = if (hasGLV) {
          mul_glv(x, positiveK);
        } else {
          mul_standard(x, positiveK);
        };

        return neg(result);
      } else {
        // Use appropriate algorithm based on curve type
        if (hasGLV) {
          return mul_glv(x, scalar);
        } else {
          return mul_standard(x, scalar);
        };
      };
    };

    public func mul_base(x : FrElt) : Jacobi = mul(G_, x);

    public func putPoint(a : Point) {
      switch (a) {
        case (#zero) {
          Debug.print("0");
        };
        case (#affine(x, y)) {
          Debug.print("(" # Hex.fromNat(Fp.toNat(x)) # ", " # Hex.fromNat(Fp.toNat(y)) # ")");
        };
      };
    };

    public func putJacobi((x, y, z) : Jacobi) {
      Debug.print("(0x" # Hex.fromNat(Fp.toNat(x)) # ", 0x" # Hex.fromNat(Fp.toNat(y)) # ", 0x" # Hex.fromNat(Fp.toNat(z)) # ")");
    };

    public func putSig((x, y) : (FrElt, FrElt)) {
      Debug.print("(0x" # Hex.fromNat(Fr.toNat(x)) # ", 0x" # Hex.fromNat(Fr.toNat(y)) # ")");
    };
  };

  public func getParams(kind : CurveKind) : CurveParams {
    switch (kind) {
      case (#secp256k1) ({
        p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
        r = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
        a = #fp(0);
        b = #fp(7);
        g = (
          #fp(0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798),
          #fp(0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8),
        );
        rHalf = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a1;
        pSqrRoot = 0x3fffffffffffffffffffffffffffffffffffffffffffffffffffffffbfffff0c;
        kind = kind;
      });
      case (#prime256v1) ({
        p = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
        r = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;
        a = #fp(0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc);
        b = #fp(0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b);
        g = (
          #fp(0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296),
          #fp(0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5),
        );
        rHalf = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;
        pSqrRoot = 0x3fffffffc0000000400000000000000000000000400000000000000000000000;
        kind = kind;
      });
    };
  };
};
