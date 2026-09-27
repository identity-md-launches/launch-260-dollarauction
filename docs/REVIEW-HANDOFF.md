# Independent review handoff

This is implementation evidence for a subsequent independent review. It is not an independent approval or a production-readiness claim. The reviewed manifest must name `LaunchToken` and exactly one application, `DollarAuction`, with the immutable token address supplied as `$token`. The approved network is Sepolia (11155111).

| Attack or failure | Reproducible evidence | Expected result |
| --- | --- | --- |
| Returning second/lower bidder miscounts the runner-up | `test_topUpsPreserveDistinctSecondHighestAndOnlyPullDifference`, `testFuzz_returningBidderPaysOnlyTopUp`, stateful ranking model | Only the new highest's delta is pulled; old highest becomes distinct second |
| A bid is both paid to seller and refunded | `test_reclaimsOnlyOtherBiddersOnceAfterSettlement`, accounting invariant | Final top two cannot reclaim; losers reclaim exactly once |
| A last-second bid races settlement | `test_lastSecondBidMakesOldDeadlineTooEarlyToSettle`, `test_exactDeadlineRejectsBidAndAllowsSettle`, `test_settleFirstAtDeadlineAlsoPreventsLateBid` | Before deadline bid can extend it; at deadline bidding fails and settlement succeeds |
| Withdrawal reentrancy | `test_withdrawReentrancySeesZeroCreditAndCannotDrainTwice` | Callback observes zero credit and guard error; exactly one payout |
| Revert after withdrawal effects | `test_revertingCallbackRestoresCreditAndUnlocksGuard` | Entire credit and escrow restored; retry succeeds |
| One recipient blocks everyone | `test_failedRecipientDoesNotBlockSettleOrOtherWithdrawalsAndCanRetry` | Settlement and another recipient's withdrawal succeed |
| Incoming token call fails | `test_failedBidLeavesRankAndDeadlineUnchanged`, `test_falseTransferFromRollsBackOpenAndBid` | No partial bid, rank, clock, count, or escrow changes |
| Reenter withdrawal during a bid payment | `test_bidTransferCallbackCannotWithdrawExistingCredit` | Cross-function guard preserves existing credit |
| Settlement work grows with bidder count | `test_settleWith200BiddersCostsExactlyTheSameAsWith2` | Equal measured gas with equal final ranking/credit state |
| Constructor takes launch supply or hidden runtime escape | `test_factoryConstructorsNeedNoInitializationOrApplicationFunding` | All supply remains with factory; app starts empty; runtime bounded with no forbidden opcodes |

The randomized handler recomputes top two by scanning participants, rather than using the implementation's replacement algorithm. It checks each expected credit, standing bid, timestamp, seller, prize and settlement flag, then verifies actual escrow equals actual outstanding obligations. `afterInvariant()` settles, reclaims, and withdraws all remaining balances. Test mocks that return false, omit return values, or invoke callbacks are confined to `test/` and do not change LaunchToken.

Review assumptions: the supplied currency must be the accepted fixed-supply ESCL artifact; no fee-on-transfer/rebasing tokens are supported; unsolicited ERC-20 transfers are surplus and cannot be recovered; forced ETH cannot be prevented or recovered. The auction is permissionless and identity is one address, not one human. There is no anti-collusion mechanism, deadline-extension limit, or ability to escape a losing top-two bid. Everyone relies on someone submitting settlement and on recipients submitting their own collection calls. Timestamp ordering is intentional and no randomness is used.

The service phase must independently link the accepted source, ABI, signed artifacts, policy and deployed bytecode. An incorrect constructor currency, privileged role, source binding or authorization remains a concrete review finding. This assignment supplies no manifest, live addresses, attestation, or wallet transaction.
