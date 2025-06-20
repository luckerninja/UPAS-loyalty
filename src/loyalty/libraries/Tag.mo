import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";

module {
    // Basic condition types for tag evaluation
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
    public type TagCondition = {
        #Simple : SimpleCondition;
        #And : [TagCondition];
        #Or : [TagCondition];
    };

    // Tag scheme definition
    public type TagScheme = {
        id: Text;
        name: Text;
        description: Text;
        condition: TagCondition;
        metadata: Text;
        createdBy: Principal;
        isActive: Bool;
    };

    // Issued tag to a user
    public type IssuedTag = {
        tagId: Text;
        userId: Principal;
        timestamp: Int;
        signature: [Nat8];
        canisterSignature: ?Text; // Optional canister signature
        metadata: ?Text;
    };

    // Context for tag evaluation
    public type TagContext = {
        userId: Principal;
        currentTime: Int;
    };

    // Helper functions to create simple conditions
    public func receiptCount(storeNames: [Text], minCount: Nat, timeWindow: ?Int) : TagCondition {
        #Simple(#ReceiptCount({
            storeNames = storeNames;
            minCount = minCount;
            timeWindow = timeWindow;
        }))
    };

    public func totalSpent(storeNames: [Text], minAmount: Nat, timeWindow: ?Int) : TagCondition {
        #Simple(#TotalSpent({
            storeNames = storeNames;
            minAmount = minAmount;
            timeWindow = timeWindow;
        }))
    };

    public func credentialRequired(schemeId: Text, issuerNames: [Text]) : TagCondition {
        #Simple(#CredentialRequired({
            schemeId = schemeId;
            issuerNames = issuerNames;
        }))
    };

    public func tagRequired(tagId: Text) : TagCondition {
        #Simple(#TagRequired({
            tagId = tagId;
        }))
    };

    // Logical operators
    public func andCondition(conditions: [TagCondition]) : TagCondition {
        #And(conditions)
    };

    public func orCondition(conditions: [TagCondition]) : TagCondition {
        #Or(conditions)
    };

    // Universal tag scheme creation function
    public func createTagScheme(
        id: Text,
        name: Text,
        description: Text,
        condition: TagCondition,
        metadata: Text,
        createdBy: Principal
    ) : TagScheme {
        {
            id = id;
            name = name;
            description = description;
            condition = condition;
            metadata = metadata;
            createdBy = createdBy;
            isActive = true;
        }
    };

    // Helper function to create an issued tag
    public func createIssuedTag(
        tagId: Text,
        userId: Principal,
        timestamp: Int,
        signature: [Nat8],
        canisterSignature: ?Text,
        metadata: ?Text
    ) : IssuedTag {
        {
            tagId = tagId;
            userId = userId;
            timestamp = timestamp;
            signature = signature;
            canisterSignature = canisterSignature;
            metadata = metadata;
        }
    };

    // Function to evaluate a tag condition (placeholder implementation)
    // The actual implementation will be in the main canister where data is available
    public func evaluateCondition(condition: TagCondition, context: TagContext) : Bool {
        switch(condition) {
            case (#Simple(simpleCondition)) {
                // This will be implemented in main canister with access to data
                true // Placeholder
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

    // Helper function to generate tag ID from name and creator
    public func generateTagId(createdBy: Principal, name: Text) : Text {
        Principal.toText(createdBy) # "_" # name
    };

    // Helper function to validate tag scheme
    public func validateTagScheme(tagScheme: TagScheme) : Bool {
        // Basic validation
        tagScheme.id.size() > 0 and
        tagScheme.name.size() > 0 and
        tagScheme.description.size() > 0
    };

    // Helper function to deactivate a tag
    public func deactivateTag(tagScheme: TagScheme) : TagScheme {
        {
            tagScheme with isActive = false
        }
    };
}; 