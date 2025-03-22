# ECDSA library for Motoko

A fork of [herumi/ecdsa-motoko](https://github.com/herumi/ecdsa-motoko), providing ECDSA-SHA-256 implementation.

## Original Project Credits

- **Author**: MITSUNARI Shigeo (herumi@nifty.com)
- **Original Repository**: https://github.com/herumi/ecdsa-motoko

## License

Apache 2.0 with LLVM Exception

This project is a fork of the original ECDSA implementation by MITSUNARI Shigeo, maintaining the same license.

## Installation

```bash
mops install ecdsa
```

To setup MOPS package manage, follow the instructions from the
[MOPS Site](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)

## Quickstart

### Verify signature

```motoko
let rawPublicKeyBytes : [Nat8] = ...;
let rawSignatureBytes : [Nat8] = ...;
let curve = Curve.Curve(#prime256v1);
let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(rawPublicKeyBytes)) return false;
let ?signature = ECDSA.deserializeSignatureRaw(rawSignatureBytes) return false;
let normalizedSig = ECDSA.normalizeSignature(curve, signature);
return ECDSA.verify(curve, publicKey, messageBytes.vals(), normalizedSig);
```

## API Reference

### Key Generation and Management

```motoko
// Generate a secret key from random bytes
public func getSecretKey(curve : Curve.Curve, rand : Iter.Iter<Nat8>) : ?SecretKey

// Derive public key from secret key
public func getPublicKey(curve : Curve.Curve, sec : SecretKey) : PublicKey
```

### Signing and Verification

```motoko
// Sign a message using SHA-256
public func sign(curve : Curve.Curve, sec : SecretKey, msg : Iter.Iter<Nat8>, rand : Iter.Iter<Nat8>) : ?Signature

// Verify a signature
public func verify(curve : Curve.Curve, pub : PublicKey, msg : Iter.Iter<Nat8>, sig : Signature) : Bool

// Sign pre-hashed message
public func signHashed(curve : Curve.Curve, sec : SecretKey, hashed : Iter.Iter<Nat8>, rand : Iter.Iter<Nat8>) : ?Signature

// Verify pre-hashed message
public func verifyHashed(curve : Curve.Curve, pub : PublicKey, hashed : Iter.Iter<Nat8>, sig : Signature) : Bool
```

### Key Serialization

```motoko
// Serialize public key (uncompressed format)
public func serializePublicKeyUncompressed(curve : Curve.Curve, key : Curve.Affine) : Blob

// Serialize public key (compressed format)
public func serializePublicKeyCompressed(curve : Curve.Curve, key : Curve.Affine) : Blob

// Deserialize public key (uncompressed format)
public func deserializePublicKeyUncompressed(curve : Curve.Curve, b : Blob) : ?PublicKey

// Deserialize public key (compressed format)
public func deserializePublicKeyCompressed(curve : Curve.Curve, b : Blob) : ?PublicKey
```

### Signature Serialization

```motoko
// Serialize signature to DER format
public func serializeSignatureDer(sig : Signature) : Blob

// Deserialize signature from DER format
public func deserializeSignatureDer(b : Blob) : ?Signature

// Deserialize signature from the raw bytes
public func deserializeSignatureRaw(b : Blob) : ?Signature
```

## Changes from Original

Adapted it to use for the MOPS package manager

## Original Project

If you'd like to support the original project:

- Original repository: https://github.com/herumi/ecdsa-motoko
- [GitHub Sponsor](https://github.com/sponsors/herumi)
