
module ol_framework::not_my_friend {
// Context: In OL all games are a) opt-in b) peer-to-peer. There is no desire
// to have elected comittees to determing network-wide policies. Instead tools
// are created to allow users to declare what games they want to play and with
// whom.

// Problem: people want to know if they are safe, and will only engage in games
// that feel safe. But, blockchains should never censor people. Even
// if you thought it was a good idea, you create a governance problem
// where you'd need a comittee to decide who is good and bad, and then tribunals
// to figure that all out. You've basically reinvented governments.
// The starting place for all blockchains is that people self-select into
// groups, and choose their trusted peers.
// What about the inverse? How do users choose to drop peers? In massively
// scalable communities it's hard for users to always keep track of actors that
// they would ordinarily not want to play games (do business) with.
// Proposal: any user (alice) can publish a list of "not friends. Bob, can
// opt-in and subscribe to this list (and other lists) and request that the
// Libra framework prevent automated actions relatedt to Bob's account happen
// with the list of Alice's non-friends. AKA opt-in network filtering.

}
