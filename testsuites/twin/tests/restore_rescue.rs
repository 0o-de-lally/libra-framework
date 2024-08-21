use libra_storage::{restore, restore_bundle::RestoreBundle};
use std::path::PathBuf;

#[tokio::test]
async fn test_full_restore() -> anyhow::Result<()> {
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

    assert!(db_temp.path().join("ledger_db").exists());
    assert!(db_temp.path().join("state_merkle_db").exists());
    Ok(())
}
