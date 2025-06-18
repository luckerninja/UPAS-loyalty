import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Blob "mo:base/Blob";
import Nat32 "mo:base/Nat32";
import Sha256 "mo:sha2/Sha256";
import Array "mo:base/Array";
import Base16 "mo:base16/Base16";
import Debug "mo:base/Debug";

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
        let textBytes = Text.encodeUtf8(Principal.toText(storePrincipal) # name);
        
        let hashValue = Sha256.fromBlob(#sha256, textBytes);
        
        let hexValue = Base16.encode(hashValue);
        
        return hexValue;
    };

    public func isValidTimestamp(timestamp: Int, currentTime: Int) : Bool {
        Debug.print("isValidTimestamp: " # debug_show(timestamp) # " " # debug_show(currentTime));
        let oneDay = 24 * 60 * 60 * 1000_000_000;
        let diff = currentTime - timestamp;
        diff >= -oneDay and diff <= oneDay
    };

    public func buildCredential(schemeId: Text, issuerId: Principal, holderId: Principal, timestamp: Int, reward: Nat) : IssuedCredential {
        let credential: IssuedCredential = {
            schemeId = schemeId;
            issuerId = issuerId;
            holderId = holderId;
            timestamp = timestamp;
            reward = reward;
        };

        return credential;
    };

    public func buildIssueHistory(schemeId: Text, holderId: Principal, timestamp: Int, reward: Nat) : IssueHistory {
        let issueHistory: IssueHistory = {
            schemeId = schemeId;
            holderId = holderId;
            timestamp = timestamp;
            reward = reward;
        };

        return issueHistory;
    };
}