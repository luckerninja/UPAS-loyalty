# Loyalty Program on Internet Computer

A decentralized loyalty program system built on the Internet Computer platform. The system allows stores to issue credentials with rewards to users using ICRC1 tokens. Motoko is used for the main canister and JavaScript is used for the test utilities.

## Project Structure

- `src/loyalty/` - Main loyalty program canister
- `src/ex/` - External canister for token management
- `flow/` - Deployment and testing scripts
- `test/` - Test utilities

## Prerequisites

1. Install DFX:
```bash
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
```

2. Install Node.js dependencies:
```bash
cd test/
npm install
```

3. Create `.env` file in test directory:
```env
STORE_PRINCIPAL=your_store_principal
USER_PRINCIPAL=your_user_principal
REWARD=100
```

## Setup and Deployment

1. Start local replica:
```bash
dfx start --background
```

2. Initialize identities:
```bash
./flow/init_identities.sh
```

3. Deploy canisters:
```bash
./flow/deploy.sh
```

## Testing Flow

1. Generate test commands:
```bash
cd test/
node index.js
```

2. Execute generated commands:
```bash
# View generated commands
cat ../flow/temp_commands.sh

# Execute specific commands:
# Test public key deserialization
dfx canister call loyalty deserializePublicKey '(...)'

# Add store and mint tokens
dfx --identity controller_upas canister call loyalty addStore '(...)'
dfx --identity controller_upas canister call ex mintAndTransferToStore '(...)'

# Issue credential
dfx --identity store_upas canister call loyalty issueCredential '(...)'

# Run all commands
sh ./flow/temp_commands.sh
```

## Main Features

1. **Store Management**
   - Add stores with public keys
   - Publish credential schemes
   - Issue credentials to users

2. **Token Management**
   - ICRC1 token integration
   - Token transfers between stores and users
   - Balance tracking

3. **Credential System**
   - Digital signature verification
   - Timestamp validation
   - Reward distribution

## Security

- Uses ECDSA (secp256k1) for signature verification
- Implements role-based access control
- Validates all transactions and credentials

## Development

To make changes to the project:

1. Modify Motoko files in `src/`
2. Update test scripts in `test/`
3. Deploy changes:
```bash
dfx deploy
```