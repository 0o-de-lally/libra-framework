use std::collections::HashMap;

use diem_config::config::NodeConfig;
use anyhow::anyhow;
use diem_data_client::client::DiemDataClient;
use libra_genesis_tools::genesis_reader;
use diem_storage_service_client::StorageServiceClient;
use diem_time_service::TimeService;

use diem_network::application::{interface::NetworkClient, storage::PeersAndMetadata};


pub fn get_node_cfg() -> anyhow::Result<NodeConfig> {
    let d = libra_types::global_config_dir();
    let val_file = d.join("validator.yaml");
    // A config file exists, attempt to parse the config
    NodeConfig::load_from_path(val_file.clone()).map_err(|error| {
        anyhow!(
            "Failed to load the node config file! Given file path: {:?}. Error: {:?}",
            val_file.display(),
            error
        )
    })
}

pub fn start() -> anyhow::Result<()> {
    let d = libra_types::global_config_dir();
    let genesis_path = d.join("genesis/genesis.blob");

    let tx = genesis_reader::read_blob_to_tx(genesis_path)?;
    let (db_rw, _) = genesis_reader::bootstrap_db_reader_from_gen_tx(&tx)?;

    let node_config = get_node_cfg()?;
    // Create mempool and consensus notifiers
    // let (mempool_notifier, _) = new_mempool_notifier_listener_pair();
    // let (_, consensus_listener) = new_consensus_notifier_listener_pair(0);

    // Create the event subscription service and a reconfig subscriber
    // let mut event_subscription_service = EventSubscriptionService::new(
    //     ON_CHAIN_CONFIG_REGISTRY,
    //     Arc::new(RwLock::new(db_rw.clone())),
    // );
    // let mut reconfiguration_subscriber = event_subscription_service
    //     .subscribe_to_reconfigurations()
    //     .unwrap();

    // Create a test streaming service client
    // let (streaming_service_client, _) = new_streaming_service_client_listener_pair();

    // Create a test diem data client
    let network_client = StorageServiceClient::new(NetworkClient::new(
        vec![],
        vec![],
        HashMap::new(),
        PeersAndMetadata::new(&[]),
    ));
    let (diem_data_client, _) = DiemDataClient::new(
        node_config.state_sync.diem_data_client,
        node_config.base.clone(),
        TimeService::real(),
        db_rw.reader.clone(),
        network_client,
        None,
    );

    let e = diem_data_client.get_response_timeout_ms();
    dbg!(&e);

    Ok(())
}
