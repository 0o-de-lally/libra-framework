use diem_types::transaction::Transaction;
use diem_types::transaction::WriteSetPayload;
use libra_rescue::session_tools::{self,libra_run_session, writeset_voodoo_events};
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
    let mut b = RestoreBundle::new(workspace.join("tools/storage/fixtures/v7"));
    b.load().unwrap();
    let mut db_temp = diem_temppath::TempPath::new();
    db_temp.persist();
    db_temp.create_as_dir()?;

    restore::full_restore(db_temp.path(), &b).await?;
    Ok(db_temp.path().to_owned())
}

#[tokio::test]
async fn test_full_restore() -> anyhow::Result<()> {
    let db_temp = test_helper_setup_restore().await?;
    dbg!(&db_temp);

    println!("Create a rescue blob from the reference db");

    // let rescue_blob_path = Twin::make_rescue_twin_blob(&temp_db_path, creds).await?;
    let rescue_blob_path = make_rescue_noop(&db_temp)?;

    println!("Apply the rescue blob to the swarm db & bootstrap");

    let wp = Twin::apply_rescue_on_db(&db_temp, &rescue_blob_path)?;

    Ok(())
}
