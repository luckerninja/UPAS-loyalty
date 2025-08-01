import ECDSA "mo:ecdsa";
import Curve "mo:ecdsa/curve";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Credential "./Credential";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Debug "mo:base/Debug";

module {
    public func verifySignature(publicKey: ECDSA.PublicKey, message: [Nat8], signatureRawBytes: [Nat8]) : Bool {
        let curve = Curve.Curve(#secp256k1);
        switch(ECDSA.deserializeSignatureRaw(Blob.fromArray(signatureRawBytes))) {
            case (?signature) {
                ECDSA.verify(curve, publicKey, Blob.fromArray(message).vals(), signature)
            };
            case null false;
        }
    };

    public func credentialToMessage(credential: Credential.IssuedCredential) : [Nat8] {
        let message = credential.schemeId # " " # 
            Principal.toText(credential.issuerId) # " " # 
            Principal.toText(credential.holderId) # " " # 
            Int.toText(credential.timestamp) # " " # 
            Nat.toText(credential.reward);
        Debug.print("Motoko message: " # message);
        Debug.print("Motoko bytes: " # debug_show(Blob.toArray(Text.encodeUtf8(message))));
        Blob.toArray(Text.encodeUtf8(message))
    };

}