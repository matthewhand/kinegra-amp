# Browsing Music Assistant with a remote

Open **Music Assistant**, choose Tracks or Playlists, then use Up/Down to highlight an item. The first returned row is selected automatically. Press **OK** on a playlist to open its tracks; **OK** on a track explicitly adds it to the queue. Arrow keys never add music.

Press **Right** from the list to reach **Play**, then **Right** again to reach **Add to Queue**. These actions remain visible. **Left** returns to the same highlighted row. **Play** plays the selected track or playlist here in Kinegra Amp, preserving the remaining queue. The main player’s Play button resumes its existing queue. **Add to Queue** appends without starting playback; adding a playlist asks Music Assistant to expand that playlist. **Queue Page** adds only the available tracks displayed on this returned page.

After an accepted Add response, the actions show confirmation and focus **View Queue**. That button opens this app’s Music Assistant queue; it does not change an offline track currently playing. Back from Queue returns to the library and its selection. Missing or ambiguous replies are not success and are never automatically retried.

Selected names wrap within a bounded area. Focus a selected-title label and press OK for its complete text. The shorter page summary distinguishes shown items from the count returned by Music Assistant; detailed counts and preview/provider-total limitations remain available in its tooltip and the paging documentation.

Library and playback configuration open as separate popups so they cannot push the list or core actions out of view. Back closes the topmost popup first, returns from playlist tracks to playlists, then closes the library. Held/repeated button packets are consumed until release, and duplicate controller/native Back paths cannot close multiple surfaces. Android’s automatic SceneTree Back-to-quit is disabled; the app handles navigation itself.

Playback uses only the unique, ungrouped wrapper for Kinegra Amp’s current paired Sendspin client. No Cast or similarly named external player is a fallback. The explicit library action sends `player_queues/play_media` with `option=play`; Add uses `option=add`. The queue-preserving Play semantics were checked against [Music Assistant 2.10.7’s pinned queue loader](https://github.com/music-assistant/server/blob/76ad754a68abdd0bfd179b13a2807d44771ddf90/music_assistant/controllers/player_queues/queue_loader.py). No default enqueue option or queue replacement is used.

Synthetic native-GUI and loopback HTTP tests exercise these paths without contacting an owner server. Physical remote/provider acceptance remains separate.
