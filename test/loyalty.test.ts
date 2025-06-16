import { resolve } from 'path';
import { Actor, PocketIc, SubnetStateType } from '@dfinity/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE, idlFactory, init } from '../src/declarations/loyalty/loyalty.did.js';
import { _SERVICE as EX_SERVICE, idlFactory as exIdlFactory, init as exInit } from '../src/declarations/ex/ex.did.js';
import { _SERVICE as ICRC_SERVICE, idlFactory as icrcIdlFactory, init as icrcInit } from '../src/declarations/icrc1_ledger_canister/icrc1_ledger_canister.did.js';
import { ec as EC } from 'elliptic';
import crypto from 'crypto';
import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';

const LOYALTY_WASM_PATH = resolve(
  __dirname,
  '..',
  '.dfx',
  'local',
  'canisters',
  'loyalty',
  'loyalty.wasm.gz'
);

const EX_WASM_PATH = resolve(
  __dirname,
  '..',
  '.dfx',
  'local',
  'canisters',
  'ex',
  'ex.wasm.gz'
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

// Controller principal for testing
const CONTROLLER_PRINCIPAL = process.env.CONTROLLER_PRINCIPAL || '';

describe('Loyalty System', () => {
  let pic: PocketIc;
  let loyaltyActor: Actor<_SERVICE>;
  let icrcActor: Actor<ICRC_SERVICE>;
  let storePrincipal: string;
  let userPrincipal: string;

  beforeEach(async () => {
    pic = await PocketIc.create(process.env.PIC_URL!, {
      nns: { state: { type: SubnetStateType.New } },
      application: [
        { state: { type: SubnetStateType.New } },
        { state: { type: SubnetStateType.New } }
      ]
    });

    const applicationSubnets = await pic.getApplicationSubnets();
    const mainSubnet = applicationSubnets[0];
    const icrcSubnet = applicationSubnets[1];

    // Create canisters
    const exCanisterId = await pic.createCanister({
      targetSubnetId: mainSubnet.id
    });
    const loyaltyCanisterId = await pic.createCanister({
      targetSubnetId: mainSubnet.id
    });

    // Deploy ICRC1 ledger with proper initialization
    const icrcCanisterId = await pic.createCanister({
      targetSubnetId: icrcSubnet.id
    });
    await pic.installCode({
      wasm: ICRC_WASM_PATH,
      canisterId: icrcCanisterId,
      targetSubnetId: icrcSubnet.id,
      arg: IDL.encode(icrcInit({ IDL }), [{
        token_symbol: "3T",
        token_name: "3Tale",
        minting_account: { owner: exCanisterId },
        transfer_fee: 10_000n,
        metadata: [],
        initial_balances: [
          [{ owner: exCanisterId }, 10_000_000_000n],
          [{ owner: loyaltyCanisterId }, 10_000_000_000n]
        ],
        archive_options: {
          num_blocks_to_archive: 1000n,
          trigger_threshold: 2000n,
          controller_id: exCanisterId
        }
      }])
    });

    // Deploy EX canister
    await pic.installCode({
      wasm: EX_WASM_PATH,
      canisterId: exCanisterId,
      targetSubnetId: mainSubnet.id,
      arg: IDL.encode(exInit({ IDL }), [CONTROLLER_PRINCIPAL])
    });

    // Deploy Loyalty canister
    const loyaltyFixture = await pic.setupCanister<_SERVICE>({
      idlFactory,
      wasm: LOYALTY_WASM_PATH,
      targetSubnetId: mainSubnet.id,
      arg: IDL.encode(init({ IDL }), [exCanisterId])
    });
    loyaltyActor = loyaltyFixture.actor;

    // Set Loyalty canister ID in EX canister
    const exActor = pic.createActor<EX_SERVICE>(exIdlFactory, exCanisterId);
    await exActor.setLoyaltyActor(loyaltyCanisterId);

    // Set up test principals
    storePrincipal = process.env.STORE_PRINCIPAL || '';
    userPrincipal = process.env.USER_PRINCIPAL || '';
  });

  afterEach(async () => {
    await pic.tearDown();
  });

  describe('store operations', () => {
    it('should add store and verify credentials', async () => {
      // Generate keys
      const ec = new EC('secp256k1');
      const keyPair = ec.genKeyPair();
      const publicKey = keyPair.getPublic(false, 'array');

      // Add store
      await loyaltyActor.addStore(storePrincipal, "Store Name", "Store Description", publicKey);
      
      // Create and verify credential
      const schemeName = "test_scheme";
      const messageId = Buffer.from(storePrincipal + schemeName, 'utf8');
      const schemeId = crypto.createHash('sha256').update(messageId).digest().toString('hex');
      
      // Create credential message
      const timestamp = BigInt(Date.now() * 1_000_000);
      const reward = 100n;
      const messageParts = [schemeId, storePrincipal, userPrincipal, timestamp.toString(), reward.toString()];
      const messageCredential = Buffer.from(messageParts.join(' '));
      
      // Sign credential
      const messageHash = crypto.createHash('sha256').update(messageCredential).digest();
      const signatureObj = keyPair.sign(messageHash, { canonical: true });
      const signature = [...signatureObj.r.toArray('be', 32), ...signatureObj.s.toArray('be', 32)];

      // Verify credential
      const result = await loyaltyActor.verifyCredential(
        schemeId,
        userPrincipal,
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
      const receiptId = await loyaltyActor.storeReceipt(encryptedData, userPrincipal, amount);
      
      // Get receipt data
      const receiptData = await loyaltyActor.getEncryptedReceiptData(receiptId);
      
      expect(receiptData).toBe(encryptedData);
    });
  });
}); 