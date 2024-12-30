use libra_smoke_tests::{configure_validator, libra_smoke::LibraSmoke};
use libra_txs::txs_cli::{self, TxsCli, TxsSub::Transfer};

/// Case 1: send to an existing account: another genesis validator
#[tokio::test(flavor = "multi_thread", worker_threads = 1)]

async fn can_save_tx_file() {
    let d = diem_temppath::TempPath::new();
    let out_file = d.path().join("offline_tx.bcs").to_owned();

    let mut s = LibraSmoke::new(Some(2), None) // going to transfer from validator #0 to validator #1
        .await
        .expect("could not start libra smoke");

    let (local_account_alice, _) =
        configure_validator::init_val_config_files(&mut s.swarm, 0, Some(d.path().to_owned()))
            .expect("could not init validator config");

    let (local_account_bob, _) =
        configure_validator::init_val_config_files(&mut s.swarm, 1, Some(d.path().to_owned()))
            .expect("could not init validator config");

    // Alice signs an offline transaction to bob
    let recipient = local_account_bob.address(); // sending to second genesis node.
    let cli = TxsCli {
        subcommand: Some(Transfer {
            to_account: recipient,
            amount: 1.0,
        }),
        offline_address: Some(local_account_alice.address()),
        offline_expire_sec: Some(30),
        offline_seq_num: Some(local_account_alice.sequence_number()),
        save_path: Some(out_file.clone()),
        test_private_key: Some(s.encoded_pri_key.clone()),
        config_path: Some(d.path().to_owned().join("libra-cli-config.yaml")),
        url: Some(s.api_endpoint.clone()),
        ..Default::default()
    };

    cli.run()
        .await
        .expect("cli could not send to existing account");
    assert!(out_file.exists());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn can_submit_tx_file() {
    let d = diem_temppath::TempPath::new();
    let out_file = d.path().join("offline_tx.bcs").to_owned();

    let mut s = LibraSmoke::new(Some(2), None) // going to transfer from validator #0 to validator #1
        .await
        .expect("could not start libra smoke");

    let (local_account_alice, _) =
        configure_validator::init_val_config_files(&mut s.swarm, 0, Some(d.path().to_owned()))
            .expect("could not init validator config");

    let (local_account_bob, _) =
        configure_validator::init_val_config_files(&mut s.swarm, 1, Some(d.path().to_owned()))
            .expect("could not init validator config");

    // Alice signs an offline transaction to bob
    let recipient = local_account_bob.address(); // sending to second genesis node.
    let cli = TxsCli {
        subcommand: Some(Transfer {
            to_account: recipient,
            amount: 1.0,
        }),
        offline_address: Some(local_account_alice.address()),
        offline_expire_sec: Some(30),
        offline_seq_num: Some(local_account_alice.sequence_number()),
        save_path: Some(out_file.clone()),
        test_private_key: Some(s.encoded_pri_key.clone()),
        config_path: Some(d.path().to_owned().join("libra-cli-config.yaml")),
        url: Some(s.api_endpoint.clone()),
        ..Default::default()
    };

    cli.run().await.expect("cli could not save offline file");

    assert!(out_file.exists());

    // Now anyone can use the txs cli to submit the offline transaction
    let cli_two = TxsCli {
        subcommand: Some(txs_cli::TxsSub::Relay {
            tx_file: out_file.clone(),
        }),
        config_path: Some(d.path().to_owned().join("libra-cli-config.yaml")),
        url: Some(s.api_endpoint.clone()),
        ..Default::default()
    };

    cli_two
        .run()
        .await
        .expect("cli could not submit pre-signed file");
}
