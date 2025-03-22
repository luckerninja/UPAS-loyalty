dfx deploy icrc1_ledger_canister --argument '(
  variant {
    Init = record {
      decimals = null;
      token_symbol = "t";
      transfer_fee = 10 : nat;
      metadata = vec {};
      minting_account = record {
        owner = principal "a34gd-jdvrz-wxxbz-msire-voajd-spunw-6mvdf-qvfs4-ejmgf-fftfg-oqe";
        subaccount = null;
      };
      initial_balances = vec {};
      maximum_number_of_accounts = null;
      accounts_overflow_trim_quantity = null;
      fee_collector_account = null;
      archive_options = record {
        num_blocks_to_archive = 90 : nat64;
        max_transactions_per_response = null;
        trigger_threshold = 90 : nat64;
        more_controller_ids = null;
        max_message_size_bytes = null;
        cycles_for_archive_creation = null;
        node_max_memory_size_bytes = null;
        controller_id = principal "a34gd-jdvrz-wxxbz-msire-voajd-spunw-6mvdf-qvfs4-ejmgf-fftfg-oqe";
      };
      max_memo_length = null;
      token_name = "test";
      feature_flags = null;
    }
  },
)'

