module ol_framework::filo_migration {
  use ol_framework::activity;
  use ol_framework::donor_voice;
  use ol_framework::founder;
  use ol_framework::page_rank_lazy;
  use ol_framework::reauthorization;
  use ol_framework::slow_wallet;
  use ol_framework::vouch;
  use std::signer;
  use std::error;

  friend diem_framework::transaction_validation;
  #[test_only]
  friend ol_framework::mock;

  /// Error codes
  /// Cannot be used by donor voice accounts
  const EDONOR_VOICE: u64 = 1;
  /// Cannot be used by accounts that have already been authorized for v8
  const EALREADY_AUTHORIZED: u64 = 2;

  // Welcome to Level 8

  // It's a quest, it's a quest
  // For the golden prize, the prize that never dies
  // For a dream that's worth the fight, worth the chase
  // It's a journey, it's a race.
  public entry fun maybe_migrate(user_sig: &signer) {
    // community wallets should not do this migration
    let addr = signer::address_of(user_sig);
    assert!(!donor_voice::is_donor_voice(addr), error::invalid_argument(EDONOR_VOICE));

    // don't allow a v8-migrated account to accidentally migrate again
    assert!(!reauthorization::is_v8_authorized(addr), error::invalid_argument(EALREADY_AUTHORIZED));

    migration_impl(user_sig);
  }

  // FILO FTW
  fun migration_impl(user_sig: &signer) {
    // Rising up, back on the street
    // Did my time, took my chances
    // Went the distance, now I'm back on my feet
    // Just a man and his will to survive.

    // did this account exist before level 8?
    activity::migrate(user_sig);

    // I am the eye of the tiger
    // I am the founder of my destiny
    // I laid the ground for the things to be
    // I'm the spark, I'm the first, I'm the one who created the fire.
    founder::migrate(user_sig);

    // Good evening
    // You know my name
    // Look, look, look up the number
    // You know my name
    // That's right, look up the number
    // You, you know, you know my name
    // You, you know, you know my name
    // You know my name, ba ba ba ba ba ba ba ba ba
    vouch::init(user_sig);


    // Don't you know that I'm still standing better than I ever did?
    // Looking like a true survivor, feeling like a little kid
    // And I'm still standing after all this time
    // Picking up the pieces of my life without you on my mind

    // I'm still standing. Yeah, yeah, yeah
    // I'm still standing. Yeah, yeah, yeah
    page_rank_lazy::maybe_initialize_trust_record(user_sig);


    // All I want is to see you smile
    // If it takes just a little while
    // I know you don't believe that it's true
    // I never meant any harm to you

    // Don't stop thinking about tomorrow
    // Don't stop, it'll soon be here
    // It'll be better than before
    // Yesterday's gone, yesterday's gone
    slow_wallet::filo_migration_reset(user_sig);
  }


  #[test_only]
  public(friend) fun test_unchecked_migration(user_sig: &signer) {
    // This is a test-only function to allow migration without checks.
    // It should not be used in production code.
    migration_impl(user_sig);
  }

}
