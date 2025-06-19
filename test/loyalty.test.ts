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
      const receiptIds = [];
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