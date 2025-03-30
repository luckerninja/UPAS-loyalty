import Store "./libraries/Store";
import Credential "./libraries/Credential";
import Principal "mo:base/Principal";
import BTree "mo:stableheapbtreemap/BTree";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import ICRC1 "canister:icrc1_ledger_canister";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Auth "./libraries/Auth";
import Lib "mo:ed25519";
import ECDSA "mo:ecdsa";
import Curve "mo:ecdsa/curve";
import Blob "mo:base/Blob";
import Signature "./libraries/Signature";

shared(msg) actor class LoyaltyProgram(externalCanisterId: Principal) {
    private let IS_PRODUCTION = false;

    private let owner = msg.caller;
    private let tokenMinter = externalCanisterId;
    private stable let stores = BTree.init<Principal, Store.Store>(?8);
    private stable let userCredentials = BTree.init<Principal, [Credential.IssuedCredential]>(?8);
    private stable let storeTokens = BTree.init<Principal, Nat>(?8);

    public shared({ caller }) func addStore(principal: Principal, name: Text, description: Text, publicKeyNat: [Nat8]) : async ?Store.Store {
        assert(caller == owner);

        let curve = Curve.Curve(#secp256k1);

        let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(publicKeyNat));

        let store : Store.Store = {
            owner = principal;
            name = name;
            description = description;
            schemes = [];
            issueHistory = [];
            publicKey = publicKey;
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

    public shared({ caller }) func issueCredential(schemeId: Text, holderId: Principal, signature: [Nat8], timestamp: Int) : async Result.Result<Nat, ICRC1.TransferError> {
        if (not Auth.isSelfAuthenticating(caller)) {
            return #err(#GenericError({ 
                message = "Caller must use self-authenticating ID"; 
                error_code = 3 
            }));
        };

        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let scheme = Array.find<Credential.CredentialScheme>(store.schemes, func(s) = s.id == schemeId);
                switch (scheme) {
                    case (?s) {
                        let storeBalance = switch (BTree.get(storeTokens, Principal.compare, caller)) {
                            case (?balance) balance;
                            case null 0;
                        };

                        if (storeBalance < s.reward) {
                            return #err(#InsufficientFunds({ balance = storeBalance }));
                        };

                        if (IS_PRODUCTION and not Credential.isValidTimestamp(timestamp, Time.now())) {
                            return #err(#GenericError({ message = "Invalid timestamp"; error_code = 0 }));
                        };

                        let transferArgs : ICRC1.TransferArg = {
                            memo = null;
                            amount = s.reward;
                            fee = null;
                            from_subaccount = null;
                            to = {
                                owner = holderId;
                                subaccount = null;
                            };
                            created_at_time = null;
                        };

                        let credential : Credential.IssuedCredential = Credential.buildCredential(schemeId, caller, holderId, timestamp, s.reward);

                        if (not Signature.verifySignature(store.publicKey, Signature.credentialToMessage(credential), signature)) {
                            return #err(#GenericError({ message = "Invalid signature"; error_code = 0 }));
                        };

                        Debug.print("Transferring to account: " # debug_show({
                            owner = holderId;
                            subaccount = null;
                        }));

                        try {
                            let transferResult = await ICRC1.icrc1_transfer(transferArgs);
                            switch (transferResult) {
                                case (#Err(transferError)) {
                                    #err(transferError)
                                };
                                case (#Ok(blockIndex)) { 
                                    ignore BTree.insert(
                                        storeTokens, 
                                        Principal.compare, 
                                        caller, 
                                        storeBalance - s.reward
                                    );

                                    let history : Credential.IssueHistory = Credential.buildIssueHistory(schemeId, holderId, timestamp, s.reward);

                                    let updatedStore = {
                                        store with 
                                        issueHistory = Array.append(store.issueHistory, [history])
                                    };
                                    ignore BTree.insert(stores, Principal.compare, caller, updatedStore);

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

                                    #ok(blockIndex)
                                };
                            };
                        } catch (error : Error) {
                            #err(#GenericError({ message = Error.message(error); error_code = 0 }))
                        };
                    };
                    case null #err(#GenericError({ message = "Scheme not found"; error_code = 1 }));
                };
            };
            case null #err(#GenericError({ message = "Store not found"; error_code = 2 }));
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

    public shared({ caller }) func addStoreTokens(storePrincipal: Principal, amount: Nat) : async () {
        if (caller != tokenMinter) {
            throw Error.reject("Unauthorized: only token minter can add tokens");
        };

        let currentBalance = switch (BTree.get(storeTokens, Principal.compare, storePrincipal)) {
            case (?balance) balance;
            case null 0;
        };

        ignore BTree.insert(storeTokens, Principal.compare, storePrincipal, currentBalance + amount);
    };

    public query func getStoreTokens(storePrincipal: Principal) : async Nat {
        switch (BTree.get(storeTokens, Principal.compare, storePrincipal)) {
            case (?balance) balance;
            case null 0;
        }
    };

    public query func verifySelfAuthenticating(principal: Principal) : async Bool {
        Auth.isSelfAuthenticating(principal)
    };

    private func isExternalCanister(caller: Principal) : Bool {
        caller == tokenMinter
    };
}