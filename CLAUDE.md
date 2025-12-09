# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview
Event management iOS application for splitting expenses fairly among group members. Features real-time synchronization, Firebase backend, invite-based event sharing, and a two-tier subscription model (Free/Pro).

## Tech Stack
- **Language**: Swift 6.0+
- **UI Framework**: SwiftUI
- **iOS Version**: iOS 18.4+
- **Backend**: Firebase (Firestore, Auth)
- **In-App Purchases**: StoreKit 2
- **Authentication**: Apple Sign In (with anonymous fallback)

## Architecture

### Core Pattern: MVVM + Service Layer with Local-First Sync

The app follows a **local-first, sync-always** architecture:
1. User action → Update local `DataStore` immediately
2. Save to `UserDefaults` for persistence (happens synchronously)
3. Background sync to Firebase if authenticated
4. Real-time Firestore listeners update UI from other collaborators

**Key benefit**: Full offline functionality with responsive UI while maintaining real-time collaboration when online.

### Key Components

#### DataStore (ViewModel)
- **Single source of truth** using `@MainActor` class with `@Published` properties
- Manages all app state: `currentEvent`, `events`, `isPro`, `hasUnsavedChanges`
- Handles bidirectional sync with Firebase (local-first, offline-capable)
- Coordinates with SubscriptionManager for Pro features
- ~900 lines - consider splitting into smaller view models for specific features

**State Properties**:
```swift
@Published var currentEvent: Event?          // Active event (free users)
@Published var events: [Event]               // All events (Pro users)
@Published var isPro: Bool                   // Subscription status
@Published var hasUnsavedChanges: Bool       // Pending Firebase sync
@Published var syncError: String?            // Network error display
```

#### Services Layer

**FirebaseService**: All Firebase operations
- Authentication (Apple Sign In, anonymous, account linking)
- Firestore CRUD for events and subcollections (members, expenses, donations)
- Real-time listeners with automatic cleanup
- Invite code generation (6-character alphanumeric)
- Nonce generation for Apple Sign In security

**SubscriptionManager**: StoreKit 2 in-app purchases
- Product loading and caching
- Purchase processing with App Store verification
- Background transaction listening
- Subscription status tracking and restoration

### Data Models

All models are `Codable`, `Identifiable`, and `Equatable`:

- **Event**: Root aggregate with dual IDs (`id: UUID` for local, `firebaseId: String?` for sync)
  - Contains arrays: `members`, `expenses`, `donations`
  - Computed properties: `sharePerPerson`, `totalExpenses`, `amountToShare`
  - Firebase metadata: `createdBy`, `collaborators`, `inviteCode`

- **Expense**: Individual spending entry with split calculation
  - `contributors: [Contributor]` for per-person breakdown
  - `optOut` flag for exclusion from splits

- **Member**: Group participant with `type: MemberType`
  - `.contributing` - Participates in splits
  - `.reimbursementOnly` - Receives payments only

- **Donation**: Optional contributions that reduce per-person splits

### Firebase Structure

**Collections**:
```
events/{eventId}
├── [event fields]
├── members/{memberId}
├── expenses/{expenseId}
│   └── contributors: [array]
└── donations/{donationId}

invites/{code}
├── eventId
├── createdBy
└── expiresAt
```

**Sync Strategy**:
- Last-write-wins with local-first preference
- Real-time listeners on `currentEvent` only (cleanup in `deinit`)
- Offline changes sync automatically when connection returns
- Dual ID system: local `UUID` + `firebaseId` for reliable sync

**Critical**: Monitor listener lifecycle - improper cleanup causes memory leaks. The app maintains ONE active listener at a time via `eventListener` property.

### Subscription Model

**Free Tier**:
- Single event only (`currentEvent`)
- Local storage only (no sync)
- Can JOIN shared events but cannot CREATE invites
- Full offline functionality

**Pro Tier** ($1.99/month or $19.99/year):
- Unlimited events (`events` array)
- Firebase sync across devices
- CREATE and share invite codes
- Real-time collaboration

**Gating**: Pro checks happen at DataStore method level (e.g., `createEvent()`, `shareEvent()`). UI hides Pro features when `isPro == false`.

### View Hierarchy

**Root Navigation**:
```
TheEqualizerApp
└── MainTabView (7 tabs)
    ├── Tab 0: EventView (wraps EventsListView)
    ├── Tab 1: MembersView
    ├── Tab 2: ExpensesView
    ├── Tab 3: DonationsView (Treasury)
    ├── Tab 4: SummaryView
    ├── Tab 5: SettlementView
    └── Tab 6: SettingsView
```

**Modal Sheets**:
- `AuthenticationView` - Apple Sign In, anonymous auth, account linking
- `PaywallView` - Pro subscription promotion
- `InviteShareView` - Generate/share invite codes
- `JoinEventView` - Join events via 6-character code

**Navigation Pattern**: Each tab wrapped in `NavigationView` with `StackNavigationViewStyle()`. Modals use `.sheet()` and `.alert()` modifiers.

## Build Commands

### Using XcodeBuild MCP (Preferred)
```
build_sim({ projectPath: "TheEqualizer.xcodeproj", scheme: "TheEqualizer", simulatorName: "iPhone 16" })
test_sim({ projectPath: "TheEqualizer.xcodeproj", scheme: "TheEqualizer", simulatorName: "iPhone 16" })
launch_app_sim({ simulatorName: "iPhone 16", bundleId: "com.yourcompany.TheEqualizer" })
```

### Direct xcodebuild Commands
```bash
# Build for simulator
xcodebuild -project TheEqualizer.xcodeproj -scheme TheEqualizer -configuration Debug build

# Run all tests
xcodebuild test -project TheEqualizer.xcodeproj -scheme TheEqualizer \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

# Run only UI tests
xcodebuild test -project TheEqualizer.xcodeproj -scheme TheEqualizer \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:TheEqualizerUITests

# Clean build
xcodebuild -project TheEqualizer.xcodeproj -scheme TheEqualizer clean
```

## Development Guidelines

### SwiftUI Best Practices
- Use `@State` for view-local state
- Use `@StateObject` for view-owned objects
- Use `@ObservedObject` for passed-in objects (typically DataStore)
- Use `@EnvironmentObject` for dependency injection (DataStore passed from App root)
- Prefer `.task { }` modifier for async operations (auto-cancels on view disappear)

### Firebase Development Patterns

**Always Handle Offline**:
```swift
// Good - local operation succeeds immediately
dataStore.addExpense(...)  // Updates local state
// Background sync happens asynchronously

// Bad - blocking on network
await firebaseService.saveExpense(...)  // Freezes UI on slow network
```

**Listener Management**:
- ONE listener active at a time (cleanup old before adding new)
- Store listener in property: `private var eventListener: ListenerRegistration?`
- Always call `eventListener?.remove()` in `deinit`
- Check for duplicate listeners before adding

**Error Handling**:
- Network errors set `syncError` but don't block local operations
- Permission errors provide user-friendly messages
- Failed syncs queue for retry when connection improves

### Testing Strategy

**Current State**: Minimal test coverage (~5%) - needs expansion

**Priority Areas for Testing**:
1. Expense calculation logic (splits, contributions, donations)
2. Firebase sync operations (create, update, real-time listeners)
3. Subscription state transitions (free → Pro upgrade)
4. Authentication flows (anonymous → Apple Sign In linking)
5. Edge cases (offline, empty states, invalid invite codes)

**Testing Firebase** (see `TESTING_GUIDE.md`):
- Use two simulators/devices for real-time sync testing
- Test invite code flow across different Apple IDs
- Verify offline → online sync recovery
- Test with Firebase Local Emulator Suite for development

**Test Devices**:
- iPhone SE (smallest screen)
- iPhone 16 (standard size)
- iPhone 16 Pro Max (largest screen)

### Common Development Tasks

#### Adding a New Field to Events
1. Update `Event` model (add property)
2. Update Firestore save/load in `FirebaseService`
3. Update UI in relevant views (e.g., `EventView`)
4. Update `FIREBASE_RULES.md` if field affects security
5. Test sync across devices
6. Consider migration for existing data

#### Adding a New View/Feature
1. Create SwiftUI view file in `Views/`
2. Access DataStore via `@EnvironmentObject`
3. Add navigation from appropriate tab
4. Test offline behavior
5. Add to `MainTabView` if it's a new tab
6. Write tests for user flow

#### Debugging Firebase Issues
- Check console for: `"DEBUG: Fetched X events from Firebase"`
- Look for: `"Error syncing with Firebase:"` messages
- Verify Firestore rules in Firebase Console
- Check network connectivity
- Verify authentication state in Settings
- Use Firebase Local Emulator for isolated testing

#### Working with Subscriptions
- Test purchases in sandbox environment (requires TestFlight or sandbox Apple ID)
- Use StoreKit Configuration file (`TheEqualizer.storekit`) for local testing
- Verify Pro features unlock immediately after purchase
- Test restore purchases functionality
- Check App Store Connect for subscription status

## Critical Files

- `TESTING_GUIDE.md` - Complete Firebase testing workflows (authentication, sharing, real-time sync)
- `FIREBASE_RULES.md` - Firestore security rules and deployment instructions
- `TheEqualizer/ViewModels/DataStore.swift` - Central state management (~900 lines)
- `TheEqualizer/Services/FirebaseService.swift` - All Firebase operations
- `TheEqualizer/Services/SubscriptionManager.swift` - StoreKit 2 IAP handling
- `TheEqualizer/MainTabView.swift` - Root navigation structure
- `the-equalizer-legal/` - Terms of service, privacy policy (Do Not Touch)

## Known Issues & Improvements

**Technical Debt**:
- Test coverage ~5% (goal: 80%+)
- DataStore is large (~900 lines) - consider splitting by feature
- Some duplicate detection logic could be more robust
- Listener cleanup could use more defensive programming

**Future Enhancements**:
- Add SwiftLint configuration
- Implement analytics for usage tracking
- Optimize Firestore queries for events with 100+ expenses
- Consider Cloud Functions for invite code validation (more secure)
- Add proper migration system for data model changes

## Security & Compliance

### Do Not Touch
- Production Firebase configurations (Firebase Console access required)
- Firestore security rules (test in emulator first, coordinate deployment)
- Legal documents in `the-equalizer-legal/`
- User data in production Firestore database
- StoreKit configuration after App Store release

### Before Deploying Firestore Rules
1. Test with Firebase Local Emulator
2. Verify read/write permissions for all user roles (creator, collaborator, anonymous)
3. Test invite code redemption flow
4. Confirm subcollection permissions propagate correctly
5. See `FIREBASE_RULES.md` for current production rules

## App Store Submission

### Current Status (2025-12-08)
**Version 1.9 (Build 11)** - In App Review

**Monetization Model**: Free app with in-app subscriptions (freemium)
- **Free Tier**: 1 event limit, local storage only, all core features
- **Pro Monthly**: $1.99/month - Unlimited events, cloud sync, sharing
- **Pro Annual**: $19.99/year - Same as monthly, save 17%

### ⚠️ CRITICAL: IAP Product IDs
These Product IDs are configured in App Store Connect and **cannot be changed**. Code must match exactly:

| Product | Product ID |
|---------|------------|
| Monthly | `com.brownsterbits.theequalizer.pro.monthly` |
| Annual | `com.brownsterbits.theequalizer.pro.annual` |

**Files containing Product IDs:**
- `TheEqualizer/Services/SubscriptionManager.swift` - `productIds` array
- `TheEqualizer/Views/PaywallView.swift` - `selectedProductId` default
- `TheEqualizer/TheEqualizer.storekit` - Local testing config

### Past Rejection Issues & Fixes (v1.9)
1. **Guideline 2.1 - "No response upon purchase" on iPad**: Added success overlay animation, pending purchase alert, fixed iPad presentation with `.navigationViewStyle(.stack)`
2. **Guideline 2.3.2 - IAP metadata identical**: Update Display Name and Description in App Store Connect to be unique
3. **Guideline 2.3.2 - Promotional image text too small**: Created new 1024x1024 image at `Screenshots/promo_image_v2.png`
4. **TestFlight purchase error**: Product IDs in code didn't match App Store Connect (was `pro_monthly`/`pro_yearly`, needed full bundle ID format)

**App Store Assets**:
- Marketing Landing Page: https://brownsterbits.github.io/TheEqualizer/
- Help & FAQ: https://brownsterbits.github.io/TheEqualizer/help.html
- Privacy Policy: https://brownsterbits.github.io/TheEqualizer/privacy.html
- Terms of Service: https://brownsterbits.github.io/TheEqualizer/terms.html

**Subscription Screenshots**:
- Located in `Screenshots/` folder
- 1024x1024 PNG, 72 dpi, RGB, no rounded corners
- Uses brand colors: #C026D3 (magenta), #A855F7 (purple)

**Documentation**:
- **`APP_STORE_SUBMISSION_GUIDE.md`** - Complete submission process (monetization, export compliance, review instructions, troubleshooting)
- **`APP_STORE_LISTING.md`** - App Store copy (name, subtitle, description, keywords)
- **`APP_STORE_DESCRIPTION_CLEAN.txt`** - Description with special characters removed for App Store Connect

**Export Compliance**: Standard encryption only (HTTPS/TLS), France excluded from initial distribution

**App Review**: No login required for testing - free tier works completely offline

### For Future Submissions
- Update version and build numbers
- Update copyright year if needed
- Test on iPhone SE, iPhone 16, iPhone 16 Pro Max
- Review seasonal promotional text opportunities
- See `APP_STORE_SUBMISSION_GUIDE.md` for complete checklist

## Resources

- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Sign in with Apple](https://developer.apple.com/documentation/sign_in_with_apple)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [App Store Connect](https://appstoreconnect.apple.com)

## Git Workflow
- Main branch: `main` (production-ready code)
- Feature branches: `feature/description`
- Bug fixes: `fix/issue-description`
- Always test Firebase sync before merging to main
