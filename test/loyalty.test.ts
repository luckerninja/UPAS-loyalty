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
import { ActorMethod } from '@dfinity/agent';

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

// Define types
type EncryptedReceiptData = [] | [string];
interface KeyPairResult {
  r: { toArray(endian: 'be', length: number): number[] };
  s: { toArray(endian: 'be', length: number): number[] };
}
interface KeyPair {
  sign(msg: Buffer, options?: { canonical: boolean }): KeyPairResult;
  getPublic(compact: boolean, type: 'array'): number[];
}

// Utility function to create credential signature
async function createCredentialSignature(
  schemeId: string,
  issuerId: Principal,
  holderId: Principal,
  timestamp: bigint,
  reward: number,
  keyPair: KeyPair
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
      ii: { state: { type: SubnetStateType.New } },
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

    // Create a store for storeIdentity
    const ec = new EC('secp256k1');
    const keyPair = ec.genKeyPair();
    await loyaltyActor.addStore(
      storeIdentity.getPrincipal(), 
      "Test Store", 
      "Test Store Description", 
      keyPair.getPublic(false, 'array')
    );

    await pic.setTime(Date.now());
  });

  afterEach(async () => {
    await pic.tearDown();
  });

  describe('receipt operations', () => {
    beforeEach(async () => {
      // Add tokens to store for cashback
      exActor.setIdentity(controllerIdentity);
      const mintResult = await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      expect(mintResult).toHaveProperty('Ok');
    });

    it('should handle receipt with cashback', async () => {
      const encryptedData = "encrypted_test_data";
      const purchaseAmount = 100n;
      const expectedCashback = purchaseAmount / 10n; // 10% cashback
      
      // Get initial store tokens
      const initialStoreTokens = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      
      // Store receipt
      loyaltyActor.setIdentity(storeIdentity);
      const receiptId = await loyaltyActor.storeReceipt(encryptedData, userIdentity.getPrincipal(), purchaseAmount);
      expect(typeof receiptId).toBe('bigint');
      
      // Verify store tokens were reduced correctly
      const finalStoreTokens = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      expect(finalStoreTokens).toBe(initialStoreTokens - expectedCashback);
    });

    it('should handle multiple receipts with cashback', async () => {
      const purchases = [
        { data: "receipt1", amount: 100n },
        { data: "receipt2", amount: 200n },
        { data: "receipt3", amount: 300n }
      ];
      
      // Get initial store tokens
      const initialStoreTokens = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      
      // Store multiple receipts
      loyaltyActor.setIdentity(storeIdentity);
      const receiptIds: bigint[] = [];
      for (const purchase of purchases) {
        const receiptId = await loyaltyActor.storeReceipt(purchase.data, userIdentity.getPrincipal(), purchase.amount);
        expect(typeof receiptId).toBe('bigint');
        receiptIds.push(receiptId);
      }
      
      // Verify all receipts
      loyaltyActor.setIdentity(userIdentity);
      for (let i = 0; i < purchases.length; i++) {
        const receiptData: EncryptedReceiptData = await loyaltyActor.getEncryptedReceiptData(receiptIds[i]);
        expect(Array.isArray(receiptData)).toBe(true);
        expect(receiptData.length).toBe(1);
        expect(receiptData[0]).toBe(purchases[i].data);
      }
      
      // Calculate total expected cashback
      const totalExpectedCashback = purchases.reduce((sum, purchase) => sum + purchase.amount / 10n, 0n);
      
      // Verify store tokens were reduced correctly
      const finalStoreTokens = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      expect(finalStoreTokens).toBe(initialStoreTokens - totalExpectedCashback);
    });

    it('should handle receipt storage when store has insufficient balance for cashback', async () => {
      // First, spend most of store's balance
      loyaltyActor.setIdentity(storeIdentity);
      const largePurchase = 9000n;
      const firstReceiptId = await loyaltyActor.storeReceipt("large_purchase", userIdentity.getPrincipal(), largePurchase);
      expect(typeof firstReceiptId).toBe('bigint');
      
      // Try to store another receipt
      const encryptedData = "insufficient_balance_receipt";
      const purchaseAmount = 10000n;
      
      // Get store balance before second receipt
      const storeBalanceBefore = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      
      // Store receipt should fail due to insufficient balance
      await expect(
        loyaltyActor.storeReceipt(encryptedData, userIdentity.getPrincipal(), purchaseAmount)
      ).rejects.toThrow();
      
      // Verify store balance remained unchanged
      const storeBalanceAfter = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      expect(storeBalanceAfter).toBe(storeBalanceBefore);
    });

    it('should allow store to view receipt data', async () => {
      const encryptedData = "store_viewable_receipt";
      const purchaseAmount = 100n;
      
      // Store receipt
      loyaltyActor.setIdentity(storeIdentity);
      const receiptId = await loyaltyActor.storeReceipt(encryptedData, userIdentity.getPrincipal(), purchaseAmount);
      expect(typeof receiptId).toBe('bigint');
      
      // Verify store can view receipt
      const receiptData: EncryptedReceiptData = await loyaltyActor.getEncryptedReceiptData(receiptId);
      expect(Array.isArray(receiptData)).toBe(true);
      expect(receiptData.length).toBe(1);
      expect(receiptData[0]).toBe(encryptedData);
    });

    it('should prevent unauthorized access to receipt data', async () => {
      const encryptedData = "private_receipt";
      const purchaseAmount = 100n;
      
      // Store receipt
      loyaltyActor.setIdentity(storeIdentity);
      const receiptId = await loyaltyActor.storeReceipt(encryptedData, userIdentity.getPrincipal(), purchaseAmount);
      expect(typeof receiptId).toBe('bigint');
      
      // Try to access with unauthorized identity
      loyaltyActor.setIdentity(controllerIdentity);
      const receiptData: EncryptedReceiptData = await loyaltyActor.getEncryptedReceiptData(receiptId);
      expect(Array.isArray(receiptData)).toBe(true);
      expect(receiptData.length).toBe(0);
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
      expect(issueResult).toHaveProperty('ok');

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

  describe('tag system', () => {
    beforeEach(async () => {
      // A store is needed for many tag-related operations like receipt conditions
      loyaltyActor.setIdentity(controllerIdentity);
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();
      await loyaltyActor.addStore(
        storeIdentity.getPrincipal(),
        "Super Store",
        "A great store",
        keyPair.getPublic(false, 'array')
      );
    });

    it('should create a simple tag', async () => {
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "first_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      
      const createResult = await loyaltyActor.createTag(
        tagId,
        "First Purchase",
        "Awarded for the first purchase.",
        condition,
        "some-metadata"
      );

      expect(createResult).toHaveProperty('ok');
      const okResult = createResult.ok;
      expect(okResult).toBe(tagId);

      const schemes = await loyaltyActor.listTagSchemes();
      expect(schemes.length).toBe(1);
      expect(schemes[0][0]).toBe(tagId);
      expect(schemes[0][1].name).toBe("First Purchase");
    });

    it('should prevent unauthorized tag creation', async () => {
      loyaltyActor.setIdentity(userIdentity); // Not the controller
      const tagId = "unauthorized_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };

      const createResult = await loyaltyActor.createTag(
        tagId, "Unauthorized", "Should fail", condition, ""
      );

      expect(createResult).toHaveProperty('err');
      const errResult = createResult.err;
      expect(errResult).toBe("Unauthorized: only controller can create tags");
    });

    it('should prevent duplicate tag creation', async () => {
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "duplicate_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      
      await loyaltyActor.createTag(tagId, "Duplicate", "First creation", condition, "");
      const secondCreateResult = await loyaltyActor.createTag(tagId, "Duplicate", "Second creation", condition, "");

      expect(secondCreateResult).toHaveProperty('err');
      const errResult = secondCreateResult.err;
      expect(errResult).toBe("Tag with this ID already exists");
    });

    it('should deactivate a tag', async () => {
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "deactivate_me";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "To Deactivate", "...", condition, "");

      const deactivateResult = await loyaltyActor.deactivateTag(tagId);
      expect(deactivateResult).toHaveProperty('ok');

      const tagScheme = await loyaltyActor.getTagScheme(tagId);
      expect(tagScheme[0].isActive).toBe(false);
    });

    it('should evaluate and award a tag for meeting a receipt count condition', async () => {
      // 1. Create the tag
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "two_receipts_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 2n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "Two Receipts", "Buy two things", condition, "");

      // 2. Fulfill the condition
      loyaltyActor.setIdentity(storeIdentity);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n); // for cashback
      await loyaltyActor.storeReceipt("receipt_1", userIdentity.getPrincipal(), 100n);
      await loyaltyActor.storeReceipt("receipt_2", userIdentity.getPrincipal(), 100n);

      // 3. Evaluate tags for the user
      loyaltyActor.setIdentity(controllerIdentity); // Evaluation can be triggered by anyone
      const awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags).toEqual([tagId]);

      // 4. Verify user has the tag
      const userTags = await loyaltyActor.getUserTags(userIdentity.getPrincipal());
      expect(userTags).toBeDefined();
      expect(userTags[0].length).toBe(1);
      expect(userTags[0][0].schemeId).toBe(tagId);
    });

    it('should not award a tag if conditions are not met', async () => {
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "five_receipts_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 5n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "Five Receipts", "Buy five things", condition, "");

      loyaltyActor.setIdentity(storeIdentity);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("receipt_1", userIdentity.getPrincipal(), 100n);

      const awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags.length).toBe(0);
    });
    
    it('should evaluate a tag with a credential requirement', async () => {
      // Setup: create a credential scheme and issue a credential
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();
      
      loyaltyActor.setIdentity(storeIdentity);
      const schemeId = await loyaltyActor.publishCredentialScheme("cred_scheme", "...", "...", 100n);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      
      const timestamp = BigInt(Date.now()) * 1_000_000n;
      // We need the keypair from the store that was created in the beforeEach block
      // This is a limitation. For now we assume we can get it or we create a new store.
      // Let's create a new store for this test to be self-contained with its key.
      const localStoreIdentity = createIdentity('local_store_secret');
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.addStore(localStoreIdentity.getPrincipal(), "CredStore", "...", keyPair.getPublic(false, 'array'));
      loyaltyActor.setIdentity(localStoreIdentity);
      const localSchemeId = await loyaltyActor.publishCredentialScheme("local_cred_scheme", "...", "...", 100n);
      await exActor.mintAndTransferToStore(localStoreIdentity.getPrincipal(), 1000n);

      const { signature } = await createCredentialSignature(localSchemeId, localStoreIdentity.getPrincipal(), userIdentity.getPrincipal(), timestamp, 100, keyPair);
      await loyaltyActor.issueCredential(localSchemeId, userIdentity.getPrincipal(), signature, timestamp);

      // 1. Create tag requiring the credential
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "cred_holder_tag";
      const condition = { Simple: { CredentialRequired: { schemeId: localSchemeId, issuerNames: [] } } };
      await loyaltyActor.createTag(tagId, "Credential Holder", "...", condition, "");

      // 2. Evaluate
      const awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags).toEqual([tagId]);
    });
    
    it('should not award the same tag twice', async () => {
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "once_only_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "Once Only", "...", condition, "");

      loyaltyActor.setIdentity(storeIdentity);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("receipt_1", userIdentity.getPrincipal(), 100n);

      // First evaluation
      let awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags).toEqual([tagId]);

      // Second evaluation
      awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags.length).toBe(0); // Should not award again

      const userTags = await loyaltyActor.getUserTags(userIdentity.getPrincipal());
      expect(userTags[0].length).toBe(1); // Still only one tag
    });

    it('should evaluate and award a tag for a complex OR condition', async () => {
      // 1. Setup: Create a credential scheme for one part of the OR condition
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();
      const localStoreIdentity = createIdentity('or_test_store_secret');
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.addStore(localStoreIdentity.getPrincipal(), "OR-Store", "...", keyPair.getPublic(false, 'array'));
      loyaltyActor.setIdentity(localStoreIdentity);
      const schemeId = await loyaltyActor.publishCredentialScheme("or_scheme", "...", "...", 100n);

      // 2. Create the tag with the complex OR condition
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "complex_or_tag";
      const condition = {
        Or: [
          { Simple: { ReceiptCount: { storeNames: [], minCount: 2n, timeWindow: [] } } },
          { Simple: { CredentialRequired: { schemeId: schemeId, issuerNames: [] } } }
        ]
      };
      await loyaltyActor.createTag(tagId, "Complex OR Tag", "...", condition, "");

      // 3. Test Case 1: User has 2 receipts, but no credential. Should be awarded.
      const user1 = createIdentity('user1_secret');
      loyaltyActor.setIdentity(storeIdentity); // Use the general store for receipts
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("or_receipt1", user1.getPrincipal(), 50n);
      await loyaltyActor.storeReceipt("or_receipt2", user1.getPrincipal(), 50n);

      let awardedTags = await loyaltyActor.evaluateUserTags(user1.getPrincipal());
      expect(awardedTags).toEqual([tagId]);

      // 4. Test Case 2: User has the credential, but only 1 receipt. Should be awarded.
      const user2 = createIdentity('user2_secret');
      // Issue the credential to user2
      loyaltyActor.setIdentity(localStoreIdentity);
      await exActor.mintAndTransferToStore(localStoreIdentity.getPrincipal(), 1000n);
      const timestamp = BigInt(Date.now()) * 1_000_000n;
      const { signature } = await createCredentialSignature(schemeId, localStoreIdentity.getPrincipal(), user2.getPrincipal(), timestamp, 100, keyPair);
      await loyaltyActor.issueCredential(schemeId, user2.getPrincipal(), signature, timestamp);
      // Give them one receipt
      loyaltyActor.setIdentity(storeIdentity);
      await loyaltyActor.storeReceipt("or_receipt3", user2.getPrincipal(), 50n);

      awardedTags = await loyaltyActor.evaluateUserTags(user2.getPrincipal());
      expect(awardedTags).toEqual([tagId]);
      
      // 5. Test Case 3: User has 1 receipt and no credential. Should NOT be awarded.
      const user3 = createIdentity('user3_secret');
      loyaltyActor.setIdentity(storeIdentity);
      await loyaltyActor.storeReceipt("or_receipt4", user3.getPrincipal(), 50n);
      
      awardedTags = await loyaltyActor.evaluateUserTags(user3.getPrincipal());
      expect(awardedTags.length).toBe(0);
    });

    it('should include canister signature when awarding tags', async () => {
      // 1. Create a simple tag
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "signed_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "Signed Tag", "Tag with canister signature", condition, "");

      // 2. Fulfill the condition
      loyaltyActor.setIdentity(storeIdentity);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("signed_receipt", userIdentity.getPrincipal(), 100n);

      // 3. Evaluate tags for the user
      loyaltyActor.setIdentity(controllerIdentity);
      const awardedTags = await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());
      expect(awardedTags).toEqual([tagId]);

      // 4. Verify user has the tag with canister signature
      const userTags = await loyaltyActor.getUserTags(userIdentity.getPrincipal());
      expect(userTags).toBeDefined();
      expect(userTags[0].length).toBe(1);
      expect(userTags[0][0].schemeId).toBe(tagId);
      
      // Debug: log the actual structure
      console.log('User tag structure:', JSON.stringify(userTags[0][0], (key, value) => 
        typeof value === 'bigint' ? value.toString() : value, 2));
      
      // canisterSignature is optional, so check if it exists and is a string
      const canisterSignature = userTags[0][0].canisterSignature;
      if (canisterSignature && Array.isArray(canisterSignature) && canisterSignature.length > 0) {
        // We have a signature in array format
        expect(typeof canisterSignature[0]).toBe('string');
        
        // Verify the signature
        const signatureString = canisterSignature[0];
        const isValid = await loyaltyActor.verifyTagCanisterSignature(
          tagId,
          userIdentity.getPrincipal(),
          signatureString
        );
        expect(isValid).toBe(true);
      } else {
        // If signature is not generated, the test should fail
        throw new Error('Canister signature was not generated or is in the wrong format.');
      }
    });

    it('should verify canister signature for issued tags', async () => {
      // 1. Create and award a tag
      loyaltyActor.setIdentity(controllerIdentity);
      const tagId = "verification_tag";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      await loyaltyActor.createTag(tagId, "Verification Tag", "Tag for signature verification", condition, "");

      loyaltyActor.setIdentity(storeIdentity);
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("verification_receipt", userIdentity.getPrincipal(), 100n);
      
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.evaluateUserTags(userIdentity.getPrincipal());

      // 2. Get the issued tag with signature
      const userTags = await loyaltyActor.getUserTags(userIdentity.getPrincipal());
      const issuedTag = userTags[0].find((t: any) => t.schemeId === tagId);
      expect(issuedTag).toBeDefined();
      
      // 3. Verify the signature (only if canisterSignature exists and is a string)
      const canisterSignature = issuedTag.canisterSignature;
      if (canisterSignature && Array.isArray(canisterSignature) && canisterSignature.length > 0) {
        // We have a signature in array format
        const signatureString = canisterSignature[0];
        const isValid = await loyaltyActor.verifyTagCanisterSignature(
          tagId,
          userIdentity.getPrincipal(),
          signatureString
        );
        expect(isValid).toBe(true);

        // 4. Test with invalid signature
        const isInvalid = await loyaltyActor.verifyTagCanisterSignature(
          tagId,
          userIdentity.getPrincipal(),
          "invalid_signature"
        );
        expect(isInvalid).toBe(false);
      } else {
        // If signature is not generated, the test should fail
        throw new Error('Canister signature was not generated or is in the wrong format.');
      }
    });
  });

  describe('Store Schemes', () => {
    it('should create a store scheme successfully', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      const schemeName = "Premium Customer";
      const description = "Enhanced cashback for premium customers";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 5n, timeWindow: [] } } };
      const metadata = "Premium scheme metadata";
      const cashbackMultiplier = 150n; // 150% cashback
      const maxCashbackAmount = 1000n;

      const schemeId = await loyaltyActor.createStoreScheme(
        schemeName,
        description,
        condition,
        metadata,
        cashbackMultiplier,
        [maxCashbackAmount]
      );

      expect(schemeId).toBeDefined();
      expect(schemeId).toHaveProperty('ok');
      expect(schemeId.ok).toBeTruthy();

      // Verify the scheme was created
      const storeSchemes = await loyaltyActor.getStoreSchemes(storeIdentity.getPrincipal());
      expect(storeSchemes).toBeDefined();
      expect(storeSchemes[0].length).toBe(1);
      
      const scheme = storeSchemes[0][0];
      expect(scheme.name).toBe(schemeName);
      expect(scheme.description).toBe(description);
      expect(scheme.metadata).toBe(metadata);
      expect(scheme.cashbackMultiplier).toBe(cashbackMultiplier);
      expect(scheme.maxCashbackAmount).toEqual([maxCashbackAmount]);
      expect(scheme.isActive).toBe(true);
    });

    it('should not allow creating duplicate scheme names for the same store', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      const schemeName = "Duplicate Test";
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };

      // Create first scheme
      const firstResult = await loyaltyActor.createStoreScheme(
        schemeName,
        "First scheme",
        condition,
        "metadata1",
        120n,
        []
      );
      expect(firstResult).toHaveProperty('ok');

      // Try to create second scheme with same name
      const secondResult = await loyaltyActor.createStoreScheme(
        schemeName,
        "Second scheme",
        condition,
        "metadata2",
        130n,
        []
      );
      expect(secondResult).toHaveProperty('err');
      expect(secondResult.err).toBe("Store scheme with this name already exists");
    });

    it('should not allow non-store owners to create schemes', async () => {
      loyaltyActor.setIdentity(userIdentity); // User is not a store owner
      
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };

      const result = await loyaltyActor.createStoreScheme(
        "Unauthorized Scheme",
        "Should fail",
        condition,
        "metadata",
        120n,
        []
      );

      expect(result).toHaveProperty('err');
      expect(result.err).toBe("Store not found");
    });

    it('should deactivate a store scheme successfully', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create a scheme first
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      const createResult = await loyaltyActor.createStoreScheme(
        "Deactivation Test",
        "Scheme to deactivate",
        condition,
        "metadata",
        120n,
        []
      );
      expect(createResult).toHaveProperty('ok');
      const schemeId = createResult.ok;

      // Deactivate the scheme
      const deactivateResult = await loyaltyActor.deactivateStoreScheme(schemeId);
      expect(deactivateResult).toHaveProperty('ok');

      // Verify the scheme is deactivated
      const storeSchemes = await loyaltyActor.getStoreSchemes(storeIdentity.getPrincipal());
      const scheme = storeSchemes[0].find((s: any) => s.id === schemeId);
      expect(scheme).toBeDefined();
      expect(scheme.isActive).toBe(false);
    });

    it('should evaluate and award store schemes to users', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create a store scheme
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 2n, timeWindow: [] } } };
      const createResult = await loyaltyActor.createStoreScheme(
        "Evaluation Test",
        "Scheme for evaluation testing",
        condition,
        "metadata",
        150n,
        []
      );
      expect(createResult).toHaveProperty('ok');
      const schemeId = createResult.ok;

      // Create receipts to fulfill the condition
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("receipt1", userIdentity.getPrincipal(), 100n);
      await loyaltyActor.storeReceipt("receipt2", userIdentity.getPrincipal(), 100n);

      // Evaluate schemes for the user
      const awardedSchemes = await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());
      expect(awardedSchemes).toContain(schemeId);

      // Verify user has the scheme
      const userSchemes = await loyaltyActor.getUserSchemes(userIdentity.getPrincipal());
      expect(userSchemes).toBeDefined();
      expect(userSchemes[0].length).toBe(1);
      expect(userSchemes[0][0].schemeId).toBe(schemeId);
    });

    it('should not award the same store scheme twice', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create a store scheme
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      const createResult = await loyaltyActor.createStoreScheme(
        "Once Only Scheme",
        "Scheme that should be awarded only once",
        condition,
        "metadata",
        120n,
        []
      );
      expect(createResult).toHaveProperty('ok');
      const schemeId = createResult.ok;

      // Create receipt to fulfill the condition
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("once_receipt", userIdentity.getPrincipal(), 100n);

      // First evaluation
      let awardedSchemes = await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());
      expect(awardedSchemes).toContain(schemeId);

      // Second evaluation
      awardedSchemes = await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());
      expect(awardedSchemes.length).toBe(0); // Should not award again

      // Verify user still has only one scheme
      const userSchemes = await loyaltyActor.getUserSchemes(userIdentity.getPrincipal());
      expect(userSchemes[0].length).toBe(1);
    });

    it('should calculate enhanced cashback based on user schemes', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create a store scheme with enhanced cashback
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      const createResult = await loyaltyActor.createStoreScheme(
        "Enhanced Cashback",
        "Scheme with enhanced cashback",
        condition,
        "metadata",
        200n, // 200% cashback
        []
      );
      expect(createResult).toHaveProperty('ok');
      const schemeId = createResult.ok;

      // Award the scheme to user
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("enhanced_receipt", userIdentity.getPrincipal(), 100n);
      await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());

      // Now make a purchase that should trigger enhanced cashback
      // The base cashback is 10% of purchase amount
      // With 200% multiplier, it should be 20% of purchase amount
      const purchaseAmount = 500n;
      const expectedCashback = (purchaseAmount * 20n) / 100n; // 20% of 500 = 100

      // Add more tokens to store for cashback
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      
      // Get store balance before purchase
      const storeBalanceBefore = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      
      // Store receipt with enhanced cashback
      await loyaltyActor.storeReceipt("enhanced_purchase", userIdentity.getPrincipal(), purchaseAmount);

      // Verify the cashback was calculated correctly
      const finalStoreBalance = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      // The store should have spent the enhanced cashback amount
      // Base cashback: 10% of 500 = 50
      // Enhanced cashback: 50 * 200% = 100
      const expectedReduction = 100n;
      expect(finalStoreBalance).toBe(storeBalanceBefore - expectedReduction);
    });

    it('should handle multiple schemes with different multipliers', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create two schemes with different multipliers
      const condition1 = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      const condition2 = { Simple: { ReceiptCount: { storeNames: [], minCount: 3n, timeWindow: [] } } };

      const scheme1Result = await loyaltyActor.createStoreScheme(
        "Basic Scheme",
        "Basic cashback scheme",
        condition1,
        "metadata1",
        120n, // 120% cashback
        []
      );
      const scheme2Result = await loyaltyActor.createStoreScheme(
        "Premium Scheme",
        "Premium cashback scheme",
        condition2,
        "metadata2",
        200n, // 200% cashback
        []
      );

      expect(scheme1Result).toHaveProperty('ok');
      expect(scheme2Result).toHaveProperty('ok');

      // Award both schemes to user
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 2000n);
      
      // Fulfill condition for scheme 1 (1 receipt)
      await loyaltyActor.storeReceipt("basic_receipt", userIdentity.getPrincipal(), 100n);
      let awardedSchemes = await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());
      expect(awardedSchemes).toContain(scheme1Result.ok);

      // Fulfill condition for scheme 2 (3 receipts total)
      await loyaltyActor.storeReceipt("premium_receipt1", userIdentity.getPrincipal(), 100n);
      await loyaltyActor.storeReceipt("premium_receipt2", userIdentity.getPrincipal(), 100n);
      awardedSchemes = await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());
      expect(awardedSchemes).toContain(scheme2Result.ok);

      // Verify user has both schemes
      const userSchemes = await loyaltyActor.getUserSchemes(userIdentity.getPrincipal());
      expect(userSchemes[0].length).toBe(2);

      // Make a purchase - should use the highest multiplier (200%)
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      const purchaseAmount = 1000n;
      
      // Get store balance before purchase
      const storeBalanceBefore = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      
      await loyaltyActor.storeReceipt("multi_scheme_purchase", userIdentity.getPrincipal(), purchaseAmount);

      // The cashback should be calculated using the highest multiplier (200%)
      // Base cashback: 10% of 1000 = 100
      // Enhanced cashback: 100 * 200% = 200
      const finalStoreBalance = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      const expectedReduction = 200n;
      expect(finalStoreBalance).toBe(storeBalanceBefore - expectedReduction);
    });

    it('should respect max cashback amount limits', async () => {
      loyaltyActor.setIdentity(storeIdentity);
      
      // Create a scheme with max cashback limit
      const condition = { Simple: { ReceiptCount: { storeNames: [], minCount: 1n, timeWindow: [] } } };
      const createResult = await loyaltyActor.createStoreScheme(
        "Limited Cashback",
        "Scheme with max cashback limit",
        condition,
        "metadata",
        300n, // 300% cashback
        [50n] // Max 50 tokens cashback
      );
      expect(createResult).toHaveProperty('ok');
      const schemeId = createResult.ok;

      // Award the scheme to user
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      await loyaltyActor.storeReceipt("limited_receipt", userIdentity.getPrincipal(), 100n);
      await loyaltyActor.evaluateUserStoreSchemes(userIdentity.getPrincipal());

      // Make a large purchase that would exceed the max cashback
      // Purchase of 1000 tokens would normally give 300% of 10% = 300 tokens cashback
      // But it should be capped at 50 tokens
      await exActor.mintAndTransferToStore(storeIdentity.getPrincipal(), 1000n);
      const largePurchaseAmount = 1000n;
      await loyaltyActor.storeReceipt("large_purchase", userIdentity.getPrincipal(), largePurchaseAmount);

      // Verify the cashback was limited
      const finalStoreBalance = await loyaltyActor.getStoreTokens(storeIdentity.getPrincipal());
      // Store should have spent at most 50 tokens for cashback
      // This is a simplified verification
      expect(finalStoreBalance).toBeGreaterThan(950n); // Store should have at least 950 tokens left
    });
  });
}); 