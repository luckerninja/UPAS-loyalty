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

describe('Loyalty System', () => {
  let pic: PocketIc;
  let loyaltyActor: Actor<_SERVICE>;
  let icrcActor: Actor<ICRC_SERVICE>;
  let storeIdentity: ReturnType<typeof createIdentity>;
  let userIdentity: ReturnType<typeof createIdentity>;
  let controllerIdentity: ReturnType<typeof createIdentity>;

  beforeEach(async () => {
    pic = await PocketIc.create(PIC_URL, {
      nns: { state: { type: SubnetStateType.New } },
      application: [
        { state: { type: SubnetStateType.New } },
        { state: { type: SubnetStateType.New } }
      ]
    });

    // Create identities
    storeIdentity = createIdentity('store_secret');
    userIdentity = createIdentity('user_secret');
    controllerIdentity = createIdentity('controller_secret');

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
    
    await pic.installCode({
      wasm: ICRC_WASM_PATH,
      canisterId: icrcCanisterId,
      targetSubnetId: icrcSubnet.id,
      arg: arg,
    });

    // Deploy EX canister
    const exArg = IDL.encode(
      [IDL.Principal],
      [controllerIdentity.getPrincipal()]
    );
    await pic.installCode({
      wasm: EX_WASM_PATH,
      canisterId: exCanisterId,
      targetSubnetId: mainSubnet.id,
      arg: exArg
    });

    // Deploy Loyalty canister
    const loyaltyArg = IDL.encode(
      [IDL.Principal],
      [exCanisterId]
    );
    const loyaltyFixture = await pic.setupCanister<_SERVICE>({
      idlFactory,
      wasm: LOYALTY_WASM_PATH,
      targetSubnetId: mainSubnet.id,
      arg: loyaltyArg,
      sender: controllerIdentity.getPrincipal()
    });
    loyaltyActor = loyaltyFixture.actor;

    // Set controller identity for loyalty actor
    loyaltyActor.setIdentity(controllerIdentity);

    // Set Loyalty canister ID in EX canister
    const exActor = pic.createActor<EX_SERVICE>(exIdlFactory, exCanisterId);
    await exActor.setLoyaltyActor(loyaltyCanisterId.toString());
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
      loyaltyActor.setIdentity(controllerIdentity);
      await loyaltyActor.addStore(storeIdentity.getPrincipal(), "Store Name", "Store Description", publicKey);
      
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

      // Debug message construction
      const messageParts = [
        schemeId,
        storeIdentity.getPrincipal().toString(),
        userIdentity.getPrincipal().toString(),
        timestamp.toString(),
        reward.toString()
      ];
      console.log("Message parts:", messageParts);
      
      const messageCredential = Buffer.from(messageParts.join(' '));
      console.log("Message credential:", messageCredential.toString());
      console.log("Message credential bytes:", Array.from(messageCredential));

      // Create credential message and hash it
      const messageHashCredential = crypto.createHash('sha256').update(messageCredential).digest();
      console.log("Message hash:", messageHashCredential.toString('hex'));

      // Sign the credential hash
      const signatureObjCredential = keyPair.sign(messageHashCredential, { canonical: true });
      const rCredential = signatureObjCredential.r.toArray('be', 32);
      const sCredential = signatureObjCredential.s.toArray('be', 32);
      const signatureCredential = [...rCredential, ...sCredential];
      console.log("Signature (hex):", Buffer.from(signatureCredential).toString('hex'));
      console.log("Signature bytes:", signatureCredential);

      // Set store identity for verification
      loyaltyActor.setIdentity(storeIdentity);

      // Verify credential
      const result = await loyaltyActor.verifyCredential(
        schemeId,
        userIdentity.getPrincipal(),
        timestamp,
        signatureCredential,
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
}); 