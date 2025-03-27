import Principal "mo:base/Principal";
import Error "mo:base/Error";

shared(msg) actor class ExternalCanister() {
    private var owner = msg.caller;

    private var loyaltyActor = actor("bkyz2-fmaaa-aaaaa-qaaaq-cai") : actor {
        addPoints : shared (Principal, Nat) -> async ();
        getPoints : shared query (Principal) -> async Nat;
    };

    private func isController(caller: Principal) : Bool {
        caller == owner
    };

    public shared({ caller }) func setLoyaltyActor(loyaltyAddress: Text): async () {
        assert owner == caller;

        loyaltyActor := actor(loyaltyAddress) : actor {
            addPoints : shared (Principal, Nat) -> async ();
            getPoints : shared query (Principal) -> async Nat;
        };
    };

    public shared({ caller }) func setController(newController: Principal) : async () {
        if (not isController(caller)) {
            throw Error.reject("Unauthorized: only controller can change controller");
        };
        owner := newController;
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
