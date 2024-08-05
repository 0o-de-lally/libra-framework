use anyhow::Result;
use diem_backup_cli::{
    backup_types::epoch_ending::restore::{EpochEndingRestoreController, EpochEndingRestoreOpt},
    storage::{local_fs::LocalFs, BackupStorage, DBToolStorageOpt},
    utils::{GlobalRestoreOpt, GlobalRestoreOptions, RestoreRunMode, TrustedWaypointOpt},
};
use std::{path::PathBuf, sync::Arc};

pub fn init_storage(local_fs_dir: PathBuf) -> Result<Arc<dyn BackupStorage>> {
    Ok(Arc::new(LocalFs::new(local_fs_dir)))
}

pub fn restore_opts(manifest_path: &str) -> EpochEndingRestoreOpt {
    EpochEndingRestoreOpt {
        manifest_handle: manifest_path.to_string(),
    }
}

pub fn trusted_waypoints(wp_str: &str) -> TrustedWaypointOpt {
    let waypoint = wp_str.parse().expect("cannot parse waypoint");
    TrustedWaypointOpt {
        trust_waypoint: vec![waypoint],
    }
}


pub async fn manifest_to_db(new_db_path: PathBuf, manifest_path: PathBuf, wp_string: &str) {

    let epoch_restore_opts = restore_opts(manifest_path);
    let global_restore_opts = GlobalRestoreOptions {
        run_mode: Arc::new(RestoreRunMode::Verify),
        target_version: 0,
        concurrent_downloads: 4,
        trusted_waypoints: Arc::new(
            trusted_waypoints(wp_str)
                .verify()
                .expect("could not verify waypoint"),
        ),
        replay_concurrency_level: 0,
    };
    let db = init_storage(path).unwrap();

    EpochEndingRestoreController::new(epoch_restore_opts, global_restore_opts, db);
}


#[tokio::test]
async fn try_read_manifest() {
      let db_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let wp_str = "..";
    let manifest_path = "tbd";

    manifest_to_db(db_path, wp_str, manifest_path);
}
