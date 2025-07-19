
// src/lib/firebase.ts
import { initializeApp, getApps, getApp, type FirebaseApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

const firebaseConfig = {
  apiKey: "REDACTED_FIREBASE_API_KEY",
  authDomain: "REDACTED_FIREBASE_PROJECT.firebaseapp.com",
  projectId: "REDACTED_FIREBASE_PROJECT",
  storageBucket: "REDACTED_FIREBASE_PROJECT.appspot.com",
  messagingSenderId: "REDACTED_SENDER_ID",
  appId: "1:REDACTED_SENDER_ID:web:REDACTED_APP_ID",
};


let app: FirebaseApp;

try {
  console.log("Attempting to initialize Firebase...");
  console.log("Using config:", firebaseConfig);
  // Initialize Firebase
  // To prevent reinitialization on hot reloads in development, check if an app is already initialized.
  app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
  console.log("Firebase initialized successfully.");
} catch (error) {
  console.error("FATAL: Firebase initialization failed.", error);
  // If initialization fails, we can't proceed. We'll set auth and db to null
  // so other parts of the app can handle it gracefully if needed, though it's likely
  // the app will be unusable.
  app = null as any; // Cast to any to satisfy type checker in error case
}

const auth = getAuth(app);
const db = getFirestore(app);

export { app, auth, db };
