use std::path::PathBuf;

use clap::Parser;

use crate::data_client;

#[derive(Parser)]
/// Demo
pub struct DemoCli {
    #[clap(short, long)]
    /// filepath to the validator or fullnode yaml config file.
    config_path: Option<PathBuf>,
}

impl DemoCli {
    pub fn run(&self) {
        println!("{:?}", &self.config_path);
        data_client::start().expect("could not run data_client");
    }
}
