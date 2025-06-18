import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import ICRC1 "canister:icrc1_ledger_canister";

shared(msg) actor class ExternalCanister() {
    private var owner = msg.caller;
    private var loyaltyActor = actor("aaaaa-aa") : actor {
        addStoreTokens : shared (Principal, Nat) -> async ();
        getStoreTokens : shared query (Principal) -> async Nat;
    };
    private var ICRC1Actor = actor("aaaaa-aa") : actor {
        icrc1_transfer : shared (ICRC1.TransferArg) -> async ICRC1.TransferResult;
    };

    public shared({ caller }) func setLoyaltyActor(loyaltyAddress: Principal): async () {
        assert owner == caller;
        Debug.print("Setting Loyalty actor with Principal: " # debug_show(loyaltyAddress));
        loyaltyActor := actor(Principal.toText(loyaltyAddress)) : actor {
            addStoreTokens : shared (Principal, Nat) -> async ();
            getStoreTokens : shared query (Principal) -> async Nat;
        };
        Debug.print("Loyalty actor Principal: " # debug_show(Principal.fromActor(loyaltyActor)));
    };

    public shared({ caller }) func setICRC1Actor(icrc1Address: Principal): async () {
        assert owner == caller;
        Debug.print("Setting ICRC1 actor with Principal: " # debug_show(icrc1Address));
        ICRC1Actor := actor(Principal.toText(icrc1Address)) : actor {
            icrc1_transfer : shared (ICRC1.TransferArg) -> async ICRC1.TransferResult;
        };
        Debug.print("ICRC1 actor Principal: " # debug_show(Principal.fromActor(ICRC1Actor)));
    };

    public shared func getICRC1Actor() : async Principal {
        Principal.fromActor(ICRC1Actor)
    };

    public shared func getLoyaltyActor() : async Principal {
        Principal.fromActor(loyaltyActor)
    };

    public shared({ caller }) func setController(newController: Principal) : async () {
        assert caller == owner;
        owner := newController;
    };

    public shared({ caller }) func mintAndTransferToStore(storePrincipal: Principal, amount: Nat) : async ICRC1.TransferResult {
        assert caller == owner;

        let transferArgs : ICRC1.TransferArg = {
            memo = null;
            amount = amount;
            from_subaccount = null;
            fee = null;
            to = {
                owner = Principal.fromActor(loyaltyActor);
                subaccount = null;
            };
            created_at_time = null;
        };

        Debug.print(
            "Transferring "
            # debug_show (amount)
            # " tokens to Loyalty Program"
        );

        Debug.print("Loyalty Actor Principal: " # debug_show(Principal.fromActor(loyaltyActor)));
        Debug.print("Store Principal: " # debug_show(storePrincipal));

        try {
            let transferResult = await ICRC1Actor.icrc1_transfer(transferArgs);
            switch (transferResult) {
                case (#Err(transferError)) {
                    #Err(transferError)
                };
                case (#Ok(blockIndex)) { 
                    Debug.print("Transfer successful, calling addStoreTokens");
                    await loyaltyActor.addStoreTokens(storePrincipal, amount);
                    #Ok(blockIndex)
                };
            };
        } catch (error : Error) {
            Debug.print("Error in mintAndTransferToStore: " # Error.message(error));
            #Err(#GenericError({ message = Error.message(error); error_code = 0 }))
        };
    };
}
