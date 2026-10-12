# FairShare — Claude / AI Assistant Instructions

## What This App Does
**FairShare** is a Flutter expense-splitting app for groups (trips, dinners, events).
> **Naming Rule**: App name is strictly case-sensitive: **"FairShare"** (never "fairshare").
- Track shared expenses, auto-calculate who owes whom (debt simplification algorithm).
- Live multi-device sync via Google Drive Shared Folders & Participant Patches (sharing is link-driven).
- Member cross-device identification by phone number, with names resolved from device address book.
- UPI payment integration with Google Pay deep-links and UPI QR codes (role-based: "Pay" / "Received").
- Google Sign-In + automatic cloud restore prompt + full data backup to Google Drive.
- Planning mode (budget + installments).
- Category management, receipt capture, location tagging.
- Modern glassmorphic UI: LiquidGlass, tactile floating nav bar, frosted sticky headers, app-tile cards.

---

## Before You Make Any Change

1. **Read `AGENTS.md`** in the repo root for schema, architecture map, and key patterns.
2. **Check what already exists** — search the codebase before creating a utility or method.
3. **Never install packages** without asking — check `pubspec.yaml` first.

---

## Code Style

- Dart 3 — use `switch` expressions, pattern matching, records where appropriate.
- `const` constructors everywhere possible.
- No `print()` — use `debugPrint()` for dev logs.
- `withValues(alpha: x)` over deprecated `.withOpacity(x)`.
- Immutable models — use `copyWith()`, never mutate directly.
- Keep `build()` methods lean — extract sub-widgets or helper methods for complex UIs.

---

## State Management Rules

| Situation | What to call |
|---|---|
| Single event's sync data changed | `EventProvider.refreshEventInList(eventId)` |
| Expense added / updated / deleted | Save to DB, `computeFinancials(id)` + `refreshEventInList(id)`, pop UI immediately, sync Drive in background |
| New event created / event deleted | `EventProvider.loadEvents()` |
| Event metadata edited | `EventProvider.updateEvent(...)` then `selectEvent(id)` |
| Selected event data needs recompute | `EventProvider.computeFinancials(eventId)` |

**Never** mutate `EventProvider._events` directly. Always go through the provider API.
**Never** await Google Drive network sync (`syncTrip`) before popping modals — sync asynchronously in the background.

---

## Hot Reload Rule (Proactive)

After editing **any** `.dart` file under `lib/`:
- UI widget change → `hot_reload` MCP tool
- State init / `initState` / global state / `main()` changed → `hot_restart` MCP tool
- Only comments/whitespace changed → skip

---

## Adding a Feature Checklist

### New Model Field
1. Add field to `lib/data/models/<model>.dart` (`toMap`, `fromMap`, `copyWith`).
2. Add column to `_createDb` in `database_helper.dart`.
3. Add `_addColumnIfNotExists` migration in the `if (oldVersion < N)` block.
4. Bump `version:` in `openDatabase` (currently **6**).

### New Screen
1. Create in appropriate `lib/ui/screens/<domain>/` folder.
2. Register route in `main_navigation_screen.dart` or call `Navigator.push` from parent.
3. Watch providers with `context.watch<Provider>()`, read-only actions with `context.read<Provider>()`.

### New Repository Method
1. Add to `lib/data/repositories/<name>_repository.dart`.
2. Expose via the corresponding provider if UI needs it.

---

## SQLite Database & Foreign Key Rules

- **NEVER use `ConflictAlgorithm.replace` on parent tables (`people`, `events`)**:
  In SQLite, `INSERT OR REPLACE` executes a `DELETE` followed by an `INSERT`. Because child tables (`expenses`, `expense_splits`, `settlements`, `event_participants`) reference `people` and `events`:
  - `ON DELETE RESTRICT` throws `FOREIGN KEY constraint failed (code 787)`.
  - `ON DELETE CASCADE` silently deletes child rows!
- **Correct Upsert Pattern**:
  Query if the record exists first (by ID or normalized phone). If found, use `db.update(...)`. If not found, use `db.insert(...)` with `ConflictAlgorithm.abort` or `ignore`.
- **Foreign Keys Pragma**: Enabled globally in `DatabaseHelper`. Only disabled temporarily inside an isolated backup restoration transaction.

---

## Member Identification & Phone Number Matching

1. **Mandatory Phone Number**:
   - On onboarding or post-Google sign-in, users are prompted for a mandatory phone number (and optional UPI ID) via `UserContactSetupDialog`.
2. **Normalized Phone Matching**:
   - Members are matched across devices using `PhoneHelper.isSamePhone(phoneA, phoneB)` which compares the last 10 digits, stripping country codes, spaces, dashes, and symbols.
3. **Phone Preservation Across App Starts**:
   - Google Sign-In does not return phone numbers. `AuthService.signInSilently()` MUST retain `existingUser.phoneNumber` from SharedPreferences so app restarts never clear it.
   - `_persistUser()` must never overwrite an existing phone number with null or empty.
   - If phone number is missing from preferences, `PhoneHelper.extractPhoneFromUpi(upiId)` extracts 10-digit phone numbers from phone-based UPI VPAs.
4. **Self Person Reconciliation**:
   - `PeopleRepository.getSelfPerson()` links the local `is_self = 1` row to `AuthService.getCurrentUser().phoneNumber`, transferring foreign key associations from any duplicate entry to the self user.
5. **Local Address Book Names**:
   - Names are resolved locally from device contacts using `ContactsService.findContactNameByPhone(phone)`. This ensures each user sees their own contact book name for a friend, even if the friend entered a nickname on their own device.

---

## Google Drive Sync Architecture (Shared Folder & Patch Pattern)

### Why This Architecture?
Under the restricted Google OAuth scope `https://www.googleapis.com/auth/drive.file`, an account can only modify or patch files created by that specific Google account. Cross-account direct file edits return HTTP 404 even with public writer permissions. To allow peer-to-peer sync without a central backend:

1. **Host (Share Trip)**:
   - Creates a shared Google Drive folder: `fairshare_trip_${eventId}_folder` with `role: 'writer', type: 'anyone'`.
   - Saves/updates master trip JSON `fairshare_trip_${eventId}.json` inside the folder (`parents: [folderId]`).
   - Stores `folderId` in SQLite `events.drive_file_id`.
   - Tapping the Share button in the AppBar immediately generates and shares an invite link:
     - Clickable join link: `DeepLinkHandler.createClickableJoinUrl` creates an HTTPS short link that 301-redirects to `fairshare://join?fileId=$driveFileId` (fallback to `fairshare://`). Chat apps like WhatsApp render this as an active clickable link.
     - Drive Backup Link is excluded from the share message text.
   - "Join a shared trip" quick action banners and buttons have been removed everywhere in favor of direct invite links.

2. **Participant (Join Trip)**:
   - User opens the shared link or deep link (`fairshare://join?fileId={folderId}`).
   - Handled by `DeepLinkHandler`, which intercepts the link, extracts `folderId`, and prompts the user via `JoinTripDialog` asking whether to join the trip.
   - Tapping "Join Trip" downloads master trip JSON, imports members and expenses into SQLite, and navigates to the event.

2.1. **Sync on Event Open & AppBar Actions**:
   - In `EventDetailScreen`, the AppBar features three consecutive actions: `Sync`, `Share`, and `Edit`.
   - Opening `EventDetailScreen` automatically triggers proactive background sync with Google Drive (`syncTrip`), updating financial totals and expenses without freezing the UI.
   - The redundant sync/share banner button inside the event detail header card has been removed.

3. **Participant (Push Expenses / Patches)**:
   - When a participant adds or edits expenses, they create/update their own patch file inside the shared folder:
     `fairshare_patch_${eventId}_${participantId}.json` with `parents: [folderId]`.
   - Because the participant created the patch file, Google Drive allows creating and updating it (HTTP 200).
   - In Step 4 (deletion reconciliation), only expenses truly belonging to others are deleted; local expenses matching the user by ID or phone number are preserved and pushed in Step 5.

4. **Host / Multi-device Sync (Pull & Merge)**:
   - When syncing (`TripSyncProvider.syncTrip()`), the host searches the shared folder for all participant patch files (`fairshare_patch_*.json`).
   - **Patch Deduplication**: Host groups patches by normalized participant phone number (`last10(phone)`). Only the newest patch per participant is merged; stale duplicate patches are deleted from Drive to prevent resurrecting deleted expenses (preventing the "ghost ₹1,000" bug).
   - Host reads valid patches, merges expenses, splits, phone numbers, and UPI IDs into local SQLite.
   - Host pushes the updated aggregate data into the master file `fairshare_trip_${eventId}.json`.
   - Other participants pull the updated master trip file on subsequent syncs.
   - Always call `EventProvider.refreshEventInList(eventId)` and `EventProvider.computeFinancials(eventId)` to update UI cards, badges, and balances immediately.

---

## Automatic Cloud Restore Prompt

- During app launch or immediately after Google Sign-In, `BackupProvider.checkForCloudBackup()` checks if a previous backup exists in the Google Drive app data folder.
- If a cloud backup is found, `CloudRestorePromptDialog` prompts the user to restore their trips and settings with a single tap.

---

## UPI Payment & Settlement Flow

- **Role-Specific Buttons in Settle Up**:
  - **Debtor ("You owe")**: Shows **"Pay"** button. Directly launches Google Pay via Android intent (`com.google.android.apps.nbu.paisa.user`) or deep link `upi://pay?pa=<upi_id>&pn=<name>&am=<amount>&tn=FairShare+Settlement&cu=INR`.
  - **Creditor ("Owes you")**: Shows **"Received"** button. Opens `RecordSettlementDialog` to record settlement locally and sync to Drive.
  - **"Request" Button**: Removed from Settle Up tab.
  - **Other Members**: Shows **"Share Reminder"** (share via WhatsApp/system sheet) and a secondary **"Received"** record button.
  - **QR Code**: Tapping QR icon opens `UpiQrDialog` to scan and pay from any banking app.
- **Validating Google Pay UPI IDs**:
  - Never use dummy `@upi` suffixes (e.g. `9876543210@upi`) — Google Pay rejects this with *"Cannot pay with this QR code: no payment account registered on google pay"*.
  - Prompt user with `HostUpiSetupDialog` suggesting their phone number with `@okaxis` (Google Pay standard) or ask for their verified UPI ID.
- **Status Recognition & Confirmation**:
  - Automatically records settlement if GPay returns `SUCCESS`. If intent status is unknown or user cancels, displays quick confirmation dialog ("Mark Paid", "Show QR", "Change UPI ID").

---

## Modern UI & Design Standards

- **LiquidGlassContainer (`lib/core/widgets/liquid_glass.dart`)**:
  - Dual-layer ambient drop shadows (contact + atmospheric soft spread).
  - Default diagonal linear gradient with specular highlight reflection.
  - Theme-adaptive hairline borders in light/dark modes.
- **Floating Navigation Bar (`lib/ui/screens/home/main_navigation_screen.dart`)**:
  - Active micro-interactions with `AnimatedScale` (1.08) and `AnimatedDefaultTextStyle`.
  - Tactile light haptic feedback on tab change.
  - Floating pill indicator with subtle border highlight.
- **Event Cards (`lib/ui/screens/events/widgets/event_card.dart`)**:
  - App-tile multi-stop gradient icon containers with matching soft glow shadows.
- **Sticky Frosted Header (`lib/ui/screens/events/event_detail_screen.dart`)**:
  - `_SliverAppBarDelegate` uses frosted liquid backdrop blur (`BackdropFilter` with `ImageFilter.blur(sigmaX: 16, sigmaY: 16)`).
  - Underline TabBar indicator with rounded corners, `dividerColor: Colors.transparent`, and bold typography.
  - Glowing pill `FloatingActionButton.extended` with 28px border radius.
- **Segmented Control (`lib/ui/screens/events/events_screen.dart`)**:
  - Smooth animated transitions with tactile elevation shadow on active tab segment.
- **Split Method Selector (`lib/ui/screens/expenses/widgets/split_selector_widget.dart`)**:
  - Explicit theme-aware colors for high contrast in dark mode across Equal, Exact, Percentage, and Shares tabs.

---

## Release APK Build Command (Size Optimization)

To generate optimized, smaller per-architecture release APKs (~15-20MB each) instead of a 60MB+ universal APK:
```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/app/outputs/symbols
```
Outputs generated in `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk`

---

## Sync Time Display

```dart
import 'package:fairshare/core/utils/sync_time_formatter.dart';

SyncTimeFormatter.formatSyncTime(event.lastSyncedAt)   // "Synced 5m ago"
SyncTimeFormatter.formatRelative(event.lastSyncedAt)   // "5m ago"
```

Thresholds: `< 1min` → "just now" · `< 1h` → "Xm ago" · `< 24h` → "Xh ago" · `1 day` → "yesterday" · `< 7d` → "Xd ago" · else → "Oct 5".

---

## Common Pitfalls to Avoid

| Pitfall | Correct approach |
|---|---|
| Lowercasing the app name | Strictly use **"FairShare"** (CamelCase) everywhere. |
| Re-adding "Request" button in Settle Up | Settle Up uses **"Pay"** for debtor and **"Received"** for creditor. |
| Using dummy `@upi` suffixes | Triggers GPay QR error; prompt with `@okaxis` or verified UPI ID. |
| Using `ConflictAlgorithm.replace` on `people` or `events` | Throws FOREIGN KEY error 787 or wipes cascaded rows! Always check existence and use `db.update()`. |
| Overwriting phone number on silent sign-in | Google Sign-In has no phone. `signInSilently()` and `_persistUser()` must preserve `existingUser.phoneNumber`. |
| Reconciling participant deletions by UUID only (Step 4) | Erroneously deletes locally added participant expenses; check ownership with `PhoneHelper.isSamePhone()` too. |
| Merging participant patches without deduplication | Resurrects deleted expenses ("ghost ₹1,000" bug). Deduplicate by participant phone and purge stale Drive files. |
| Direct cross-account file PATCH under `drive.file` scope | Returns 404! Always use the Shared Folder & Participant Patch pattern. |
| Using 6-digit trip codes in UI | Trip codes are deprecated; use Drive folder links and deep links instead. |
| Comparing phone numbers with `==` | Use `PhoneHelper.isSamePhone()` to handle country codes and formatting. |
| Using `?key: value` syntax in map literals | Use `if (x != null) map['key'] = x`. |
| Calling `loadEvents()` after every sync | Use `refreshEventInList(id)` for single-event updates. |
| Reading stale in-memory event after DB write | Always call `refreshEventInList` or `selectEvent` and `computeFinancials`. |
| Adding a column without a migration | Must add both to `_createDb` AND `_addColumnIfNotExists` in `onUpgrade`. |
| Setting `last_synced_at` as ISO string | Must be epoch ms integer: `dateTime.millisecondsSinceEpoch`. |

---

---

## File Quick Reference

| File | Purpose |
|---|---|
| `lib/data/database/database_helper.dart` | SQLite schema (v6) & migrations |
| `lib/data/models/event_model.dart` | EventModel with all fields incl. `lastSyncedAt`, `driveFileId` |
| `lib/data/services/google_drive_trip_sync_service.dart` | Google Drive folders, files, participant patches, and REST API calls |
| `lib/data/services/google_drive_backup_service.dart` | Full app backup snapshot in Drive AppData folder |
| `lib/core/services/deep_link_handler.dart` | AppLinks stream handler for `drive.google.com` & `fairshare://` URLs |
| `lib/core/utils/phone_helper.dart` | Normalized phone number matching (`isSamePhone`, `normalize`) |
| `lib/ui/providers/trip_sync_provider.dart` | `shareTripToDrive`, `joinTripFromDrive`, `syncTrip`, patch merging |
| `lib/ui/providers/backup_provider.dart` | Backup snapshot & `checkForCloudBackup` |
| `lib/ui/screens/events/widgets/join_trip_dialog.dart` | Modal for joining a trip from a shared folder link |
| `lib/ui/screens/profile/widgets/user_contact_setup_dialog.dart` | Mandatory phone + optional UPI setup prompt |
| `lib/ui/screens/profile/widgets/cloud_restore_prompt_dialog.dart` | Prompt to restore cloud backup on sign-in |
| `lib/core/utils/sync_time_formatter.dart` | `formatSyncTime`, `formatRelative` |
| `lib/core/utils/upi_payment_helper.dart` | UPI deep-link launcher |
| `lib/ui/screens/events/widgets/event_card.dart` | Trip list card (shows sync badge) |
| `lib/ui/screens/events/event_detail_screen.dart` | Trip detail + AppBar Sync/Share/Edit actions & auto-sync on open |
| `lib/ui/screens/events/widgets/trip_share_sheet.dart` | Share folder link / Sync Now bottom sheet |
| `lib/ui/screens/profile/backup_sync_screen.dart` | Backup & Google Sync UI |
