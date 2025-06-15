const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Read environment variables from .env file
require('dotenv').config();

function generateKeysAndSignMessage() {
    // Generate keys
    const keyPair = ec.genKeyPair();
    const publicKey = keyPair.getPublic('array', 'uncompressed');

    // Create test data for credential
    const issuerId = process.env.STORE_PRINCIPAL || '';
    const schemeName = "test_scheme";
    
    // Generate schemeId the same way as in Motoko:
    // 1. Create message bytes
    const messageId = Buffer.from(issuerId + schemeName, 'utf8');
    // 2. Get SHA-256 hash
    const sha256Hash = crypto.createHash('sha256').update(messageId).digest();
    // 3. Convert to hex string (like Base16.encode in Motoko)
    const schemeId = sha256Hash.toString('hex');
    
    const holderId = process.env.USER_PRINCIPAL || '';
    const timestamp = Date.now() * 1_000_000;
    const reward = parseInt(process.env.REWARD) || 100;

    // Debug message construction
    const message_parts = [
        schemeId,
        issuerId,
        holderId,
        timestamp.toString(),
        reward.toString()
    ];
    console.log("Message parts:", message_parts);
    console.log("Generated schemeId:", schemeId);
    
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

    // Test encrypted receipts functionality
    // public shared({ caller }) func storeReceipt(encryptedData: Text, holderId: Principal, amount: Nat) : async Receipt.ReceiptId
    const storeReceiptCommand = `dfx --identity store_upas canister call loyalty storeReceipt '("encrypted_test_data", principal "${holderId}", 100)'`;
    
    // public shared({ caller }) func getEncryptedReceiptData(receiptId: Receipt.ReceiptId) : async ?Text
    const getEncryptedReceiptDataCommand = `dfx --identity user_upas canister call loyalty getEncryptedReceiptData '(1)'`;

    // Save commands to file
    const commands = `# test command for deserializePublicKey
${deserializeCommand}
# test command for verifySignature
${verifyCommand}
# test command for verifyCredential
${verifyCredentialCommand}
# Contoller adding store
${addStoreCommand}
# Getting store
${getStoreCommand}
# Store publishing credential scheme
${publishCredentialSchemeCommand}
# Controller minting and transferring points to store
${mintAndTransferToStoreCommand}
# Store issuing credential
${issueCredentialCommand}
# Checking ICRC1 balance
${checkHolderBalanceCommand}
# Store creating encrypted receipt
${storeReceiptCommand}
# User getting encrypted receipt data
${getEncryptedReceiptDataCommand}`;
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