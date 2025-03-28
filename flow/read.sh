dfx identity use store_upas

STORE_PRINCIPAL=$(dfx identity get-principal)
EX_CANISTER_ID=$(dfx canister id ex)
LOYALTY_CANISTER_ID=$(dfx canister id loyalty)



dfx canister call icrc1_ledger_canister icrc1_minting_account
dfx canister call icrc1_ledger_canister icrc1_balance_of "(record { owner = principal \"${EX_CANISTER_ID}\"; })"
dfx canister call icrc1_ledger_canister icrc1_balance_of "(record { owner = principal \"${LOYALTY_CANISTER_ID}\"; })"

dfx --identity controller_upas canister call loyalty getStore "(principal \"${STORE_PRINCIPAL}\")"
dfx canister call loyalty getStoreTokens "(principal \"${STORE_PRINCIPAL}\")"