

pub fn start() -> anyhow::Result<()> {
    // Create a test database
    let tmp_dir = TempPath::new();
    let db = DiemDB::open(
        &tmp_dir,
        false,
        NO_OP_STORAGE_PRUNER_CONFIG,
        RocksdbConfigs::default(),
        false,
        BUFFERED_STATE_TARGET_ITEMS,
        DEFAULT_MAX_NUM_NODES_PER_LRU_CACHE_SHARD,
    )
    .unwrap();
    let (_, db_rw) = DbReaderWriter::wrap(db);

    // Bootstrap the database
    let (node_config, _) = test_config();
    bootstrap_genesis::<DiemVM>(&db_rw, get_genesis_txn(&node_config).unwrap()).unwrap();

    // Create mempool and consensus notifiers
    let (mempool_notifier, _) = new_mempool_notifier_listener_pair();
    let (_, consensus_listener) = new_consensus_notifier_listener_pair(0);

    // Create the event subscription service and a reconfig subscriber
    let mut event_subscription_service = EventSubscriptionService::new(
        ON_CHAIN_CONFIG_REGISTRY,
        Arc::new(RwLock::new(db_rw.clone())),
    );
    let mut reconfiguration_subscriber = event_subscription_service
        .subscribe_to_reconfigurations()
        .unwrap();

    // Create a test streaming service client
    let (streaming_service_client, _) = new_streaming_service_client_listener_pair();

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
        TimeService::mock(),
        db_rw.reader.clone(),
        network_client,
        None,
    );
}
