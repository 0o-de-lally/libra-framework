// MACHINE GENERATED CODE

use diem_sdk::move_types::{
    ident_str,
    identifier::IdentStr,
    language_storage::TypeTag,
    move_resource::{MoveResource, MoveStructType},
};
use move_core_types::account_address::AccountAddress;

// Mapping of Move structs to Rust types

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FixedPoint32Resource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for FixedPoint32Resource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::fixed_point32");
    const STRUCT_NAME: &'static IdentStr = ident_str!("FixedPoint32");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for FixedPoint32Resource {}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ACLResource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for ACLResource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::acl");
    const STRUCT_NAME: &'static IdentStr = ident_str!("ACL");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for ACLResource {}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct BitVectorResource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for BitVectorResource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::bit_vector");
    const STRUCT_NAME: &'static IdentStr = ident_str!("BitVector");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for BitVectorResource {}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FeaturesResource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for FeaturesResource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::features");
    const STRUCT_NAME: &'static IdentStr = ident_str!("Features");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for FeaturesResource {}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct OptionResource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for OptionResource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::option");
    const STRUCT_NAME: &'static IdentStr = ident_str!("Option");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for OptionResource {}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct StringResource {
    validators: Vec<AccountAddress>,
}

impl MoveStructType for StringResource {
    const MODULE_NAME: &'static IdentStr = ident_str!("0x1::string");
    const STRUCT_NAME: &'static IdentStr = ident_str!("String");

    fn type_params() -> Vec<TypeTag> {
        vec![]
    }
}

impl MoveResource for StringResource {}
