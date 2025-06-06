use libra_framework::release::ReleaseTarget;
use libra_rescue::{
    cli_bootstrapper::BootstrapOpts,
    cli_main::{RescueCli, Sub, UPGRADE_FRAMEWORK_BLOB},
};
use libra_smoke_tests::libra_smoke::LibraSmoke;

#[tokio::test]
async fn test_framework_upgrade_writeset() -> anyhow::Result<()> {
    println!("0. create a valid test database from smoke-tests");
    let mut s = LibraSmoke::new(Some(3), None)
        .await
        .expect("could not start libra smoke");

    let env = &mut s.swarm;

    let val_db_path = env.validators().next().unwrap().config().storage.dir();
    assert!(val_db_path.exists());

    for node in env.validators_mut() {
        node.stop();
    }

    println!("1. generate framework upgrade writeset which should execute");
    let blob_path = diem_temppath::TempPath::new();
    blob_path.create_as_dir()?;

    let r = RescueCli {
        db_path: val_db_path.clone(),
        blob_path: Some(blob_path.path().to_owned()),
        command: Sub::UpgradeFramework {
            upgrade_mrb: ReleaseTarget::Head
                .find_bundle_path()
                .expect("cannot find head.mrb"),
            set_validators: None,
        },
    };

    r.run()?;

    let file = blob_path.path().join(UPGRADE_FRAMEWORK_BLOB);
    assert!(file.exists());

    println!(
        "3. check we can apply the tx to existing db, and can get a waypoint, don't commit it"
    );

    let boot = BootstrapOpts {
        db_dir: val_db_path.clone(),
        genesis_txn_file: file.clone(),
        waypoint_to_verify: None,
        commit: false,
        update_node_config: None,
        info: false,
    };

    let wp = boot.run()?;

    println!("4. with the known waypoint confirm it, and apply the tx");
    let boot = BootstrapOpts {
        db_dir: val_db_path,
        genesis_txn_file: file,
        waypoint_to_verify: wp,
        commit: true,
        update_node_config: None,
        info: false,
    };

    let new_w = boot.run()?;

    assert_eq!(wp, new_w, "waypoint mismatch");

    Ok(())
}
