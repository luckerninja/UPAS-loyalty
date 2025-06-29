#!/bin/bash

dfx identity use upas_deployer

# Create canisters to get their IDs
dfx --identity upas_deployer canister create loyalty --ic
dfx --identity upas_deployer canister create ex --ic

CONTROLLER_ID=$(dfx identity get-principal)

EX_CANISTER_ID=$(dfx canister id ex --ic)

LOYALTY_CANISTER_ID=$(dfx canister id loyalty --ic)

# Deploy ICRC1 ledger canister
# Use the EX canister ID as the minting account
dfx deploy icrc1_ledger_canister --ic --argument "(variant { Init =
record {
     token_symbol = \"3T\";
     token_name = \"3Tale\";
     minting_account = record { owner = principal \"${EX_CANISTER_ID}\" };
     transfer_fee = 10_000;
     metadata = vec {};
     initial_balances = vec { record { record { owner = principal \"${EX_CANISTER_ID}\"; }; 10_000_000_000; }; record { record { owner = principal \"${LOYALTY_CANISTER_ID}\"; }; 10_000_000_000; }; };
     archive_options = record {
         num_blocks_to_archive = 1000;
         trigger_threshold = 2000;
         controller_id = principal \"${EX_CANISTER_ID}\";
     };
 }
})"

# Deploy EX canister
# Set the controller ID as the controller
dfx deploy ex --ic --argument "(principal \"${CONTROLLER_ID}\")"

ICRC1_LEDGER_CANISTER_ID=$(dfx canister id icrc1_ledger_canister --ic)

# Deploy Loyalty canister
dfx --identity upas_deployer deploy loyalty --ic --argument "(principal \"${EX_CANISTER_ID}\")"

# Set the Loyalty canister ID in the EX canister
dfx --identity upas_deployer canister call ex setLoyaltyActor "(principal \"${LOYALTY_CANISTER_ID}\")" --ic