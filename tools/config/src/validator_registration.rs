use anyhow;
use diem_genesis::config::OperatorConfiguration;
use diem_types::account_address::AccountAddress;
use libra_types::global_config_dir;
use libra_wallet::validator_files::OPERATOR_FILE;
use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};

/// Public data structure for validators to register their nodes on chain
/// creating this depends on access to private keys.

// TODO: this matches the libra framework sdk ValidatorUniverseRegisterValidator, there may be other duplications elsewhere.

#[derive(Debug, Serialize, Deserialize)]
pub struct ValCredentials {
    pub account_address: AccountAddress,
    /// key for signing consensus transactions
    pub consensus_pubkey: Vec<u8>,
    /// proof that the node is in possession of the keys
    pub proof_of_possession: Vec<u8>,
    /// network addresses for consensus
    pub network_addresses: Vec<u8>,
    /// network addresses for public validator fullnode
    pub fullnode_addresses: Vec<u8>,
}

impl ValCredentials {
    /// given the operators private keys file at operator.yaml (usually)
    /// create the data structure needed for a registration transaction
    pub fn new_from_operator_file(operator_keyfile: Option<PathBuf>) -> anyhow::Result<Self> {
        let file = operator_keyfile.to_owned().unwrap_or_else(|| {
            let a = global_config_dir();
            a.join(OPERATOR_FILE)
        });

        let yaml_str = fs::read_to_string(file)?;
        let oc: OperatorConfiguration = serde_yaml::from_str(&yaml_str)?;

        let val_net_protocol = oc
            .validator_host
            .as_network_address(oc.validator_network_public_key)?;

        let vfn_list = if let Some(vfn_host) = oc.full_node_host {
            let key = oc
                .full_node_network_public_key
                .unwrap_or(oc.validator_network_public_key);
            let cfg = vfn_host.as_network_address(key)?;
            vec![cfg]
        } else {
            vec![]
        };

        Ok(ValCredentials {
            account_address: oc.operator_account_address.into(),
            consensus_pubkey: oc.consensus_public_key.to_bytes().to_vec(),
            proof_of_possession: oc.consensus_proof_of_possession.to_bytes().to_vec(),
            network_addresses: bcs::to_bytes(&vec![val_net_protocol])?,
            fullnode_addresses: bcs::to_bytes(&vfn_list)?,
        })
    }
    /// create the list of validators that need to be created on chain
    /// NOTE: this is for testnet purposes.
    pub fn new_from_file_list(files: Vec<PathBuf>) -> anyhow::Result<Vec<Self>> {
        let creds: Vec<Self> = files
            .into_iter()
            .map(|p| {
                println!("reading file: {}", p.display());
                Self::new_from_operator_file(Some(p)).expect("expected to parse operator.yaml")
            })
            .collect();
        Ok(creds)
    }
}
