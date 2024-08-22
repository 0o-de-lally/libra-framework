use diem_types::transaction::Transaction;
use diem_types::transaction::WriteSetPayload;
use libra_rescue::session_tools::{self, libra_run_session, writeset_voodoo_events};
use libra_storage::utils;
use libra_storage::{restore, restore_bundle::RestoreBundle};
use libra_twin_tests::runner::Twin;
use std::path::{Path, PathBuf};

// do a noop rescue blob
fn make_rescue_noop(db_path: &Path) -> anyhow::Result<PathBuf> {
    println!("run session to create validator onboarding tx (rescue.blob)");
    let vmc = libra_run_session(db_path.to_path_buf(), writeset_voodoo_events, None, None)?;

    let cs = session_tools::unpack_changeset(vmc)?;

    let gen_tx = Transaction::GenesisTransaction(WriteSetPayload::Direct(cs));
    let out = db_path.join("rescue.blob");

    let bytes = bcs::to_bytes(&gen_tx)?;
    std::fs::write(&out, bytes.as_slice())?;

    Ok(out)
}

// do a restore using fixtures
async fn test_helper_setup_restore() -> anyhow::Result<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace = dir
        .parent()
        .unwrap() //testsuites
        .parent()
        .unwrap(); //root
    let fixtures_path = workspace.join("tools/storage/fixtures/v7");
    let mut b = RestoreBundle::new(fixtures_path.clone());
    b.load().unwrap();
    let mut db_temp = diem_temppath::TempPath::new();
    db_temp.persist();
    db_temp.create_as_dir()?;

    // db would not yet have been bootstrapped with a genesis tx
    utils::bootstrap_without_node(db_temp.path(), fixtures_path.join("genesis.blob").as_ref())?;


    restore::full_restore(db_temp.path(), &b).await?;


    Ok(db_temp.path().to_owned())
}

#[tokio::test]
async fn test_full_restore_e2e() -> anyhow::Result<()> {
    // let db_temp = test_helper_setup_restore().await?;
    // let db_temp = Path::new("/tmp/fa27fe959d023d6efc0163f0ae71f47b");
    let db_temp = Path::new("/root/.libra/data/db");
    // let db_temp = Path::new("/root/.libra/rescue_db_two");

    dbg!(&db_temp);

    println!("Create a rescue blob from the reference db");

    // let rescue_blob_path = Twin::make_rescue_twin_blob(&temp_db_path, creds).await?;
    let rescue_blob_path = make_rescue_noop(&db_temp)?;

    println!("Apply the rescue blob to the swarm db & bootstrap");

    let wp = Twin::apply_rescue_on_db(&db_temp, &rescue_blob_path)?;
    dbg!(&wp);
    Ok(())
}
