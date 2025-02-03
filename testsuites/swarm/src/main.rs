use clap::Parser;
use libra_swarm::cli::SwarmCli;
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    SwarmCli::parse().run().await?;
    Ok(())
}
