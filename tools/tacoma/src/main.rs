use anyhow::Context;
use clap::{Parser, Subcommand};
use tacoma::demo_cli::DemoCli;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
#[command(propagate_version = true)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    Demo(DemoCli),
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match &cli.command.context("no options given")? {
        Commands::Demo(d) => d.run(),
    }

    Ok(())
}
