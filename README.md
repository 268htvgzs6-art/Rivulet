## About this fork (1.6.5)

This is a community fork of [l984-451/Rivulet](https://github.com/l984-451/Rivulet), based on Rivulet 1.3.1 (129). It is not affiliated with or endorsed by Rivulet's author, and the upstream repository remains the official app. Each change is its own commit, so it can be offered upstream on its own.

Changes in 1.6.5:

- Player: a touch-surface swipe scrubs only while the video is paused, as in Apple's player, and Select after a scrub lands there and plays (from upstream; the clock toggle is unchanged) (tvOS)
- From upstream 1.3.1 (132): AetherEngine 7.71.0, the display mode asked for before a server conversion loads (no black screen with Match Dynamic Range, #677), hidden libraries kept out of the Home hero on every server, multichannel surround music, and no asset-pack crash on a free Apple ID (#696)

Changes in 1.6:

- Scrolling: up and down on Home, libraries, Search and the detail, season and person pages use the system's own focus scrolling (upstream #631); sideways rows keep the fork's spring (tvOS)
- Player: the first Down shows the play bar, and the next Down opens the Info pane; Back on the bar a skip shows closes it instead of leaving the video (tvOS)
- Home: the featured title's buttons start on Next, so one click moves to the next title (tvOS)
- Defaults: 15 second skips both ways, Arabic subtitles when the audio is not English, and IMDb on the detail page's rating row, applied once over earlier settings. Rotten Tomatoes no longer stands in for a missing IMDb score
- From upstream 1.3.1: Dolby Vision stays on with any audio track, Plex works over the LAN when plex.tv is down, playback falls back between the original file and a transcode, AetherEngine 7.69.0, Up Next with Countdown Off, Live TV freezes fixed, aspect ratio in Information, Unwatched counts episodes, Top Shelf episode names, a grid keyboard for Search, Stereo with Subwoofer, loudness levelling, skip-back subtitle limits, a redacted profile PIN in error reports, and Jellyfin and Emby fixes

Changes in 1.5:

- Theme music: a TV show's theme tune plays once, quietly, on its show, season and episode pages, with Theme Music and Theme Music Volume in Settings > Appearance (tvOS, Plex servers)
- Home: the background is dark once focus leaves the hero, and resting on a tile for two seconds fades the rest of the page out for that title's backdrop
- Poster Spotlight in Settings > Appearance turns that held-tile backdrop off, or sets its wait to 1, 2, 3 or 5 seconds (tvOS)
- Theme music: a small note on a show's, season's and episode's page marks a show that has a tune, with a ring while the tune loads (tvOS, Plex servers)
- Season posters: a show with two or more seasons lists them as posters that open the season page; Settings > Appearance > Seasons switches back to the episode row (tvOS)
- Anime: a MyAnimeList score beside the rating on anime pages, read from a scores file bundled at build time. The file is not in the repository, so a build without it shows nothing (tvOS)
- The IMDb mark is drawn as a ticket stub
- Player: a Skip Intro / Skip Credits button shows with focus for 3 seconds after the controls or the seek bar hide, then fades and hands focus back to the video; the controls still offer it (tvOS)
- Player: playback starts with the controls hidden (tvOS)
- Privacy: the developer's online extras, Plex's online age guidance and Plex's online actor details are off unless switched on in Settings > About > Privacy (switches on tvOS; off on iOS and Mac)
- Fast Up and Down runs on Home no longer brake on every press
- Detail, season and person pages, the music queue and held-arrow scrolling are timed to the displayed frame
- Less work per episode card and show badge
- A poster tile no longer flashes the failed icon while it reloads the same poster
- A collection the server features in a library can be pinned to that library page
- Swipe to scrub on a title of unknown length no longer leaves the bar at 0:00
- The player's Font list shows current labels
- A remote skip during fast-forward no longer stops the fast-forward
- Playback falls back to the original file when the server refuses a quality transcode

Changes in 1.4:

- Home and shelf rows scroll on a spring timed to the displayed frame, and Home's scroll stops when it lands
- Home's vertical scroll lands softly, with momentum on repeated presses
- Detail pages and the music queue settle in 0.35 s
- Posters do less work per tile while scrolling, with solid artwork on tvOS 27
- Less main-thread work while browsing
- Home and library posters download in the background
- Library: Up from any grid column reaches the header buttons
- Library: a poster opens straight to its full-screen detail
- Library: one Recently Added row above the grid
- Home builds a page's rows when it opens, not while scrolling
- Home has no full-screen blur behind the rows
- Detail: IMDb scores show IMDb's yellow badge
- Detail: no Starring line beside the action buttons
- Detail: one card per episode, and Select plays it
- Preview card: a chevron hints that Down opens the full details
- Subtitles: Subtitle Brightness, a font choice from the Apple TV's Arabic fonts, and Apple's downloadable Arabic fonts
- iCloud Sync: no launch crash in a build without the iCloud entitlement
- Swipe to scrub starts only on a clearly sideways swipe, and the playhead follows the finger
- Player: Up from a pane's tabs closes the pane, and Down with the controls up moves to the tabs
- Skip pill: Up and Down land in the controls in one move

Same license as upstream: [PolyForm Noncommercial 1.0.0](LICENSE). The fork carries no signing changes and no optional engine build options; to install it, set your own team, bundle identifiers and app group in Xcode and sign it with your own Apple ID. The build steps are under Building below.

---

<div align="center">

<img src="Branding/logo_glow_transparent.png" alt="Rivulet" width="220">

# Rivulet

**Built for simplicity.**

A native Apple TV app for Plex, Jellyfin, Emby, and Live TV.

<a href="https://apps.apple.com/us/app/rivulet-for-plex/id6756892857">
  <img src="https://img.shields.io/badge/Download_on_the-App_Store-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store">
</a>
&nbsp;
<a href="https://testflight.apple.com/join/TcCsF5As">
  <img src="https://img.shields.io/badge/Join_the-TestFlight_Beta-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Join the TestFlight Beta">
</a>

</div>

---

<div align="center">

<img src="Screenshots/tvOS/01-home.jpg" alt="Home" width="100%">

</div>

<div align="center">

<img src="Screenshots/tvOS/02-detail.jpg" alt="Movie detail" width="49%">
<img src="Screenshots/tvOS/07-music-album.jpg" alt="Music album" width="49%">

</div>

---

<br></br> 

**Rivulet is built for Apple TV first. I care a lot about its speed, performance, and simplicity in tvOS.**

**If you like it, please share it around.**

This project is opinionated. All suggestions and ideas are always welcome, but please don’t be offended if I decline an enhancement or feature suggestion. 

_A camel is a horse designed by a committee. I don’t want Rivulet to be a camel._


## Why this exists
I began this project in Decemeber 2025. At the time there was quite a lack of Plex player alternatives, especially for tvOS (not much so anymore). My goals for the app were/are:
- **Simplicity**: what is the best design to get me to the media I want to watch.
- **Live TV**: Plex's live TV is, to put it nicely, sub-par. I've spent too long trying to get it to work well for me (kudos if you don't have this problem). I don't want live TV in a separate app, so this solves my problems.
- **HomePod Integration**: the Plex app has never worked well when setting HomePod as the default audio output on my Apple TV. It hurts to have a HomePod sitting there collecting dust while my sub-par TV speakers play sound. This app helps the hurt.
- **Apple-Esque**: I enjoy Apple’s designs and apps, and enjoy the challenge of creating an app that feels native to the Apple ecosystem.
<br></br>

## Live TV

Rivulet works with several kinds of Live TV source. You don't need a Plex, Jellyfin, or Emby server. Add just a Live TV source and the app opens straight to Live TV.

- **What's On**: what's airing now, what starts soon, and a For You row that learns what you watch.
- **Guide**: standard guide layout if you want.
- **Multiview**: watch up to four channels at once.
- **Scores**: live scores if thats your thing. NFL, college football, NBA, MLB, and NHL.
- **Sources**: Dispatcharr, Plex Live TV (HDHomeRun and DVB tuners), Xtream Codes, and any M3U/XMLTV playlist.

<div align="center">

<img src="Screenshots/tvOS/03-whats-on.jpg" alt="What's On" width="49%">
<img src="Screenshots/tvOS/04-multiview.jpg" alt="Multiview" width="49%">

</div>
<br></br>

## Insights

This is a fun one. Open insights from the bottom row buttons while playing media. You get trivia about the movie or episode you’re watching: production stories, casting, adaptation changes, fan lore, and more.

<div align="center">

<img src="Screenshots/tvOS/05-insights-trivia.jpg" alt="Insights trivia" width="49%">
<img src="Screenshots/tvOS/06-insights-cast.jpg" alt="Insights cast" width="49%">

</div>
<br></br>

## Video player

Playback runs on [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

- **Containers**: MKV, MP4, WebM, MPEG-TS, AVI, WMV, OGG, FLV, and more.
- **Video**: H.264 and HEVC (including 10-bit) decode in hardware. AV1, VP9, MPEG-2, VC-1, MPEG-4 Part 2, and almost anything else FFmpeg can decode play in software. Interlaced broadcasts are deinterlaced on the GPU.
- **HDR**: HDR10, HDR10+, HLG, and Dolby Vision profiles 5, 8.1, and 8.4. On a Dolby Vision TV, Profile 7 plays as 8.1, and a FEL title keeps most of its enhancement layer's picture. Without one, it plays its HDR10 base layer.
- **Audio**: Apple TV can't bitstream audio, so everything goes through tvOS. AAC, AC3, E-AC3, FLAC, and ALAC are handed to tvOS as-is, and it outputs them the same way it does in Apple's own apps. Atmos in E-AC3 reaches an Atmos receiver as Dolby MAT, and everything else goes out as multichannel PCM or Dolby Digital, depending on your Apple TV audio settings. TrueHD, DTS, DTS-HD MA, Opus, Vorbis, and PCM are decoded by Rivulet first and reach tvOS as lossless multichannel audio. TrueHD and DTS-HD MA stay lossless at up to 7.1, but your receiver will show PCM instead of the original format.
- **Subtitles**: SRT, ASS/SSA, and WebVTT, plus image subtitles (PGS, DVB, DVD/VobSub), CEA-608 closed captions, DVB teletext, and external subtitle files from your server. ASS/SSA renders through libass with its original styling and embedded fonts.
- **Stream quality**: direct play by default, or pick a transcode quality when bandwidth is tight.
- **Content filtering** (work in progress): mute language and skip scenes on your device, from the title's subtitles or an imported EDL list. The file is never touched.

<br></br>

## Music

- Album, artist, and playlist browsing, modeled on Apple's Music app for tvOS. I think its beautiful.
- Lyrics, synced when the source provides timestamps.
- System Now Playing controls. HomePod, AirPods, Siri Remote, and Control Center all work.

<div align="center">

<img src="Screenshots/tvOS/08-music-library.jpg" alt="Music library" width="49%">
<img src="Screenshots/tvOS/09-now-playing.jpg" alt="Now Playing" width="49%">

</div>
<br></br>

## iPhone and iPad

The iOS app follows the Apple TV app and should have all the features one needs. It shares the same Core code as the tvOS app.

<div align="center">

<img src="Screenshots/iOS/01-home.jpg" alt="iPhone home" width="24%">
<img src="Screenshots/iOS/02-movie.jpg" alt="iPhone movie detail" width="24%">
<img src="Screenshots/iOS/03-show.jpg" alt="iPhone show detail" width="24%">
<img src="Screenshots/iOS/04-library.jpg" alt="iPhone library" width="24%">

</div>

---
<br></br>
> [!IMPORTANT]
> ## Rivulet is free, but not for sale.
>
> Licensed under [PolyForm Noncommercial 1.0.0](LICENSE). You may **clone it, run it, modify it, share it, and contribute back** for personal, educational, research, hobby, or any other noncommercial use.
>
> You may **not** sell Rivulet, charge for access to it, or bundle it (or any derivative of it) into a paid app, product, or service. **Anything derived from this code inherits the same restriction.** I'd rather give this away than watch someone else charge for it.

---
<br></br>

## Building

Requires Xcode 27. Copy the secrets template once (placeholder values are fine), then open the project:

```bash
cp RivuletCore/Config/Secrets.swift.template RivuletCore/Config/Secrets.swift
open Rivulet.xcodeproj
```

`Rivulet` is the tvOS scheme and `Rivulet iOS` is the iPhone and iPad scheme. `Rivulet/` holds the tvOS app, `RivuletiOS/` the iOS app, and `RivuletCore/` the code both share. See `CLAUDE.md` for the architecture.
<br></br>

## Contributing

Found a bug? [Open an issue](../../issues/new/choose) and pick the platform (tvOS or iOS). If the same bug shows up on both, open one issue per platform so each fix is tracked on its own.

I welcome all contributions from any level of developer. I welcome contributions from LLMs too as long as they are checked and tested.

**If you do contribute, please build and test on an actual Apple TV. The simulator is close, but does not mimic the Apple TV fully.**

By submitting a pull request, you agree to license your contribution under the same terms as Rivulet (PolyForm Noncommercial 1.0.0, see [LICENSE](LICENSE)).
<br></br>

## License

Rivulet is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).

Everything here is free to use, read, fork, and build on. The only thing you can't do is sell it. I'd rather give this away than watch someone else charge for it.

In short: clone it, run it, modify it, share it, contribute back, for personal, educational, research, hobby, or other noncommercial use. You may not use Rivulet (or anything derived from it) for commercial purposes, including selling it, charging for access to it, or bundling it into a paid product or service.

This restriction is not decorative. If you ship Rivulet's code (in whole or in part, modified or not) inside something you sell, you are infringing the copyright in this project. If you spot a commercial app built on this code, please [open an issue](../../issues) so it can be reported to the relevant platform (App Store, GitHub, etc.).

Third-party components retain their original licenses. FFmpeg is included under LGPL-2.1+; libdovi under MIT. See [LICENSE](LICENSE) for details.
<br></br>

## Acknowledgments

- [AetherEngine](https://github.com/superuser404notfound/AetherEngine): the playback engine
- [FFmpeg](https://ffmpeg.org/): demuxing, decoding, and remuxing
- [libdovi](https://github.com/quietvoid/dovi_tool): Dolby Vision RPU handling
- [libass](https://github.com/libass/libass): ASS/SSA subtitle rendering
- [Plex](https://plex.tv/): media server platform
- [Jellyfin](https://jellyfin.org/): open source media server
- [Emby](https://emby.media/): media server platform
- [Dispatcharr](https://github.com/Dispatcharr/Dispatcharr): IPTV management
- [TMDB](https://www.themoviedb.org/): artwork and metadata for Discover

---

<div align="center">

Rivulet is not affiliated with or endorsed by Plex, Inc., the Jellyfin project, or Emby LLC.

Media used in the README is AI generated for copyright reasons.

</div>
