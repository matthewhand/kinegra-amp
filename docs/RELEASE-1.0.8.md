# ShieldAmp 1.0.8

*Historical release notes from before the Kinegra Amp rebrand.*

Save a current/upcoming local-file queue with up to1,024 entries and keep its order for offline playback. The local queue now pages32 rows at a time. Idle queues without a current index start copying at the first track. Empty, oversized and unavailable-position errors are distinct. This completes the1.0.7 offline-copying path with the same host-helper setup, integrity checks and bounded streaming recovery. [Setup and limits](OFFLINE-COPYING.md).

Host checks cover queue paging, selection/removal across pages, persisted order, cancellation, corrupted transfers, local decode/seek and own-output recovery. No music, private covers or runtime credentials are distributed. Physical acceptance is recorded separately.
