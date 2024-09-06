use diem_framework::{build_model, ReleaseOptions};
use move_model::ty::Type;
use std::fs;

pub fn create_rust_struct_models(release_opts: &ReleaseOptions) -> anyhow::Result<()> {
    let ReleaseOptions {
        build_options,
        packages,
        rust_bindings,
        output,
    } = release_opts.clone();

    for (package_path, _rust_binding_path) in packages.into_iter().zip(rust_bindings.into_iter()) {
        let model = &build_model(
            build_options.dev,
            package_path.as_path(),
            build_options.named_addresses.clone(),
            None,
            build_options.bytecode_version,
        )?;

        let mut file = RUST_IMPORTS.to_owned();

        for m in model.get_modules() {

            let module_name = m.get_full_name_str();
            for s in m.get_structs() {
                let struct_name = s.get_name().display(s.symbol_pool()).to_string();

                let fields: Vec<(String, Type)> = s.get_fields().map(|f| {
                    let name = f.get_name().display(s.symbol_pool()).to_string();
                    let ty = f.get_type();
                    (name, ty)
                })
                .collect();

                let code_gen = generate_resource_string(&module_name, &struct_name, fields);
                file = file + &code_gen;
            }
        }
        println!("{:#?}", &file);
        let out_path = output.unwrap_or(package_path.as_path().join("struct_map.rs"));
        let _ = fs::write(&out_path, file.as_bytes());

        std::process::Command::new("rustfmt")
            .arg("--config")
            .arg("imports_granularity=crate")
            .arg(&out_path)
            .status()?;
    }

    Ok(())
}

pub const RUST_IMPORTS: &str = "
// MACHINE GENERATED CODE

use diem_sdk::move_types::{
    ident_str,
    identifier::IdentStr,
    language_storage::TypeTag,
    move_resource::{MoveResource, MoveStructType},
};
use move_core_types::account_address::AccountAddress;

// Mapping of Move structs to Rust types
";

pub fn generate_resource_string(
    module_name: &str,
    struct_name: &str,
    field_envs: Vec<(String, Type)>,
) -> String {
    populate_fields(field_envs);

    let rust_def = format!(
"
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct {struct_name}Resource {{
    validators: Vec<AccountAddress>,
}}

impl MoveStructType for {struct_name}Resource {{
    const MODULE_NAME: &'static IdentStr = ident_str!(\"{module_name}\");
    const STRUCT_NAME: &'static IdentStr = ident_str!(\"{struct_name}\");

    fn type_params() -> Vec<TypeTag> {{
        vec![]
    }}
}}

impl MoveResource for {struct_name}Resource {{}}
"
    );

    return rust_def;
}

fn populate_fields(field_envs: Vec<(String, Type)>) -> String {
  let mut fields_str = "".to_string();
  for f in field_envs {
    match f {

    }
    fields_str = format!("{}\n{}: {:?}", fields_str, f.0, f.1);
  }
  fields_str
}

#[test]
fn try_get_defs() {
    use crate::release::ReleaseTarget;
    let target = ReleaseTarget::Head;
    let opts = target.create_release_options(false, None);
    create_rust_struct_models(&opts).expect("cannot generate models");
}
