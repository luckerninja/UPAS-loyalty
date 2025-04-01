const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function generateKeysAndSignMessage() {
    // Generate keys
    const keyPair = ec.genKeyPair();
    const publicKey = keyPair.getPublic('array', 'uncompressed');

    // Create test data for credential
    const issuerId = "h45c6-kpdwh-ayjrp-hb4eg-f7wf6-kl4wb-6rwhr-widwg-nb6lc-6b2ad-vae";
    const schemeId = `${issuerId}test_scheme`;
    const holderId = "aaaaa-aa";
    const timestamp = Date.now() * 1_000_000;
    const reward = 100;

    // Debug message construction
    const message_parts = [
        schemeId,
        issuerId,
        holderId,
        timestamp.toString(),
        reward.toString()
    ];
    console.log("Message parts:", message_parts);
    
    const message_credential = Buffer.from(message_parts.join(' '));
    console.log("Raw message bytes:", Array.from(message_credential));

    // Create credential message and hash it
    const messageHash_credential = crypto.createHash('sha256').update(message_credential).digest();

    // Sign the credential hash
    const signatureObj_credential = keyPair.sign(messageHash_credential, { canonical: true });
    const r_credential = signatureObj_credential.r.toArray('be', 32);
    const s_credential = signatureObj_credential.s.toArray('be', 32);
    const signature_credential = [...r_credential, ...s_credential];

    // Original test message
    const message = Buffer.from("Hello, Motoko!");
    const messageHash = crypto.createHash('sha256').update(message).digest();
    const signatureObj = keyPair.sign(messageHash, { canonical: true });
    const r = signatureObj.r.toArray('be', 32);
    const s = signatureObj.s.toArray('be', 32);
    const signature = [...r, ...s];

    // Format arrays for dfx commands
    const formatArray = (arr) => `vec {${arr.join('; ')}}`;

    // Create commands
    const deserializeCommand = `dfx canister call loyalty deserializePublicKey "(${formatArray(publicKey)})"`;
    const verifyCommand = `dfx canister call loyalty verifySignature "(${formatArray(publicKey)}, ${formatArray(Array.from(message))}, ${formatArray(signature)})"`;
    const verifyCredentialCommand = `dfx --identity store_upas canister call loyalty verifyCredential "(\\"${schemeId}\\", principal \\"${holderId}\\", ${timestamp}, ${formatArray(signature_credential)}, ${formatArray(publicKey)})"`;
    // addStore(principal: Principal, name: Text, description: Text, publicKeyNat: [Nat8])
    const addStoreCommand = `dfx --identity controller_upas canister call loyalty addStore '(principal "${issuerId}", "Store Name", "Store Description", ${formatArray(publicKey)})'`;
    // public query func getStore(owner: Principal) : async ?Store.Store
    const getStoreCommand = `dfx --identity controller_upas canister call loyalty getStore '(principal "${issuerId}")'`;
    // public shared({ caller }) func publishCredentialScheme(name: Text, description: Text, metadata: Text, reward: Nat) : async Text
    const publishCredentialSchemeCommand = `dfx --identity store_upas canister call loyalty publishCredentialScheme '("test_scheme", "Test Description", "Test Metadata", 100)'`;
    
    // public shared({ caller }) func mintAndTransferToStore(storePrincipal: Principal, amount: Nat) : async Result.Result<Nat, Text> 
    const mintAndTransferToStoreCommand = `dfx --identity controller_upas canister call ex mintAndTransferToStore '(principal "${issuerId}", 1000)'`;

    // public shared({ caller }) func issueCredential(schemeId: Text, holderId: Principal, signature: [Nat8], timestamp: Int)
    const issueCredentialCommand = `dfx --identity store_upas canister call loyalty issueCredential '("${schemeId}", principal "${holderId}", ${formatArray(signature_credential)}, ${timestamp})'`;
    
    // Check ICRC1 balance
    const checkHolderBalanceCommand = `dfx canister call icrc1_ledger_canister icrc1_balance_of '(record { owner = principal "${holderId}"; })'`;

    // Save commands to file
    const commands = `${deserializeCommand}\n${verifyCommand}\n${verifyCredentialCommand}\n${addStoreCommand}\n${getStoreCommand}\n${publishCredentialSchemeCommand}\n${mintAndTransferToStoreCommand}\n${issueCredentialCommand}\n${checkHolderBalanceCommand}`;
    fs.writeFileSync(path.join(__dirname, '../flow/temp_commands.sh'), commands);

    // Debug info
    console.log("\nDebug Info:");
    console.log("Original message:", message.toString());
    console.log("Credential message:", message_credential.toString());
    console.log("Credential hash:", messageHash_credential);
    console.log("Message hash:", messageHash);
    console.log("Signature length:", signature.length);
    console.log("Commands saved to flow/temp_commands.sh");
}

generateKeysAndSignMessage();