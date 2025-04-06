# UPAS: User Public Achievement Standard
## A Decentralized Loyalty and Reputation Protocol on Internet Computer

## Abstract

UPAS (User Public Achievement Standard) is an open protocol for building decentralized loyalty and reputation systems on the Internet Computer Platform (ICP). The protocol enables businesses to create and manage loyalty programs while maintaining user privacy and data sovereignty through cryptographic proofs and self-authenticating identities.

## About

The loyalty program market is projected to reach $200+ billion by 2027 (Statista). While major players like Pollen ($150M), Blackbird.xyz ($24M from a16z), and Shopify are implementing Web3 loyalty solutions, none offer truly open standards. UPAS aims to establish a universal standard for Web3 loyalty and reputation systems on ICP, addressing critical flaws in traditional programs through:

- Open Protocol: Non-expiring points architecture supporting cross-program transfers
- Privacy-first: Direct data exchange between users and businesses
- Business-Ready: Jurisdiction-agnostic design minimizing regulatory risks
- Data Marketplace: Enabling users to monetize anonymized purchase data

## Core Entities

### Store
A business entity in the loyalty system with:
- Meta information (name, description)
- Public key for credential verification
- Credential schemes management
- Issue history tracking
```motoko
public type Store = {
    owner: Principal;
    name: Text;
    description: Text;
    schemes: [CredentialScheme];
    issueHistory: [IssueHistory];
    publicKey: PublicKey;
};
```

### Credential
Digital proof of achievement or purchase:
- Unique SHA-256 based identification
- ECDSA signature verification
- Timestamp validation
- Associated reward points
```motoko
public type CredentialScheme = {
    id: Text;
    name: Text;
    description: Text;
    metadata: Text;
    reward: Nat;
};
```

### Identity Wallet
Mobile/browser application implementing:
- ICP self-authenticating wallet functionality
- Local credential storage and management
- Purchase history decryption
- Delegated key generation for store interactions

### Loyalty Points
ICRC-1 token implementation with:
- No expiration
- Cross-program transfer capability
- Automated reward distribution
- Optional liquidity for crypto-projects

### Controllers
Entities managing:
- Fiat-token exchange compliance
- Regulatory requirements
- Program parameters

### Tag
Computed reputation marker based on user achievements and purchase history:
- Decentralized computation within canister
- Signed by canister using threshold ECDSA
- Used for dynamic cashback calculation
- Time-limited for promotional campaigns

```motoko
public type Tag = {
    id: Text;
    name: Text;
    description: Text;
    computationScheme: ComputationScheme;
    validUntil: ?Int;  // Optional expiration for promotional tags
};

public type ComputationScheme = {
    requiredCredentials: [Text];  // Required credential IDs
    purchaseRanges: [PurchaseRange];
    minimumTransactions: Nat;
    timeframe: Int;  // Period for calculation in nanoseconds
};
```

Tag computation process:
1. Controller publishes computation scheme
2. Canister processes user's:
   - Verified credentials
   - Purchase history
   - Transaction volumes
3. Tag is issued with canister signature
4. Tag can be used for:
   - Increased cashback rates
   - Special promotions
   - Cross-program benefits

Example computation:
```motoko
public shared({ caller }) func computeUserTags(userId: Principal) : async [Tag] {
    // Verify caller authorization
    assert(isAuthorizedController(caller));

    // Get user's credentials and purchase history
    let credentials = getUserCredentials(userId);
    let purchases = getUserPurchases(userId);
    
    // Apply computation schemes
    let validTags = Array.filter(
        availableTags,
        func(tag: Tag) : Bool {
            meetsTagRequirements(tag, credentials, purchases)
        }
    );

    // Sign tags using canister threshold ECDSA
    let signedTags = await signTags(validTags, userId);
    
    return signedTags;
};
```

## Technical Implementation

### Security Model

1. **Store Authentication**
```motoko
public shared({ caller }) func addStore(
    principal: Principal, 
    name: Text, 
    description: Text, 
    publicKeyNat: [Nat8]
) : async ?Store
```
- ECDSA key pair verification
- Role-based access control
- Store metadata validation

2. **Credential Issuance**
```motoko
public shared({ caller }) func issueCredential(
    schemeId: Text,
    holderId: Principal,
    signature: [Nat8],
    timestamp: Int
) : async Result.Result<Nat, Text>
```
- Signature verification
- Timestamp validation
- Reward point calculation

3. **Points Management**
```motoko
public shared({ caller }) func mintAndTransferToStore(
    storePrincipal: Principal, 
    amount: Nat
) : async Result.Result<Nat, Text>
```
- ICRC-1 token operations
- Balance tracking
- Transfer validation

### Flow

1. **Store Registration**
- Store deploys public key
- Controller verifies and adds store
- Store publishes credential schemes

2. **User Interaction**
- User generates sub-key for store
- Store verifies user identity
- User receives credential with points

3. **Credential Management**
- Credentials stored locally
- Points transferred automatically
- History tracked on-chain

## Future Development

### Milestone 1: Base Store Functionality
- Delegated keys for employees
- Dynamic credential schemes
- Integration specifications

### Milestone 2: Points and Indexation
- ICRC-1 token deployment
- Receipt indexing
- Secure storage scheme

### Milestone 3: Reputation System
- Tag computation through canister signature
- Dynamic cashback based on user tags
- Decentralized reputation calculation
- Time-limited promotional tags
- Cross-program tag recognition

## Conclusion

UPAS provides the foundation for next-generation loyalty programs by combining the security and transparency of blockchain with the privacy and usability requirements of modern businesses. Through its open standard and flexible architecture, UPAS enables seamless integration of Web2 businesses into the Web3 ecosystem while preserving user privacy and data sovereignty.

## References

1. Internet Computer Protocol Documentation
2. ICRC-1 Token Standard
3. ECDSA Specification
4. SHA-2 Standard 