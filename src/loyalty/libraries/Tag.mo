import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Conditions "./Conditions";

module {
    // Re-export types from Conditions for backward compatibility
    public type SimpleCondition = Conditions.SimpleCondition;
    public type TagCondition = Conditions.Condition;
    public type IssuedTag = Conditions.IssuedTag;
    public type TagContext = Conditions.EvaluationContext;

    // Re-export helper functions from Conditions
    public let receiptCount = Conditions.receiptCount;
    public let totalSpent = Conditions.totalSpent;
    public let credentialRequired = Conditions.credentialRequired;
    public let tagRequired = Conditions.tagRequired;
    public let andCondition = Conditions.andCondition;
    public let orCondition = Conditions.orCondition;
    public let evaluateCondition = Conditions.evaluateCondition;

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
            schemeId = tagId;
            userId = userId;
            timestamp = timestamp;
            signature = signature;
            canisterSignature = canisterSignature;
            metadata = metadata;
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

    // Tag scheme definition (re-export from Scheme)
    public type TagScheme = {
        id: Text;
        name: Text;
        description: Text;
        condition: TagCondition;
        metadata: Text;
        createdBy: Principal;
        isActive: Bool;
    };

    // Tag scheme creation function
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
}; 