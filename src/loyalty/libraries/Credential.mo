import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Int "mo:base/Int";

module {
    public type CredentialScheme = {
        id: Text;
        name: Text;
        description: Text;
        metadata: Text;
        reward: Nat;
    };

    public type IssuedCredential = {
        schemeId: Text;
        issuerId: Principal;  // Store principal
        holderId: Principal;  // User principal
        timestamp: Int;
        reward: Nat;
    };

    public type IssueHistory = {
        schemeId: Text;
        holderId: Principal;
        timestamp: Int;
        reward: Nat;
    };

    public func generateSchemeId(storePrincipal: Principal, name: Text) : Text {
        Text.concat(Principal.toText(storePrincipal), name)
    };

    public func isValidTimestamp(timestamp: Int, currentTime: Int) : Bool {
        let oneDay = 24 * 60 * 60 * 1000_000_000;
        let diff = currentTime - timestamp;
        diff >= -oneDay and diff <= oneDay
    };
}