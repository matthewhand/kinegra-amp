# ShieldAmp 1.0.5

*Historical release notes from before the Kinegra Amp rebrand.*

- Optional key-free web control restricted to explicitly trusted private IPv4 ranges. Key authentication remains the default, and the production web listener remains off until enabled.
- Editable trusted addresses, CIDR blocks and start-end ranges. Invalid or public ranges are rejected; applied changes revoke existing web sessions.
- Play after reconnect rebuilds the saved queue stream instead of unpausing a stream that no longer exists. Existing streams retain normal unpause. No playback mutation is automatically retried.
- Playback failure messages stay visible instead of being overwritten by the audio-wait timer; the web status includes the TV’s playback detail.
- Private-LAN playback diagnostics distinguish a connection waiting for audio from a working audio stream. A successful Play request alone does not prove sound is arriving.

Music-free package; users supply their own music or Music Assistant library. Original code, artwork and hero media remain MIT; third-party components retain their own terms.
