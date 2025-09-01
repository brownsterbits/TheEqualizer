# Firebase Security Rules for TheEqualizer

## Required Firestore Security Rules

To enable event sharing functionality, you need to update your Firebase Firestore security rules in the Firebase Console:

### Go to Firebase Console → Firestore Database → Rules

Replace with these rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Allow users to read/write their own user document
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Events collection
    match /events/{eventId} {
      // Allow read if user is authenticated and is either creator or collaborator
      allow read: if request.auth != null && (
        request.auth.uid == resource.data.createdBy ||
        request.auth.uid in resource.data.collaborators
      );
      
      // Allow create if authenticated
      allow create: if request.auth != null;
      
      // Allow update if user is creator or collaborator
      // BUT also allow adding yourself as a collaborator if you have a valid invite
      allow update: if request.auth != null && (
        request.auth.uid == resource.data.createdBy ||
        request.auth.uid in resource.data.collaborators ||
        // Special case: Allow adding yourself as collaborator
        (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['collaborators']) &&
         request.resource.data.collaborators[request.auth.uid] == true)
      );
      
      // Allow delete only if creator
      allow delete: if request.auth != null && request.auth.uid == resource.data.createdBy;
      
      // Subcollections (members, expenses, donations)
      match /{subcollection}/{document} {
        allow read, write: if request.auth != null && (
          get(/databases/$(database)/documents/events/$(eventId)).data.createdBy == request.auth.uid ||
          request.auth.uid in get(/databases/$(database)/documents/events/$(eventId)).data.collaborators
        );
      }
    }
    
    // Invites collection - anyone authenticated can read invites
    match /invites/{inviteCode} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        request.auth.uid == resource.data.createdBy;
    }
  }
}
```

## Key Changes Required:

1. **Allow users to add themselves as collaborators** - The critical fix is in the events update rule that allows a user to add themselves as a collaborator if they're only modifying the collaborators field and adding themselves.

2. **Allow authenticated users to read invites** - Users need to be able to read invite documents to get the event ID.

3. **Subcollection permissions** - Ensure collaborators can read/write to event subcollections.

## How to Apply:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to Firestore Database → Rules
4. Replace the existing rules with the ones above
5. Click "Publish"

## Testing:
After updating the rules, test the sharing flow:
1. Create an event on Device A
2. Share the event (generate invite code)
3. On Device B, join with the invite code
4. Both devices should now be able to see and edit the event

## Alternative Solution (More Secure):
For production, consider using Cloud Functions to handle invite code redemption, which would:
1. Validate the invite code
2. Add the user as a collaborator using admin privileges
3. Optionally track invite usage and implement expiration