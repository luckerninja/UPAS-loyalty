import Principal "mo:base/Principal";
import Error "mo:base/Error";

actor class ExternalCanister(loyaltyCanisterId: Text) {
    private let loyaltyActor = actor(loyaltyCanisterId) : actor {
        addPoints : shared (Principal, Nat) -> async ();
        getPoints : shared query (Principal) -> async Nat;
    };

    private stable var controller: Principal = Principal.fromText("aaaaa-aa");

    private func isController(caller: Principal) : Bool {
        caller == controller
    };

    public shared({ caller }) func setController(newController: Principal) : async () {
        if (not isController(caller)) {
            throw Error.reject("Unauthorized: only controller can change controller");
        };
        controller := newController;
    };

    public shared({ caller }) func addPoints(userPrincipal: Principal, amount: Nat) : async () {
        if (not isController(caller)) {
            throw Error.reject("Unauthorized: only controller can add points");
        };
        await loyaltyActor.addPoints(userPrincipal, amount);
    };

    public shared({ caller }) func getPoints(userPrincipal: Principal) : async Nat {
        await loyaltyActor.getPoints(userPrincipal)
    };
}
