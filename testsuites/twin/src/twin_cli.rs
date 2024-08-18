use crate::setup;
use clap::{self, Parser};
use libra_config::validator_registration::{self, ValCredentials};
use libra_smoke_tests::libra_smoke::LibraSmoke;
use std::{fs, path::PathBuf};
/// Twin of the network
#[derive(Parser)]
pub struct TwinCli {
    /// path of a working production db to become a test twin
    #[clap(long, short)]
    pub db_dir: PathBuf,

    #[clap(subcommand)]
    pub command: Sub,
}

#[derive(clap::Subcommand)]
pub enum Sub {
    /// Run a swarm locally with the prepared db
    Swarm {
        /// number of local validators to start
        #[clap(long, short)]
        count_vals: Option<u8>,
    },
    /// Just apply a change to DB at rest
    Testnet {
        #[clap(long, short)]
        /// Registration files (operator.yaml) for testnet validators which will drive the Twin.
        operator_pubkeys: Vec<PathBuf>,
    },
}

impl TwinCli {
    /// Runner for the twin
    pub async fn run(&self) -> anyhow::Result<(), anyhow::Error> {
        let db_path = fs::canonicalize(&self.db_dir)?;

        match &self.command {
            Sub::Swarm { count_vals } => {
                let num_validators = count_vals.unwrap_or(1);

                let mut smoke = LibraSmoke::new(Some(num_validators), None).await?;
                setup::make_twin_swarm(&mut smoke, Some(db_path), true).await?;
            }
            Sub::Testnet { operator_pubkeys } => {
                let creds = ValCredentials::new_from_file_list(operator_pubkeys.clone())?;
                println!("Creating a rescue blob from the reference db");

                let rescue_blob_path = setup::make_rescue_twin_blob(&db_path, creds).await?;

                println!("Apply the rescue blob to the swarm db & bootstrap");

                let wp = setup::apply_rescue_on_db(&db_path, &rescue_blob_path)?;

                println!("waypoint: {}", wp);
            }
        }
        Ok(())
    }
}
