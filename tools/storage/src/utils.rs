use std::{fs, path::Path};

use diem_config::config::{
    RocksdbConfigs, BUFFERED_STATE_TARGET_ITEMS, DEFAULT_MAX_NUM_NODES_PER_LRU_CACHE_SHARD,
    NO_OP_STORAGE_PRUNER_CONFIG,
};
use diem_db::DiemDB;
use diem_executor::db_bootstrapper::{generate_waypoint, maybe_bootstrap};
use diem_storage_interface::DbReaderWriter;
use diem_types::transaction::Transaction;
use diem_vm::DiemVM;

/// get a diem_db struct from path, just kv storage
pub fn get_db_kv(db_dir: &Path) -> anyhow::Result<DiemDB> {
    DiemDB::open_kv_only(
        db_dir.to_owned(),
        false,                       /* read_only */
        NO_OP_STORAGE_PRUNER_CONFIG, /* pruner config */
        RocksdbConfigs::default(),
        false,
        BUFFERED_STATE_TARGET_ITEMS,
        DEFAULT_MAX_NUM_NODES_PER_LRU_CACHE_SHARD,
    )
}

/// read the genesis tx from file
pub fn get_genesis_tx(genesis_blob_path: &Path) -> anyhow::Result<Transaction> {
    let genesis_transaction = {
        let buf = fs::read(genesis_blob_path).unwrap();
        bcs::from_bytes::<Transaction>(&buf).unwrap()
    };
    Ok(genesis_transaction)
}

/// databases that are restored need to be bootstrapped i.e.; a genesis transaction need to be verified.
/// usually the diem-node process with do this with the info in NodeConfig yaml files.
/// Here we have a helper to bootstrap without starting a node.
pub fn bootstrap_without_node(db_path: &Path, gen_tx_path: &Path) -> anyhow::Result<()> {
    let db = get_db_kv(db_path)?;
    let genesis_txn = get_genesis_tx(gen_tx_path)?;
    let db_rw = DbReaderWriter::new(db);
    let genesis_waypoint = generate_waypoint::<DiemVM>(&db_rw, &genesis_txn)?;
    maybe_bootstrap::<DiemVM>(&db_rw, &genesis_txn, genesis_waypoint)?;
    Ok(())
}
