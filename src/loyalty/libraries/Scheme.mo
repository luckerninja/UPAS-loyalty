import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Conditions "./Conditions";

module {
    // Re-export types from Conditions for backward compatibility
    public type SimpleCondition = Conditions.SimpleCondition;
    public type SchemeCondition = Conditions.Condition;
    public type IssuedScheme = Conditions.IssuedTag;
    public type SchemeContext = Conditions.EvaluationContext;

    // Base scheme definition
    public type BaseScheme = {
        id: Text;
        name: Text;
        description: Text;
        condition: SchemeCondition;
        metadata: Text;
        createdBy: Principal;
        isActive: Bool;
    };

    // Tag scheme (extends base scheme)
    public type TagScheme = BaseScheme;

    // Store scheme (extends base scheme with cashback multiplier)
    public type StoreScheme = {
        id: Text;
        name: Text;
        description: Text;
        condition: SchemeCondition;
        metadata: Text;
        createdBy: Principal;
        isActive: Bool;
        cashbackMultiplier: Nat; // Multiplier for cashback (e.g., 150 = 50% more cashback, 100 = normal)
        maxCashbackAmount: ?Nat; // Optional maximum cashback amount
    };

    // Re-export helper functions from Conditions
    public let receiptCount = Conditions.receiptCount;
    public let totalSpent = Conditions.totalSpent;
    public let credentialRequired = Conditions.credentialRequired;
    public let tagRequired = Conditions.tagRequired;
    public let andCondition = Conditions.andCondition;
    public let orCondition = Conditions.orCondition;
    public let evaluateCondition = Conditions.evaluateCondition;

    // Tag scheme creation function
    public func createTagScheme(
        id: Text,
        name: Text,
        description: Text,
        condition: SchemeCondition,
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

    // Store scheme creation function
    public func createStoreScheme(
        id: Text,
        name: Text,
        description: Text,
        condition: SchemeCondition,
        metadata: Text,
        createdBy: Principal,
        cashbackMultiplier: Nat,
        maxCashbackAmount: ?Nat
    ) : StoreScheme {
        {
            id = id;
            name = name;
            description = description;
            condition = condition;
            metadata = metadata;
            createdBy = createdBy;
            isActive = true;
            cashbackMultiplier = cashbackMultiplier;
            maxCashbackAmount = maxCashbackAmount;
        }
    };

    // Helper function to create an issued scheme
    public func createIssuedScheme(
        schemeId: Text,
        userId: Principal,
        timestamp: Int,
        signature: [Nat8],
        canisterSignature: ?Text,
        metadata: ?Text
    ) : IssuedScheme {
        {
            schemeId = schemeId;
            userId = userId;
            timestamp = timestamp;
            signature = signature;
            canisterSignature = canisterSignature;
            metadata = metadata;
        }
    };

    // Helper function to generate scheme ID from name and creator
    public func generateSchemeId(createdBy: Principal, name: Text) : Text {
        Principal.toText(createdBy) # "_" # name
    };

    // Helper function to validate tag scheme
    public func validateTagScheme(tagScheme: TagScheme) : Bool {
        // Basic validation
        tagScheme.id.size() > 0 and
        tagScheme.name.size() > 0 and
        tagScheme.description.size() > 0
    };

    // Helper function to validate store scheme
    public func validateStoreScheme(storeScheme: StoreScheme) : Bool {
        // Basic validation
        storeScheme.id.size() > 0 and
        storeScheme.name.size() > 0 and
        storeScheme.description.size() > 0 and
        storeScheme.cashbackMultiplier > 0
    };

    // Helper function to deactivate a tag scheme
    public func deactivateTagScheme(tagScheme: TagScheme) : TagScheme {
        {
            tagScheme with isActive = false
        }
    };

    // Helper function to deactivate a store scheme
    public func deactivateStoreScheme(storeScheme: StoreScheme) : StoreScheme {
        {
            storeScheme with isActive = false
        }
    };

    // Calculate cashback amount based on store scheme
    public func calculateCashbackAmount(baseAmount: Nat, storeScheme: StoreScheme) : Nat {
        let calculatedAmount = (baseAmount * storeScheme.cashbackMultiplier) / 100;
        
        switch(storeScheme.maxCashbackAmount) {
            case (?maxAmount) {
                if (calculatedAmount > maxAmount) {
                    maxAmount
                } else {
                    calculatedAmount
                }
            };
            case null calculatedAmount;
        }
    };
}; 