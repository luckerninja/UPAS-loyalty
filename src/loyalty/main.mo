import Store "./libraries/Store";
import Principal "mo:base/Principal";
import BTree "mo:stableheapbtreemap/BTree";
import Error "mo:base/Error";

shared(msg) actor class LoyaltyProgram() {
    private let owner = msg.caller;
    private stable let stores = BTree.init<Principal, Store.Store>(?8);

    public shared({ caller }) func addStore(principal: Principal, name: Text, description: Text) : async ?Store.Store {
        assert(caller == owner);

        let store : Store.Store = {
            owner = principal;
            name = name;
            description = description;
            points = 0;
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
}