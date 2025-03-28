dfx identity use store_upas

STORE_PRINCIPAL=$(dfx identity get-principal)

dfx identity use controller_upas

dfx --identity controller_upas canister call loyalty addStore "(principal \"${STORE_PRINCIPAL}\", \"Store 1\", \"Store 1 description\")"

dfx --identity controller_upas canister call ex mintAndTransferToStore "(principal \"${STORE_PRINCIPAL}\", 1000)"

dfx identity use user_upas

USER_PRINCIPAL=$(dfx identity get-principal)

dfx --identity store_upas canister call loyalty publishCredentialScheme "(\"Test\", \"Test\", \"Test\", 1000)"

dfx --identity store_upas canister call loyalty issueCredential "(\"${STORE_PRINCIPAL}Test\", principal \"${USER_PRINCIPAL}\")"