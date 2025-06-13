module {
    public type ReceiptId = Nat;
    public type StorePrincipal = Principal;
    public type UserPrincipal = Principal;
    
    public type EncryptedReceipt = {
        id: ReceiptId;
        store: StorePrincipal;
        timestamp: Int;
    };

    public type ReceiptHistory = {
        id: ReceiptId;
        timestamp: Int;
        holderId: Principal;
    };

    // Helper functions
    public func isAuthorized(receipt: EncryptedReceipt, user: Principal, store: Principal) : Bool {
        receipt.store == store or receipt.store == user
    };
}