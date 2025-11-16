# Navigation and Refresh Fix Documentation

## Issue Date
2025-11-15

## Problem Description

### Symptom 1: Unwanted Navigation
After adding or deleting members, expenses, or donations, the app would automatically navigate back to the Events tab instead of staying on the current page.

### Symptom 2: Missing Refresh
After adding or deleting items, the new data would not appear in the list until the user manually pulled down to refresh the page.

## Root Cause

Both issues were caused by a single bug in `MainTabView.swift`:

```swift
// BROKEN CODE (lines 85-91)
.onChange(of: dataStore.currentEvent) { oldEvent, newEvent in
    if let _ = newEvent, !subscriptionManager.isProUser {
        // In free mode, after event creation, stay on Events tab and refresh
        selectedTab = 0  // ← FORCES NAVIGATION
        refreshID = UUID()  // ← INTERRUPTS VIEW UPDATE
    }
}
```

**Why this broke everything:**

1. **CRUD Operations Pattern**: All add/delete operations use this pattern:
   ```swift
   guard var event = currentEvent else { return }
   event.members.append(member)
   currentEvent = event  // ← Triggers onChange!
   ```

2. **onChange Fired on Every Edit**: The handler triggered on EVERY `currentEvent` modification, including:
   - Adding a member
   - Deleting a member
   - Adding an expense
   - Deleting an expense
   - Adding a donation
   - Deleting a donation

3. **Navigation Interruption**: When `selectedTab = 0` executed:
   - Current view (Members/Expenses/Treasury) was torn down
   - Navigation forced to Events tab
   - SwiftUI's @Published update cycle was interrupted mid-update
   - View never completed its refresh

4. **Data Appeared Missing**: Because the view update was interrupted, the @Published property change never triggered the final view render, making newly added/deleted items invisible until manual refresh.

## The Fix

**File**: `MainTabView.swift` (lines 85-92)

Changed from:
```swift
.onChange(of: dataStore.currentEvent) { oldEvent, newEvent in
    if let _ = newEvent, !subscriptionManager.isProUser {
        selectedTab = 0
        refreshID = UUID()
    }
}
```

To:
```swift
.onChange(of: dataStore.currentEvent) { oldEvent, newEvent in
    // Only navigate to Events tab when creating a NEW event (oldEvent was nil)
    // Don't navigate when just modifying the current event
    if oldEvent == nil && newEvent != nil && !subscriptionManager.isProUser {
        // In free mode, after event creation, stay on Events tab and refresh
        selectedTab = 0
        refreshID = UUID()
    }
}
```

**Key Change**: Added condition `oldEvent == nil` to ensure navigation ONLY happens when:
- Creating a NEW event (transitioning from no event to having an event)

NOT when:
- Modifying an existing event (oldEvent exists, just being updated)

## Why The Fix Works

1. **Navigation Stays Put**: When editing (add/delete), `oldEvent != nil`, so the onChange doesn't fire
2. **View Stays Intact**: Current view (Members/Expenses/Treasury) remains mounted
3. **Update Completes**: SwiftUI's @Published update cycle runs to completion
4. **Data Appears Immediately**: View re-renders with new data automatically

Both issues fixed with a single condition change!

## Expected Behavior After Fix

### Members Page
- ✅ Add Member → Stays on Members page, member appears immediately
- ✅ Delete Member → Stays on Members page, member disappears immediately
- ✅ No pull-down refresh needed

### Expenses Page
- ✅ Add Expense → Stays on Expenses page, expense appears immediately
- ✅ Delete Expense → Stays on Expenses page, expense disappears immediately
- ✅ Add Direct Donation to Expense → Stays on Expenses page, updates immediately
- ✅ No pull-down refresh needed

### Treasury Page (Donations)
- ✅ Add Donation → Stays on Treasury page, donation appears immediately
- ✅ Delete Donation → Stays on Treasury page, donation disappears immediately
- ✅ No pull-down refresh needed

### Events Page (Unaffected)
- ✅ Create Event (free user) → Navigates to Events tab (intended behavior)
- ✅ Create Event (pro user) → Stays on current page (intended behavior)

## How to Detect Regression

If you see these symptoms again, check `MainTabView.swift`:

1. **Unwanted navigation after edit** → Check if `onChange(of: currentEvent)` is firing on modifications
2. **Data not appearing** → Check if view is being torn down during update
3. **Pull-down refresh required** → Indicates SwiftUI update cycle is being interrupted

### Test Checklist
Run through these scenarios to verify fix is still working:
- [ ] Add member on Members page → Should stay on page, member appears
- [ ] Delete member on Members page → Should stay on page, member disappears
- [ ] Add expense on Expenses page → Should stay on page, expense appears
- [ ] Delete expense on Expenses page → Should stay on page, expense disappears
- [ ] Add donation on Treasury page → Should stay on page, donation appears
- [ ] Delete donation on Treasury page → Should stay on page, donation disappears
- [ ] Create event as free user → Should navigate to Events tab (correct behavior)

## Related Code Files

### MainTabView.swift
Contains the fixed `onChange(of: currentEvent)` handler.

### DataStore.swift
Contains CRUD operations that trigger `currentEvent` changes:
- `addMember()` - line ~400
- `removeMember()` - line ~410
- `addExpense()` - line ~420
- `removeExpense()` - line ~430
- `addContributor()` - line ~440
- `removeContributor()` - line ~450
- `addDonation()` - line ~460
- `removeDonation()` - line ~470

All use the pattern:
```swift
guard var event = currentEvent else { return }
event.property.append(item)
currentEvent = event  // Triggers @Published and onChange
```

This pattern is correct and should be maintained. The fix ensures the onChange handler responds appropriately.

## Commit Information

**Commit**: 09f6a36
**Date**: 2025-11-15
**Title**: Fix: Prevent unwanted navigation to Events tab on member/expense/donation edits

## Notes

- This fix maintains the intended behavior for free users creating their first event
- Pro users are unaffected by the onChange logic (they can have multiple events)
- The fix is minimal and surgical - only changes the condition, not the overall architecture
- SwiftUI's built-in @Published mechanism now works as designed
