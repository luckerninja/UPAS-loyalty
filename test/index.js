const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const crypto = require('crypto');

function generateKeysAndSignMessage() {
    // Generate keys
    const keyPair = ec.genKeyPair();
    const publicKey = keyPair.getPublic('array', 'uncompressed');

    // Create message and hash it with SHA-256 first
    const message = Buffer.from("Hello, Motoko!");
    const messageHash = crypto.createHash('sha256').update(message).digest();
    
    // Sign the hash
    const signatureObj = keyPair.sign(messageHash, { canonical: true });
    const r = signatureObj.r.toArray('be', 32);
    const s = signatureObj.s.toArray('be', 32);
    const signature = [...r, ...s];

    // Format arrays for dfx commands
    const formatArray = (arr) => `(vec {${arr.join('; ')}})`;

    // Debug info
    console.log("\nDebug Info:");
    console.log("Original message:", message);
    console.log("Message hash:", messageHash);
    console.log("Signature length:", signature.length);

    // Verify locally first
    const isValidLocal = keyPair.verify(messageHash, { r: signatureObj.r, s: signatureObj.s });
    console.log("Valid locally:", isValidLocal);

    console.log("\nDFX Commands:");
    console.log("Deserialize Public Key:");
    console.log(`dfx canister call loyalty deserializePublicKey '(${formatArray(publicKey)})'`);
    
    console.log("Verify Signature:");
    console.log(`dfx canister call loyalty verifySignature '(${formatArray(publicKey)}, ${formatArray(Array.from(message))}, ${formatArray(signature)})'`);
}

generateKeysAndSignMessage();