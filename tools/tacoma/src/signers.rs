use diem_crypto::test_utils::KeyPair;
use diem_crypto::{
    bls12381::{PrivateKey, PublicKey},
    Uniform,
};
use diem_crypto_derive::{BCSCryptoHash, CryptoHasher};
use diem_types::account_address::AccountAddress;
use diem_types::validator_verifier::ValidatorConsensusInfo;
use rand_core::OsRng;
use serde::{Deserialize, Serialize};

#[derive(BCSCryptoHash, CryptoHasher, Deserialize, Serialize)]
pub struct Msg {
    content: String,
}

impl Msg {
    pub fn new(content: String) -> Self {
        Self { content }
    }
}

pub fn make_consensus_info(
    address: AccountAddress,
    key_pair: KeyPair<PrivateKey, PublicKey>,
) -> anyhow::Result<ValidatorConsensusInfo> {
    Ok(ValidatorConsensusInfo::new(address, key_pair.public_key, 1))
}

// crates/diem-crypto/src/unit_tests/bls12381_test.rs
pub fn rando() -> anyhow::Result<(AccountAddress, KeyPair<PrivateKey, PublicKey>)> {
    let addr = AccountAddress::random();
    let mut rng = OsRng;
    let key_pair = KeyPair::<PrivateKey, PublicKey>::generate(&mut rng);

    Ok((addr, key_pair))
}

#[test]

fn test_rando() {
    use diem_crypto::SigningKey;

    let (_addr, key_pair) = rando().unwrap();

    // let message = b"Hello world";
    let m = Msg::new("hello".to_string());

    let signature = key_pair.private_key.sign(&m).unwrap();
    dbg!(&signature);
}
