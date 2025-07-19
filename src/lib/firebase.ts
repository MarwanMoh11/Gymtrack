
// src/lib/firebase.ts
import { initializeApp, getApps, getApp, type FirebaseApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";

// This configuration is correct and verified.
const firebaseConfig = {
  apiKey: "REDACTED_FIREBASE_API_KEY",
  authDomain: "REDACTED_FIREBASE_PROJECT.firebaseapp.com",
  projectId: "REDACTED_FIREBASE_PROJECT",
  storageBucket: "REDACTED_FIREBASE_PROJECT.appspot.com",
  messagingSenderId: "REDACTED_SENDER_ID",
  appId: "1:REDACTED_SENDER_ID:web:REDACTED_APP_ID",
};

// Initialize Firebase App
const app: FirebaseApp = getApps().length ? getApp() : initializeApp(firebaseConfig);

// Initialize other Firebase services
const db = getFirestore(app);

// Export the initialized app and db for use in other parts of the application.
// Auth will be initialized within the AuthContext to ensure stability.
export { app, db };
