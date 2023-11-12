mod node_cli;

use anyhow::anyhow;
use clap::{Parser, Subcommand};
use libra_swarm::swarm_cli::SwarmCli;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let s = SwarmCli::parse();

    s.run()
}
