use crate::twin::Twin;
use clap::{self, Parser, Subcommand};
use libra_smoke_tests::libra_smoke::LibraSmoke;
use std::{fs, path::PathBuf, thread, time::Duration};

/// Set up a twin of the network, with a synced db
#[derive(Parser)]

pub struct SwarmCli {
    /// which variant of swarm to run
    #[clap(subcommand)]
    sub: SwarmSub,
    /// set a different timeout, defaults to 1 min
    #[clap(long, short)]
    pub timeout: Option<u64>,
    /// provide info about the DB state, e.g. version
    #[clap(long, short)]
    pub info: bool,
    /// number of local validators to start
    #[clap(long, short)]
    pub count_vals: Option<u8>,
}

#[derive(Subcommand)]
pub enum SwarmSub {
    Twin {
        /// path of snapshot db we want marlon to drive
        #[clap(long, short)]
        db_dir: PathBuf,
        /// The operator.yaml file which contains registration information
        #[clap(long, short)]
        oper_file: Option<PathBuf>,
    },
    Simple {},
}

impl SwarmCli {
    /// Runner for the twin
    pub async fn run(&self) -> anyhow::Result<(), anyhow::Error> {
        let timeout = 60 * self.timeout.unwrap_or(1);
        let num_validators = self.count_vals.unwrap_or(1);

        // swarm starts running now
        let mut smoke = LibraSmoke::new(Some(num_validators), None).await?;

        match &self.sub {
            SwarmSub::Twin { db_dir, .. } => {
                let db_path = fs::canonicalize(db_dir)?;
                // TODO: sleep
                Twin::make_twin_swarm(&mut smoke, Some(db_path), true).await?;
            }
            SwarmSub::Simple {} => {
                // TODO: does anything need to happen here?
            }
        }

        thread::sleep(Duration::from_secs(timeout));

        Ok(())
    }
}
