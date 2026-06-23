# Snapzy Release Workflow

## Prerequisites

1. EdDSA private key in Keychain (generated via `generate_keys`)
2. Preferred: Developer ID signed and notarized app
3. GitHub repository with Releases enabled

## Release Steps

### 1. Build & Archive

```bash
# In Xcode:
# Product > Archive > Distribute App > Developer ID
# Wait for notarization to complete
```

### 2. Create Update Archive

```bash
# Navigate to exported app location
cd /path/to/exported

# Create ZIP archive (preserves code signature)
zip -r ~/Snapzy-Updates/Snapzy-X.Y.Z.zip Snapzy.app

# Optional: Create release notes HTML
cat > ~/Snapzy-Updates/Snapzy-X.Y.Z.html << 'EOF'
<html>
<body>
<h2>What's New in X.Y.Z</h2>
<ul>
  <li>Feature 1</li>
  <li>Bug fix 2</li>
</ul>
</body>
</html>
EOF
```

### 3. Generate Appcast

```bash
# Locate Sparkle tools
SPARKLE_BIN=~/Library/Developer/Xcode/DerivedData/Snapzy-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate appcast (auto-signs and creates deltas)
$SPARKLE_BIN/generate_appcast ~/Snapzy-Updates

# Output:
# - appcast.xml (updated)
# - *.delta files (for incremental updates)
```

### 4. Upload to GitHub Releases

```bash
# Create and push tag
git tag -a vX.Y.Z -m "Version X.Y.Z"
git push origin vX.Y.Z

# Create release with assets
gh release create vX.Y.Z \
  ~/Snapzy-Updates/Snapzy-X.Y.Z.zip \
  ~/Snapzy-Updates/Snapzy-X.Y.Z.html \
  --title "Snapzy X.Y.Z" \
  --notes "See release notes for details"

# Upload appcast.xml to repo root or GitHub Pages
cp ~/Snapzy-Updates/appcast.xml ./appcast.xml
git add appcast.xml
git commit -m "chore: update appcast for vX.Y.Z"
git push
```

## Key Management

### Backup Private Key
```bash
$SPARKLE_BIN/generate_keys -x sparkle_private_key.pem
# Store securely (password manager, encrypted backup)
# NEVER commit to git!
```

### Restore on New Machine
```bash
$SPARKLE_BIN/generate_keys -f sparkle_private_key.pem
```

### View Public Key
```bash
$SPARKLE_BIN/generate_keys -p
```

## SUFeedURL Configuration

Current URL in Info.plist:
```
https://raw.githubusercontent.com/duongductrong/Snapzy/master/appcast.xml
```

Update this value in `Snapzy/Resources/Info.plist` if your release repository changes.

## Testing Updates

```bash
# Clear last check time to force update check
defaults delete com.trongduong.snapzy SULastCheckTime

# Run app and click "Check for Updates..."
```

## Fallback Distribution

When Developer ID credentials are unavailable, the GitHub release workflow now produces an ad-hoc signed fallback app and verifies the bundle with `codesign --verify --deep --strict`.

- Move the app to `/Applications` before first launch
- Expect Gatekeeper/notarization limitations on these fallback builds
- If permissions were granted to an older bundle ID, macOS will require re-granting them

## Release Notifications

Release notifications are handled by a **separate workflow** (`release-notify.yml`) that triggers automatically after `release-publish.yml` completes successfully. This keeps the publish workflow focused on build/sign/release, and makes it easy to add new notification channels.

**Architecture:**

```
release-publish.yml (build → sign → release)
        ↓ workflow_run trigger
release-notify.yml
  ├── prepare  (fetch release metadata from GitHub API)
  ├── discord  (parallel)
  ├── slack    (parallel, add when needed)
  └── telegram (parallel, add when needed)
```

### Discord

#### 1. Create a Discord Webhook

1. Open your Discord server
2. Go to **Server Settings → Integrations → Webhooks**
3. Click **New Webhook**
4. Choose the target channel for release announcements
5. (Optional) Set the webhook name (e.g., "Snapzy Releases") and avatar
6. Click **Copy Webhook URL** — it looks like:
   ```
   https://discord.com/api/webhooks/123456789012345678/abcdefg...
   ```

#### 2. Add the Secret to GitHub

1. Go to your GitHub repository → **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Name: `DISCORD_WEBHOOK_URL`
4. Value: paste the webhook URL from step 1
5. Click **Add secret**

#### What Gets Posted

Each release notification includes:
- **Title**: version number with link to the GitHub release page
- **Body**: full changelog from `CHANGELOG.md` (features, bug fixes, etc.)
- **Quick links**: DMG download and release page
- **Timestamp**: when the release was published

If `DISCORD_WEBHOOK_URL` is not configured, the job is silently skipped — no failures.

### Adding a New Channel

To add a notification channel (e.g., Slack, Telegram):

1. Open `.github/workflows/release-notify.yml`
2. Add a new job that depends on `prepare`
3. Use `${{ needs.prepare.outputs.version }}`, `.release_url`, `.download_url`, and `.body` for release data
4. Add the required secrets (e.g., `SLACK_WEBHOOK_URL`) to GitHub repository settings

See the commented examples at the bottom of `release-notify.yml`.

## Troubleshooting

1. **Button always disabled**: Check Info.plist has SUFeedURL and SUPublicEDKey
2. **Signature errors**: Ensure private key matches public key in app
3. **No updates found**: Verify appcast.xml sparkle:version > current CFBundleVersion
4. **Notification not sent**: Verify the channel secret (e.g., `DISCORD_WEBHOOK_URL`) is set correctly in GitHub repository settings. Check the `release-notify` workflow run logs for HTTP status warnings.
