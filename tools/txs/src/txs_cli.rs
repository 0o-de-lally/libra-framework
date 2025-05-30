use crate::{
    publish::encode_publish_payload, submit_transaction::Sender, txs_cli_community::CommunityTxs,
    txs_cli_governance::GovernanceTxs, txs_cli_stream::StreamTxs, txs_cli_user::UserTxs,
    txs_cli_vals::ValidatorTxs,
};
use anyhow::Result;
use clap::Parser;
use diem::common::types::MovePackageDir;
use diem_sdk::{
    crypto::{ed25519::Ed25519PrivateKey, ValidCryptoMaterialStringExt},
    rest_client::Client,
    types::{account_address::AccountAddress, AccountKey},
};
use indoc::indoc;
use libra_types::{
    core_types::app_cfg::{AppCfg, TxCost, TxType},
    exports::{ChainId, NamedChain},
};
use libra_wallet::account_keys::{get_keys_from_mnem, get_keys_from_prompt};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use url::Url;

#[derive(Parser, Default)]
#[clap(name = env!("CARGO_PKG_NAME"), author, version, about, long_about = None, arg_required_else_help = true)]
/// Submit a transaction to the blockchain
pub struct TxsCli {
    #[clap(subcommand)]
    pub subcommand: Option<TxsSub>,

    /// optional, path to the libra cli config file
    #[clap(short, long)]
    pub config_path: Option<PathBuf>,

    /// optional, mnemonic to pass at runtime. Otherwise this will prompt for mnemonic
    #[clap(short, long)]
    pub mnemonic: Option<String>,

    /// optional, Private key of the account. Otherwise this will prompt for mnemonic. Warning: intended for testing
    #[clap(short, long)]
    pub test_private_key: Option<String>,

    /// optional, Use a transaction profile used in libra-cli-config.yaml.
    /// Is mutually exclusive with --tx-cost
    #[clap(long)]
    pub tx_profile: Option<TxType>,

    /// optional, Maximum number of gas units to be used to send this
    /// transaction. Is mutually exclusive with --tx-profile
    #[clap(flatten)]
    pub tx_cost: Option<TxCost>,

    /// optional, Id of chain as name. Will default to MAINNET
    #[clap(long)]
    pub chain_name: Option<NamedChain>,

    /// optional, URL of the upstream node to send tx to, including port
    /// Otherwise will default to what is in the config file
    #[clap(short, long)]
    pub url: Option<Url>,

    /// optional, Only estimate the gas fees
    #[clap(long)]
    pub estimate_only: bool,

    /// optional, use legacy (v5) 16-byte address format for a sender
    #[clap(long)]
    pub legacy_address: bool,
}

#[derive(clap::Subcommand)]
pub enum TxsSub {
    #[clap(subcommand)]
    /// User account utils
    User(UserTxs),
    #[clap(subcommand)]
    /// Validator configuration transactions
    Validator(ValidatorTxs),
    #[clap(subcommand)]
    /// Network upgrade transactions
    Governance(GovernanceTxs),
    #[clap(subcommand)]
    /// Perform transactions for addresses with Community Wallet settings
    Community(CommunityTxs),
    /// Transfer coins between accounts (and create new account)
    // Transferring can also be used to create accounts
    Transfer {
        /// Address of the recipient
        #[clap(short, long)]
        to_account: AccountAddress,

        /// The amount of coins to transfer
        #[clap(short, long)]
        amount: f64,
    },
    #[clap(subcommand, hide(true))]
    /// Warn: Streaming transactions is experimental
    Stream(StreamTxs),
    #[clap(hide(true))]
    /// Warn: Publishing contracts is for testing purposes only on Testnet
    Publish(MovePackageDir),
    /// Execute arbitrary on-chain `entry` function
    GenerateTransaction {
        #[clap(
            short,
            long,
            help = indoc!{r#"
                Function identifier has the form <ADDRESS>::<MODULE_ID>::<FUNCTION_NAME>

                Example:
                0x1::coin::transfer
            "#}
        )]
        function_id: String,

        #[clap(
            short,
            long,
            help = indoc!{ r#"
                Type arguments separated by commas

                Example:
                'u8, u16, u32, u64, u128, u256, bool, address, vector<u8>, signer'
                '0x1::diem_coin::AptosCoin'
            "#}
        )]
        type_args: Option<String>,

        #[clap(
            short,
            long,
            help = indoc!{ r#"
                Function arguments separated by commas

                Example:
                '0x1, true, 12, 24_u8, x"123456"'
            "#}
        )]
        args: Option<String>,
    },
}

impl TxsCli {
    /// Executes the transaction CLI command based on parsed arguments.
    pub async fn run(&self) -> Result<()> {
        // Load application configuration
        let app_cfg = AppCfg::load(self.config_path.clone())?;
        let profile = app_cfg.get_profile(None)?;

        // Determine private key based on CLI options or prompts
        let pri_key = if let Some(pk) = &self.test_private_key {
            println!("using private key from cli args --test-private-key");
            Ed25519PrivateKey::from_encoded_string(pk)?
        } else if let Some(m) = &self.mnemonic {
            println!("using private key from cli args --mnemonic");
            let legacy = get_keys_from_mnem(m.to_string())?;
            legacy.child_0_owner.pri_key
        } else if let Ok(p) = profile.borrow_private_key() {
            println!("use private key from test libra-cli-config.yaml");
            p.to_owned()
        } else {
            let legacy = get_keys_from_prompt()?;
            legacy.child_0_owner.pri_key
        };

        // Determine chain ID and URL for client
        let chain_name = self
            .chain_name
            .unwrap_or(app_cfg.workspace.default_chain_id);

        let url = if let Some(u) = self.url.as_ref() {
            u.to_owned()
        } else {
            app_cfg.pick_url(Some(chain_name))?
        };

        // Initialize client
        let client = Client::new(url);

        // Initialize sender
        let mut send = Sender::new(
            AccountKey::from_private_key(pri_key),
            ChainId::new(chain_name.id()),
            Some(client),
            self.legacy_address,
        )
        .await?;

        // Handle mutually exclusive options for transaction cost
        if self.tx_cost.is_some() && self.tx_profile.is_some() {
            println!("ERROR: --tx-cost and --tx-profile are mutually exclusive. Either set the costs explicitly or choose a profile in libra-cli-config.yaml, exiting");
        }

        // Determine transaction cost
        let tx_cost = self
            .tx_cost
            .clone()
            .unwrap_or_else(|| app_cfg.tx_configs.get_cost(self.tx_profile.clone()));

        // Set transaction cost for sender
        send.set_tx_cost(&tx_cost);

        // Execute subcommand based on parsed input
        match &self.subcommand {
            Some(TxsSub::Transfer { to_account, amount }) => {
                send.transfer(to_account.to_owned(), amount.to_owned(), self.estimate_only)
                    .await?;
                Ok(())
            }
            Some(TxsSub::Publish(move_opts)) => {
                let payload = encode_publish_payload(move_opts)?;
                send.sign_submit_wait(payload).await?;
                Ok(())
            }

            Some(TxsSub::GenerateTransaction {
                function_id,
                type_args: ty_args,
                args,
            }) => send.generic(function_id, ty_args, args).await,
            Some(TxsSub::Validator(val_txs)) => val_txs.run(&mut send).await,
            Some(TxsSub::Governance(upgrade_txs)) => upgrade_txs.run(&mut send).await,
            Some(TxsSub::User(user_txs)) => user_txs.run(&mut send).await,
            Some(TxsSub::Community(comm_txs)) => comm_txs.run(&mut send).await,
            Some(TxsSub::Stream(stream_txs)) => {
                let arc_send = Arc::new(Mutex::new(send));
                stream_txs.start(arc_send);
                Ok(())
            }
            _ => {
                println!(
                    "\n\"I'm searching, though I don't succeed
But someone look, there's a growing need
Oh, he is lost, there's no place for beginning
All that's left is an unhappy ending\"
\n... did you forget a subcommand?"
                );
                Ok(())
            }
        }
    }
}

/// Converts an account address to a legacy format (v5).
pub fn to_legacy_address(address: &AccountAddress) -> anyhow::Result<AccountAddress> {
    // trim the first 16 bytes for legacy v5 address
    let mut address_str = address.to_string();
    if address_str.len() >= 32 {
        let rest = &address_str[32..];
        address_str = format!("{:0<32}{}", "", rest);
    }

    AccountAddress::from_hex_literal(&format!("0x{}", address_str)).map_err(|e| anyhow::anyhow!(e))
}
