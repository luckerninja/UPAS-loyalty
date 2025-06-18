import { resolve } from 'path';
import { Actor, PocketIc, SubnetStateType, createIdentity } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE, idlFactory, init } from '../src/declarations/loyalty/loyalty.did.js';
import { _SERVICE as EX_SERVICE, idlFactory as exIdlFactory, init as exInit } from '../src/declarations/ex/ex.did.js';
import { _SERVICE as ICRC_SERVICE, idlFactory as icrcIdlFactory, init as icrcInit } from '../src/declarations/icrc1_ledger_canister/icrc1_ledger_canister.did.js';
import { ec as EC } from 'elliptic';
import crypto from 'crypto';
import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import dotenv from 'dotenv';
import { Principal } from '@dfinity/principal';

// Load environment variables from .env file
dotenv.config({ path: resolve(__dirname, '.env') });

const LOYALTY_WASM_PATH = resolve(
  __dirname,
  '..',
  '.dfx',
  'local',
  'canisters',
  'loyalty',
  'loyalty.wasm'
);

const EX_WASM_PATH = resolve(
  __dirname,
  '..',
  '.dfx',
  'local',
  'canisters',
  'ex',
  'ex.wasm'
);

const ICRC_WASM_PATH = resolve(
  __dirname,
  '..',
  '.dfx',
  'local',
  'canisters',
  'icrc1_ledger_canister',
  'icrc1_ledger_canister.wasm.gz'
);

// PocketIC URL
const PIC_URL = process.env.PIC_URL;
if (!PIC_URL) {
  throw new Error('PIC_URL is not defined in .env file');
}

// Utility function to create credential signature
async function createCredentialSignature(
  schemeId: string,
  issuerId: Principal,
  holderId: Principal,
  timestamp: bigint,
  reward: number,
  keyPair: any
): Promise<{
  signature: number[],
  publicKey: number[],
  messageHash: Buffer
}> {
  // Create message parts
  const messageParts = [
    schemeId,
    issuerId.toString(),
    holderId.toString(),
    timestamp.toString(),
    BigInt(reward).toString()
  ];

  // Create message and hash it
  const messageCredential = new TextEncoder().encode(messageParts.join(' '));
  console.log('Message parts:', messageParts);
  console.log('Message:', Array.from(messageCredential));
  const messageHashCredential = crypto.createHash('sha256').update(messageCredential).digest();
  console.log('Message hash:', messageHashCredential.toString('hex'));

  // Sign the credential hash
  const signatureObjCredential = keyPair.sign(messageHashCredential, { canonical: true });
  const rCredential = signatureObjCredential.r.toArray('be', 32);
  const sCredential = signatureObjCredential.s.toArray('be', 32);
  const signatureCredential = [...rCredential, ...sCredential];
  console.log('Signature:', Buffer.from(signatureCredential).toString('hex'));

  // Get public key
  const publicKey = keyPair.getPublic(false, 'array');

  return {
    signature: signatureCredential,
    publicKey,
    messageHash: messageHashCredential
  };
}

describe('Loyalty System', () => {
  let pic: PocketIc;
  let loyaltyActor: Actor<_SERVICE>;
  let icrcActor: Actor<ICRC_SERVICE>;
  let storeIdentity: ReturnType<typeof createIdentity>;
  let userIdentity: ReturnType<typeof createIdentity>;
  let controllerIdentity: ReturnType<typeof createIdentity>;
  let exActor: Actor<EX_SERVICE>;

  beforeEach(async () => {
    pic = await PocketIc.create(PIC_URL, {
      nns: { state: { type: SubnetStateType.New } },
      application: [
        { state: { type: SubnetStateType.New } },
      ]
    });

    // Create identities
    storeIdentity = createIdentity('store_secret');
    userIdentity = createIdentity('user_secret');
    controllerIdentity = createIdentity('controller_secret');

    const applicationSubnets = await pic.getApplicationSubnets();
    const mainSubnet = applicationSubnets[0];

    const exCanisterId = await pic.createCanister({
      targetSubnetId: mainSubnet.id
    });
    const loyaltyCanisterId = await pic.createCanister({
      targetSubnetId: mainSubnet.id,
      sender: controllerIdentity.getPrincipal()
    });
    const icrcCanisterId = await pic.createCanister({
      targetSubnetId: mainSubnet.id
    });

    // Then install code in each canister
    const arg = IDL.encode(
      [IDL.Variant({
        Init: IDL.Record({
          token_symbol: IDL.Text,
          token_name: IDL.Text,
          minting_account: IDL.Record({ owner: IDL.Principal }),
          transfer_fee: IDL.Nat,
          metadata: IDL.Vec(IDL.Record({})),
          initial_balances: IDL.Vec(
            IDL.Tuple(
              IDL.Record({ owner: IDL.Principal }),
              IDL.Nat
            )
          ),
          archive_options: IDL.Record({
            num_blocks_to_archive: IDL.Nat64,
            trigger_threshold: IDL.Nat64,
            controller_id: IDL.Principal,
          }),
        }),
      })],
      [
        {
          Init: {
            token_symbol: "3T",
            token_name: "3Tale",
            minting_account: { owner: exCanisterId },
            transfer_fee: 10_000n,
            metadata: [],
            initial_balances: [
              [{ owner: exCanisterId }, 10_000_000_000n],
              [{ owner: loyaltyCanisterId }, 10_000_000_000n],
            ],
            archive_options: {
              num_blocks_to_archive: 1000n,
              trigger_threshold: 2000n,
              controller_id: exCanisterId,
            },
          },
        },
      ]
    );

    // Debug logs for canister IDs
    // console.log('ICRC Canister ID:', icrcCanisterId.toString());
    // console.log('EX Canister ID:', exCanisterId.toString());
    // console.log('Loyalty Canister ID:', loyaltyCanisterId.toString());

    await pic.installCode({
      wasm: ICRC_WASM_PATH,
      canisterId: icrcCanisterId,
      targetSubnetId: mainSubnet.id,
      arg: arg,
    });

    // Create ICRC1 actor
    icrcActor = pic.createActor<ICRC_SERVICE>(icrcIdlFactory, icrcCanisterId);
    icrcActor.setIdentity(controllerIdentity);

    // Deploy EX canister
    const exArg = IDL.encode(
      [IDL.Principal],
      [controllerIdentity.getPrincipal()]
    );
    await pic.installCode({
      wasm: EX_WASM_PATH,
      canisterId: exCanisterId,
      targetSubnetId: mainSubnet.id,
      arg: exArg,
    });

    // Deploy Loyalty canister
    const loyaltyArg = IDL.encode(
      [IDL.Principal],
      [exCanisterId]
    );
    await pic.installCode({
      wasm: LOYALTY_WASM_PATH,
      canisterId: loyaltyCanisterId,
      targetSubnetId: mainSubnet.id,
      arg: loyaltyArg,
      sender: controllerIdentity.getPrincipal()
    });

    // Create loyalty actor
    loyaltyActor = pic.createActor<_SERVICE>(idlFactory, loyaltyCanisterId);
    loyaltyActor.setIdentity(controllerIdentity);

    // Set ICRC1 actor in Loyalty canister
    loyaltyActor.setIdentity(controllerIdentity);
    await loyaltyActor.setICRC1Actor(icrcCanisterId);

    // Set Loyalty canister ID in EX canister
    exActor = pic.createActor<EX_SERVICE>(exIdlFactory, exCanisterId);
    await exActor.setController(controllerIdentity.getPrincipal());
    exActor.setIdentity(controllerIdentity);
    await exActor.setLoyaltyActor(loyaltyCanisterId);
    await exActor.setICRC1Actor(icrcCanisterId);
    
    // Verify Loyalty actor setup
    const loyaltyActorId = await exActor.getLoyaltyActor();
    // console.log('Loyalty actor ID from EX canister:', loyaltyActorId);

    // Debug log for ICRC1 actor setup
    // console.log('ICRC1 actor set in EX canister:', icrcCanisterId.toString());

    await pic.setTime(Date.now()); 
  });

  afterEach(async () => {
    await pic.tearDown();
  });

  describe('store operations', () => {
    it('should add store and verify credentials', async () => {
      // Generate keys
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();

      // Add store
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.addStore(storeIdentity.getPrincipal(), "Store Name", "Store Description", keyPair.getPublic(false, 'array'));
      
      // Create and verify credential
      const schemeName = "test_scheme";
      
      // Generate schemeId the same way as in Motoko:
      // 1. Create message bytes
      const messageId = Buffer.from(storeIdentity.getPrincipal().toString() + schemeName, 'utf8');
      // 2. Get SHA-256 hash
      const sha256Hash = crypto.createHash('sha256').update(messageId).digest();
      // 3. Convert to hex string (like Base16.encode in Motoko)
      const schemeId = sha256Hash.toString('hex');
      
      const timestamp = BigInt(Date.now()) * 1_000_000n;
      const reward = 100;

      // Create credential signature
      const { signature, publicKey, messageHash } = await createCredentialSignature(
        schemeId,
        storeIdentity.getPrincipal(),
        userIdentity.getPrincipal(),
        timestamp,
        reward,
        keyPair
      );

      // Set store identity for verification
      loyaltyActor.setIdentity(storeIdentity);

      // Verify credential
      const result = await loyaltyActor.verifyCredential(
        schemeId,
        userIdentity.getPrincipal(),
        timestamp,
        signature,
        publicKey
      );
      
      expect(result).toBe(true);
    });
  });

  describe('receipt operations', () => {
    it('should handle encrypted receipts', async () => {
      const encryptedData = "encrypted_test_data";
      const amount = 100n;
      
      // Store receipt
      loyaltyActor.setIdentity(storeIdentity);
      const receiptId = await loyaltyActor.storeReceipt(encryptedData, userIdentity.getPrincipal(), amount);
      
      // Get receipt data
      loyaltyActor.setIdentity(userIdentity);
      const receiptData = await loyaltyActor.getEncryptedReceiptData(receiptId);
      
      expect(receiptData).toBe(encryptedData);
    });
  });

  describe('credential operations', () => {
    it('should verify credential signature', async () => {
      // ... existing test code ...
    });

    it('should complete full credential lifecycle', async () => {
      // Generate keys for store
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();

      // Add store
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.addStore(storeIdentity.getPrincipal(), "Store Name", "Store Description", keyPair.getPublic(false, 'array'));

      // Create credential scheme
      loyaltyActor.setIdentity(storeIdentity);
      const schemeName = "test_scheme";
      const schemeId = await loyaltyActor.publishCredentialScheme(
        schemeName,
        "Test Description",
        "Test Metadata",
        100n
      );

      // Add tokens to store through ex canister
      exActor.setIdentity(controllerIdentity);
      const mintResult = await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      expect(mintResult).toHaveProperty('Ok');
      expect(mintResult.Ok).toBe(2n);

      // Create credential signature
      const timestamp = BigInt(Date.now()) * 1_000_000n;
      const reward = 100;
      const { signature, publicKey } = await createCredentialSignature(
        schemeId,
        storeIdentity.getPrincipal(),
        userIdentity.getPrincipal(),
        timestamp,
        reward,
        keyPair
      );

      // Issue credential
      loyaltyActor.setIdentity(storeIdentity);
      const issueResult = await loyaltyActor.issueCredential(
        schemeId,
        userIdentity.getPrincipal(),
        signature,
        timestamp
      );

      // Check that credential was issued successfully
      expect(issueResult.ok).toBe(3n);

      // Get user credentials
      loyaltyActor.setIdentity(userIdentity);
      const userCredentials = await loyaltyActor.getUserCredentials(userIdentity.getPrincipal());
      // console.log('User credentials:', userCredentials);
      
      // Verify user has the credential
      expect(userCredentials.length).toBe(1);
      expect(userCredentials[0].length).toBe(1);
      expect(userCredentials[0][0].reward).toBe(100n);
      expect(userCredentials[0][0].schemeId).toBe(schemeId);

      // Get store history
      loyaltyActor.setIdentity(storeIdentity);
      const storeHistory = await loyaltyActor.getStoreHistory(storeIdentity.getPrincipal());
      // console.log('Store history:', storeHistory);
      
      // Verify store history
      expect(storeHistory.length).toBe(1);
      expect(storeHistory[0].length).toBe(1);
      expect(storeHistory[0][0].reward).toBe(100n);
      expect(storeHistory[0][0].schemeId).toBe(schemeId);
    });
  });
}); 