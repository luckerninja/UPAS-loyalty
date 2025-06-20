import Store "./libraries/Store";
import Credential "./libraries/Credential";
import Tag "./libraries/Tag";
import Scheme "./libraries/Scheme";
import Conditions "./libraries/Conditions";
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
import Buffer "mo:base/Buffer";
import VetKey "mo:ic-vetkeys";
import Int "mo:base/Int";
import IC "./libraries/IC";
import Sha256 "mo:sha2/Sha256";
import Cycles "mo:base/ExperimentalCycles";
import Hex "./libraries/Hex";

shared(msg) actor class LoyaltyProgram(externalCanisterId: Principal) {

    let ic: IC.IC = actor("aaaaa-aa");

    let RECEIPTS_MAP_NAME = "receipts";
    
    private let owner = msg.caller;
    private let tokenMinter = externalCanisterId;
    private stable let stores = BTree.init<Principal, Store.Store>(?8);
    private stable let userCredentials = BTree.init<Principal, [Credential.IssuedCredential]>(?8);
    private stable let storeTokens = BTree.init<Principal, Nat>(?8);
    private stable let userReceipts = BTree.init<Principal, [Receipt.EncryptedReceipt]>(?8);
    private stable let tagSchemes = BTree.init<Text, Tag.TagScheme>(?8);
    private stable let userTags = BTree.init<Principal, [Tag.IssuedTag]>(?8);
    private stable let storeSchemes = BTree.init<Principal, [Scheme.StoreScheme]>(?8);
    private stable let userSchemes = BTree.init<Principal, [Scheme.IssuedScheme]>(?8);


    type EncryptedMaps = VetKey.EncryptedMaps.EncryptedMaps<VetKey.AccessRights>;
    let accessRightsOperations = VetKey.accessRightsOperations();
    func newEncryptedMaps() : EncryptedMaps {
        VetKey.EncryptedMaps.EncryptedMaps<VetKey.AccessRights>(
            { curve = #bls12_381_g2; name = "dfx_test_key" },
            "receipts",
            accessRightsOperations
        );
    };

    private var ICRC1Actor = actor("aaaaa-aa") : actor {
        icrc1_transfer : shared (ICRC1.TransferArg) -> async ICRC1.TransferResult;
    };

    public shared({ caller }) func setICRC1Actor(icrc1Address: Principal): async () {
        assert owner == caller;
        Debug.print("Setting ICRC1 actor with Principal: " # debug_show(icrc1Address));
        ICRC1Actor := actor(Principal.toText(icrc1Address)) : actor {
            icrc1_transfer : shared (ICRC1.TransferArg) -> async ICRC1.TransferResult;
        };
        Debug.print("ICRC1 actor Principal: " # debug_show(Principal.fromActor(ICRC1Actor)));
    };

    let encryptedMaps = newEncryptedMaps();


    private stable var nextReceiptId : Nat = 1;

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
            let result = await ICRC1Actor.icrc1_transfer(transferArgs);
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
        Debug.print("verifyCredential called by: " # Principal.toText(caller));
        Debug.print("schemeId: " # schemeId);
        Debug.print("holderId: " # Principal.toText(holderId));
        Debug.print("timestamp: " # Int.toText(timestamp));
        Debug.print("signature length: " # Nat.toText(signature.size()));
        Debug.print("publicKey length: " # Nat.toText(publicKeyRawBytes.size()));
        let credential = Credential.buildCredential(schemeId, caller, holderId, timestamp, 100);
        let curve = Curve.Curve(#secp256k1);
        let ?publicKey = ECDSA.deserializePublicKeyUncompressed(curve, Blob.fromArray(publicKeyRawBytes));
        Signature.verifySignature(publicKey, Signature.credentialToMessage(credential), signature)
    };

    // Store encrypted receipt
    public shared({ caller }) func storeReceipt(encryptedData: Text, holderId: Principal, amount: Nat) : async Receipt.ReceiptId {
        let receipt : Receipt.EncryptedReceipt = {
            id = nextReceiptId;
            store = caller;
            timestamp = Time.now();
        };

        // Calculate cashback amount (10% of purchase amount)
        let baseCashbackAmount = amount / 10;
        
        // Calculate enhanced cashback based on user's schemes
        let cashbackAmount = calculateEnhancedCashback(baseCashbackAmount, holderId, caller);
        
        Debug.print("Purchase amount: " # Nat.toText(amount) # ", Base cashback: " # Nat.toText(baseCashbackAmount) # ", Enhanced cashback: " # Nat.toText(cashbackAmount));

        // Check store balance for cashback
        let storeBalance = switch (BTree.get(storeTokens, Principal.compare, caller)) {
            case (?balance) balance;
            case null 0;
        };

        if (storeBalance >= cashbackAmount) {
            // Send cashback to user
            switch(await transferTokens(holderId, cashbackAmount)) {
                case (#ok(blockIndex)) {
                    // Update store balance after successful cashback
                    ignore BTree.insert(
                        storeTokens, 
                        Principal.compare, 
                        caller, 
                        storeBalance - cashbackAmount
                    );
                    Debug.print("Cashback sent successfully. Block index: " # Nat.toText(blockIndex));
                };
                case (#err(err)) {
                    Debug.print("Failed to send cashback: " # debug_show(err));
                };
            };
        } else {
            Debug.print("Insufficient store balance for cashback. Required: " # Nat.toText(cashbackAmount) # ", Available: " # Nat.toText(storeBalance));
            throw Error.reject("Insufficient store balance for cashback");
        };

        // Store encrypted data in EncryptedMaps using receipt ID
        let mapId = (caller, Text.encodeUtf8("receipts"));
        let key = Text.encodeUtf8(Nat.toText(receipt.id));
        let value = Text.encodeUtf8(encryptedData);
        
        ignore encryptedMaps.insertEncryptedValue(
            caller,
            mapId,
            key,
            value
        );

        // Set read-only rights for the holder
        ignore encryptedMaps.setUserRights(
            caller,
            mapId,
            holderId,
            #ReadWriteManage
        );

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

    // Get encrypted receipt data
    public shared({ caller }) func getEncryptedReceiptData(receiptId: Receipt.ReceiptId) : async ?Text {
        // Find receipt to check authorization
        for ((user, receipts) in BTree.entries(userReceipts)) {
            switch(Array.find<Receipt.EncryptedReceipt>(receipts, func(r) = r.id == receiptId)) {
                case (?receipt) {
                    if (Receipt.isAuthorized(receipt, caller, receipt.store)) {
                        let mapId = (receipt.store, Text.encodeUtf8("receipts"));
                        let key = Text.encodeUtf8(Nat.toText(receiptId));
                        switch(encryptedMaps.getEncryptedValue(caller, mapId, key)) {
                            case (#ok(?value)) {
                                let decoded = Text.decodeUtf8(value);
                                switch(decoded) {
                                    case (?text) return ?text;
                                    case null return null;
                                }
                            };
                            case _ return null;
                        }
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

    // ECDSA FUNCTIONS

    public shared (msg) func public_key() : async { #Ok : { public_key: Blob }; #Err : Text } {
        let caller = Principal.toBlob(msg.caller);

        try {

        //request the management canister to compute an ECDSA public key
        let { public_key } = await ic.ecdsa_public_key({

            //When `null`, it defaults to getting the public key of the canister that makes this call
            canister_id = null;
            derivation_path = [ caller ];
            //this code uses the mainnet test key
            key_id = { curve = #secp256k1; name = "test_key_1" };
        });

        #Ok({ public_key })

        } catch (err) {

        #Err(Error.message(err))

        }
    };

    public shared (msg) func sign(message: Text) : async { #Ok : { signature_hex: Text };  #Err : Text } {
        let caller = Principal.toBlob(msg.caller);
        try {
            let message_hash: Blob = Sha256.fromArray(#sha256, Blob.toArray(Text.encodeUtf8(message)));
            Cycles.add(30_000_000_000);
            let { signature } = await ic.sign_with_ecdsa({
                message_hash;
                derivation_path = [ caller ];
                key_id = { curve = #secp256k1; name = "dfx_test_key" };
        });
            #Ok({ signature_hex = Hex.encode(Blob.toArray(signature))})
        } catch (err) {
            #Err(Error.message(err))
        }
    };

    // INTERMEDIATE FUNCTIONS FOR CONDITION EVALUATION

    // Create evaluation context with all required data
    private func createEvaluationContext(userId: Principal) : Conditions.EvaluationContext {
        {
            userId = userId;
            currentTime = Time.now();
            stores = stores;
            userCredentials = userCredentials;
            userTags = userTags;
        }
    };

    // Generic function to evaluate any condition
    private func evaluateCondition(condition: Conditions.Condition, context: Conditions.EvaluationContext) : Bool {
        Conditions.evaluateCondition(condition, context)
    };

    // Generic function to create issued tag/scheme
    private func createIssuedTag(
        schemeId: Text,
        userId: Principal,
        timestamp: Int,
        signature: [Nat8],
        canisterSignature: ?Text,
        metadata: ?Text
    ) : Tag.IssuedTag {
        {
            schemeId = schemeId;
            userId = userId;
            timestamp = timestamp;
            signature = signature;
            canisterSignature = canisterSignature;
            metadata = metadata;
        }
    };

    // Generic function to generate signature
    private func generateSignature(schemeId: Text, userId: Principal) : [Nat8] {
        let message = schemeId # Principal.toText(userId) # Int.toText(Time.now());
        Blob.toArray(Text.encodeUtf8(message))
    };

    // Generic function to award tag/scheme to user
    private func awardSchemeToUser(
        schemeId: Text,
        userId: Principal,
        existingItems: [Tag.IssuedTag],
        storageMap: BTree.BTree<Principal, [Tag.IssuedTag]>
    ) : async Bool {
        let signature = generateSignature(schemeId, userId);
        let canisterSignature = try {
            await generateCanisterSignature(schemeId, userId)
        } catch (error) {
            Debug.print("Failed to generate canister signature for scheme " # schemeId # ": " # Error.message(error));
            null
        };
        
        let issuedItem = createIssuedTag(
            schemeId,
            userId,
            Time.now(),
            signature,
            canisterSignature,
            null
        );

        let updatedItems = Array.append(existingItems, [issuedItem]);
        ignore BTree.insert(storageMap, Principal.compare, userId, updatedItems);
        true
    };

    // TAG MANAGEMENT FUNCTIONS

    // Create a new tag scheme (only controller can create tags)
    public shared({ caller }) func createTag(
        id: Text,
        name: Text,
        description: Text,
        condition: Tag.TagCondition,
        metadata: Text
    ) : async Result.Result<Text, Text> {
        if (caller != owner) {
            return #err("Unauthorized: only controller can create tags");
        };

        if (BTree.has(tagSchemes, Text.compare, id)) {
            return #err("Tag with this ID already exists");
        };

        let tagScheme = Tag.createTagScheme(
            id,
            name,
            description,
            condition,
            metadata,
            caller
        );

        if (not Tag.validateTagScheme(tagScheme)) {
            return #err("Invalid tag scheme");
        };

        ignore BTree.insert(tagSchemes, Text.compare, id, tagScheme);
        #ok(id)
    };

    // Get all tag schemes
    public query func listTagSchemes() : async [(Text, Tag.TagScheme)] {
        BTree.toArray(tagSchemes)
    };

    // Get specific tag scheme
    public query func getTagScheme(tagId: Text) : async ?Tag.TagScheme {
        BTree.get(tagSchemes, Text.compare, tagId)
    };

    // Get user's tags
    public query func getUserTags(userId: Principal) : async ?[Tag.IssuedTag] {
        BTree.get(userTags, Principal.compare, userId)
    };

    // Verify canister signature for a tag
    public query func verifyTagCanisterSignature(tagId: Text, userId: Principal, canisterSignature: Text) : async Bool {
        // Get the tag scheme to verify it exists
        switch (BTree.get(tagSchemes, Text.compare, tagId)) {
            case (?tagScheme) {
                // Get user's tags to find the specific tag
                switch (BTree.get(userTags, Principal.compare, userId)) {
                    case (?userTags) {
                        switch(Array.find<Tag.IssuedTag>(userTags, func(tag) = tag.schemeId == tagId)) {
                            case (?issuedTag) {
                                // Compare the stored signature with the provided one
                                switch(issuedTag.canisterSignature) {
                                    case (?storedSignature) storedSignature == canisterSignature;
                                    case null false;
                                }
                            };
                            case null false;
                        }
                    };
                    case null false;
                }
            };
            case null false;
        }
    };

    // Deactivate tag (only controller)
    public shared({ caller }) func deactivateTag(tagId: Text) : async Result.Result<(), Text> {
        if (caller != owner) {
            return #err("Unauthorized: only controller can deactivate tags");
        };

        switch (BTree.get(tagSchemes, Text.compare, tagId)) {
            case (?tagScheme) {
                let deactivatedTag = Tag.deactivateTag(tagScheme);
                ignore BTree.insert(tagSchemes, Text.compare, tagId, deactivatedTag);
                #ok()
            };
            case null #err("Tag not found");
        }
    };

    // Evaluate and award tags for a user (can be called periodically or on events)
    public shared({ caller }) func evaluateUserTags(userId: Principal) : async [Text] {
        let context = createEvaluationContext(userId);

        let awardedTags = Buffer.Buffer<Text>(0);
        
        // Get existing user tags to avoid duplicates
        let existingTags = switch (BTree.get(userTags, Principal.compare, userId)) {
            case (?tags) tags;
            case null [];
        };

        // Check all active tag schemes
        for ((tagId, tagScheme) in BTree.entries(tagSchemes)) {
            if (tagScheme.isActive) {
                // Check if user already has this tag
                let hasTag = switch(Array.find<Tag.IssuedTag>(existingTags, func(issuedTag) = issuedTag.schemeId == tagId)) {
                    case (?_) true;
                    case null false;
                };

                if (not hasTag) {
                    // Evaluate condition using the new evaluation function
                    if (evaluateCondition(tagScheme.condition, context)) {
                        // Award the tag using the new award function
                        let success = await awardSchemeToUser(tagId, userId, existingTags, userTags);
                        if (success) {
                            awardedTags.add(tagId);
                        };
                    };
                };
            };
        };

        Buffer.toArray(awardedTags)
    };

    // Private function to evaluate tag conditions with access to canister data
    private func evaluateTagCondition(condition: Tag.TagCondition, context: Tag.TagContext) : Bool {
        switch(condition) {
            case (#Simple(simpleCondition)) {
                evaluateSimpleTagCondition(simpleCondition, context)
            };
            case (#And(conditions)) {
                for (c in conditions.vals()) {
                    if (not evaluateTagCondition(c, context)) {
                        return false;
                    };
                };
                true
            };
            case (#Or(conditions)) {
                for (c in conditions.vals()) {
                    if (evaluateTagCondition(c, context)) {
                        return true;
                    };
                };
                false
            };
        }
    };

    // Private function to evaluate simple tag conditions
    private func evaluateSimpleTagCondition(condition: Tag.SimpleCondition, context: Tag.TagContext) : Bool {
        switch(condition) {
            case (#ReceiptCount({ storeNames; minCount; timeWindow })) {
                evaluateReceiptCount(context.userId, storeNames, minCount, timeWindow, context.currentTime)
            };
            case (#TotalSpent({ storeNames; minAmount; timeWindow })) {
                evaluateTotalSpent(context.userId, storeNames, minAmount, timeWindow, context.currentTime)
            };
            case (#CredentialRequired({ schemeId; issuerNames })) {
                evaluateCredentialRequired(context.userId, schemeId, issuerNames)
            };
            case (#TagRequired({ tagId })) {
                evaluateTagRequired(context.userId, tagId)
            };
        }
    };

    // Helper functions for condition evaluation
    private func evaluateReceiptCount(userId: Principal, storeNames: [Text], minCount: Nat, timeWindow: ?Int, currentTime: Int) : Bool {
        var count : Nat = 0;
        
        // Inefficiently iterate through all stores and their receipt histories.
        // A dedicated user->receipts mapping would be better for performance.
        for ((storeId, store) in BTree.entries(stores)) {
            // TODO: Filter by storeNames if not empty. Requires store name to be on receipt or a lookup.
            
            for (receipt in store.receiptHistory.vals()) {
                if (receipt.holderId == userId) {
                    let inWindow = switch(timeWindow) {
                        case (?win) receipt.timestamp >= currentTime - win;
                        case null true;
                    };

                    if (inWindow) {
                        count += 1;
                    };
                };
            };
        };
        
        return count >= minCount;
    };

    private func evaluateTotalSpent(userId: Principal, storeNames: [Text], minAmount: Nat, timeWindow: ?Int, currentTime: Int) : Bool {
        // This condition cannot be implemented currently as the 'amount' of a purchase
        // is not stored in the ReceiptHistory. The data structure would need to be
        // updated to support this feature.
        false
    };

    private func evaluateCredentialRequired(userId: Principal, schemeId: Text, issuerNames: [Text]) : Bool {
        switch (BTree.get(userCredentials, Principal.compare, userId)) {
            case (?credentials) {
                switch(Array.find<Credential.IssuedCredential>(credentials, func(cred) = cred.schemeId == schemeId)) {
                    case (?_) true;
                    case null false;
                }
            };
            case null false;
        }
    };

    private func evaluateTagRequired(userId: Principal, tagId: Text) : Bool {
        switch (BTree.get(userTags, Principal.compare, userId)) {
            case (?tags) {
                switch(Array.find<Tag.IssuedTag>(tags, func(tag) = tag.schemeId == tagId)) {
                    case (?_) true;
                    case null false;
                }
            };
            case null false;
        }
    };

    // Generate signature for issued tag (placeholder implementation)
    private func generateTagSignature(tagId: Text, userId: Principal) : [Nat8] {
        let message = tagId # Principal.toText(userId) # Int.toText(Time.now());
        Blob.toArray(Text.encodeUtf8(message))
    };

    // Generate canister signature for issued tag
    public shared({ caller }) func generateCanisterSignature(tagId: Text, userId: Principal) : async ?Text {
        let message = tagId # Principal.toText(userId) # Int.toText(Time.now());
        let signatureResult = await sign(message);
        Debug.print("Signature result: " # debug_show(signatureResult));
        switch(signatureResult) {
            case (#Ok(result)) ?result.signature_hex;
            case (#Err(error)) {
                Debug.print("Failed to generate canister signature: " # error);
                throw Error.reject("Failed to generate canister signature");
            };
        }
    };

    // STORE SCHEME MANAGEMENT FUNCTIONS

    // Create a new store scheme (only store owners can create schemes)
    public shared({ caller }) func createStoreScheme(
        name: Text,
        description: Text,
        condition: Scheme.SchemeCondition,
        metadata: Text,
        cashbackMultiplier: Nat,
        maxCashbackAmount: ?Nat
    ) : async Result.Result<Text, Text> {
        // Verify caller is a store owner
        switch (BTree.get(stores, Principal.compare, caller)) {
            case (?store) {
                let schemeId = Scheme.generateSchemeId(caller, name);
                
                // Check if scheme with this name already exists for this store
                let existingSchemes = switch (BTree.get(storeSchemes, Principal.compare, caller)) {
                    case (?schemes) schemes;
                    case null [];
                };
                
                let hasScheme = switch(Array.find<Scheme.StoreScheme>(existingSchemes, func(scheme) = scheme.name == name)) {
                    case (?_) true;
                    case null false;
                };
                
                if (hasScheme) {
                    return #err("Store scheme with this name already exists");
                };

                let storeScheme = Scheme.createStoreScheme(
                    schemeId,
                    name,
                    description,
                    condition,
                    metadata,
                    caller,
                    cashbackMultiplier,
                    maxCashbackAmount
                );

                if (not Scheme.validateStoreScheme(storeScheme)) {
                    return #err("Invalid store scheme");
                };

                let updatedSchemes = Array.append(existingSchemes, [storeScheme]);
                ignore BTree.insert(storeSchemes, Principal.compare, caller, updatedSchemes);
                #ok(schemeId)
            };
            case null #err("Store not found");
        }
    };

    // Get all store schemes for a specific store
    public query func getStoreSchemes(storeId: Principal) : async ?[Scheme.StoreScheme] {
        BTree.get(storeSchemes, Principal.compare, storeId)
    };

    // Get user's available store schemes
    public query func getUserSchemes(userId: Principal) : async ?[Scheme.IssuedScheme] {
        BTree.get(userSchemes, Principal.compare, userId)
    };

    // Deactivate store scheme (only store owner)
    public shared({ caller }) func deactivateStoreScheme(schemeId: Text) : async Result.Result<(), Text> {
        switch (BTree.get(storeSchemes, Principal.compare, caller)) {
            case (?schemes) {
                let updatedSchemes = Array.map<Scheme.StoreScheme, Scheme.StoreScheme>(
                    schemes,
                    func(scheme) {
                        if (scheme.id == schemeId) {
                            Scheme.deactivateStoreScheme(scheme)
                        } else {
                            scheme
                        }
                    }
                );
                ignore BTree.insert(storeSchemes, Principal.compare, caller, updatedSchemes);
                #ok()
            };
            case null #err("Store not found or no schemes");
        }
    };

    // Evaluate and award store schemes for a user
    public shared({ caller }) func evaluateUserStoreSchemes(userId: Principal) : async [Text] {
        let context = createEvaluationContext(userId);

        let awardedSchemes = Buffer.Buffer<Text>(0);
        
        // Get existing user schemes to avoid duplicates
        let existingSchemes = switch (BTree.get(userSchemes, Principal.compare, userId)) {
            case (?schemes) schemes;
            case null [];
        };

        // Check all store schemes from all stores
        for ((storeId, schemes) in BTree.entries(storeSchemes)) {
            for (scheme in schemes.vals()) {
                if (scheme.isActive) {
                    // Check if user already has this scheme
                    let hasScheme = switch(Array.find<Scheme.IssuedScheme>(existingSchemes, func(issuedScheme) = issuedScheme.schemeId == scheme.id)) {
                        case (?_) true;
                        case null false;
                    };

                    if (not hasScheme) {
                        // Evaluate condition using the new evaluation function
                        if (evaluateCondition(scheme.condition, context)) {
                            // Award the scheme using the new award function
                            let success = await awardSchemeToUser(scheme.id, userId, existingSchemes, userSchemes);
                            if (success) {
                                awardedSchemes.add(scheme.id);
                            };
                        };
                    };
                };
            };
        };

        Buffer.toArray(awardedSchemes)
    };

    // Calculate cashback amount based on user's active schemes
    private func calculateEnhancedCashback(baseAmount: Nat, userId: Principal, storeId: Principal) : Nat {
        let userIssuedSchemes = switch (BTree.get(userSchemes, Principal.compare, userId)) {
            case (?schemes) schemes;
            case null [];
        };

        let storeSchemesList = switch (BTree.get(storeSchemes, Principal.compare, storeId)) {
            case (?schemes) schemes;
            case null [];
        };

        var maxMultiplier : Nat = 100; // Default 100% (no enhancement)

        // Find the highest applicable multiplier from user's schemes
        for (issuedScheme in userIssuedSchemes.vals()) {
            switch(Array.find<Scheme.StoreScheme>(storeSchemesList, func(scheme) = scheme.id == issuedScheme.schemeId)) {
                case (?storeScheme) {
                    if (storeScheme.cashbackMultiplier > maxMultiplier) {
                        maxMultiplier := storeScheme.cashbackMultiplier;
                    };
                };
                case null {};
            };
        };

        (baseAmount * maxMultiplier) / 100
    };
}