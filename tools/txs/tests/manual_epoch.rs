use libra_smoke_tests::{configure_validator, libra_smoke::LibraSmoke};
use libra_txs::{
  submit_transaction::Sender,
  // txs_cli::{TxsCli, TxsSub::Transfer}
};
// use libra_types::legacy_types::app_cfg::TxCost;
use libra_cached_packages::libra_stdlib;

// Testing that we can send the minimal transaction: a transfer from one existing validator to another.
// Case 1: send to an existing account: another genesis validator
// Case 2: send to an account which does not yet exist, and the account gets created on chain.

/// Case 1: send to an existing account: another genesis validator
#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn smoke_manual_epoch() -> anyhow::Result<()>{
    let d = diem_temppath::TempPath::new();

    let mut s = LibraSmoke::new(Some(1))
        .await
        .expect("could not start libra smoke");

    let (_, app_cfg) =
        configure_validator::init_val_config_files(&mut s.swarm, 0, d.path().to_owned())
            .await
            .expect("could not init validator config");

    // s.swarm.
    let mut sender =
        Sender::from_app_cfg(&app_cfg, None).await?;

    let payload = libra_stdlib::diem_governance_trigger_epoch();

    sender.sign_submit_wait(payload).await?;

    Ok(())
}
