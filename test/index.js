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
    const schemeId = "test_scheme";
    const issuerId = "d3bjt-52ql3-x6mpz-jfmmc-2qtrn-hbs37-mvaub-jzxjt-cibj4-luxho-iqe";
    const holderId = "aaaaa-aa";
    const timestamp = Date.now() * 1_000_000;
    const reward = 0;

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
    const verifyCredentialCommand = `dfx canister call loyalty verifyCredential "(\\"${schemeId}\\", principal \\"${holderId}\\", ${timestamp}, ${formatArray(signature_credential)}, ${formatArray(publicKey)})"`;

    // Save commands to file
    const commands = `${deserializeCommand}\n${verifyCommand}\n${verifyCredentialCommand}`;
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