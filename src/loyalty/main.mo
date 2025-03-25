import Store "./libraries/Store";
import Credential "./libraries/Credential";
import Principal "mo:base/Principal";
import BTree "mo:stableheapbtreemap/BTree";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

shared(msg) actor class LoyaltyProgram() {
    private let owner = msg.caller;
    private stable let stores = BTree.init<Principal, Store.Store>(?8);
    private stable let userCredentials = BTree.init<Principal, [Credential.IssuedCredential]>(?8);

    public shared({ caller }) func addStore(principal: Principal, name: Text, description: Text) : async ?Store.Store {
        assert(caller == owner);

        let store : Store.Store = {
            owner = principal;
            name = name;
            description = description;
            points = 0;
            schemes = [];
            issueHistory = [];
        };
        
        BTree.insert(
            stores,
            Principal.compare,
            principal,
            store
        )
    };

    public query func getStore(owner: Principal) : async ?Store.Store {
        BTree.get(stores, Principal.compare, owner)
    };

    public query func listStores() : async [(Principal, Store.Store)] {
        BTree.toArray(stores)
    };

    public shared({ caller }) func publishCredentialScheme(name: Text, description: Text, metadata: Text, reward: Nat) : async Text {
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let schemeId = Credential.generateSchemeId(caller, name);
                let scheme : Credential.CredentialScheme = {
                    id = schemeId;
                    name = name;
                    description = description;
                    metadata = metadata;
                    reward = reward;
                };
                
                let newSchemes = Array.append(store.schemes, [scheme]);
                let updatedStore = {
                    store with schemes = newSchemes;
                };
                ignore BTree.insert(stores, Principal.compare, caller, updatedStore);
                schemeId
            };
            case null {
                throw Error.reject("Store not found");
            };
        };
    };

    public shared({ caller }) func updateSchemeReward(schemeId: Text, newReward: Nat) : async () {
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let updatedSchemes = Array.map<Credential.CredentialScheme, Credential.CredentialScheme>(
                    store.schemes,
                    func(scheme) {
                        if (scheme.id == schemeId) {
                            { scheme with reward = newReward }
                        } else {
                            scheme
                        }
                    }
                );
                let updatedStore = {
                    store with schemes = updatedSchemes;
                };
                ignore BTree.insert(stores, Principal.compare, caller, updatedStore);
            };
            case null {
                throw Error.reject("Store not found");
            };
        };
    };

    public shared({ caller }) func issueCredential(schemeId: Text, holderId: Principal) : async () {
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let scheme = Array.find<Credential.CredentialScheme>(store.schemes, func(s) = s.id == schemeId);
                switch (scheme) {
                    case (?s) {
                        let timestamp = Time.now();

                        let credential : Credential.IssuedCredential = {
                            schemeId = schemeId;
                            issuerId = caller;
                            holderId = holderId;
                            timestamp = timestamp;
                            reward = s.reward;
                        };

                        let history : Credential.IssueHistory = {
                            schemeId = schemeId;
                            holderId = holderId;
                            timestamp = timestamp;
                            reward = s.reward;
                        };

                        // Update store history
                        let updatedStore = {
                            store with 
                            issueHistory = Array.append(store.issueHistory, [history])
                        };
                        ignore BTree.insert(stores, Principal.compare, caller, updatedStore);

                        // Update user credentials
                        let existingCredentials = switch (BTree.get(userCredentials, Principal.compare, holderId)) {
                            case (?creds) creds;
                            case null [];
                        };
                        ignore BTree.insert(
                            userCredentials, 
                            Principal.compare, 
                            holderId, 
                            Array.append(existingCredentials, [credential])
                        );
                    };
                    case null throw Error.reject("Scheme not found");
                };
            };
            case null throw Error.reject("Store not found");
        };
    };

    public query func getUserCredentials(userId: Principal) : async ?[Credential.IssuedCredential] {
        BTree.get(userCredentials, Principal.compare, userId)
    };

    public query func getStoreHistory(storeId: Principal) : async ?[Credential.IssueHistory] {
        switch (BTree.get(stores, Principal.compare, storeId)) {
            case (?store) ?store.issueHistory;
            case null null;
        };
    };
}