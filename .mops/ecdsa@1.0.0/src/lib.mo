/**
 * Module      : lib.mo
 * Description : ECDSA-SHA-256
 * Copyright   : 2022 Mitsunari Shigeo
 * License     : Apache 2.0 with LLVM Exception
 * Maintainer  : herumi <herumi@nifty.com>
 * Stability   : Stable
 */

import Iter "mo:base/Iter";
import Nat8 "mo:base/Nat8";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Sha256 "mo:sha2/Sha256";
import Curve "curve";
import Util "util";
import Prelude "mo:base/Prelude";

module {
  public func sha2(iter : Iter.Iter<Nat8>) : Blob {
    Sha256.fromIter(#sha256, iter);
  };

  public type PublicKey = Curve.Jacobi;
  public type SecretKey = { #non_zero : Curve.FrElt };
  public type Signature = (Curve.FrElt, Curve.FrElt);

  func getExponent(curve : Curve.Curve, rand : Iter.Iter<Nat8>) : Curve.FrElt = curve.Fr.fromNat(Util.toNatAsBigEndian(rand));

  /// Get secret key from rand.
  public func getSecretKey(curve : Curve.Curve, rand : Iter.Iter<Nat8>) : ?SecretKey {
    let s = getExponent(curve, rand);
    if (s == #fr(0)) null else ?#non_zero(s);
  };
  /// Get public key from sec.
  /// public key is a point of elliptic curve
  public func getPublicKey(curve : Curve.Curve, #non_zero(s) : SecretKey) : PublicKey {
    if (s == #fr(0)) Prelude.unreachable(); // type error
    curve.mul_base(s);
  };
  /// Sign hashed by sec and rand return lower S signature (r, s) such that s < rHalf
  /// hashed : 32-byte SHA-256 value of a message.
  /// rand : 32-byte random value.
  public func signHashed(curve : Curve.Curve, #non_zero(sec) : SecretKey, hashed : Iter.Iter<Nat8>, rand : Iter.Iter<Nat8>) : ?Signature {
    if (sec == #fr(0)) Prelude.unreachable(); // type error
    let k = getExponent(curve, rand);
    let x = switch (curve.fromJacobi(curve.mul_base(k))) {
      case (#zero) return null; // k was 0, bad luck with rand
      case (#affine(x, _)) x;
    };
    let r = curve.Fr.fromNat(curve.Fp.toNat(x));
    if (r == #fr(0)) return null; // x was 0 mod r, bad luck with rand
    let z = getExponent(curve, hashed);
    // s = (r * sec + z) / k
    let s = curve.Fr.div(curve.Fr.add(curve.Fr.mul(r, sec), z), k);
    ?normalizeSignature(curve, (r, s));
  };
  /// convert a signature to lower S signature
  public func normalizeSignature(curve : Curve.Curve, (r, s) : Signature) : Signature {
    if (curve.Fr.toNat(s) < curve.params.rHalf) (r, s) else (r, curve.Fr.neg(s));
  };
  /// verify a tuple of pub, hashed, and lowerS sig
  public func verifyHashed(curve : Curve.Curve, pub : PublicKey, hashed : Iter.Iter<Nat8>, (r, s) : Signature) : Bool {
    if (not curve.isValid(pub)) return false;
    if (r == #fr(0)) return false;
    if (s == #fr(0)) return false;
    if (curve.Fr.toNat(s) >= curve.params.rHalf) return false;
    let z = getExponent(curve, hashed);
    let w = curve.Fr.inv(s);
    let u1 = curve.Fr.mul(z, w);
    let u2 = curve.Fr.mul(r, w);
    let R = curve.add(curve.mul_base(u1), curve.mul(pub, u2));
    switch (curve.fromJacobi(R)) {
      case (#zero) false;
      case (#affine(x, _)) curve.Fr.fromNat(curve.Fp.toNat(x)) == r;
    };
  };
  /// Sign a message by sec and rand with SHA-256
  public func sign(curve : Curve.Curve, sec : SecretKey, msg : Iter.Iter<Nat8>, rand : Iter.Iter<Nat8>) : ?Signature {
    signHashed(curve, sec, sha2(msg).vals(), rand);
  };
  // verify a tuple of pub, msg, and sig
  public func verify(curve : Curve.Curve, pub : PublicKey, msg : Iter.Iter<Nat8>, sig : Signature) : Bool {
    verifyHashed(curve, pub, sha2(msg).vals(), sig);
  };
  /// return 0x04 + bigEndian(x) + bigEndian(y)
  public func serializePublicKeyUncompressed(curve : Curve.Curve, (x, y) : Curve.Affine) : Blob {
    let prefix = 0x04 : Nat8;
    let n = 32;
    let x_bytes = Util.toBigEndianPad(n, curve.Fp.toNat(x));
    let y_bytes = Util.toBigEndianPad(n, curve.Fp.toNat(y));
    let ith = func(i : Nat) : Nat8 {
      if (i == 0) {
        prefix;
      } else if (i <= n) {
        x_bytes[i - 1];
      } else {
        y_bytes[i - 1 - n];
      };
    };
    let ar = Array.tabulate<Nat8>(1 + n * 2, ith);
    Blob.fromArray(ar);
  };
  /// return 0x02 + bigEndian(x) if y is even
  /// return 0x03 + bigEndian(x) if y is odd
  public func serializePublicKeyCompressed(curve : Curve.Curve, (x, y) : Curve.Affine) : Blob {
    let prefix : Nat8 = if ((curve.Fp.toNat(y) % 2) == 0) 0x02 else 0x03;
    let n = 32;
    let x_bytes = Util.toBigEndianPad(n, curve.Fp.toNat(x));
    let ith = func(i : Nat) : Nat8 {
      if (i == 0) {
        prefix;
      } else {
        x_bytes[i - 1];
      };
    };
    let ar = Array.tabulate<Nat8>(1 + n, ith);
    Blob.fromArray(ar);
  };
  /// Deserialize an uncompressed public key
  public func deserializePublicKeyUncompressed(curve : Curve.Curve, b : Blob) : ?PublicKey {
    if (b.size() != 65) return null;
    let a = Blob.toArray(b);
    if (a[0] != 0x04) return null;
    class range(a : [Nat8], begin : Nat, size : Nat) {
      var i = 0;
      public func next() : ?Nat8 {
        if (i == size) return null;
        let ret = ?a[begin + i];
        i += 1;
        ret;
      };
    };
    let n = 32;
    let x = Util.toNatAsBigEndian(range(a, 1, n));
    let y = Util.toNatAsBigEndian(range(a, 1 + n, n));
    if (x >= curve.params.p) return null;
    if (y >= curve.params.p) return null;
    let pub = (#fp(x), #fp(y));
    if (not curve.isValidAffine(pub)) return null;
    ?(#fp(x), #fp(y), #fp(1));
  };
  /// Deserialize a compressed public key.
  public func deserializePublicKeyCompressed(curve : Curve.Curve, b : Blob) : ?PublicKey {
    let n = 32;
    if (b.size() != n + 1) return null;
    let iter = b.vals();
    let even = switch (iter.next()) {
      case (?0x02) true;
      case (?0x03) false;
      case _ return null;
    };
    let x_ = Util.toNatAsBigEndian(iter);
    if (x_ >= curve.params.p) return null;
    let x = #fp(x_);
    return switch (curve.getYfromX(x, even)) {
      case (null) null;
      case (?y) ?(x, y, #fp(1));
    };
  };
  /// serialize to DER format
  /// https://www.oreilly.com/library/view/programming-bitcoin/9781492031482/ch04.html
  public func serializeSignatureDer(sig : Signature) : Blob {
    let buf = Buffer.Buffer<Nat8>(80);
    buf.add(0x30); // top marker
    buf.add(0); // modify later
    let append = func(x : Nat) {
      buf.add(0x02); // marker
      let a = Util.toBigEndian(x);
      let adj = if (a[0] >= 0x80) 1 else 0;
      buf.add(Nat8.fromNat(a.size() + adj));
      if (adj == 1) buf.add(0x00);
      for (e in a.vals()) {
        buf.add(e);
      };
    };
    let (#fr(r), #fr(s)) = sig;
    append(r);
    append(s);
    let va = Buffer.toVarArray(buf);
    va[1] := Nat8.fromNat(va.size()) - 2;
    Blob.fromArrayMut(va);
  };
  /// deserialize DER to signature
  public func deserializeSignatureDer(b : Blob) : ?Signature {
    let a = Blob.toArray(b);
    if (a.size() <= 2 or a[0] != 0x30) return null;
    if (a.size() != Nat8.toNat(a[1]) + 2) return null;
    let read = func(a : [Nat8], begin : Nat) : ?(Nat, Nat) {
      if (a.size() < begin + 2) return null;
      if (a[begin] != 0x02) return null;
      let n = Nat8.toNat(a[begin + 1]);
      if (a.size() < begin + 1 + n) return null;
      let top = a[begin + 2];
      if (top >= 0x80) return null;
      if (top == 0 and n > 1 and (a[begin + 2 + 1] & 0x80) == 0) return null;
      var v = 0;
      var i = 0;
      while (i < n) {
        v := v * 256 + Nat8.toNat(a[begin + 2 + i]);
        i += 1;
      };
      ?(n + 2, v);
    };
    return switch (read(a, 2)) {
      case (null) null;
      case (?(read1, r)) {
        switch (read(a, 2 + read1)) {
          case (null) null;
          case (?(read2, s)) {
            if (a.size() != 2 + read1 + read2) return null;
            ?(#fr(r), #fr(s));
          };
        };
      };
    };
  };

  public func deserializeSignatureRaw(signatureBlob : Blob) : ?Signature {
    let signatureBytes = Blob.toArray(signatureBlob);

    // JWT ECDSA signatures are 64 bytes - 32 bytes for r and 32 bytes for s
    if (signatureBytes.size() != 64) {
      return null;
    };

    // Extract r and s values
    let rBytes = Array.subArray(signatureBytes, 0, 32);
    let sBytes = Array.subArray(signatureBytes, 32, 32);

    let r = Util.toNatAsBigEndian(rBytes.vals());
    let s = Util.toNatAsBigEndian(sBytes.vals());

    // Return as Curve.FrElt values
    ?(#fr(r), #fr(s));
  };
};
