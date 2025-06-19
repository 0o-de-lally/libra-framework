/// community wallets had an edge case where a v8 user rejoin could be
/// executed on it. This would create some unexpected behavior
/// This function can be called by any signer of a CW to sanitize
// the state of the community wallet and remove any
/// unwanted state that was created by the v8 rejoin.

module ol_framework::community_wallet_clean {

    use std::error;
    use std::signer;
    use diem_framework::multisig_account;
    use ol_framework::donor_voice;
    use ol_framework::multi_action;


    /// Error codes
    /// Invalid Donor Voice address
    const  EINVALID_DV_ADDRESS: u64 = 1;
    /// Not a signer authority
    const ENOT_SIGNER_AUTHORITY: u64 = 2;

    public entry fun clean(dv_signer: &signer, multisig_address: address) {

        assert!(multisig_account::is_multisig(multisig_address) &&
        multi_action::is_multi_action(multisig_address) &&
        donor_voice::is_donor_voice(multisig_address), error::invalid_argument(EINVALID_DV_ADDRESS));

        assert!(multi_action::is_authority(signer::address_of(dv_signer)), error::invalid_argument(ENOT_SIGNER_AUTHORITY));


          // remove slow wallet structs
          // remove founder struct
          // remove page_rank_lazy
          // remove vouch
    }
}
