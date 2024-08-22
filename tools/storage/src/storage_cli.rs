use anyhow::{bail, Result};
use clap::{Parser, Subcommand};
use diem_db_tool::DBTool;
use diem_logger::{Level, Logger};
use diem_push_metrics::MetricsPusher;
use std::{fs, path::PathBuf};

use crate::{read_snapshot, restore, restore_bundle::RestoreBundle, utils};

#[derive(Parser)]
#[clap(author, version, about, long_about = None)]
#[clap(arg_required_else_help(true))]
/// DB tools e.g.: backup, restore, export to json
pub struct StorageCli {
    #[clap(subcommand)]
    command: Sub,
}

#[derive(Subcommand)]
#[allow(clippy::large_enum_variant)]
pub enum Sub {
    #[clap(subcommand)]
    /// DB tools for backup, restore, verify, etc.
    Db(DBTool),
    /// simple restore from a bundle for one epoch
    EpochRestore {
        /// backup bundle directory
        #[clap(short, long)]
        bundle_path: PathBuf,
        /// dir to save db, will create directory
        #[clap(short, long)]
        destination_db: PathBuf,
        /// clean start from a genesis blob
        #[clap(short, long)]
        genesis_tx_path: Option<PathBuf>,
    },
    /// Read a snapshot, parse and export to JSON
    ExportSnapshot {
        /// dir of snapshot files
        #[clap(short, long)]
        manifest_path: PathBuf,
        /// file path for the json export
        #[clap(short, long)]
        out_path: Option<PathBuf>,
    },
    /// try bootstrap
    TryBootstrap {
        /// path to initialize database
        #[clap(short, long)]
        db_path: PathBuf,
        /// genesis blob file path
        #[clap(short, long)]
        genesis_tx_path: PathBuf,
    },
}

impl StorageCli {
    // Note: using owned self since DBTool::run uses an owned self.
    pub async fn run(self) -> Result<()> {
        Logger::new().level(Level::Info).init();
        let _mp = MetricsPusher::start(vec![]);

        match self.command {
            Sub::Db(tool) => {
                tool.run().await?;
            }
            Sub::ExportSnapshot {
                manifest_path,
                out_path,
            } => {
                read_snapshot::manifest_to_json(manifest_path.to_owned(), out_path.to_owned())
                    .await;
            }
            Sub::EpochRestore {
                bundle_path,
                destination_db,
                genesis_tx_path
            } => {
                if !bundle_path.exists() {
                    bail!("bundle directory not found: {}", &bundle_path.display());
                };
                if destination_db.exists() {
                    println!("you are trying to restore to a directory that already exists, and may have conflicting state: {}", &destination_db.display());
                };


                if !destination_db.exists() {
                    fs::create_dir_all(&destination_db)?;
                }


                // if db doesn't exist it needs to be bootstrapped first.
                if let Some(p) = genesis_tx_path {
                  println!("attempting to boostrap from genesis.blob from {}", &p.display());
                  utils::bootstrap_without_node(&destination_db, &p)?;
                  println!("DB bootstrapped with genesis tx");
                }

                // underlying tools get lost with relative paths
                let bundle_path = fs::canonicalize(bundle_path)?;
                let destination_db = fs::canonicalize(destination_db)?;

                let mut bundle = RestoreBundle::new(bundle_path);

                bundle.load()?;

                restore::full_restore(&destination_db, &bundle).await?;

                println!(
                    "SUCCESS: restored to epoch: {}, version: {}",
                    bundle.epoch, bundle.version
                );
            }
            Sub::TryBootstrap {
                db_path,
                genesis_tx_path,
            } => {
                utils::bootstrap_without_node(&db_path, &genesis_tx_path)?;
                println!("DB bootstrapped with genesis tx");
            }
            // _ => {} // prints help
        }

        Ok(())
    }
}
