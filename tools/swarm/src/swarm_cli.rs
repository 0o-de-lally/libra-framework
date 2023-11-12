use anyhow::{anyhow, bail};
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser)]
#[clap(author, version, about, long_about = None)]
#[clap(arg_required_else_help(true))]
struct SwarmCli {
    #[clap(short, long)]
    /// publish a move contract under Alice
    count: Option<u64>
    #[clap(short, long)]

    /// publish a move contract under Alice
    publish: Option<PathBuf>
}

impl SwarmCli {
  pub fn run(&self) {

  }
}
