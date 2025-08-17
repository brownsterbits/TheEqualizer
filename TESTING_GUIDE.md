# TheEqualizer - Firebase Sharing Workflow Testing Guide

## Prerequisites
- The app builds successfully with Firebase integration
- Apple Sign In capability is configured in Xcode
- Firebase project is set up with Firestore and Authentication

## Test Scenarios

### 1. First-Time User Flow

#### Test 1.1: Anonymous Sign In
1. Launch the app fresh (no previous data)
2. When prompted, tap "Continue Without Account"
3. Create a test event named "Test Event 1"
4. Add some members and expenses
5. **Expected**: Event is saved locally only, no share button appears on swipe

#### Test 1.2: Upgrade to Apple Sign In
1. From the anonymous state above
2. Go to Settings > tap "Sign In with Apple"
3. Complete Apple Sign In flow
4. **Expected**: 
   - Authentication completes successfully
   - Previous event data is preserved
   - Share button now appears when swiping right on the event

### 2. Authenticated User Flow

#### Test 2.1: Direct Apple Sign In
1. Launch the app fresh
2. When prompted, tap "Sign in with Apple"
3. Complete Apple Sign In
4. **Expected**: Authentication successful, can create events with sharing capability

#### Test 2.2: Create and Share Event
1. As an authenticated user, create "Party Planning" event
2. Add members: Alice, Bob, Charlie
3. Add expense: "Pizza" for $50 paid by Alice
4. Swipe right on the event in the list
5. Tap the share button (person.badge.plus icon)
6. **Expected**: 
   - 6-character invite code appears (e.g., "ABC123")
   - Copy and Share buttons are functional

### 3. Sharing and Collaboration

#### Test 3.1: Copy Invite Code
1. From the invite share view, tap "Copy Invite Code"
2. **Expected**: Code is copied to clipboard, can paste elsewhere

#### Test 3.2: Join Event with Code
1. On a second device (or simulator), sign in with a different Apple ID
2. Create any event to access the events list
3. Tap the "+" button and select "Join Event"
4. Enter the 6-character code from Test 3.1
5. Tap "Join Event"
6. **Expected**:
   - Success message appears
   - The shared event appears in the events list
   - Can view all members and expenses from the original

### 4. Real-Time Sync Testing

#### Test 4.1: Live Updates
1. Have the shared event open on both devices
2. On Device 1: Add a new expense "Drinks" for $30
3. **Expected on Device 2**: 
   - New expense appears within a few seconds
   - No manual refresh needed

#### Test 4.2: Member Changes
1. On Device 2: Add a new member "David"
2. **Expected on Device 1**: 
   - David appears in the members list automatically
   - Can use David in new expenses

### 5. Edge Cases

#### Test 5.1: Invalid Invite Code
1. Try to join with code "XXXXXX"
2. **Expected**: Error message "Invalid or expired invite code"

#### Test 5.2: Offline Behavior
1. Turn on Airplane Mode
2. Try to share an event
3. **Expected**: Share button is disabled or shows error
4. Turn off Airplane Mode
5. **Expected**: Share functionality returns

#### Test 5.3: Multiple Events
1. Create 3 different events
2. Share each with different codes
3. Switch between events
4. **Expected**: Each maintains its own data and share state

### 6. Security Testing

#### Test 6.1: Unauthorized Access
1. Sign out from the app
2. Try to access Settings > Manage Subscription
3. **Expected**: Redirected to sign in

#### Test 6.2: Cross-User Isolation
1. User A creates private event (don't share)
2. User B signs in on another device
3. **Expected**: User B cannot see User A's private event

## Troubleshooting Common Issues

### Issue: "No share button appears"
- Check: Are you signed in? (Settings should show email)
- Check: Is the device online?
- Check: Did the event sync to Firebase? (Check for firebase ID in debug logs)

### Issue: "Cannot join event"
- Check: Is the code exactly 6 characters?
- Check: Are you signed in?
- Check: Is the invite code typed correctly (case-sensitive)?

### Issue: "Changes don't sync"
- Check: Internet connection on both devices
- Check: Both users are authenticated
- Check: No Firebase errors in console

## Debug Commands

To check Firebase sync status, look for these console logs:
- "DEBUG: Fetched X events from Firebase"
- "DEBUG: Uploading local event 'Name' to Firebase"
- "Error syncing with Firebase:" (indicates problems)

## Success Criteria

✅ All authenticated users can create and share events
✅ Invite codes work across different Apple IDs
✅ Real-time sync works within 5 seconds
✅ Offline changes sync when back online
✅ No data loss during sign in/out
✅ Share UI is intuitive and responsive