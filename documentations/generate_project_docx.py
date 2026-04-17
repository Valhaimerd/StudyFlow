from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape
import zipfile


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_PATH = ROOT / "documentations" / "Summary.docx"
OUTPUT_PATH = ROOT / "documentations" / "StudyFlow Project Documentation.docx"


def _paragraph(
    text: str,
    *,
    style: str | None = None,
    bold: bool = False,
    page_break_before: bool = False,
) -> str:
    props: list[str] = []
    if style:
        props.append(f"<w:pStyle w:val=\"{escape(style)}\"/>")
    if page_break_before:
        props.append("<w:pageBreakBefore/>")
    ppr = f"<w:pPr>{''.join(props)}</w:pPr>" if props else ""

    run_props = "<w:rPr><w:b/></w:rPr>" if bold else ""
    safe_text = escape(text)
    run = (
        f"<w:r>{run_props}<w:t xml:space=\"preserve\">{safe_text}</w:t></w:r>"
        if text
        else "<w:r/>"
    )
    return f"<w:p>{ppr}{run}</w:p>"


def _document_xml(blocks: list[dict[str, object]]) -> bytes:
    paragraphs: list[str] = []
    for index, block in enumerate(blocks):
        kind = block["kind"]
        text = str(block["text"])
        if kind == "title":
            paragraphs.append(
                _paragraph(
                    text,
                    style="Title",
                    bold=True,
                    page_break_before=index != 0 and bool(block.get("new_page")),
                )
            )
        elif kind == "heading1":
            paragraphs.append(
                _paragraph(
                    text,
                    style="Heading1",
                    page_break_before=bool(block.get("new_page")),
                )
            )
        elif kind == "heading2":
            paragraphs.append(_paragraph(text, style="Heading2"))
        elif kind == "bullet":
            paragraphs.append(_paragraph(f"- {text}"))
        elif kind == "strong":
            paragraphs.append(_paragraph(text, bold=True))
        else:
            paragraphs.append(_paragraph(text))

    body = "".join(paragraphs)
    xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/word/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  <w:body>
    {body}
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
      <w:cols w:space="708"/>
      <w:docGrid w:linePitch="360"/>
    </w:sectPr>
  </w:body>
</w:document>
"""
    return xml.encode("utf-8")


def _core_xml() -> bytes:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00",
        "Z",
    )
    xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>StudyFlow Project Documentation</dc:title>
  <dc:subject>Comprehensive project documentation</dc:subject>
  <dc:creator>OpenAI Codex</dc:creator>
  <cp:keywords>StudyFlow, Flutter, Firebase, Google Classroom</cp:keywords>
  <dc:description>Implementation-aligned project documentation generated from the current workspace.</dc:description>
  <cp:lastModifiedBy>OpenAI Codex</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>
</cp:coreProperties>
"""
    return xml.encode("utf-8")


def _build_blocks() -> list[dict[str, object]]:
    return [
        {"kind": "title", "text": "StudyFlow Project Documentation"},
        {
            "kind": "para",
            "text": "Prepared from the current workspace on 2026-04-17. This document is based on the Flutter source code, Android configuration, Firebase wiring, automated tests, and existing documentation files in this repository.",
        },
        {
            "kind": "para",
            "text": "Version identified in pubspec.yaml: 1.2.1+4",
        },
        {
            "kind": "heading1",
            "text": "1. Purpose and Scope",
            "new_page": True,
        },
        {
            "kind": "para",
            "text": "This document explains the StudyFlow project as a complete software system, not only as a set of Flutter screens. It covers what the product does, how the application is structured, how data moves through the system, which services and integrations it depends on, how the app behaves online and offline, what has been tested, and which parts of the current workspace still reflect development-stage configuration.",
        },
        {
            "kind": "para",
            "text": "Unlike the earlier summary document, this version uses the full available workspace rather than only the lib layer. It therefore includes repository structure, platform configuration, Firebase setup status, Android permissions, and test results in addition to feature explanations.",
        },
        {
            "kind": "heading1",
            "text": "2. Project Overview",
        },
        {
            "kind": "para",
            "text": "StudyFlow is a student productivity and academic planning application built with Flutter. It combines manual planning tools with Google Classroom visibility so that a student can manage tasks, exams, projects, recurring study schedules, and subject organization in one mobile-first workspace.",
        },
        {"kind": "bullet", "text": "Manual planner for tasks, projects, exams, and recurring schedule blocks"},
        {"kind": "bullet", "text": "Subject management for manually created academic subjects"},
        {"kind": "bullet", "text": "Google sign-in and Firebase-backed user workspace"},
        {"kind": "bullet", "text": "Google Classroom read-only sync for courses, course work, and submission state"},
        {"kind": "bullet", "text": "Calendar, dashboard, and task views that merge local and synced academic data"},
        {"kind": "bullet", "text": "Device-local reminders and study goal alerts"},
        {"kind": "bullet", "text": "Offline-aware behavior through Firebase Realtime Database persistence and local caching"},
        {
            "kind": "para",
            "text": "Architecturally, the project is a thick-client mobile app. The visible backend is made up of managed services rather than a custom application server. The core backend stack is Firebase Authentication, Firebase Realtime Database, local SharedPreferences storage, and Google Classroom REST APIs.",
        },
        {
            "kind": "heading1",
            "text": "3. Repository and Workspace Structure",
        },
        {
            "kind": "para",
            "text": "The workspace root contains the Flutter application folder, documentation assets, visual assets, screenshots, and a prebuilt Android APK.",
        },
        {"kind": "bullet", "text": "documentations/: Word, text, and PDF project documents"},
        {"kind": "bullet", "text": "icons/: icon source assets"},
        {"kind": "bullet", "text": "screens/: screenshot assets"},
        {"kind": "bullet", "text": "studyflow/: main Flutter application"},
        {"kind": "bullet", "text": "StudyFlow 1.2.1.apk: packaged Android build artifact"},
        {
            "kind": "para",
            "text": "Inside the Flutter app folder, the codebase is organized into feature screens, services, models, shared widgets, theme files, tests, and multi-platform scaffold folders for Android, iOS, macOS, Linux, Windows, and web.",
        },
        {"kind": "bullet", "text": "35 Dart files under lib/"},
        {"kind": "bullet", "text": "11 screen files under lib/screens/"},
        {"kind": "bullet", "text": "11 service files under lib/services/"},
        {"kind": "bullet", "text": "6 model files under lib/models/"},
        {"kind": "bullet", "text": "3 shared widget files under lib/widgets/"},
        {"kind": "bullet", "text": "7 test files under test/"},
        {
            "kind": "para",
            "text": "The repository root does not currently expose Git metadata in this workspace snapshot, so this documentation reflects the files present locally rather than a commit history or branch state.",
        },
        {
            "kind": "heading1",
            "text": "4. Technology Stack",
        },
        {
            "kind": "para",
            "text": "StudyFlow uses Flutter 3.41.6 and Dart 3.11.4 in the inspected environment. The dependency set shows a conventional Flutter UI layer combined with Firebase, Google sign-in, HTTP-based Classroom access, SVG assets, local preferences, timezone support, and local notifications.",
        },
        {"kind": "bullet", "text": "Framework: Flutter with Material design"},
        {"kind": "bullet", "text": "Language: Dart"},
        {"kind": "bullet", "text": "Authentication: firebase_auth plus google_sign_in"},
        {"kind": "bullet", "text": "Database: firebase_database"},
        {"kind": "bullet", "text": "Storage dependency present: firebase_storage"},
        {"kind": "bullet", "text": "HTTP integration: http package for Google Classroom REST requests"},
        {"kind": "bullet", "text": "Local settings and cache: shared_preferences"},
        {"kind": "bullet", "text": "Reminders: flutter_local_notifications, timezone, flutter_timezone"},
        {"kind": "bullet", "text": "External links and intents: url_launcher and android_intent_plus"},
        {"kind": "bullet", "text": "Graphics: flutter_svg plus packaged image/icon assets"},
        {
            "kind": "heading1",
            "text": "5. High-Level Application Architecture",
        },
        {
            "kind": "para",
            "text": "The runtime architecture is centered on a small number of coordinating layers. main.dart performs staged initialization. AppController holds app-wide settings and sync state. AppBootstrapper decides whether the user enters the login flow or the authenticated application. AppShell provides the persistent multi-tab interface once the user is signed in. Individual screens then consume services and streams directly.",
        },
        {"kind": "bullet", "text": "Startup layer: Firebase, local database persistence, authentication, notifications, and saved preferences are initialized before normal navigation begins"},
        {"kind": "bullet", "text": "Session gate: AppBootstrapper uses Firebase auth state and recent session information to restore a signed-in user when possible"},
        {"kind": "bullet", "text": "Global controller: AppController tracks theme mode, accent, font size, reminder defaults, sync timestamps, and sync status"},
        {"kind": "bullet", "text": "Persistent shell: AppShell owns the top bar, bottom navigation, global search, onboarding guides, FAB behavior, and auto-sync triggers"},
        {"kind": "bullet", "text": "Feature screens: dashboard, calendar, tasks, subjects, and profile provide domain-specific UI and workflows"},
        {"kind": "bullet", "text": "Singleton services: AuthService, DatabaseService, CalendarRepository, ClassroomService, NotificationService, and AppSettingsService carry most of the business logic"},
        {
            "kind": "para",
            "text": "State management is intentionally lightweight. The code does not use Provider, Riverpod, Bloc, or another formal state-management package. Instead, it relies on StatefulWidget state, Firebase streams, singleton services, ValueNotifier objects, and explicit refresh logic inside the screens.",
        },
        {
            "kind": "heading1",
            "text": "6. Startup, Authentication, and Session Flow",
        },
        {
            "kind": "heading2",
            "text": "6.1 Startup sequence",
        },
        {
            "kind": "para",
            "text": "Application startup is staged so that the splash screen reflects real initialization progress. The code in main.dart updates labels such as CONNECTING SERVICES, PREPARING LOCAL DATA, READYING SIGN-IN, SETTING REMINDERS, LOADING PREFERENCES, and WORKSPACE READY while loading dependencies.",
        },
        {"kind": "bullet", "text": "Firebase.initializeApp() loads Firebase services"},
        {"kind": "bullet", "text": "DatabaseService.initialize() enables Realtime Database persistence and sets cache size"},
        {"kind": "bullet", "text": "AuthService.initialize() prepares Google sign-in and listens for authentication events"},
        {"kind": "bullet", "text": "NotificationService.initialize() prepares local notification channels and timezone support"},
        {"kind": "bullet", "text": "AppController.bootstrap() loads saved settings from SharedPreferences"},
        {
            "kind": "heading2",
            "text": "6.2 Authentication model",
        },
        {
            "kind": "para",
            "text": "Authentication is Google-based. The app uses GoogleSignIn to obtain an ID token and then exchanges that token for a Firebase credential. After a successful sign-in, the app creates or updates the user profile node in Firebase Realtime Database.",
        },
        {"kind": "bullet", "text": "Sign-in entry point: LoginScreen"},
        {"kind": "bullet", "text": "Auth service: AuthService.signInWithGoogle()"},
        {"kind": "bullet", "text": "Database profile write: DatabaseService.createOrUpdateUserProfile()"},
        {"kind": "bullet", "text": "Session stream: FirebaseAuth.authStateChanges()"},
        {
            "kind": "para",
            "text": "The implementation supports user-friendly error messages for canceled sign-ins, UI unavailability, configuration problems, network failures, disabled users, and invalid credentials.",
        },
        {
            "kind": "heading2",
            "text": "6.3 Session restoration",
        },
        {
            "kind": "para",
            "text": "AppBootstrapper checks whether Firebase already has a current user and briefly presents a resume flow before showing the authenticated shell. Once a user is present, DatabaseService.keepUserWorkspaceSynced(uid) enables local sync for the major user workspace paths.",
        },
        {
            "kind": "heading1",
            "text": "7. Main User Interface and Feature Modules",
        },
        {
            "kind": "heading2",
            "text": "7.1 App shell",
        },
        {
            "kind": "para",
            "text": "The authenticated experience is wrapped in AppShell. It exposes five main tabs: Home or Dashboard, Calendar, Tasks, Subjects, and Profile. The shell maintains these screens in an IndexedStack so that switching tabs is fast and state can be retained across navigation.",
        },
        {"kind": "bullet", "text": "Shared top navigation with avatar, branding, search, and guide entry"},
        {"kind": "bullet", "text": "Shared bottom navigation for the five modules"},
        {"kind": "bullet", "text": "Context-sensitive floating action button depending on the current tab"},
        {"kind": "bullet", "text": "Global search that routes results back into the relevant tab"},
        {"kind": "bullet", "text": "One-time onboarding and per-screen guide sheets stored locally"},
        {"kind": "bullet", "text": "Back-twice-to-exit behavior on Android"},
        {
            "kind": "heading2",
            "text": "7.2 Splash and login",
        },
        {
            "kind": "para",
            "text": "SplashScreen is a pure startup-status screen. LoginScreen handles the product entry experience. It presents branding, a Google sign-in button, account-access guidance, and internal informational sheets for privacy, terms, and FAQ-style explanations.",
        },
        {
            "kind": "heading2",
            "text": "7.3 Dashboard or Home",
        },
        {
            "kind": "para",
            "text": "The dashboard is the command center of the application. It combines manual planner items with cached or live Google Classroom data and presents a student-focused summary of pending work, due-soon items, schedule visibility, quick actions, and sync status.",
        },
        {"kind": "bullet", "text": "Greeting and date header"},
        {"kind": "bullet", "text": "Search card"},
        {"kind": "bullet", "text": "Statistic cards such as pending tasks and upcoming exams"},
        {"kind": "bullet", "text": "Today's schedule section"},
        {"kind": "bullet", "text": "Due soon section"},
        {"kind": "bullet", "text": "Overdue review flow, including bulk completion for eligible manual items"},
        {"kind": "bullet", "text": "Quick actions for adding tasks, exams, schedules, subjects, and manual sync"},
        {"kind": "bullet", "text": "Visible sync trust state driven by settings timestamps and connectivity"},
        {
            "kind": "heading2",
            "text": "7.4 Calendar",
        },
        {
            "kind": "para",
            "text": "CalendarScreen is the date-based planning surface. It merges manual planner records with Classroom-derived calendar entries. Users can navigate months, select a date, inspect agenda items, filter visible content, search inside the calendar, and trigger sync or date-aware creation flows.",
        },
        {"kind": "bullet", "text": "Month header with previous and next navigation"},
        {"kind": "bullet", "text": "Month grid with entry markers"},
        {"kind": "bullet", "text": "Selected-date agenda and detail sheet"},
        {"kind": "bullet", "text": "Pull-to-refresh and explicit sync entry points"},
        {"kind": "bullet", "text": "Actions for Classroom links, hiding entries, and hiding subjects"},
        {
            "kind": "heading2",
            "text": "7.5 Tasks",
        },
        {
            "kind": "para",
            "text": "TasksScreen is the manual planning workspace. It focuses on the user's editable planner records while still being aware of Classroom-backed items. Users can search, sort, filter, inspect, edit, complete, delete, and create new planner items from this module.",
        },
        {"kind": "bullet", "text": "Supported filters include all, pending, past due, no due date, completed, high priority, exams, and schedules"},
        {"kind": "bullet", "text": "Supported sort modes include due date, post date, title, subject, and priority"},
        {"kind": "bullet", "text": "Planner item cards expose due information, type, subject, and completion state"},
        {"kind": "bullet", "text": "Completion is blocked for schedule-type items because schedules are not completable tasks"},
        {
            "kind": "heading2",
            "text": "7.6 Planner item editor",
        },
        {
            "kind": "para",
            "text": "PlannerItemEditorSheet is a multi-step modal used for tasks, projects, and exams. It collects basics, timing, extra details, and subtasks. Validation is built into the editor so that incomplete records are not saved accidentally.",
        },
        {"kind": "bullet", "text": "Core fields include title, subject link, type, priority, category, description, notes, location, reminder settings, dates, times, repeat settings, and subtasks"},
        {"kind": "bullet", "text": "The editor protects against accidental dismissal when unsaved changes exist"},
        {"kind": "bullet", "text": "PlannerItem.normalizedForSave() enforces important business rules before persistence"},
        {
            "kind": "heading2",
            "text": "7.7 Smart Schedule editor",
        },
        {
            "kind": "para",
            "text": "SmartScheduleEditorSheet handles recurring weekly class or study schedules. Unlike standard planner items, schedules are stored with weekly time slots and repeat-until rules so that future occurrences can be computed dynamically.",
        },
        {"kind": "bullet", "text": "Schedule identity step for title, subject, and category"},
        {"kind": "bullet", "text": "Weekly meeting step for day-of-week and time blocks"},
        {"kind": "bullet", "text": "Review step for reminders, notes, and location"},
        {"kind": "bullet", "text": "Multiple meetings can exist for the same subject and even on the same day"},
        {
            "kind": "heading2",
            "text": "7.8 Subjects",
        },
        {
            "kind": "para",
            "text": "SubjectsScreen is the course-centric organization module. It manages both manually created subjects and Classroom-derived subject summaries. This distinction is important: manual subjects are durable stored records, while Classroom subjects are derived from synced data and can be hidden or visually customized.",
        },
        {"kind": "bullet", "text": "Manual subject create, edit, archive, restore, and detail flows"},
        {"kind": "bullet", "text": "Classroom subject summary, hidden-state control, and appearance customization"},
        {"kind": "bullet", "text": "Search and filtering across all, manual, classroom, and archived subject collections"},
        {"kind": "bullet", "text": "Subject editor fields include name, code, instructor, term, notes, icon, and color"},
        {
            "kind": "heading2",
            "text": "7.9 Profile and settings",
        },
        {
            "kind": "para",
            "text": "ProfileScreen acts as the control center for user account data and local application settings. It exposes profile editing, notification controls, sync preferences, reminder defaults, appearance settings, release notes, and sign-out.",
        },
        {"kind": "bullet", "text": "Editable profile fields include name, email, academic program, year level, birth date, and phone number"},
        {"kind": "bullet", "text": "Notification toggles exist for app notifications, task reminders, exam reminders, schedule reminders, vibration-only schedules, and study goal alerts"},
        {"kind": "bullet", "text": "Appearance controls include light or dark mode, accent palette, and font size"},
        {"kind": "bullet", "text": "About section surfaces app version and release notes"},
        {
            "kind": "heading1",
            "text": "8. Core Data Model",
        },
        {
            "kind": "para",
            "text": "StudyFlow uses a small but expressive model layer. The models are strong enough to represent ordinary tasks, recurring schedules, subject metadata, cached calendar snapshots, and imported Classroom activities without requiring a separate server-side domain model in this workspace.",
        },
        {
            "kind": "heading2",
            "text": "8.1 PlannerItem",
        },
        {
            "kind": "para",
            "text": "PlannerItem is the central user-owned work record. It supports four item types: task, project, exam, and schedule. It also stores priority, status, scheduling data, reminders, repeat logic, subtasks, completion timestamps, optional Classroom linkage, and soft-delete state.",
        },
        {"kind": "bullet", "text": "Status values: active, completed, archived"},
        {"kind": "bullet", "text": "Repeat values: none, daily, weekly, monthly"},
        {"kind": "bullet", "text": "Subtasks support optional auto-completion of the parent item"},
        {"kind": "bullet", "text": "Schedule items store weekly slots instead of behaving like ordinary completable tasks"},
        {
            "kind": "heading2",
            "text": "8.2 SubjectRecord and SubjectAppearance",
        },
        {
            "kind": "para",
            "text": "SubjectRecord stores manual subject information such as name, code, icon, color, instructor, term, notes, status, and timestamps. SubjectAppearance is lighter-weight and is used to preserve custom visual styling for subject-like data, especially Classroom subjects that are not stored as full manual records.",
        },
        {
            "kind": "heading2",
            "text": "8.3 Calendar models",
        },
        {
            "kind": "para",
            "text": "CalendarEntry is the normalized presentation model used by calendar-facing screens. CalendarCacheSnapshot wraps a list of those entries with a course count, sync time, and source marker. ClassroomActivity and ClassroomSnapshot represent raw Classroom-side data before it is mapped into the app's normalized entry format.",
        },
        {
            "kind": "heading1",
            "text": "9. Backend and Persistence Architecture",
        },
        {
            "kind": "para",
            "text": "There is no custom backend server implementation in the current workspace. Backend responsibilities are handled by Firebase Authentication, Firebase Realtime Database, SharedPreferences, and Google Classroom APIs. The client directly orchestrates these services.",
        },
        {
            "kind": "heading2",
            "text": "9.1 Firebase Realtime Database structure",
        },
        {
            "kind": "para",
            "text": "DatabaseService shows that user data is organized under users/{uid}/. The following branches are actively used by the app.",
        },
        {"kind": "bullet", "text": "users/{uid}: profile fields such as fullName, email, googleEmail, createdAt, updatedAt"},
        {"kind": "bullet", "text": "users/{uid}/plannerItems"},
        {"kind": "bullet", "text": "users/{uid}/subjects"},
        {"kind": "bullet", "text": "users/{uid}/subjectAppearances"},
        {"kind": "bullet", "text": "users/{uid}/hiddenClassroomSubjects"},
        {"kind": "bullet", "text": "users/{uid}/hiddenClassroomEntries"},
        {"kind": "bullet", "text": "users/{uid}/calendarCache"},
        {"kind": "bullet", "text": "users/{uid}/subjectCodeIndex"},
        {"kind": "bullet", "text": "users/{uid}/syncRecord"},
        {"kind": "bullet", "text": "app_status for a database-ready health marker"},
        {
            "kind": "heading2",
            "text": "9.2 Database behavior",
        },
        {
            "kind": "para",
            "text": "DatabaseService enables Realtime Database offline persistence and explicitly keeps the key workspace collections synced for the authenticated user. Planner items are created with push IDs, updated in place, and soft deleted using a deletedAt timestamp. Subjects are archived rather than hard deleted. Hidden Classroom entries and hidden Classroom subjects are stored separately and applied across screens.",
        },
        {"kind": "bullet", "text": "Subject-code uniqueness is checked client-side and, when online, also reserved atomically through a database transaction"},
        {"kind": "bullet", "text": "Calendar cache snapshots are stored both locally and remotely"},
        {"kind": "bullet", "text": "Connection state is read from .info/connected to drive offline-aware UX"},
        {
            "kind": "heading2",
            "text": "9.3 Local settings",
        },
        {
            "kind": "para",
            "text": "AppSettingsService uses SharedPreferences to persist theme mode, accent theme, font size, notification toggles, lecture vibration mode, study goal alerts, auto-sync, reminder defaults, sync status, last sync timestamps, and one-time guide completion flags.",
        },
        {
            "kind": "heading1",
            "text": "10. Google Classroom Integration",
        },
        {
            "kind": "para",
            "text": "Classroom integration is implemented as a read-only import and sync layer. The app requests Google Classroom scopes for active courses, coursework assigned to the current student, and the current student's submission state. It does not post assignments, grades, or submissions back to Classroom.",
        },
        {"kind": "bullet", "text": "ClassroomService fetches active courses, courseWork items, and studentSubmissions"},
        {"kind": "bullet", "text": "ClassroomDateTimeParser converts Classroom due date and UTC due time fields into device-local DateTime values"},
        {"kind": "bullet", "text": "ClassroomCalendarMapper transforms ClassroomActivity records into CalendarEntry objects for display and reminders"},
        {"kind": "bullet", "text": "Entries can be hidden individually, and entire Classroom subjects can be hidden across the application"},
        {
            "kind": "para",
            "text": "The mapping logic uses heuristics. For example, exam-like titles are promoted to exam entries, project-like wording becomes project entries, and near-term due work is surfaced with stronger urgency tone. This is useful product behavior, but it should be understood as heuristic interpretation rather than authoritative course metadata.",
        },
        {
            "kind": "heading1",
            "text": "11. Sync, Caching, and Offline Behavior",
        },
        {
            "kind": "para",
            "text": "Sync design is one of the stronger parts of the project. Manual planner data is made offline-capable through Firebase Realtime Database persistence. Classroom data is cached in both SharedPreferences and the database. AppController tracks freshness and the shell uses that information to decide when auto-refresh should occur.",
        },
        {"kind": "bullet", "text": "Sync statuses tracked in settings: stable, syncing, pendingChanges, failed, offlineLocalOnly"},
        {"kind": "bullet", "text": "Display statuses derived from that state: stable, syncing, offline, outdated"},
        {"kind": "bullet", "text": "Freshness window used by AppController: 12 hours"},
        {"kind": "bullet", "text": "Auto-sync interval used by AppController: 30 minutes"},
        {"kind": "bullet", "text": "When a database write times out, the app treats it as queued instead of immediately failed because Firebase persistence will replay it later"},
        {"kind": "bullet", "text": "CalendarRepository chooses the newer snapshot between local SharedPreferences cache and Firebase cache by comparing lastSyncedAt"},
        {
            "kind": "para",
            "text": "This design allows a student to keep using existing planner data during poor connectivity, while also surfacing whether the last Classroom snapshot is fresh, stale, or only locally available.",
        },
        {
            "kind": "heading1",
            "text": "12. Notifications and Reminder Engine",
        },
        {
            "kind": "para",
            "text": "NotificationService is responsible for device-local reminders. It initializes Android, iOS, and macOS notification support and maintains multiple Android channels for different reminder behaviors.",
        },
        {"kind": "bullet", "text": "General reminder channel for StudyFlow reminders"},
        {"kind": "bullet", "text": "Dedicated schedule vibration channel"},
        {"kind": "bullet", "text": "Dedicated schedule alarm channel"},
        {"kind": "bullet", "text": "Goal alert channel for higher-level study prompts"},
        {"kind": "bullet", "text": "Look-ahead window: 60 days"},
        {"kind": "bullet", "text": "Maximum scheduled notifications: 64"},
        {"kind": "bullet", "text": "Reminder labels such as 15m before or 2 days before are parsed into real durations"},
        {
            "kind": "para",
            "text": "On Android, the manifest requests POST_NOTIFICATIONS, USE_EXACT_ALARM, SCHEDULE_EXACT_ALARM, USE_FULL_SCREEN_INTENT, RECEIVE_BOOT_COMPLETED, and VIBRATE. Boot receivers are registered so scheduled notifications can be restored after device restart or package replacement.",
        },
        {
            "kind": "heading1",
            "text": "13. Search, Onboarding, and UX System",
        },
        {
            "kind": "para",
            "text": "StudyFlow includes more than raw CRUD screens. It also has a thin UX layer for discoverability and ongoing navigation support. ScreenGuideService stores one-time guide visibility per user and per screen in SharedPreferences, allowing the app to show welcome and instructional sheets without repeating them unnecessarily.",
        },
        {"kind": "bullet", "text": "Global search from the app shell spans planner items, subjects, and cached Classroom entries"},
        {"kind": "bullet", "text": "Tasks, Calendar, and Subjects also provide local search experiences"},
        {"kind": "bullet", "text": "Theming includes light and dark modes plus six accent themes: Study, Forest, Sunset, Blossom, Mono, and Passion"},
        {"kind": "bullet", "text": "Font-size settings currently support Default and Small"},
        {"kind": "bullet", "text": "Shared visual components include the branded background, modal sheet header, and user avatar widget"},
        {
            "kind": "heading1",
            "text": "14. Testing and Verification",
        },
        {
            "kind": "para",
            "text": "The project includes automated tests under studyflow/test. I ran flutter test in the inspected workspace on 2026-04-17, and all 21 tests passed.",
        },
        {"kind": "bullet", "text": "app_settings_service_test.dart verifies reminder defaults"},
        {"kind": "bullet", "text": "calendar_cache_service_test.dart verifies local cache save, restore, and corrupted-payload handling"},
        {"kind": "bullet", "text": "classroom_calendar_mapper_test.dart verifies mapping rules for exams, due-soon items, open-ended items, labs, and selected-date logic"},
        {"kind": "bullet", "text": "classroom_date_time_parser_test.dart verifies UTC-to-local due time conversion"},
        {"kind": "bullet", "text": "planner_item_test.dart verifies priority, subtasks, reminder label parsing, and timestamp parsing"},
        {"kind": "bullet", "text": "screen_guide_service_test.dart verifies one-time guide behavior"},
        {"kind": "bullet", "text": "widget_test.dart verifies splash and login rendering text"},
        {
            "kind": "para",
            "text": "The test suite gives decent confidence in core utility logic and selected UI behavior. It does not, however, replace end-to-end validation of Firebase integration, Google sign-in, Classroom permissions, or production notification behavior on physical devices.",
        },
        {
            "kind": "heading1",
            "text": "15. Platform and Deployment Status",
        },
        {
            "kind": "para",
            "text": "The repository contains scaffold folders for Android, iOS, macOS, Linux, Windows, and web, but the current Firebase configuration is only complete for Android. firebase.json and firebase_options.dart show the configured Firebase project as studyflow-fa5f9 with Android app ID 1:882187981254:android:1900fb5839a754402c22c7.",
        },
        {"kind": "bullet", "text": "Current Android namespace and applicationId are both com.example.studyflow"},
        {"kind": "bullet", "text": "android/app/build.gradle.kts still contains TODO notes indicating the application ID should be replaced with a final unique package name"},
        {"kind": "bullet", "text": "The release build type currently signs with the debug key, which is acceptable for development but not for production distribution"},
        {"kind": "bullet", "text": "firebase_options.dart throws UnsupportedError for web, iOS, macOS, Windows, and Linux because those platforms are not configured in the generated Firebase options file"},
        {"kind": "bullet", "text": "The Kotlin Android entry point is MainActivity in package com.example.studyflow"},
        {
            "kind": "para",
            "text": "These details matter because the codebase is feature-rich enough to feel like a near-real product, but some platform and release settings still clearly reflect a development-stage mobile build rather than a fully hardened production release pipeline.",
        },
        {
            "kind": "heading1",
            "text": "16. Current Strengths",
        },
        {"kind": "bullet", "text": "The project has a coherent product idea and the implementation reflects that idea well"},
        {"kind": "bullet", "text": "The separation between services, models, and screens is practical and readable"},
        {"kind": "bullet", "text": "Offline-aware data writes and snapshot caching are stronger than in many student projects"},
        {"kind": "bullet", "text": "The app handles both manual academic planning and Classroom import instead of being only a simple task list"},
        {"kind": "bullet", "text": "Theming, search, onboarding, and reminders give the product a fuller user experience"},
        {"kind": "bullet", "text": "The existing test suite covers several important utility and business-rule layers"},
        {
            "kind": "heading1",
            "text": "17. Current Risks, Gaps, and Constraints",
        },
        {"kind": "bullet", "text": "No custom backend, admin API, or server-side automation layer is visible in the workspace"},
        {"kind": "bullet", "text": "Firebase security rules are not included here, so data-protection guarantees cannot be fully documented from the client alone"},
        {"kind": "bullet", "text": "Release signing is still using debug keys"},
        {"kind": "bullet", "text": "The Android package ID still uses the example namespace rather than a final product namespace"},
        {"kind": "bullet", "text": "Firebase is only configured for Android even though multi-platform folders exist"},
        {"kind": "bullet", "text": "There is no visible CI/CD pipeline, crash reporting, analytics, or deployment automation in this snapshot"},
        {"kind": "bullet", "text": "Classroom interpretation relies partly on heuristics, so label and urgency classification may not always match academic intent exactly"},
        {
            "kind": "heading1",
            "text": "18. Recommended Next Steps",
        },
        {"kind": "bullet", "text": "Finalize production package naming and release signing for Android"},
        {"kind": "bullet", "text": "Configure Firebase options for every platform that is actually intended to be supported"},
        {"kind": "bullet", "text": "Add explicit Firebase Realtime Database security rules to the documented system design"},
        {"kind": "bullet", "text": "Expand automated testing toward service integration and higher-level widget flows"},
        {"kind": "bullet", "text": "Document operational setup steps such as Firebase project initialization, Google OAuth configuration, and Classroom consent requirements"},
        {"kind": "bullet", "text": "Consider a formal architecture note for state management if the app continues to grow"},
        {
            "kind": "heading1",
            "text": "19. Important Source Files",
        },
        {"kind": "bullet", "text": "lib/main.dart: application bootstrap and session gate"},
        {"kind": "bullet", "text": "lib/app_controller.dart: global settings and sync-state controller"},
        {"kind": "bullet", "text": "lib/screens/app_shell.dart: main authenticated shell and global interactions"},
        {"kind": "bullet", "text": "lib/screens/dashboard_screen.dart: dashboard logic and overview UI"},
        {"kind": "bullet", "text": "lib/screens/calendar_screen.dart: calendar module"},
        {"kind": "bullet", "text": "lib/screens/tasks_screen.dart: planner task workspace"},
        {"kind": "bullet", "text": "lib/screens/subjects_screen.dart: subject management module"},
        {"kind": "bullet", "text": "lib/screens/profile_screen.dart: profile and settings module"},
        {"kind": "bullet", "text": "lib/screens/planner_item_editor_sheet.dart: standard planner item editor"},
        {"kind": "bullet", "text": "lib/screens/smart_schedule_editor_sheet.dart: recurring schedule editor"},
        {"kind": "bullet", "text": "lib/services/database_service.dart: Firebase Realtime Database access layer"},
        {"kind": "bullet", "text": "lib/services/auth_service.dart: Google sign-in and Firebase auth wrapper"},
        {"kind": "bullet", "text": "lib/services/classroom_service.dart: Google Classroom API client"},
        {"kind": "bullet", "text": "lib/services/calendar_repository.dart: sync and cache coordination for Classroom calendar data"},
        {"kind": "bullet", "text": "lib/services/notification_service.dart: local reminder scheduling"},
        {"kind": "bullet", "text": "lib/services/app_settings_service.dart: local settings persistence"},
        {
            "kind": "heading1",
            "text": "20. Final Summary",
        },
        {
            "kind": "para",
            "text": "StudyFlow is a substantial Flutter academic planner with a well-defined product direction and a respectable implementation scope. Its strongest qualities are its hybrid planning model, offline-aware sync behavior, Classroom integration, recurring schedule support, subject-centric organization, and local reminder system. The main remaining gaps are not in basic functionality but in production hardening: security-rule visibility, release configuration, cross-platform Firebase setup, and broader automated validation.",
        },
        {
            "kind": "para",
            "text": "For documentation purposes, the project should be described as a Flutter mobile application that uses Firebase-managed backend services and Google Classroom APIs rather than a traditional custom backend stack. That framing is the most accurate representation of the current codebase.",
        },
    ]


def generate() -> Path:
    if not TEMPLATE_PATH.exists():
        raise FileNotFoundError(f"Template not found: {TEMPLATE_PATH}")

    document_xml = _document_xml(_build_blocks())
    core_xml = _core_xml()

    with zipfile.ZipFile(TEMPLATE_PATH) as src, zipfile.ZipFile(
        OUTPUT_PATH,
        "w",
        compression=zipfile.ZIP_DEFLATED,
    ) as dst:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename == "word/document.xml":
                data = document_xml
            elif item.filename == "docProps/core.xml":
                data = core_xml
            dst.writestr(item, data)

    return OUTPUT_PATH


if __name__ == "__main__":
    path = generate()
    print(path)
