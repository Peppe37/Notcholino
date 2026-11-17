# Vikunja for Notcholino

Install **Vikunja** from Notcholino's Plugin Store. Open **Settings → Extensions → Vikunja**, enable it, then enter your instance's
HTTPS URL (for example `https://app.vikunja.cloud` or your self-hosted address) and choose **Test and save**.
The instance may be hosted under a subpath. HTTP is supported only on loopback for local testing.
For a private CA, macOS must trust the certificate for the domain. The API must be reachable directly; an interactive proxy login will block it.

[Create an API token](https://vikunja.io/help/settings/#api-tokens) in Vikunja. Grant it permission to list projects and list tasks for project views.
For writing, also allow creating project tasks and moving tasks to a bucket. The extension stores the URL and token together in the macOS Keychain
and only sends the token to the configured API. **Disconnect** removes the saved connection from this Mac.

Open the extensions page in the notch and select Vikunja. Choose a board using the picker and scroll to see all columns.
Open a task by clicking its title. Use **…** on a card to move it to another manual column, or **+** to create a task in the project.
Vikunja applies its own rules for the default and done columns. Filtered columns can be browsed; move tasks in Vikunja when they require changing a filter field.
