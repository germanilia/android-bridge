# In-App Sync Relay and Brain Search Requirements Questions

The relay is now scoped as **in-app synchronization for all Android Bridge information**, not merely a TCP proxy for the existing live link. Your confirmed answer is already recorded in Question 1.

Please fill every remaining `[Answer]:` line with one listed letter. Use `X` and add details when no option fits.

## Question 1
Which information should the optional relay synchronize?

A) Everything Android Bridge handles: Second Brain notes, meeting text and selected meeting media, clipboard, notifications, SMS/call state, files, protocol events, and live feature traffic when both apps are online

B) Only the current direct device-link protocol traffic

X) Other (please describe after [Answer]: tag below)

[Answer]: A — confirmed in chat: “meetings, notes, clipboard, everything”

## Question 2
How should relay sync coexist with the current direct link and Syncthing-based Second Brain?

A) Prefer direct LAN and local folders; use the relay as an automatic in-app fallback and synchronization path when direct connectivity is unavailable

B) When configured, make the relay the primary sync path and keep direct LAN/Syncthing only as fallback paths

C) Replace Syncthing for Second Brain whenever relay sync is enabled, while retaining direct LAN for live features

X) Other (please describe after [Answer]: tag below)

[Answer]: if lan is off immideielty fall abck to relay

## Question 3
What should happen while one app is offline or the Mac is asleep?

A) Keep a bounded, end-to-end encrypted server queue for asynchronous information; calls, screen control, and other live actions wait until both apps are online

B) Relay only live connections; both apps must be online, but they may be on different networks

C) Retain every supported asynchronous item until the destination reconnects, without a fixed storage bound

X) Other (please describe after [Answer]: tag below)

[Answer]: when one is a sleep the sync is paused and resumes from the last know place after reconnect

## Question 4
Which meeting data may leave its existing Mac meeting directory through relay sync?

A) Text only: metadata, summary, transcript, questions, status, and recording count; audio/photos remain Mac-local

B) Text plus meeting photos; audio remains Mac-local

C) Text, photos, and meeting audio recordings

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 5
How will the phone and Mac reach the home server?

A) Tailscale-only private access

B) Public HTTPS domain through the existing reverse proxy

C) Support both Tailscale and a public HTTPS domain

X) Other (please describe after [Answer]: tag below)

[Answer]: it shuold be configurable, but im using private tailsscale

## Question 6
What connection policy should the apps use?

A) Prefer direct LAN; automatically fall back to the configured relay

B) Prefer relay; automatically fall back to direct LAN

C) Let the user manually choose Direct or Relay each time

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 7
How should the relay be packaged for the home server?

A) Docker Compose service with persistent encrypted queue storage, health check, and reverse-proxy instructions

B) Single native executable managed by systemd

C) Add it to an existing home-server stack (describe that stack using X)

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 8
How should relay enrollment work?

A) Generate a one-time setup code on the relay; enroll the Mac, then reuse Android Bridge pairing to authorize the phone

B) Manually create one relay token and paste it into both apps

C) Use Tailscale identity only, with no additional relay credential

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 9
Where should relay settings be configured?

A) Configure URL and enrollment on the Mac, then transfer the configuration to Android through a QR code

B) Configure URL and credential separately in both apps

C) Use a configuration file on both devices

X) Other (please describe after [Answer]: tag below)

[Answer]: b

## Question 10
What maximum offline queue retention should apply?

A) 24 hours and 100 MB per paired device

B) 7 days and 1 GB per paired device

C) 30 days and 5 GB per paired device

X) Other (please describe retention time and size after [Answer]: tag below)

[Answer]:the offlien is no limted, the informatoin reams as is and when connected the sync happens on all delta

## Question 11
How should conflicting note edits made on both devices while offline be handled?

A) Preserve both versions and show a conflict in Brain for manual resolution

B) Last completed upload wins, while preserving the replaced version in history

C) Automatically merge non-overlapping Markdown edits and preserve both versions when merging fails

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 12
What should Brain search do when searching for `games` and `Personal/Games` is a folder?

A) Return the matching folder even when empty; opening it reveals that folder in the Brain tree

B) Return the folder and every note beneath it

C) Search only notes, but include notes whose parent-folder path matches `games`

X) Other (please describe after [Answer]: tag below)

[Answer]: curreny it acts ok, no changes here

## Question 13
Where should folder-aware Brain search be fixed?

A) Android only, where the problem was observed

B) Android and macOS so both apps behave consistently

X) Other (please describe after [Answer]: tag below)

[Answer]: no issue

## Question 14
Should the resiliency baseline be enabled for this relay feature?

A) Yes — apply availability, reconnect, recovery, observability, and failure-testing guidance

B) No — use only explicitly requested reliability behavior

X) Other (please describe after [Answer]: tag below)

[Answer]: b

## Question 15
Should security extension rules remain blocking for this internet-reachable relay?

A) Yes — enforce authentication, authorization, end-to-end encryption, rate limits, safe logging, least privilege, and supply-chain controls

B) No — skip the security baseline

X) Other (please describe after [Answer]: tag below)

[Answer]: it will be private completu behind tailscale so minimal security

## Question 16
How should property-based testing apply to relay framing, queue invariants, conflict handling, and serialization?

A) Full — enforce all applicable property-based testing rules

B) Partial — enforce round trips, invariants, generator quality, shrinking/reproducibility, and framework rules

C) No — use example-based and integration tests only

X) Other (please describe after [Answer]: tag below)

[Answer]: A
