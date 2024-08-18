use clap::{self, Parser};
use libra_smoke_tests::libra_smoke::LibraSmoke;
use std::{fs, path::PathBuf};

/// Twin of the network
#[derive(Parser)]
pub struct TwinCli {
  /// path of a working production db to become a test twin
  #[clap(long, short)]
  pub db_dir: PathBuf,

  #[clap(subcommand)]
  command: Sub

}

#[derive(clap::Subcommand)]
pub enum Sub {
  /// Run a swarm locally with the prepared db
  Swarm {
    /// number of local validators to start
    #[clap(long, short)]
    pub count_vals: Option<u8>,
  },
  /// Just apply a change to DB at rest
  Testnet {
    #[clap(long, short)]
    /// Pubkey files for the testnet validators which will drive the Twin
    /// should point to validator-identity.yaml
    pub val_id_files: Vec<PathBuf>
  }
}

impl TwinCli {
    /// Runner for the twin
    pub async fn run(&self) -> anyhow::Result<(), anyhow::Error> {
        let db_path = fs::canonicalize(&self.db_dir)?;

        match self.command {
          Sub::Swarm {count_vals} => {
            let num_validators = count_vals.unwrap_or(1);

            let mut smoke = LibraSmoke::new(Some(num_validators), None).await?;
            Twin::make_twin_swarm(&mut smoke, Some(db_path), true).await?;
          },
          Sub::Testnet {val_id_files} => {
            let creds = validtor_registration::parse_pub_files_to_vec(val_id_files);
            println!("Creating a rescue blob from the reference db");

            let rescue_blob_path = Self::make_rescue_twin_blob(&db_path, creds).await?;

            println!("3. Apply the rescue blob to the swarm db & bootstrap");

            let wp = Self::apply_rescue_on_db(&temp_db_path, &rescue_blob_path)?;
          }
        }



        Ok(())
    }
}
