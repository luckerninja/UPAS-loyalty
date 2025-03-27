# dfx identity use controller_upas

# CONTROLLER_ID=$(dfx identity get-principal)

# dfx --identity controller_upas deploy ex

# EX_CANISTER_ID=$(dfx canister id ex)

# dfx deploy icrc1_ledger_canister --argument "(variant { Init =
# record {
#      token_symbol = \"3T\";
#      token_name = \"3Tale\";
#      minting_account = record { owner = principal \"${EX_CANISTER_ID}\" };
#      transfer_fee = 10_000;
#      metadata = vec {};
#      initial_balances = vec { record { record { owner = principal \"${EX_CANISTER_ID}\"; }; 10_000_000_000; }; };
#      archive_options = record {
#          num_blocks_to_archive = 1000;
#          trigger_threshold = 2000;
#          controller_id = principal \"${CONTROLLER_ID}\";
#      };
#  }
# })"

# ICRC1_LEDGER_CANISTER_ID=$(dfx canister id icrc1_ledger_canister)

# dfx --identity controller_upas deploy loyalty --argument "(principal \"${EX_CANISTER_ID}\", principal \"${ICRC1_LEDGER_CANISTER_ID}\")"

LOYALTY_CANISTER_ID=$(dfx canister id loyalty)

dfx --identity controller_upas canister call ex setLoyaltyActor "(\"${LOYALTY_CANISTER_ID}\")"