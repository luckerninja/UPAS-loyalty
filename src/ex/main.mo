import Principal "mo:base/Principal";
import Error "mo:base/Error";
import ICRC1 "canister:icrc1_ledger_canister";
import Debug "mo:base/Debug";
import Result "mo:base/Result";

shared(msg) actor class ExternalCanister() {
    private var owner = msg.caller;
    private var loyaltyActor = actor("aaaaa-aa") : actor {
        addStoreTokens : shared (Principal, Nat) -> async ();
        getStoreTokens : shared query (Principal) -> async Nat;
    };

    public shared({ caller }) func setLoyaltyActor(loyaltyAddress: Text): async () {
        assert owner == caller;
        loyaltyActor := actor(loyaltyAddress);
    };

    public shared({ caller }) func setController(newController: Principal) : async () {
        assert caller == owner;
        owner := newController;
    };

    public shared({ caller }) func mintAndTransferToStore(storePrincipal: Principal, amount: Nat) : async Result.Result<Nat, Text> {
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

        try {
            let transferResult = await ICRC1.icrc1_transfer(transferArgs);
            switch (transferResult) {
                case (#Err(transferError)) {
                    #err("Couldn't transfer funds:\n" # debug_show (transferError))
                };
                case (#Ok(blockIndex)) { 
                    await loyaltyActor.addStoreTokens(storePrincipal, amount);
                    #ok(blockIndex)
                };
            };
        } catch (error : Error) {
            #err("Reject message: " # Error.message(error))
        };
    };
}
