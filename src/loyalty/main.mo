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
import Result "mo:base/Result";
import Auth "./libraries/Auth";
import ECDSA "mo:ecdsa";
import Curve "mo:ecdsa/curve";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Signature "./libraries/Signature";
import Receipt "./libraries/Receipt";
import Map "mo:base/HashMap";
import Buffer "mo:base/Buffer";
import Hex "./libraries/Hex";

shared(msg) actor class LoyaltyProgram(externalCanisterId: Principal) {
    private let owner = msg.caller;
    private let tokenMinter = externalCanisterId;
    private stable let stores = BTree.init<Principal, Store.Store>(?8);
    private stable let userCredentials = BTree.init<Principal, [Credential.IssuedCredential]>(?8);
    private stable let storeTokens = BTree.init<Principal, Nat>(?8);
    private stable let userReceipts = BTree.init<Principal, [Receipt.EncryptedReceipt]>(?8);
    private stable var nextReceiptId : Nat = 1;

    // vetKD system API interface
    private type VETKD_SYSTEM_API = actor {
        vetkd_public_key : ({
            canister_id : ?Principal;
            derivation_path : [Blob];
            key_id : { curve : { #bls12_381_g2 }; name : Text };
        }) -> async ({ public_key : Blob });
        
        vetkd_derive_encrypted_key : ({
            derivation_path : [Blob];
            derivation_id : Blob;
            key_id : { curve : { #bls12_381_g2 }; name : Text };
            encryption_public_key : Blob;
        }) -> async ({ encrypted_key : Blob });
    };

    let vetkd_system_api : VETKD_SYSTEM_API = actor ("s55qq-oqaaa-aaaaa-aaakq-cai");

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
            receiptHistory = [];
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

    // Check store balance
    private func checkStoreBalance(store: Store.Store, scheme: Credential.CredentialScheme) : Result.Result<Nat, ICRC1.TransferError> {
        let storeBalance = switch (BTree.get(storeTokens, Principal.compare, store.owner)) {
            case (?balance) balance;
            case null 0;
        };

        if (storeBalance < scheme.reward) {
            #err(#InsufficientFunds({ balance = storeBalance }))
        } else {
            #ok(storeBalance)
        };
    };

    // Validate signature and timestamp
    private func validateCredential(store: Store.Store, credential: Credential.IssuedCredential, signature: [Nat8]) : Result.Result<(), ICRC1.TransferError> {
        if (not Credential.isValidTimestamp(credential.timestamp, Time.now())) {
            return #err(#GenericError({ message = "Invalid timestamp"; error_code = 0 }));
        };

        if (not Signature.verifySignature(store.publicKey, Signature.credentialToMessage(credential), signature)) {
            return #err(#GenericError({ message = "Invalid signature"; error_code = 0 }));
        };

        #ok()
    };

    // Execute token transfer
    private func transferTokens(to: Principal, amount: Nat) : async Result.Result<Nat, ICRC1.TransferError> {
        let transferArgs : ICRC1.TransferArg = {
            memo = null;
            amount = amount;
            fee = null;
            from_subaccount = null;
            to = { owner = to; subaccount = null; };
            created_at_time = null;
        };

        try {
            let result = await ICRC1.icrc1_transfer(transferArgs);
            switch(result) {
                case (#Ok(blockIndex)) #ok(blockIndex);
                case (#Err(err)) #err(err);
            }
        } catch (error : Error) {
            #err(#GenericError({ message = Error.message(error); error_code = 0 }))
        };
    };

    // Update state after successful transfer
    private func updateState(store: Store.Store, credential: Credential.IssuedCredential, storeBalance: Nat) {
        // Update store balance
        ignore BTree.insert(
            storeTokens, 
            Principal.compare, 
            store.owner, 
            storeBalance - credential.reward
        );

        // Update issue history
        let history = Credential.buildIssueHistory(
            credential.schemeId, 
            credential.holderId, 
            credential.timestamp, 
            credential.reward
        );

        let updatedStore = {
            store with 
            issueHistory = Array.append(store.issueHistory, [history])
        };
        ignore BTree.insert(stores, Principal.compare, store.owner, updatedStore);

        // Update user credentials
        let existingCredentials = switch (BTree.get(userCredentials, Principal.compare, credential.holderId)) {
            case (?creds) creds;
            case null [];
        };
        ignore BTree.insert(
            userCredentials, 
            Principal.compare, 
            credential.holderId, 
            Array.append(existingCredentials, [credential])
        );
    };

    // Main credential issuance function
    public shared({ caller }) func issueCredential(schemeId: Text, holderId: Principal, signature: [Nat8], timestamp: Int) : async Result.Result<Nat, ICRC1.TransferError> {
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                switch (Array.find<Credential.CredentialScheme>(store.schemes, func(s) = s.id == schemeId)) {
                    case (?scheme) {
                        // Check balance
                        let #ok(storeBalance) = checkStoreBalance(store, scheme) else return #err(#InsufficientFunds({ balance = 0 }));
                        
                        Debug.print(debug_show(Credential.buildCredential(schemeId, caller, holderId, timestamp, scheme.reward)));

                        // Create credential
                        let credential = Credential.buildCredential(schemeId, caller, holderId, timestamp, scheme.reward);

                        // Validate signature and timestamp
                        let #ok() = validateCredential(store, credential, signature) else return #err(#GenericError({ message = "Validation failed"; error_code = 0 }));

                        // Execute transfer
                        switch(await transferTokens(holderId, scheme.reward)) {
                            case (#ok(blockIndex)) {
                                updateState(store, credential, storeBalance);
                                #ok(blockIndex)
                            };
                            case (#err(err)) #err(err);
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

    // FOR TESTING

    public query func deserializePublicKey(publicKeyRawBytes: [Nat8]) : async ?ECDSA.PublicKey {
        let curve = Curve.Curve(#secp256k1);
        let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(publicKeyRawBytes));
        ?publicKey
    };

    public query func verifySignature(publicKeyRawBytes: [Nat8], message: [Nat8], signature: [Nat8]) : async Bool {
        let curve = Curve.Curve(#secp256k1);
        let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(publicKeyRawBytes));
        Signature.verifySignature(publicKey, message, signature)
    };

    public shared({ caller }) func verifyCredential(schemeId: Text, holderId: Principal, timestamp: Int, signature: [Nat8], publicKeyRawBytes: [Nat8]) : async Bool {
        let credential = Credential.buildCredential(schemeId, caller, holderId, timestamp, 100);
        let curve = Curve.Curve(#secp256k1);
        let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(publicKeyRawBytes));
        Signature.verifySignature(publicKey, Signature.credentialToMessage(credential), signature)
    };

    // Get verification key for receipt encryption
    public shared ({ caller }) func receipt_symmetric_key_verification_key() : async Text {
        let { public_key } = await vetkd_system_api.vetkd_public_key({
            canister_id = null;
            derivation_path = Array.make(Text.encodeUtf8("receipt_symmetric_key"));
            key_id = { curve = #bls12_381_g2; name = "test_key_1" };
        });
        Hex.encode(Blob.toArray(public_key));
    };

    // Store encrypted receipt
    public shared({ caller }) func storeReceipt(encryptedData: Text, holderId: Principal, amount: Nat) : async Receipt.ReceiptId {
        let receipt : Receipt.EncryptedReceipt = {
            id = nextReceiptId;
            store = caller;
            encryptedData = encryptedData;
            timestamp = Time.now();
        };

        // Store receipt for the store
        let storeReceipts = switch (BTree.get(userReceipts, Principal.compare, caller)) {
            case (?receipts) receipts;
            case null [];
        };
        ignore BTree.insert(
            userReceipts,
            Principal.compare,
            caller,
            Array.append(storeReceipts, [receipt])
        );

        // Update store receipt history
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let history : Receipt.ReceiptHistory = {
                    id = receipt.id;
                    holderId = holderId;
                    timestamp = receipt.timestamp;
                    amount = amount;
                };
                
                let updatedStore = {
                    store with 
                    receiptHistory = Array.append(store.receiptHistory, [history]);
                };
                ignore BTree.insert(stores, Principal.compare, caller, updatedStore);
            };
            case null { };
        };

        nextReceiptId += 1;
        receipt.id
    };

    // Get receipt if authorized
    public shared({ caller }) func getReceipt(receiptId: Receipt.ReceiptId) : async ?Receipt.EncryptedReceipt {
        for ((user, receipts) in BTree.entries(userReceipts)) {
            switch(Array.find<Receipt.EncryptedReceipt>(receipts, func(r) = r.id == receiptId)) {
                case (?receipt) {
                    if (Receipt.isAuthorized(receipt, caller, receipt.store)) {
                        return ?receipt;
                    };
                    return null; // Unauthorized
                };
                case null {};
            };
        };
        null // Not found
    };

    // Get user receipts
    public shared({ caller }) func getUserReceipts() : async ?[Receipt.EncryptedReceipt] {
        BTree.get(userReceipts, Principal.compare, caller)
    };
}