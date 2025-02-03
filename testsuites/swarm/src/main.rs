use clap::Parser;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    Swarm::parse().run().await?;
    Ok(())
}
