import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Sha512 "mo:sha2/Sha512";
import Array "mo:base/Array";

module {
    public func createSelfAuthenticatingId(publicKey: [Nat8]) : Principal {
        let hash = Sha512.fromBlob(#sha512_224, Blob.fromArray(publicKey));
        
        let bytes : [Nat8] = Array.tabulate<Nat8>(29, func (i) {
            if (i < 28) {
                Blob.toArray(hash)[i]
            } else {
                0x02
            }
        });
        
        Principal.fromBlob(Blob.fromArray(bytes))
    };

    public func isSelfAuthenticating(p: Principal) : Bool {
        let bytes = Blob.toArray(Principal.toBlob(p));
        bytes.size() == 29 and bytes[28] == 0x02
    };

    public func getPublicKeyHash(p: Principal) : ?[Nat8] {
        let bytes = Blob.toArray(Principal.toBlob(p));
        if (isSelfAuthenticating(p)) {
            ?Array.tabulate<Nat8>(28, func(i) = bytes[i])
        } else {
            null
        }
    };
} 