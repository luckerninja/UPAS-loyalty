module {
    public type IC = actor {
        ecdsa_public_key : ({
        canister_id : ?Principal;
        derivation_path : [Blob];
        key_id : { curve: { #secp256k1; } ; name: Text };
        }) -> async ({ public_key : Blob; chain_code : Blob; });
        sign_with_ecdsa : ({
        message_hash : Blob;
        derivation_path : [Blob];
        key_id : { curve: { #secp256k1; } ; name: Text };
        }) -> async ({ signature : Blob });
    };
};