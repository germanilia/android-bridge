# Business Rules — MCAL1

- **BR-1**: Stop capture before starting any expensive final work.
- **BR-2**: Never run LLM, Whisper, EventKit query, or Second Brain command on the main/network receive path.
- **BR-3**: Preserve serial chunk-before-finalize ordering per meeting.
- **BR-4**: Do not show a custom completion modal.
- **BR-5**: Event overlap uses strict interval intersection; boundary-only contact is not overlap.
- **BR-6**: One match may apply automatically; multiple matches require user choice.
- **BR-7**: Multiple-match UI always includes manual entry and no-event choices.
- **BR-8**: User-edited non-generic title/customer wins over calendar enrichment.
- **BR-9**: Generic email providers never become customer names.
- **BR-10**: Multiple external organizations produce no automatic customer.
- **BR-11**: Calendar access/failure never blocks local meeting readiness.
- **BR-12**: Second Brain transfer occurs only after explicit user action.
- **BR-13**: Calendar strings pass through existing safe filesystem/customer boundaries.
- **BR-14**: Do not log participant/event/private meeting content.
- **BR-15**: Interrupted finalization is recoverable from retained meeting files.
