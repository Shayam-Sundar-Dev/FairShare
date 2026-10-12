# FairShare — Agent Instructions

## Project Overview

**FairShare** is a Flutter mobile app for splitting trip and event expenses among a group.
Core capabilities: expense tracking, debt simplification, Google Drive live sync, UPI payments, Google Sign-In backup, and planning mode with installments.

> **Naming Rule**: The app name is strictly case-sensitive: **"FairShare"** (CamelCase — never lowercase "fairshare"). Keep this casing across UI, manifests, plists, and window titles.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart SDK `^3.13.4`) |
| State Management | `provider ^6.1.5+1` |
| Local DB | `sqflite ^2.4.4` (SQLite), current version **6** |
| Auth / Cloud | `google_sign_in ^6.2.2`, Google Drive REST API (via `http`) |
| Payments | UPI deep-link / intent via `url_launcher` |
| Contacts | `flutter_contacts ^2.5.0` |
| Location | `geolocator`, `geocoding` |
| QR Code | `qr_flutter ^4.1.0` |
| Sharing | `share_plus ^13.3.0` |
| Formatting | `intl ^0.20.3` |
| ID generation | `uuid ^4.6.0` |

---

## Architecture

```
lib/
├── core/
│   ├── constants/       app_constants.dart
│   ├── services/        deep_link_handler.dart
│   ├── theme/           app_theme.dart
│   ├── utils/           avatar_helper, currency_formatter, phone_helper, sync_time_formatter, upi_payment_helper
│   └── widgets/         fair_share_app_icon, fair_share_logo, liquid_glass
│
├── data/
│   ├── database/        database_helper.dart  ← single SQLite helper (singleton)
│   ├── models/          event, expense, expense_split, person, settlement, category, trip_installment, user
│   ├── repositories/    event, expense, people, settlement, category, trip_installment
│   └── services/        auth_service, contacts_service, google_drive_backup_service,
│                        google_drive_trip_sync_service, location_service, permission_service
│
├── domain/
│   ├── algorithms/      debt_simplifier, installment_calculator, split_calculator
│   └── models/          balance_summary, settlement_proposal
│
├── ui/
│   ├── providers/       auth, backup, category, event, expense, onboarding, people, theme, trip_sync
│   └── screens/
│       ├── auth/        sign_in_screen + widgets
│       ├── events/      events_screen, event_detail_screen, add_event_screen + widgets
│       │                  event_card, trip_share_sheet, share_trip_sheet, join_trip_dialog,
│       │                  expense_approval_dialog
│       ├── expenses/    add_expense_screen + split_selector_widget
│       ├── home/        main_navigation_screen
│       ├── onboarding/  get_started_screen
│       ├── payments/    host_upi_setup_dialog, upi_qr_dialog
│       ├── people/      people_screen, add_person_dialog, contact_picker_sheet
│       ├── profile/     profile_screen, backup_sync_screen + widgets
│       │                  user_contact_setup_dialog, cloud_restore_prompt_dialog
│       ├── settlements/ record_settlement_dialog + settlement_card
│       └── splash/      splash_screen
│
└── main.dart
```

---

## SQLite Database Schema (v6)

### `people`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| name | TEXT | |
| phone_number | TEXT | |
| contact_id | TEXT | From device contacts |
| avatar_color | TEXT | Hex string |
| is_self | INTEGER | 1 = current device user |
| upi_id | TEXT | VPA e.g. `user@upi` |
| count | INTEGER | Default 1 (headcount) |

### `events`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| title | TEXT | |
| event_type | TEXT | Category (Trip, Birthday, etc.) |
| currency | TEXT | Default `₹` |
| description | TEXT | |
| created_at | INTEGER | Epoch ms |
| is_archived | INTEGER | 0/1 |
| status | TEXT | `active` / `planning` / `completed` |
| estimated_budget | REAL | For planning mode |
| installments_count | INTEGER | |
| creator_id | TEXT | Google UID of creator |
| creator_email | TEXT | |
| drive_file_id | TEXT | Google Drive Shared Folder ID for sync |
| share_code | TEXT | Deprecated in UI/sync (retained in schema v6 for backwards compatibility) |
| is_shared | INTEGER | 0/1 |
| last_synced_at | INTEGER | Epoch ms — updated on every Drive sync |

### `event_participants`
| Column | Type | Notes |
|---|---|---|
| event_id | TEXT FK | → events.id |
| person_id | TEXT FK | → people.id |
| count | INTEGER | Person's headcount in this event |

### `expenses`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| event_id | TEXT FK | → events.id |
| payer_id | TEXT FK | → people.id |
| title | TEXT | |
| amount | REAL | |
| category | TEXT | |
| split_type | TEXT | `equal` / `exact` / `percentage` / `shares` |
| date | INTEGER | Epoch ms |
| location | TEXT | |
| latitude / longitude | REAL | |
| receipt_path | TEXT | Local file path |
| approval_status | TEXT | `approved` / `pending` / `rejected` |
| submitted_by_person_id | TEXT | For participant-submitted expenses |
| submitted_by_name | TEXT | |
| rejection_reason | TEXT | |
| approved_at | INTEGER | Epoch ms |
| is_committee_spend | INTEGER | 0/1 |

### `expense_splits`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | |
| expense_id | TEXT FK | → expenses.id |
| person_id | TEXT FK | → people.id |
| allocated_amount | REAL | Final split amount |
| raw_value | REAL | Input value (% or shares) |

### `settlements`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| event_id | TEXT FK | |
| payer_id | TEXT FK | person paying |
| payee_id | TEXT FK | person receiving |
| amount | REAL | |
| settled_at | INTEGER | Epoch ms |
| notes | TEXT | |

### `categories`
| Column | Type |
|---|---|
| id | TEXT PK |
| name | TEXT |
| icon_code_point | INTEGER |
| color_value | INTEGER |
| is_default | INTEGER |

### `trip_installments`
| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | |
| event_id | TEXT FK | |
| installment_number | INTEGER | |
| person_id | TEXT FK | |
| expected_amount | REAL | |
| paid_amount | REAL | |
| is_paid | INTEGER | 0/1 |
| paid_at | INTEGER | Epoch ms |
| notes | TEXT | |

---

## Provider Dependency Map

```
EventProvider       → EventRepository, ExpenseRepository, SettlementRepository, TripInstallmentRepository
ExpenseProvider     → ExpenseRepository, SettlementRepository
TripSyncProvider    → GoogleDriveTripSyncService, EventRepository, ExpenseRepository, PeopleRepository, DatabaseHelper
                      (accepts optional EventProvider for refreshEventInList after sync)
BackupProvider      → GoogleDriveBackupService, EventRepository, PeopleRepository
AuthProvider        → AuthService
PeopleProvider      → PeopleRepository
CategoryProvider    → CategoryRepository
```

---

## Key Patterns & Rules

### Hot Reload / Restart
After editing any `.dart` file under `lib/`:
- **UI-only change** → `hot_reload`
- **State init / global state / `main()` changed** → `hot_restart`

### Adding a DB Column
1. Add to the `CREATE TABLE` statement in `_createDb` in `database_helper.dart`.
2. Add `_addColumnIfNotExists(db, table, column, type)` inside the relevant `if (oldVersion < N)` migration block.
3. Bump `version:` in `openDatabase`.
4. Add field to the corresponding `Model.toMap()` / `Model.fromMap()` / `copyWith()`.

### Refreshing In-Memory State After DB Write
- **After Drive sync / share**: call `EventProvider.refreshEventInList(eventId)` — reads a single event from DB and patches `_events[]` in-place without a full `loadEvents()`.
- **After full structural changes** (new event, delete, archive): call `EventProvider.loadEvents()`.

### Fast Expense Saving (Optimistic UI & Background Sync)
- Adding, editing, or deleting an expense saves directly to SQLite in milliseconds, recomputes financials (`computeFinancials`), patches the in-memory event (`refreshEventInList`), and dismisses the modal immediately (`Navigator.pop()`).
- Never `await` Google Drive network sync (`syncTrip`) before popping the modal or updating local UI. Drive sync runs asynchronously in the background.
- `ExpenseRepository.getExpensesForEvent` batch-fetches splits with a single `IN (...)` query instead of N+1 individual queries per expense.

### SQLite Foreign Key Rule (Never `ConflictAlgorithm.replace` on Parent Tables)
In SQLite with foreign keys enabled (`PRAGMA foreign_keys = ON`), `INSERT OR REPLACE` (or `conflictAlgorithm: ConflictAlgorithm.replace`) is implemented as an atomic `DELETE` followed by an `INSERT`.
- For tables referenced by `FOREIGN KEY ... ON DELETE RESTRICT` (e.g., `people` referenced by `expenses.payer_id`, `expense_splits.person_id`, `settlements`), using `ConflictAlgorithm.replace` throws `FOREIGN KEY constraint failed (code 787 SQLITE_CONSTRAINT_FOREIGNKEY)`.
- For tables referenced by `ON DELETE CASCADE` (e.g., `events` referenced by `event_participants`), it silently deletes all dependent child rows!
- **Rule**: Never use `ConflictAlgorithm.replace` on `people` or `events`. Query first: if the entity exists (by ID or normalized phone), use `db.update(...)`; if new, use `db.insert(...)` with `ConflictAlgorithm.abort` or `ignore`. (Full backups disable `PRAGMA foreign_keys` inside an isolated transaction only).

### Phone Number Preservation & Linking
- **Google Sign-In**: Google OAuth does not provide phone numbers. `AuthService.signInSilently()` must always preserve `existingUser.phoneNumber` from SharedPreferences so app restarts do not erase it.
- **No Overwrite on Empty**: `_persistUser()` must never overwrite an existing phone number with null or empty.
- **UPI Extraction Fallback**: If a phone number is missing from auth preferences, `PhoneHelper.extractPhoneFromUpi(upiId)` extracts 10-digit phone numbers from phone-based UPI VPAs (e.g. `9876543210@okicici`).
- **Self Person Linking**: `PeopleRepository.getSelfPerson()` reconciles empty dummy self rows against `AuthService.getCurrentUser().phoneNumber`, transferring foreign key associations from any duplicate entry to the self user.

### Participant Patch Ownership & Deletion Reconciliation (Sync Steps 4 & 5)
- In Step 4 of participant sync, local expenses missing from the host's Master file are deleted **only** if they were created by someone else.
- Ownership check must check **both** person ID and contact phone number (`PhoneHelper.isSamePhone(submitterPhone, selfPhone)` / `payerPhone`). If ownership checks only match local UUID, participant expenses where another member was payer or where local ID differed get erroneously deleted before Step 5 can push them.
- Step 5 pushes all local expenses belonging to the participant (by ID or phone) to the participant's patch file.

### Host Patch Deduplication & Ghost Expense Prevention
- If multiple patch files exist in Google Drive for the same participant (from reinstalls, ID regeneration, or multiple devices), merging each patch sequentially can resurrect deleted expenses (the "ghost ₹1,000" bug).
- In Host Step 1, patch files are grouped by normalized participant phone number (`PhoneHelper.clean(phone)` / last 10 digits).
- The host retains and merges **only the newest patch file** per participant phone number.
- Older, stale patch files for that participant are deleted from Google Drive during the sync.

### Sync Time Display
Use `SyncTimeFormatter` (`lib/core/utils/sync_time_formatter.dart`):
```dart
SyncTimeFormatter.formatSyncTime(event.lastSyncedAt)  // "Synced 5m ago"
SyncTimeFormatter.formatRelative(event.lastSyncedAt)  // "5m ago" (compact)
```

### UPI Payments & Settlement Flow
See `UpiPaymentHelper` (`lib/core/utils/upi_payment_helper.dart`) and `SettlementCard` (`lib/ui/screens/settlements/widgets/settlement_card.dart`).
- **Role-Specific Actions in Settle Up**:
  - **Debtor (You owe)**: Shows the **"Pay"** button. Tapping launches Google Pay directly (`com.google.android.apps.nbu.paisa.user`) via Android intent/deep-link `upi://pay?pa=<upi_id>&pn=<name>&am=<amount>&tn=FairShare+Settlement&cu=INR`.
  - **Creditor (They owe you)**: Shows the **"Received"** button. Tapping opens `RecordSettlementDialog` to record and confirm the settlement in SQLite and Drive.
  - **"Request" Button**: Removed from the Settle Up tab.
  - **Other Members (View-only)**: Shows **"Share Reminder"** (WhatsApp/Share sheet reminder) and a secondary **"Received"** record button.
  - **QR Code Action**: Tapping the QR icon opens `UpiQrDialog` allowing payment via camera scanning with any UPI app.
- **Google Pay UPI Validation & Fallbacks**:
  - Never generate dummy `@upi` suffixes (e.g. `9876543210@upi`) — Google Pay rejects these with `"Cannot pay with this QR code: no payment account registered on google pay"`.
  - If a payee has no saved UPI ID, prompt with `HostUpiSetupDialog` suggesting their phone number with `@okaxis` (Google Pay standard) or ask for their exact VPA.
- **Payment Completion Recognition**:
  - When returning from Google Pay, if the app receives the intent result `SUCCESS`, it automatically records the settlement. If status is unknown, prompts the user: *"Did your payment complete successfully in Google Pay?"* with quick options ("Mark Paid", "Show QR", "Change UPI ID").
- **Sync**: UPI IDs and recorded settlements sync seamlessly across devices via Drive trip sync.

### Google Drive Sync Flow (Shared Folder & Patch Architecture)
Under the Google OAuth `https://www.googleapis.com/auth/drive.file` scope, a user can only write to files created by their own Google account. Directly modifying another user's file returns 404 even with public writer permissions. To support seamless multi-user collaboration without requiring a central server or restricted Google Drive scopes:

1. **Host (Share Trip)**:
   - Creates a shared Google Drive folder: `fairshare_trip_${eventId}_folder` with `role: 'writer', type: 'anyone'`.
   - Saves/updates the master trip JSON `fairshare_trip_${eventId}.json` inside the folder (`parents: [folderId]`).
   - Saves `folderId` as `drive_file_id` in SQLite `events` table.
   - Tapping the Share button in the AppBar immediately generates and shares an invite link:
     - Clickable link: `DeepLinkHandler.createClickableJoinUrl` creates an HTTPS short link that 301-redirects directly to `fairshare://join?fileId=$driveFileId` (fallback to `fairshare://`). This ensures messaging apps like WhatsApp format it as an active clickable hyperlink instead of inert plain text.
     - Drive Backup Link is excluded from the share message text.
   - "Join a shared trip" quick action banners have been removed everywhere in favor of direct invite links.

2. **Participant (Join Trip)**:
   - User opens the shared link or deep link (`fairshare://join?fileId={folderId}`).
   - `DeepLinkHandler` intercepts the link, extracts `folderId`, and prompts the user via `JoinTripDialog` asking whether they want to join the trip.
   - Tapping "Join Trip" downloads the master trip file, imports members, approved expenses, and pending expenses into SQLite.
   - Automatically navigates to `EventDetailScreen` upon completion.

2.1. **Sync on Event Open & AppBar Actions**:
   - In `EventDetailScreen`, the AppBar features three consecutive actions: `Sync`, `Share`, and `Edit`.
   - Whenever an event is opened, `EventDetailScreen` automatically triggers proactive background sync with Google Drive (`syncTrip`), updating financial totals and expenses without freezing the UI.
   - The redundant sync/share banner button inside the event detail header card is removed.

3. **Participant (Add / Update Expenses)**:
   - When a participant adds or edits an expense, `TripSyncProvider.syncTrip()` or `pushParticipantPatch()` writes to a participant patch file *inside the shared folder*:
     `fairshare_patch_${eventId}_${participantPersonId}.json` with `parents: [folderId]`.
   - Because the participant created this file, `drive.file` scope allows creating and updating it reliably (200 OK).

4. **Host / Member Sync**:
   - Host lists files in the shared folder (`'folderId' in parents and name contains 'fairshare_patch_'`).
   - Host deduplicates patches by participant phone number, processes the latest patch per participant, and purges stale patch files.
   - Host merges submitted expenses, splits, phone numbers, and UPI IDs into local SQLite.
   - Host updates the master trip file with all aggregated data.
   - Other participants pull the updated master trip file on their next sync.
   - `EventProvider.computeFinancials(eventId)` and `EventProvider.refreshEventInList(eventId)` are called immediately so UI balances, expense lists, and sync badges update in real time.

### Contact Number Matching & Local Names
- Phone numbers are mandatory after Google Sign-In; UPI ID is optional (`UserContactSetupDialog`).
- Trip members are identified and linked across devices by phone number (`PhoneHelper.isSamePhone`), ignoring country code/formatting differences.
- Member display names are resolved locally against the device's phone contacts (`ContactsService.findContactNameByPhone`), so each device sees their own address book name for that person.

### Backup vs. Sync & Automatic Cloud Restore
- **Backup** (`GoogleDriveBackupService`): Full snapshot of all trips, expenses, people, and profile data in Google Drive App Data folder.
- **Trip Sync** (`GoogleDriveTripSyncService`): Per-trip shared Google Drive folder with master and participant patch JSON files for real-time group collaboration.
- **Auto Restore Prompt**: After login or during onboarding, `BackupProvider.checkForCloudBackup()` checks if a cloud backup exists. If found, prompts the user via `CloudRestorePromptDialog` whether to restore.

---

## Modern UI & Design System

FairShare follows Material 3 Expressive and iOS 18 glassmorphic design standards:

1. **`LiquidGlassContainer` (`lib/core/widgets/liquid_glass.dart`)**:
   - **Dual-Layer Ambient Shadows**: Built-in contact depth plus soft atmospheric diffusion for realistic physical layering.
   - **Specular Light Reflection**: Default diagonal linear gradient (`Alignment.topLeft` to `Alignment.bottomRight`) with specular highlight reflection.
   - **Hairline Borders**: Theme-adaptive border contrast in both light and dark modes.
2. **Floating Bottom Navigation (`lib/ui/screens/home/main_navigation_screen.dart`)**:
   - **Active Micro-Interactions**: Active items scale smoothly with `AnimatedScale` (1.08) and `AnimatedDefaultTextStyle`.
   - **Tactile Haptics**: Light haptic feedback triggered on tab selection.
   - **Floating Pill Indicator**: Theme-tinted active pill with subtle border highlight.
3. **App-Tile Event Cards (`lib/ui/screens/events/widgets/event_card.dart`)**:
   - Event category icons render inside multi-stop gradient app tiles with matching soft glow shadows.
4. **Frosted Pinned Header & TabBar (`lib/ui/screens/events/event_detail_screen.dart`)**:
   - `_SliverAppBarDelegate` utilizes frosted liquid backdrop blur (`BackdropFilter` with `ImageFilter.blur(sigmaX: 16, sigmaY: 16)`) and a subtle bottom hairline border.
   - Modern TabBar with custom rounded underline indicator, `dividerColor: Colors.transparent`, and bold typography.
   - Modernized `FloatingActionButton.extended` with a 28px pill shape and soft primary-colored glow diffusion shadow.
5. **Segmented Tab Control (`lib/ui/screens/events/events_screen.dart`)**:
   - Minimal 3-way toggle (Active / Planning / History) with animated transitions and subtle drop shadow on the selected segment pill.
6. **Dark Theme Split Selector (`lib/ui/screens/expenses/widgets/split_selector_widget.dart`)**:
   - Split method tabs (Equal, Exact, Percentage, Shares) use theme-aware background and border colors for crisp contrast in dark mode.

---

## Release APK Build (Size Optimization)

To generate compact, release-ready APKs (~15–20MB each) instead of an unoptimized 60MB+ universal APK:
```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/app/outputs/symbols
```
Outputs are located in `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` (modern Android devices)
- `app-armeabi-v7a-release.apk` (older 32-bit devices)
- `app-x86_64-release.apk` (emulators / Chromebooks)

---

## Common Gotchas

- **App Name Casing**: App name is strictly **"FairShare"** (CamelCase). Never use lowercase "fairshare".
- `EventModel` is **immutable** — always use `copyWith()` to update fields.
- `last_synced_at` is stored as **epoch milliseconds** (INTEGER), not ISO string.
- Never use `ConflictAlgorithm.replace` on `people` or `events` — it triggers foreign key constraint failures or deletes cascaded children. Use `db.update` for existing records.
- Direct Drive file updates across different accounts fail under `drive.file` scope — always use the Shared Folder patch pattern (`pushParticipantPatch` / `fetchParticipantPatches`).
- In participant sync, check both ID and phone when reconciling deleted expenses to prevent deleting local unpushed expenses.
- After any Drive write or sync, call `EventProvider.refreshEventInList(id)` and `EventProvider.computeFinancials(id)` so the trips list and detail cards show updated totals and sync badges immediately.
- `people.count` column (headcount per event member) lives in both `people` table (default) and `event_participants.count` (per-event override).
- Settle Up tab: Debtor action is **"Pay"**; Creditor action is **"Received"**. Do not add a "Request" button.
- Never use `@upi` dummy suffixes for UPI IDs — it causes GPay QR code errors.


