dfx identity use store_upas

STORE_PRINCIPAL=$(dfx identity get-principal)

dfx --identity controller_upas canister call loyalty getStore "(principal \"${STORE_PRINCIPAL}\")"