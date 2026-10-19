# Notchy

## [0.3.0-alpha] - 2026-10-19

- **Ask about any day**, not only today: “che ho in agenda domani?”, “what is on my calendar on Friday?”, “cosa devo fare questa settimana?”. Notchy reads the calendars you ticked in Notcholino and the reminders it shows, for the days you asked, and answers in a few words, with the times. If there is nothing, it says so in your language. (Needs Notcholino 0.28.0.)
- The agenda of today is no longer added to every spoken request: it is read when you ask for it.

## [0.2.0-alpha] - 2026-10-19

- **Add things by voice.** Say it outright, in any language: “aggiungi al calendario dentista martedì alle 15”, “ricordami di chiamare Marco domani alle 10”, “annotati: comprare il latte”, “remind me to call Anna on Friday”. One AI call turns the sentence into a small JSON object (event, reminder, note, or just an answer), and plain code puts it in Calendar, Reminders or Notes. What was added is shown, with **Undo**. It only acts when you ask outright; otherwise it answers as before.
- Choose the calendar and the reminders list it writes to in Settings → Notchy → Day & email (or leave the Mac's defaults).

## [0.1.1-alpha] - 2026-10-19

- The store no longer lists capabilities Notchy does not have (running commands, Calendar access: the app reads the agenda for it).

## [0.1.0-alpha] - 2026-10-19

- Notchy is now an extension: installed from the Plugin Store and removed from it, like a plugin, instead of being part of the app. Its settings and keys are kept when you remove it, so installing it again picks up where you left off.
- Everything it already did: summaries of text, notes, code, PDFs and images (right-click → Send to Notchy), your day planned from the calendars you ticked, the weather and the time, a look at the screen, voice with a shortcut you record, email alerts through Mail, the cube with its moods and accessories, Silent / Normal / Lively.
