# Navigation Edge Cases Documentation

## SwiftUI Navigation Architecture

### Current Implementation
- **EventView**: Root NavigationView with `.navigationBarHidden(true)`
- **ContentView**: Tab structure where each tab wraps its content in NavigationView  
- **Individual Views**: Self-contained navigation with `navigationTitle` and toolbar setup

### Known Edge Cases and Mitigations

#### 1. Free User Navigation Issues
**Problem**: In free mode, some tabs show missing titles and + buttons due to SwiftUI lazy initialization of TabView navigation.

**Root Cause**: SwiftUI's TabView lazily initializes navigation contexts, and only the first accessed tab gets proper NavigationView initialization.

**Mitigation**: 
- Ensure each tab has self-contained NavigationView wrapper
- Each view implements its own `navigationTitle` and toolbar
- Use `.navigationViewStyle(StackNavigationViewStyle())` consistently

#### 2. Data Corruption from Debug Functions  
**Problem**: `clearAllData()` and `resetToFreeUser()` could leave inconsistent state.

**Mitigation**:
- Added comprehensive state reset with UserDefaults.synchronize()
- Added NotificationCenter refresh trigger
- Added navigation health check after state changes

#### 3. State Transition Edge Cases
**Problem**: Invalid state transitions could break navigation flow.

**Mitigation**:
- Added state transition guards in key functions:
  - `createEvent()`: Validates free user limits and empty names
  - `selectEvent()`: Ensures only Pro users can select events  
  - `deleteEvent()`: Validates event exists before deletion
- Added `performNavigationHealthCheck()` diagnostic function

#### 4. Pro/Free Mode Switching
**Problem**: Switching between Pro and Free modes could leave navigation in inconsistent state.

**Mitigation**:
- Tab index adjustments in ContentView onChange handlers
- Refresh ID regeneration on subscription status change
- Proper event cleanup for free users (single event limit)

#### 5. CloudKit Sync Issues
**Problem**: CloudKit sync failures could corrupt local navigation state.

**Mitigation**:
- Robust error handling in CloudKit operations
- Local state preservation during sync failures
- Fallback to local data when CloudKit unavailable

### Diagnostic Tools

#### Navigation Health Check
Call `dataStore.performNavigationHealthCheck()` to validate:
- Event/member consistency 
- Pro user state alignment
- Unsaved changes flag consistency

The function returns `Bool` and logs specific issues found.

### Testing Scenarios

1. **Free User Flow**: Create event → Add members → Navigate between tabs
2. **Pro Upgrade**: Free user with data → Upgrade → Verify data preserved  
3. **Debug Functions**: Use Clear All Data → Verify clean state
4. **CloudKit Sync**: Network toggle during operations
5. **State Corruption**: Manual UserDefaults manipulation → App recovery

### Future Considerations

- Monitor iOS updates for SwiftUI navigation changes
- Consider NavigationStack migration (iOS 16+)
- Evaluate single NavigationView architecture alternatives
- Add automated navigation health checks on app lifecycle events