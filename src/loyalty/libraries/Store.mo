import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Credential "./Credential";
import ECDSA "mo:ecdsa";
import Receipt "./Receipt";

module {
    public type Store = {
        owner: Principal;
        name: Text;
        description: Text;
        schemes: [Credential.CredentialScheme];
        issueHistory: [Credential.IssueHistory];
        receiptHistory: [Receipt.ReceiptHistory];
        publicKey: ECDSA.PublicKey
    };
}