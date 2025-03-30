import ECDSA "mo:ecdsa";
import Curve "mo:ecdsa/curve";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Credential "./Credential";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Int "mo:base/Int";

module {
    public func verifySignature(publicKey: ECDSA.PublicKey, message: [Nat8], signatureRawBytes: [Nat8]) : Bool {
        let curve = Curve.Curve(#prime256v1);
        let ?signature = ECDSA.deserializeSignatureRaw(Blob.fromArray(signatureRawBytes));

        return ECDSA.verify(curve, publicKey, Blob.fromArray(message).vals(), signature);
    };

    public func credentialToMessage(credential: Credential.IssuedCredential) : [Nat8] {
        Blob.toArray(Text.encodeUtf8(credential.schemeId # " " # Principal.toText(credential.issuerId) # " " # Principal.toText(credential.holderId) # " " # Int.toText(credential.timestamp) # " " # Nat.toText(credential.reward)))
    };

}