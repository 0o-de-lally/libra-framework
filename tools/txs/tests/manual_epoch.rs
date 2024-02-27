
use std::time::Duration;

use diem_forge::Swarm;
use diem_types::transaction::EntryFunction;
use libra_smoke_tests::{configure_validator, libra_smoke::LibraSmoke};
use libra_txs::{
  txs_cli_governance::GovernanceTxs::EpochBoundary,
  txs_cli::{TxsCli, TxsSub::Governance}
};
use libra_types::legacy_types::app_cfg::TxCost;


#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn smoke_epoch_gov() -> anyhow::Result<()> {
    let d = diem_temppath::TempPath::new();

    let mut s = LibraSmoke::new(None)
        .await
        .expect("could not start libra smoke");

    let (_, _app_cfg) =
        configure_validator::init_val_config_files(&mut s.swarm, 0, d.path().to_owned())
            .await
            .expect("could not init validator config");

    let pi = s.swarm.diem_public_info();
    let tf = pi.transaction_factory();
    // let e: EntryFunction =
    // "0x1::epoch_boundary::swarm_set_trigger".try_into()?;
    // EntryFunction::
    // EntryFunction::
    // let f = tf.entry_function(e);

    // case 2. Account does not yet exist.
    let cli = TxsCli {
        subcommand: Some(Governance(EpochBoundary)),
        mnemonic: None,
        test_private_key: Some(s.encoded_pri_key.clone()),
        chain_id: None,
        config_path: Some(d.path().to_owned().join("libra.yaml")),
        url: Some(s.api_endpoint.clone()),
        tx_profile: None,
        tx_cost: Some(TxCost::default_baseline_cost()),
        estimate_only: false,
    };

    cli.run()
        .await
        .expect("cli could not create and transfer to new account");

    std::thread::sleep(Duration::from_secs(5));
    s.swarm.health_check().await.expect("is healthy");

    // TODO: check the balance
}


// #[ignore]
// /// Case 1: send to an existing account: another genesis validator
// #[tokio::test(flavor = "multi_thread", worker_threads = 1)]
// async fn smoke_manual_epoch() -> anyhow::Result<()> {
//     let d = diem_temppath::TempPath::new();


//     let mut s = LibraSmoke::new(Some(1))
//         .await
//         .expect("could not start libra smoke");
//     let id = s.swarm.chain_id().clone();
//     let mut pub_info = s.swarm.diem_public_info();
//     let core_resources = pub_info.root_account();

//     let payload = libra_stdlib::diem_governance_trigger_epoch();
//     let builder = TransactionBuilder::new(payload, 10000, id);

//     let tx = core_resources.sign_with_transaction_builder(builder);
//     let res = pub_info.client().wait_for_signed_transaction(&tx).await?;

//     dbg!(&res);

//     Ok(())
// }
