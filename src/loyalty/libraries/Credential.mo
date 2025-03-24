import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Int "mo:base/Int";

module {
    public type CredentialScheme = {
        id: Text;
        name: Text;
        description: Text;
        metadata: Text;
        reward: Nat;  // Reward in tokens
    };

    public type IssuedCredential = {
        schemeId: Text;
        issuerId: Principal;
        holderId: Principal;
        timestamp: Int;
        reward: Nat;  // Reward at the time of issuance
        signature: Blob;
    };

    public type IssueHistory = {
        schemeId: Text;
        holderId: Principal;
        timestamp: Int;
        reward: Nat;
    };

    public func generateSchemeId(storePrincipal: Principal, name: Text) : Text {
        let hash = Text.hash(Principal.toText(storePrincipal) # name);
        Nat32.toText(hash)
    };

    public func createSignatureMessage(schemeId: Text, holderId: Principal, timestamp: Int, reward: Nat) : Text {
        schemeId # Principal.toText(holderId) # Int.toText(timestamp) # Nat.toText(reward)
    };

    public func isValidTimestamp(timestamp: Int, currentTime: Int) : Bool {
        let oneDay = 24 * 60 * 60 * 1000_000_000;
        let diff = currentTime - timestamp;
        diff >= -oneDay and diff <= oneDay
    };
}