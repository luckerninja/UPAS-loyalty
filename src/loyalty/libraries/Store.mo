import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Credential "./Credential";

module {
    public type Store = {
        owner: Principal;
        name: Text;
        description: Text;
        points: Int;
        schemes: [Credential.CredentialScheme];
        issueHistory: [Credential.IssueHistory];
    };
}