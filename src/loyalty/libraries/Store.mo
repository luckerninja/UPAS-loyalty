import Text "mo:base/Text";
import Principal "mo:base/Principal";

module {
    public type Store = {
        owner: Principal;
        name: Text;
        description: Text;
        points: Int;
    };
}