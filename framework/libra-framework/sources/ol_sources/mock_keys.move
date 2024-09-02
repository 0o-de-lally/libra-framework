// Diem platform uses compilation flags for their binaries, e.g. "testing"
// the testing flag is used to create a test-only vm
// we think this is not a great practice and is confusing.
// really the only functions used by the vm in testing mode are
// key generation utilities.
// This should be handled by the test runner in a different way.
// for now we will use a mock generator with a number of fixtures.


// Some fixtures are complex and are repeatedly needed
#[test_only]
module ol_framework::mock_keys {
    use diem_std::ed25519;
    // use diem_std::bls12381;
    use std::debug::print;

    #[test]
    ///  NOTE: you will need a libra or diem binary compiled with "testing" flag for these helpers to work.
    fun ed25519_create_and_check(): (ed25519::SecretKey, ed25519::ValidatedPublicKey) {
      let (new_sk, new_pk) = ed25519::generate_keys();
      let upk = ed25519::public_key_into_unvalidated(new_pk);

      // print(&new_sk);
      let msg1 = b"Hello Diem!";
      let sig1 = ed25519::sign_arbitrary_bytes(&new_sk, msg1);
      assert!(ed25519::signature_verify_strict(&sig1, &upk, msg1), 73570001);
      return (new_sk, new_pk)
    }

    #[test]
    ///  NOTE: you will need a libra or diem binary compiled with "testing" flag for these helpers to work.
    fun ed25519_factory() {
      let i = 0;
      while (i < 5) {
        let (new_sk, new_pk) = ed25519_create_and_check();
        print(&new_sk);
        print(&new_pk);
        i = i + 1;
      }
    }

  #[test]
  public fun mock_generate() {
      // let sk_1 = ed25519::SecretKey {
      //   bytes: b"0x0cb6f6116b7f79221854098f712cf35c16afa0db04f2f6b52732c5583d391a24"
      // };

      let pk_1 = ed25519::new_validated_public_key_from_bytes(1434238021383504737485146965592440853489457569744095795323619019547692433196u256);

      // let pk_1 = ValidatedPublicKey {
      //   bytes: 0x032bbffce797707bc8fefbbc8464350e7458d73c2c52e0a149725ae98646ff2c
      // }

      print(&pk_1);

  }
  //   public fun generate_identity(): (bls12381::SecretKey, bls12381::PublicKey, bls12381::ProofOfPossession) {
  //     let (sk, pkpop) = bls12381::generate_keys();
  //     let pop = bls12381::generate_proof_of_possession(&sk);
  //     let unvalidated_pk = bls12381::public_key_with_pop_to_normal(&pkpop);
  //     (sk, unvalidated_pk, pop)
  // }

  // public fun mock_multi_ed25519_generate_keys


  // let (curr_sk, curr_pk) = multi_ed25519::generate_keys(2, 3);

}
