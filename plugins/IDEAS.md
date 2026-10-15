# Plugin ideas

Things that would fit the notch and that nobody has built yet. Each is small. The **needs** column is what the plugin has to reach for; "nothing special" means only what the API already gives.

New here? Start with a **first plugin**: they teach one new thing each. Say in an issue that you are taking one, so two people don't build the same.

| Idea | What it does | Needs | Level |
| --- | --- | --- | --- |
| **Weather** | The temperature as the button, an hourly graph and the sunrise and sunset, from [Open-Meteo](https://open-meteo.com) (no key). | the network, a city picked in the options | first plugin |
| **World clocks** | The time in another city as the button, the others as read-only rows. | nothing special | first plugin |
| **Shortcuts** | Lists your Shortcuts as buttons and runs the one you pick (`shortcuts list`, `shortcuts run`). | the `shortcuts` tool | first plugin |
| **Break reminder** | A popup every so often to stand up, drink or rest your eyes, with a Pomodoro-like start and stop. | a timer | first plugin |
| **Speed** | Download and upload speed as the button (`↓12M`), with a graph. | network counters (`getifaddrs`) | easy |
| **Monitor** | CPU, memory and disk as the button, with graphs, like Hotter does for the temperature. | `host_statistics` | easy |
| **Downloads** | A popup when a file finishes downloading in your Downloads folder, with its name. | watching a folder | easy |
| **Charge alert** | A popup when the battery reaches the percentage you chose, to unplug it. | the power source notifications | easy |
| **Snippets** | Text you paste often, one click to copy each. | the clipboard | easy |
| **Stocks and crypto** | A price as the button, others as rows. | the network, a free API | medium |
| **Repo watcher** | The number of open pull requests or the state of the last CI run of a GitHub repository. | the network, a token in the Keychain | medium |
| **Clipboard to number** | Reads a number from the clipboard and converts it (units, currencies). | the clipboard, a rates API | medium |
| **Next meeting** | The time to your next event as the button. | Calendar access (declared by the app) | medium |
| **Screen timer** | A clock that counts while a screen recording runs. | detecting a recording | hard |

Have another idea? Open an issue with the label `plugin idea`. If it needs a piece the API doesn't offer (a new kind of option, a new place to show something), say so: that is how the API grew to what it is.
