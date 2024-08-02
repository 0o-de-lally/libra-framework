use diem_debugger::DiemDebugger;
// use diem_sdk::types::account_address::AccountAddress;
// use diem_validator_interface::DebuggerStateView;
use libra_types::exports::Client;
// use diem_vm::data_cache::StorageAdapter;
use diem_vm::move_vm_ext::SessionExt;
use move_core_types::{language_storage::StructTag, value::serialize_values};
use move_vm_types::gas::UnmeteredGasMeter;

#[tokio::test(flavor = "multi_thread", worker_threads = 1)]
async fn test_init_debugger() {
    let url_string = "https://rpc.0l.fyi";
    let client = Client::new(url_string.parse().unwrap());

    let d = DiemDebugger::rest_client(client).unwrap();
    let version = d.get_latest_version().await.unwrap();

    // let r = d.execute_past_transactions(version - 100, 10).await;

    let r = d.run_session_at_version(version, |session| {
        view_function_test(session).unwrap();
        Ok(())
    });
    dbg!(&r);

    // d.debugger
    // let state_view = DebuggerStateView::new(d.debugger, version);

    // let state_view_storage = StorageAdapter::new(&state_view);

    // dbg!(state_view_storage.);
}

fn view_function_test(session: &mut SessionExt) -> anyhow::Result<()> {
    // let vm_signer = MoveValue::Signer(AccountAddress::ZERO);

    let function_tag: StructTag = "0x1::proof_of_fee::get_consensus_reward".parse().unwrap();
    // let args = vec![
    //         &vm_signer,
    //         // note: any address would work below
    //         &vm_signer,
    //     ];
    let res = session
        .execute_function_bypass_visibility(
            &function_tag.module_id(),
            function_tag.name.as_ident_str(),
            function_tag.type_params,
            serialize_values(vec![]),
            &mut UnmeteredGasMeter,
        )
        .unwrap();

    // let b = session.data_cache;

    dbg!(&res);

    Ok(())
}
