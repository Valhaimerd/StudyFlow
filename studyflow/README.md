# StudyFlow Functionality, UI, and Backend Manual

Version documented: `studyflow` app version `1.2.1+4`
Prepared from the current Flutter source in `studyflow/lib`, the automated tests in `studyflow/test`, and the existing project documentation set.

## 1. Purpose of this document

This manual documents the implemented StudyFlow application end to end. It covers:

- what the app does
- how the user moves through the app
- the visible UI on each major screen
- what each button, action, search flow, and modal does
- how planner data, subject data, reminders, Classroom data, and sync behave
- how the backend and local storage layers work together

This document is implementation-aligned. When the current source differs from earlier mockups or proposals, this manual follows the current codebase.

## 2. Application overview

StudyFlow is a Flutter mobile planner for students. It combines:

- Google sign-in through Firebase Authentication
- user-scoped planner items for tasks, projects, exams, and repeating schedules
- manual subject management
- Google Classroom coursework import and sync
- calendar and dashboard views built from both local and synced data
- local reminder scheduling through device notifications
- local settings for theme, sync, reminder defaults, and readability

The app is not a full learning management system. It does not submit coursework, grade assignments, or replace Google Classroom. It acts as a personal academic workspace centered on planning, tracking, and reminders.

## 3. Core application flow

### 3.1 Startup sequence

When the app launches, `main.dart` boots the app and shows the splash screen. The startup pipeline is:

1. Initialize Firebase.
2. Enable Firebase Realtime Database local persistence.
3. Initialize Google sign-in support.
4. Initialize the local notification service and timezone support.
5. Load local app settings from `SharedPreferences`.
6. Render the main app with theme, accent, and font-size settings applied.

The splash screen visibly steps through startup states such as:

- `CONNECTING SERVICES`
- `PREPARING LOCAL DATA`
- `READYING SIGN-IN`
- `SETTING REMINDERS`
- `LOADING PREFERENCES`
- `WORKSPACE READY`

### 3.2 Authentication and session restoration

After startup, `AppBootstrapper` decides whether the user goes to:

- the login screen
- or directly into the authenticated app shell

Behavior:

- if Firebase already has a signed-in user, the app briefly resumes the session
- if no user is signed in, the login screen is shown
- once authenticated, the app starts syncing the user workspace locally and opens Home

### 3.3 First-use onboarding and screen guides

Inside the app shell, StudyFlow uses `ScreenGuideService` to show:

- a one-time welcome sheet
- one-time per-screen guide sheets for Home, Calendar, Tasks, Subjects, and Profile

These guides are stored locally per user in `SharedPreferences` and do not repeat unless reset.

### 3.4 Ongoing app behavior

After sign-in, the app stays inside a persistent shell with:

- a top navigation bar
- a bottom navigation bar
- context-specific floating action buttons
- auto-sync checks while the app is open and when it resumes

## 4. Global UI structure

### 4.1 Shared shell layout

The authenticated experience is built by `AppShell`. It contains five main tabs:

1. Home
2. Calendar
3. Tasks
4. Subjects
5. Profile

The shell keeps all screens mounted in an `IndexedStack`, which means:

- moving between tabs is fast
- tab state can be preserved
- screen-specific keys can be used to open search, details, and creation flows programmatically

### 4.2 Top navigation bar

The top bar is shared across the authenticated shell. It provides:

- the user avatar
- the StudyFlow wordmark
- a search button
- access to the guide flow

The search button behavior is context-aware:

- Home opens global search across planner items, subjects, and cached Classroom entries
- Calendar opens calendar search
- Tasks opens task search
- Subjects opens subject search
- Profile redirects to task search

### 4.3 Bottom navigation bar

The bottom navigation bar switches between the five main modules:

- Home
- Calendar
- Tasks
- Subjects
- Profile

Selecting a tab can also trigger a guide check for that screen.

### 4.4 Floating action button behavior

The floating action button changes by tab:

- Home: opens a quick-actions bottom sheet
- Calendar: opens a calendar-aware create menu
- Tasks: opens the planner-item create menu
- Subjects: opens the create-subject flow
- Profile: no floating action button

### 4.5 Android back behavior

The app intercepts back presses at the shell level:

- first back press shows `Press back again to exit StudyFlow.`
- second back press within two seconds exits the app

## 5. Login and access experience

### 5.1 Login screen purpose

The login screen exists to authenticate the user with Google and explain how account access works.

### 5.2 Visible UI

The login screen shows:

- StudyFlow branding
- the headline `Access your workspace`
- explanatory copy about syncing schedules, tasks, and Classroom work
- a primary `Sign in with Google` button
- a `Google account access` text button that opens an explanation sheet
- footer links for `Privacy Policy`, `Terms of Service`, and `Google FAQ`
- a security/info card explaining which account should be used

### 5.3 Login actions

`Sign in with Google`

- starts Google authentication through `AuthService.signInWithGoogle()`
- signs the user into Firebase using the Google ID token
- creates or updates the user profile node in Firebase Realtime Database
- on success, updates the UI message to `Signing you in and preparing your workspace.`

`Google account access`

- opens an info sheet
- explains that any Google account can sign in
- explains that Classroom data only appears when the signed-in account has Classroom courses and has granted access

Footer info links

- each opens an informational bottom sheet inside the app
- none navigate to an external browser in the current implementation

### 5.4 Login error handling

The login screen surfaces user-friendly messages for:

- canceled sign-in
- interrupted sign-in
- unavailable Google UI
- configuration errors
- network failures
- disabled users
- too many requests
- invalid credentials

Important implementation note:

- the current code supports general Google sign-in
- Google Classroom sync is permission-based
- earlier institutional-access mockups are not the current enforced authentication rule

## 6. Splash screen

The splash screen shows:

- the app logo
- the StudyFlow name
- the tagline `Plan smarter. Submit on time.`
- a progress bar
- a changing startup label
- the footer phrase `YOUR ACADEMIC SANCTUARY`

It is purely transitional and reflects startup state rather than user data.

## 7. Home dashboard

### 7.1 Role of the dashboard

The Home dashboard is the command center of the app. It combines:

- manual planner items
- cached or live Classroom-derived items
- daily schedule visibility
- sync trust state
- quick creation shortcuts

### 7.2 Main dashboard sections

The screen includes:

- greeting and date header
- search card
- summary cards
- today schedule section
- due-soon section
- overdue review capability
- subject workload summaries
- quick actions
- sync status card

### 7.3 Summary cards

The dashboard calculates and displays summary metrics such as:

- pending tasks
- due today
- upcoming exams
- completed count

These values are derived from:

- active manual planner items
- visible Classroom entries
- hidden-subject and hidden-entry rules

### 7.4 Due Soon section

The Due Soon section shows urgent upcoming work from both:

- StudyFlow planner items
- visible Classroom items

For manual planner items:

- items can be opened
- eligible items can be marked complete

For Classroom items:

- they remain informational unless they have been imported or edited into planner items
- completion rules are more restrictive for Classroom-backed content

### 7.5 Overdue review

If overdue, completable planner items exist, the dashboard can open an overdue review sheet.

That sheet offers:

- per-item `Complete`
- `Open Tasks`
- `Complete all N`

The bulk-complete flow asks for confirmation before marking overdue items complete.

### 7.6 Today's Schedule

This section shows schedule-oriented items for the current day, including:

- repeating Smart Schedule blocks
- dated planner entries
- Classroom items that map into the day view

### 7.7 Quick Actions

Home exposes quick actions for:

- `Add Task`
- `Exams & Quizzes`
- `Smart Schedule`
- `Add Subject`
- `Sync Data`

The floating action button on Home opens the same quick-action options inside a bottom sheet.

### 7.8 Search on Home

The Home search action opens global search, which searches across:

- planner items
- subjects
- cached Classroom entries

Result actions:

- planner result -> opens the Tasks tab and item details
- Classroom result -> opens the Calendar tab and entry details
- subject result -> opens the Subjects tab

### 7.9 Sync center behavior

The Home screen shows sync trust state using local settings and snapshot freshness. It can show:

- stable
- syncing
- offline
- outdated

The sync card also explains when data was last checked or last refreshed.

## 8. Calendar module

### 8.1 Purpose

Calendar is the date-based planning surface. It shows:

- manually created tasks, projects, exams, and schedules
- Google Classroom coursework mapped into calendar entries
- filters by item type and completion state
- selected-date focus content

### 8.2 Data sources

Calendar builds from:

- live or cached Classroom snapshot data via `CalendarRepository`
- planner items from Firebase Realtime Database
- subject appearance customizations
- hidden Classroom subject and hidden Classroom entry preferences

### 8.3 Main UI sections

The Calendar screen includes:

- month header
- previous/next month navigation
- month grid
- entry markers on dates
- a selected date state
- filter chips
- focus/agenda cards for the selected date

### 8.4 Filters

The calendar supports chips such as:

- All
- Tasks
- Exams
- Projects
- Completed

These filters limit which entries appear in the agenda/focus list while the date grid still reflects the underlying month data.

### 8.5 Date selection behavior

When the user taps a date:

- that date becomes selected
- the focus list updates to entries for that date
- date cards can then be opened for more detail

### 8.6 Calendar create actions

The create menu on Calendar is date-aware. It can:

- create a task prefilled with the selected date
- create an exam prefilled with the selected date
- create a subject

### 8.7 Manual Classroom sync

Calendar can run sync directly. The sync flow:

1. checks connectivity
2. requests authorization if necessary
3. fetches Classroom data
4. maps Classroom activities to `CalendarEntry` records
5. stores the snapshot locally
6. stores the snapshot in Firebase
7. updates sync state
8. refreshes notifications

### 8.8 Offline behavior

If the device is offline:

- Calendar uses the best available cached snapshot
- sync state changes to `offlineLocalOnly`
- the user sees offline-oriented sync messaging instead of a silent failure

### 8.9 Classroom entry actions

Depending on entry details, the user can:

- inspect the entry
- open the Classroom alternate link externally when available
- hide the entry
- hide the whole Classroom subject

## 9. Tasks module

### 9.1 Purpose

Tasks is the full planner workspace for all manual and editable planning records:

- tasks
- projects
- exams and quizzes
- Smart Schedule repeating schedule items

It also surfaces Classroom-backed work where applicable.

### 9.2 Main UI sections

Tasks contains:

- search input
- filter row
- sort menu
- task count summary
- scrollable list of planner cards

### 9.3 Supported filters

The current implementation includes:

- all
- pending
- past due
- no due date
- completed
- high priority
- exams
- schedules

### 9.4 Supported sorts

Tasks can be sorted by:

- due date earliest
- due date latest
- posted newest
- posted oldest
- title A-Z
- subject A-Z
- priority

### 9.5 Task cards

Task cards can show:

- item title
- subject
- due label
- type-specific icon
- priority chip
- completion state
- optional description/notes context

### 9.6 Completion behavior

Eligible items can be completed from the list.

Rules:

- schedules cannot be marked complete
- Classroom-backed items have different edit/completion rules
- completed timestamps are stored
- notification refresh is triggered after updates

### 9.7 Create planner item menu

The Tasks floating action button opens a create sheet with:

- `Add Task`
- `Exams & Quizzes`
- `Smart Schedule`

The description under the menu states that created records feed Calendar and Home.

### 9.8 Search inside Tasks

Tasks search narrows task results inside the module rather than using Home's global search sheet.

### 9.9 Item detail and editing

Opening an item leads into editing/detail flows where the user can:

- update title
- update subject
- change type, category, and priority
- set or clear dates and times
- control reminders
- add notes, descriptions, and location
- manage repetition and schedule slots
- manage subtasks
- archive or delete when appropriate

## 10. Planner item editor

### 10.1 Purpose

`PlannerItemEditorSheet` is the multi-step modal used to create and edit standard planner items.

### 10.2 Supported item types

The editor supports:

- Task
- Project
- Exams & Quizzes
- Smart Schedule-compatible schedule item creation entry points, though full schedule authoring is handled separately

### 10.3 Multi-step structure

The editor has four steps:

1. Basics
2. Timing
3. Details
4. Subtasks

Buttons at the bottom:

- `Back`
- `Next`
- `Save Item`

### 10.4 Basics step

The Basics step supports:

- item type dropdown
- title field
- subject selection from existing subjects
- custom subject input
- category dropdown
- priority dropdown

Validation:

- title is required
- subject must be chosen or entered

### 10.5 Timing step

The Timing step supports:

- schedule date
- explicit time toggle and time selection
- optional end time
- reminder enabled toggle
- reminder timing label
- repeat pattern
- repeat-until date where relevant

### 10.6 Details step

The Details step supports:

- description
- notes
- location
- status updates

### 10.7 Subtasks step

The Subtasks step supports:

- adding subtasks
- editing subtask text
- marking subtasks complete
- enabling automatic parent completion when all subtasks are done

Normalization rules in `PlannerItem.normalizedForSave()` ensure:

- non-completable items do not stay completed
- completed items get a completion timestamp
- subtasks are auto-completed when the parent is completed
- fully completed subtasks can auto-complete manual items

### 10.8 Discard protection

The editor traps back/close navigation when the form is dirty and asks the user to confirm discarding unsaved changes.

## 11. Smart Schedule editor

### 11.1 Purpose

`SmartScheduleEditorSheet` creates or edits weekly recurring class or study schedule blocks.

### 11.2 Multi-step structure

The Smart Schedule flow has three steps:

1. Schedule identity
2. Weekly meetings
3. Review details

Primary bottom actions:

- `Back`
- `Next`
- `Save Schedule`

### 11.3 Schedule identity step

The user can set:

- schedule title
- subject source
- custom subject
- category

Subject mode choices:

- `Select subject`
- `Custom subject`

The editor also accepts Classroom course names even if they are not saved as manual subjects.

### 11.4 Weekly meetings step

This step supports:

- start date
- optional repeat-until date
- one or more weekly meeting slots
- day-of-week selection
- start time
- end time
- `Add another meeting`

The editor supports multiple meetings on the same day.

### 11.5 Review step

The review step summarizes:

- title
- subject
- start date
- repeat-until date
- all weekly slots

It also supports:

- `Enable lecture reminder`
- reminder timing selection
- description
- notes
- location

## 12. Subjects module

### 12.1 Purpose

Subjects manages both:

- manual StudyFlow subjects
- Classroom-derived subject summaries

It is the course-centric organization screen.

### 12.2 Main UI sections

The screen includes:

- subject search
- filter options
- manual subject list
- Classroom subject summaries
- archived subject access
- subject insights
- subject creation flow

### 12.3 Subject filters

The current implementation supports:

- all
- manual
- classroom
- archived

### 12.4 Manual subject cards

Manual subject cards show:

- subject code
- subject name
- icon and color identity
- workload information
- nearest deadline
- archive state when applicable

### 12.5 Classroom subject summaries

Classroom-derived subject summaries are built from the cached snapshot and can show:

- course name
- pending visible work
- sync freshness label
- hidden state

### 12.6 Subject actions

Depending on subject type, the user can:

- open details
- edit a manual subject
- archive a manual subject
- restore an archived subject
- hide a Classroom subject
- restore a hidden Classroom subject

### 12.7 Create subject flow

The subject editor supports:

- subject name
- subject code
- instructor name
- semester/term label
- notes
- icon selection
- color selection

Configured icon options include keys such as:

- `menu_book_outlined`
- `school_outlined`
- `calculate_outlined`
- `science_outlined`
- `code_outlined`
- `biotech_outlined`
- `language_outlined`
- `palette_outlined`
- `history_edu_outlined`
- `terminal_outlined`

Semester presets currently include:

- First Semester
- Second Semester
- Mid-Year

### 12.8 Subject validation and uniqueness

The backend enforces subject-code uniqueness per user workspace. Attempts to save duplicate subject codes raise `DuplicateSubjectCodeException`.

## 13. Profile and settings module

### 13.1 Purpose

Profile gives the user control over:

- account profile details
- notification behavior
- sync preferences
- reminder defaults
- theme and readability settings
- release information
- sign-out

### 13.2 Profile header

The top card shows:

- user avatar
- edit profile action
- display name
- email
- academic program
- year level

### 13.3 Notifications section

The Notifications card includes toggles for:

- App Notifications
- Task Notifications
- Quiz Notifications
- Schedule Notifications
- Vibrate-Only Schedules
- Study Goal Alerts

Behavior:

- changing a toggle updates local settings immediately
- planner notifications are refreshed after each change
- schedule notifications can use either vibration-only or ringtone plus vibration

### 13.4 Sync Preferences

The sync preferences area currently exposes:

- `Auto Sync`

When enabled, the app checks for Classroom updates:

- while the app is active
- when the app resumes

### 13.5 Reminder Defaults

The user can edit default reminder lead times for:

- Tasks
- Exams
- Schedules

Implemented option sets:

- Tasks: `10m before`, `15m before`, `30m before`, `1 hour before`
- Exams: `1 day before`, `2 days before`, `3 days before`, `1 week before`
- Lectures/Schedules: `5m before`, `10m before`, `15m before`, `30m before`

These defaults affect future reminder scheduling and are stored locally.

### 13.6 Appearance

The Appearance section controls:

- theme mode: Light or Dark
- theme accent
- font size

Available theme accents:

- Study
- Forest
- Sunset
- Blossom
- Mono
- Passion

Available font sizes:

- Default
- Small

### 13.7 About App

The About App section shows:

- app name
- version
- build number
- `Release Notes`

Release notes are displayed in a bottom sheet and currently include an internal release history list defined in code.

### 13.8 Sign out

The `Sign Out` button opens a confirmation flow. On sign out, the app:

- signs out of Firebase
- signs out of Google
- clears the in-memory Google account reference
- returns the user to the login experience

## 14. Search behavior

### 14.1 Global search

Global search exists at the shell level and searches across:

- planner items
- subjects
- cached Classroom entries

Matching fields include examples such as:

- title
- description
- notes
- subject name
- subject code
- type label
- priority label

### 14.2 Result sections

Results are grouped into:

- Planner
- Classroom
- Subjects

### 14.3 Context-specific search

Each major module also supports narrower search behavior:

- Calendar search is calendar-focused
- Tasks search narrows planner items
- Subjects search filters subjects

## 15. Sync architecture

### 15.1 Sync goals

StudyFlow is designed to:

- keep planner data available offline
- merge local planning with Classroom coursework
- maintain a trustable sync state instead of hiding failures

### 15.2 Sync statuses

`AppSettingsService` stores sync state using:

- `stable`
- `syncing`
- `pendingChanges`
- `failed`
- `offlineLocalOnly`

The UI maps these into user-facing display states such as:

- stable
- syncing
- offline
- outdated

### 15.3 Auto-sync rules

The shell checks whether auto-refresh should run based on:

- connectivity
- whether auto sync is enabled
- whether a sync is already running
- whether the last successful sync is stale
- whether the last sync check was long enough ago

Timing constants:

- sync freshness window: 12 hours
- auto-sync interval: 30 minutes

### 15.4 Manual sync flow

Manual sync can be triggered from:

- the Home quick action grid
- the Home floating action button quick-actions sheet
- the sync card
- Calendar sync entry points

The flow:

1. set sync state to syncing
2. fetch Classroom data if online
3. map Classroom coursework into `CalendarEntry`
4. save the snapshot locally in `SharedPreferences`
5. save the snapshot remotely to Firebase Realtime Database
6. update sync record timestamps
7. refresh local notifications
8. refresh Tasks and Subjects consumers that depend on the cached snapshot

### 15.5 Offline sync fallback

If the app is offline:

- manual planner data still works
- Firebase persistence keeps cached user data available
- the Classroom snapshot falls back to the best available local or remote cache
- sync state becomes `offlineLocalOnly`

## 16. Notification and reminder system

### 16.1 Service role

`NotificationService` is responsible for scheduling device-local notifications for planner items.

### 16.2 Supported platforms

The service initializes on:

- Android
- iOS
- macOS

It does not actively support web reminders in this implementation.

### 16.3 Notification channels

On Android, the app creates channels for:

- StudyFlow Reminders
- StudyFlow Schedule Vibrations
- StudyFlow Schedule Alarms
- StudyFlow Goal Alerts

### 16.4 Reminder scheduling rules

The service schedules reminders for:

- planner items with reminders enabled
- visible Classroom items transformed into planner-like reminder candidates

Rules include:

- a maximum of 64 scheduled notifications
- a 60-day look-ahead window
- at least 20 seconds of lead time
- exact alarms where appropriate and permitted

### 16.5 Goal alerts

If enabled, StudyFlow can also create higher-level goal alerts tied to:

- overdue work
- exam preparation
- general study-planning prompts derived from the open planner set

### 16.6 Reminder label parsing

Reminder labels like `15m before`, `1 hour before`, and `1 week before` are converted into `Duration` values by the notification service.

## 17. Google Classroom integration

### 17.1 Access scopes

The app requests Classroom read-only scopes for:

- active courses
- course work assigned to the student
- the student's submission state

### 17.2 What is fetched

`ClassroomService` loads:

- active courses
- coursework for each course
- the current student's submission state for each coursework item

### 17.3 How Classroom data is mapped

Each Classroom activity is converted into a `CalendarEntry` by `ClassroomCalendarMapper`.

The mapper infers type and urgency based on title, description, completion state, and due date:

- exam-like wording -> exam entry with `EXAM` badge
- project-like wording -> project entry
- lab-like wording -> laboratory-toned entry
- near-term due items -> critical tone with `DUE SOON`
- completed work -> completed tone

### 17.4 Hidden Classroom rules

Users can hide:

- individual Classroom entries
- entire Classroom subjects

These hidden settings are applied consistently across:

- Home
- Calendar
- Tasks
- Subjects
- notifications

## 18. Data model

### 18.1 Planner item model

Planner items store:

- id
- title
- subjectId
- subjectCode
- subjectName
- type
- priority
- status
- description
- notes
- location
- category label
- scheduledAt
- endAt
- reminder enabled flag
- reminder label
- repeat pattern
- repeat-until date
- schedule slots
- subtasks
- completion timestamp
- createdAt
- updatedAt
- deletedAt

Planner item types:

- task
- project
- exam
- schedule

Planner item statuses:

- active
- completed
- archived

### 18.2 Subject model

Subjects store:

- id
- subjectName
- subjectCode
- iconKey
- colorValue
- instructorName
- termLabel
- notes
- status
- archivedAt
- createdAt
- updatedAt

Subject statuses:

- active
- archived

### 18.3 Calendar snapshot model

Calendar snapshots store:

- entries
- courseCount
- lastSyncedAt
- source

Snapshot source values:

- local
- firebase
- live

## 19. Backend architecture

### 19.1 Backend stack

StudyFlow uses:

- Firebase Authentication for sign-in/session state
- Firebase Realtime Database for user workspace data
- `SharedPreferences` for local app settings and cache
- Google Classroom REST APIs for academic coursework import

### 19.2 Firebase Realtime Database structure

The effective user workspace is stored under:

`users/{uid}/...`

Current key areas include:

- `users/{uid}` profile fields
- `users/{uid}/plannerItems`
- `users/{uid}/subjects`
- `users/{uid}/subjectAppearances`
- `users/{uid}/hiddenClassroomSubjects`
- `users/{uid}/hiddenClassroomEntries`
- `users/{uid}/calendarCache`

Additional app status support:

- `app_status`

### 19.3 Profile persistence

When a user signs in, the backend updates:

- `uid`
- `fullName`
- `email`
- `googleEmail`
- `updatedAt`
- `createdAt` if missing

### 19.4 Planner-item persistence

Planner items are stored per user and:

- created with generated push IDs
- soft-deleted by writing `deletedAt`
- updated in place
- filtered client-side so deleted items do not appear in active views

### 19.5 Subject persistence

Subjects are stored per user and:

- created with generated push IDs
- updated in place
- archived by changing status and `archivedAt`
- restored by changing status back to active
- protected against duplicate subject codes per user

### 19.6 Classroom cache persistence

The Classroom snapshot is stored in two places:

- local `SharedPreferences` via `CalendarCacheService`
- Firebase Realtime Database via `DatabaseService.saveCalendarCache`

This design gives:

- offline device fallback
- cross-device availability of the last synced snapshot

### 19.7 Local settings persistence

The app stores local settings in `SharedPreferences`, including:

- theme mode
- theme accent
- font size
- notification toggles
- lecture vibration mode
- study goal alerts
- auto sync setting
- default reminder values
- sync status
- last sync checked timestamp
- last synced timestamp
- one-time guide completion flags

### 19.8 Connectivity awareness

The app monitors Firebase connection state using:

`.info/connected`

This drives:

- offline status
- sync messaging
- fallback decisions

## 20. Security and data ownership model

The app is built around user-scoped ownership:

- every planner item is stored under the authenticated user's path
- every subject is stored under the authenticated user's path
- hidden Classroom rules are stored per user
- profile data is stored per user

This means one signed-in student cannot see another student's StudyFlow workspace through the client-side data structure.

## 21. End-to-end user journeys

### 21.1 Returning user journey

1. User launches StudyFlow.
2. Splash screen shows startup phases.
3. Firebase and local services initialize.
4. Existing Firebase session is detected.
5. The app restores the workspace and opens the authenticated shell.
6. Auto-sync may run if the sync state is stale and connectivity exists.
7. Dashboard becomes the main landing page.

### 21.2 New sign-in journey

1. User launches StudyFlow.
2. Login screen appears.
3. User taps `Sign in with Google`.
4. Google authentication completes.
5. Firebase session is created.
6. User profile is created or refreshed in Realtime Database.
7. Home opens.
8. Welcome onboarding and screen guide flows can appear.
9. Notification permissions and reminder refresh are primed after onboarding.

### 21.3 Planner creation journey

1. User opens Home, Calendar, or Tasks.
2. User taps a create action.
3. User chooses Task, Exams & Quizzes, or Smart Schedule.
4. User completes the editor steps.
5. Validation runs.
6. The record is written to Firebase.
7. Local/offline-capable write tracking updates sync state.
8. Notifications are refreshed.
9. Home, Calendar, and Tasks all reflect the saved record.

### 21.4 Classroom sync journey

1. User taps `Sync Data` or auto-sync starts.
2. The app checks if the device is online.
3. If online, the app requests Classroom authorization headers if needed.
4. Courses and coursework are downloaded.
5. Coursework is mapped into calendar-friendly entries.
6. The snapshot is written locally and remotely.
7. Sync status and timestamps update.
8. Dependent screens reload the snapshot.
9. Notifications are refreshed.

### 21.5 Offline planning journey

1. User loses connectivity.
2. The app marks sync as offline-local-only.
3. Existing Firebase-persisted manual data remains accessible.
4. The latest cached Classroom snapshot remains visible when available.
5. The user can still review and often edit local planner data.
6. When connectivity returns, sync can resume manually or automatically.

## 22. Implementation notes and current constraints

- The current login implementation is broad Google sign-in plus Classroom permission gating, not a hard institutional-domain gate.
- The app uses Firebase Realtime Database, not Firestore and not a separate custom API backend.
- The app stores important UX state locally, including sync trust markers and guide completion.
- Classroom import is read-only and based on Google Classroom API access.
- Task and schedule reminders are device-local notifications, not server-pushed notifications.
- Deleted planner items are soft deleted.
- Subjects are archived rather than hard deleted in normal workflow.

## 23. Final summary

StudyFlow is a multi-screen Flutter student planner with a hybrid local-plus-cloud architecture.

Front-end/UI highlights:

- splash, login, Home, Calendar, Tasks, Subjects, and Profile
- consistent shell navigation
- context-aware floating action buttons
- multi-step editors for planner items and repeating schedules
- search, sync, onboarding, and notification controls

Functional highlights:

- manual academic planning
- subject organization
- recurring schedule management
- overdue review
- Classroom sync and visibility controls
- device notifications and reminder defaults
- theme, font, and sync customization

Backend highlights:

- Firebase Authentication for sign-in
- Firebase Realtime Database for user workspace records
- `SharedPreferences` for settings, guides, and local cache
- Google Classroom API for imported academic activity data
- explicit sync-state tracking and offline-aware fallback behavior

This is the current implemented application process from launch to sign-in, planning, sync, search, reminders, profile configuration, and session exit.
