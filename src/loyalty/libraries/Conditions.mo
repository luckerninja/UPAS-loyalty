import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import BTree "mo:stableheapbtreemap/BTree";
import Credential "../libraries/Credential";
import Receipt "../libraries/Receipt";
import Store "../libraries/Store";

module {
    // Issued tag/scheme to a user (common structure)
    public type IssuedTag = {
        schemeId: Text;
        userId: Principal;
        timestamp: Int;
        signature: [Nat8];
        canisterSignature: ?Text; // Optional canister signature
        metadata: ?Text;
    };

    // Basic condition types for evaluation
    public type SimpleCondition = {
        #ReceiptCount : {
            storeNames: [Text];
            minCount: Nat;
            timeWindow: ?Int; // Optional time window in nanoseconds
        };
        #TotalSpent : {
            storeNames: [Text];
            minAmount: Nat;
            timeWindow: ?Int;
        };
        #CredentialRequired : {
            schemeId: Text;
            issuerNames: [Text];
        };
        #TagRequired : {
            tagId: Text;
        };
    };

    // Recursive condition structure supporting AND/OR logic
    public type Condition = {
        #Simple : SimpleCondition;
        #And : [Condition];
        #Or : [Condition];
    };

    // Context for condition evaluation
    public type EvaluationContext = {
        userId: Principal;
        currentTime: Int;
        stores: BTree.BTree<Principal, Store.Store>;
        userCredentials: BTree.BTree<Principal, [Credential.IssuedCredential]>;
        userTags: BTree.BTree<Principal, [IssuedTag]>;
    };

    // Re-export types for backward compatibility
    public type TagCondition = Condition;
    public type SchemeCondition = Condition;
    public type TagContext = EvaluationContext;
    public type SchemeContext = EvaluationContext;

    // Helper functions to create simple conditions
    public func receiptCount(storeNames: [Text], minCount: Nat, timeWindow: ?Int) : Condition {
        #Simple(#ReceiptCount({
            storeNames = storeNames;
            minCount = minCount;
            timeWindow = timeWindow;
        }))
    };

    public func totalSpent(storeNames: [Text], minAmount: Nat, timeWindow: ?Int) : Condition {
        #Simple(#TotalSpent({
            storeNames = storeNames;
            minAmount = minAmount;
            timeWindow = timeWindow;
        }))
    };

    public func credentialRequired(schemeId: Text, issuerNames: [Text]) : Condition {
        #Simple(#CredentialRequired({
            schemeId = schemeId;
            issuerNames = issuerNames;
        }))
    };

    public func tagRequired(tagId: Text) : Condition {
        #Simple(#TagRequired({
            tagId = tagId;
        }))
    };

    // Logical operators
    public func andCondition(conditions: [Condition]) : Condition {
        #And(conditions)
    };

    public func orCondition(conditions: [Condition]) : Condition {
        #Or(conditions)
    };

    // Main evaluation function
    public func evaluateCondition(condition: Condition, context: EvaluationContext) : Bool {
        switch(condition) {
            case (#Simple(simpleCondition)) {
                evaluateSimpleCondition(simpleCondition, context)
            };
            case (#And(conditions)) {
                for (c in conditions.vals()) {
                    if (not evaluateCondition(c, context)) {
                        return false;
                    };
                };
                true
            };
            case (#Or(conditions)) {
                for (c in conditions.vals()) {
                    if (evaluateCondition(c, context)) {
                        return true;
                    };
                };
                false
            };
        }
    };

    // Evaluate simple conditions
    private func evaluateSimpleCondition(condition: SimpleCondition, context: EvaluationContext) : Bool {
        switch(condition) {
            case (#ReceiptCount({ storeNames; minCount; timeWindow })) {
                evaluateReceiptCount(context.userId, storeNames, minCount, timeWindow, context.currentTime, context.stores)
            };
            case (#TotalSpent({ storeNames; minAmount; timeWindow })) {
                evaluateTotalSpent(context.userId, storeNames, minAmount, timeWindow, context.currentTime, context.stores)
            };
            case (#CredentialRequired({ schemeId; issuerNames })) {
                evaluateCredentialRequired(context.userId, schemeId, issuerNames, context.userCredentials)
            };
            case (#TagRequired({ tagId })) {
                evaluateTagRequired(context.userId, tagId, context.userTags)
            };
        }
    };

    // Helper functions for condition evaluation
    private func evaluateReceiptCount(
        userId: Principal, 
        storeNames: [Text], 
        minCount: Nat, 
        timeWindow: ?Int, 
        currentTime: Int,
        stores: BTree.BTree<Principal, Store.Store>
    ) : Bool {
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

    private func evaluateTotalSpent(
        userId: Principal, 
        storeNames: [Text], 
        minAmount: Nat, 
        timeWindow: ?Int, 
        currentTime: Int,
        stores: BTree.BTree<Principal, Store.Store>
    ) : Bool {
        // This condition cannot be implemented currently as the 'amount' of a purchase
        // is not stored in the ReceiptHistory. The data structure would need to be
        // updated to support this feature.
        false
    };

    private func evaluateCredentialRequired(
        userId: Principal, 
        schemeId: Text, 
        issuerNames: [Text],
        userCredentials: BTree.BTree<Principal, [Credential.IssuedCredential]>
    ) : Bool {
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

    private func evaluateTagRequired(
        userId: Principal, 
        tagId: Text,
        userTags: BTree.BTree<Principal, [IssuedTag]>
    ) : Bool {
        switch (BTree.get(userTags, Principal.compare, userId)) {
            case (?tags) {
                switch(Array.find<IssuedTag>(tags, func(tag) = tag.schemeId == tagId)) {
                    case (?_) true;
                    case null false;
                }
            };
            case null false;
        }
    };
}; 